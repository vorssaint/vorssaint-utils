// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import Foundation
import Network
import Security

// MARK: - Director State (App → Web)

struct DirectorState: Codable {
    let words: [String]
    let highlightedCharCount: Int
    let totalCharCount: Int
    let isActive: Bool
    let isDone: Bool
    let isListening: Bool
    let fontColor: String
    let lastSpokenText: String
    let audioLevels: [Double]
}

// MARK: - Director Command (Web → App)

struct DirectorCommand: Codable {
    let type: String          // "setText", "updateText", "stop", "nextPage", "prevPage"
    let text: String?
    let readCharCount: Int?
}

// MARK: - Director Server

final class DirectorServer {
    private var httpListener: NWListener?
    private var wsListener: NWListener?
    private var wsConnections: [NWConnection] = []
    private var authenticatedConnections: Set<ObjectIdentifier> = []
    private var authToken: String?
    private var broadcastTimer: Timer?

    // Content state
    private var words: [String] = []
    private var totalCharCount: Int = 0
    private weak var speechRecognizer: SpeechRecognizer?
    private var contentActive: Bool = false

    // Callbacks
    var onSetText: ((String) -> Void)?
    var onUpdateText: ((String, Int) -> Void)?
    var onStop: (() -> Void)?
    var onNextPage: (() -> Void)?
    var onPrevPage: (() -> Void)?

    var httpPort: UInt16 {
        let saved = UserDefaults.standard.integer(forKey: DefaultsKey.teleprompterDirectorServerPort)
        return saved > 1024 && saved < 65535 ? UInt16(saved) : 7575
    }

    var wsPort: UInt16 { httpPort + 1 }
    var isRunning: Bool { httpListener != nil }
    var connectedClients: Int { authenticatedConnections.count }

    // MARK: - Lifecycle

    func start() {
        stop()
        authToken = Self.generateToken()
        startHTTPListener()
        startWSListener()
    }

    func stop() {
        broadcastTimer?.invalidate()
        broadcastTimer = nil

        httpListener?.cancel()
        httpListener = nil
        wsListener?.cancel()
        wsListener = nil

        for conn in wsConnections { conn.cancel() }
        wsConnections.removeAll()
        authenticatedConnections.removeAll()
        authToken = nil
        contentActive = false
    }

    // MARK: - Content Management

    func showContent(speechRecognizer: SpeechRecognizer, words: [String], totalCharCount: Int) {
        self.speechRecognizer = speechRecognizer
        self.words = words
        self.totalCharCount = totalCharCount
        self.contentActive = true
        startBroadcasting()
    }

    func updateContent(words: [String], totalCharCount: Int) {
        self.words = words
        self.totalCharCount = totalCharCount
    }

    func hideContent() {
        contentActive = false
        broadcastTimer?.invalidate()
        broadcastTimer = nil
        broadcastInactive()
    }

    // MARK: - HTTP Server

    private func startHTTPListener() {
        guard let port = NWEndpoint.Port(rawValue: httpPort) else { return }
        do {
            httpListener = try NWListener(using: .tcp, on: port)
        } catch { return }

        httpListener?.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.httpListener = nil }
        }
        httpListener?.newConnectionHandler = { [weak self] conn in
            self?.handleHTTPConnection(conn)
        }
        httpListener?.start(queue: .main)
    }

    private func handleHTTPConnection(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, _, error in
            guard let self else { conn.cancel(); return }
            guard error == nil else { conn.cancel(); return }

            let response = self.buildHTTPResponse()
            conn.send(content: response, completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }

    private func buildHTTPResponse() -> Data {
        let html = Self.generateHTML(wsPort: wsPort, authToken: authToken ?? "")
        let body = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - WebSocket Server

    private func startWSListener() {
        guard let port = NWEndpoint.Port(rawValue: wsPort) else { return }
        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            wsListener = try NWListener(using: params, on: port)
        } catch { return }

        wsListener?.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.wsListener = nil }
        }
        wsListener?.newConnectionHandler = { [weak self] conn in
            self?.handleWSConnection(conn)
        }
        wsListener?.start(queue: .main)
    }

    private func handleWSConnection(_ conn: NWConnection) {
        guard wsConnections.count < 5 else { conn.cancel(); return }
        conn.start(queue: .main)
        wsConnections.append(conn)
        receiveWSMessage(conn)
        let identifier = ObjectIdentifier(conn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak conn] in
            guard let self, let conn, !self.authenticatedConnections.contains(identifier) else { return }
            conn.cancel()
        }

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.authenticatedConnections.remove(ObjectIdentifier(conn))
                self?.wsConnections.removeAll { $0 === conn }
            default: break
            }
        }
    }

    private func receiveWSMessage(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if error != nil { conn.cancel(); return }
            if let data {
                self?.handleIncomingMessage(data, from: conn)
            }
            self?.receiveWSMessage(conn)
        }
    }

    private func handleIncomingMessage(_ data: Data, from conn: NWConnection) {
        guard let command = try? JSONDecoder().decode(DirectorCommand.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let identifier = ObjectIdentifier(conn)
            guard self.authenticatedConnections.contains(identifier) else {
                guard command.type == "auth", command.text == self.authToken else {
                    conn.cancel()
                    return
                }
                self.authenticatedConnections.insert(identifier)
                return
            }
            switch command.type {
            case "setText":
                if let text = command.text {
                    self.onSetText?(text)
                }
            case "updateText":
                if let text = command.text, let readCharCount = command.readCharCount {
                    self.onUpdateText?(text, readCharCount)
                }
            case "stop":
                self.onStop?()
            case "nextPage":
                self.onNextPage?()
            case "prevPage":
                self.onPrevPage?()
            default:
                break
            }
        }
    }

    // MARK: - Broadcasting

    private func startBroadcasting() {
        broadcastTimer?.invalidate()
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.broadcastState()
        }
    }

    private func broadcastState() {
        guard !wsConnections.isEmpty else { return }
        guard let sr = speechRecognizer else { return }

        let state = DirectorState(
            words: words,
            highlightedCharCount: sr.recognizedCharCount,
            totalCharCount: totalCharCount,
            isActive: contentActive,
            isDone: sr.recognizedCharCount >= totalCharCount,
            isListening: sr.isListening,
            fontColor: "#FFFFFF",
            lastSpokenText: sr.lastSpokenText,
            audioLevels: sr.audioLevels.map { Double($0) }
        )

        guard let json = try? JSONEncoder().encode(state) else { return }
        sendToAllClients(data: json)
    }

    private func broadcastInactive() {
        guard !wsConnections.isEmpty else { return }
        let state = DirectorState(
            words: [],
            highlightedCharCount: 0,
            totalCharCount: 0,
            isActive: false,
            isDone: false,
            isListening: false,
            fontColor: "#FFFFFF",
            lastSpokenText: "",
            audioLevels: []
        )
        guard let json = try? JSONEncoder().encode(state) else { return }
        sendToAllClients(data: json)
    }

    private func sendToAllClients(data: Data) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "director", metadata: [meta])

        for conn in wsConnections where authenticatedConnections.contains(ObjectIdentifier(conn)) {
            conn.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - HTML Page Generation

    nonisolated static func generateHTML(wsPort: UInt16, authToken: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
            <title>Vorssaint Director Studio</title>
            <style>
                :root {
                    --bg: #0c0d10;
                    --card: #16181d;
                    --card-border: #242731;
                    --accent: #ff4757;
                    --text: #f1f2f6;
                    --text-secondary: #747d8c;
                    --highlight: #ffd32a;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body {
                    background: var(--bg);
                    color: var(--text);
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Roboto, sans-serif;
                    padding: 20px;
                    min-height: 100vh;
                    display: flex;
                    flex-direction: column;
                    gap: 16px;
                }
                header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    background: var(--card);
                    border: 1px solid var(--card-border);
                    padding: 12px 18px;
                    border-radius: 14px;
                }
                .logo {
                    font-weight: 700;
                    font-size: 16px;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }
                .badge {
                    padding: 3px 8px;
                    background: rgba(255, 71, 87, 0.2);
                    color: var(--accent);
                    border-radius: 6px;
                    font-size: 11px;
                    font-weight: 600;
                    text-transform: uppercase;
                }
                .status-pill {
                    display: flex;
                    align-items: center;
                    gap: 6px;
                    font-size: 12px;
                    color: var(--text-secondary);
                }
                .dot {
                    width: 8px;
                    height: 8px;
                    border-radius: 50%;
                    background: #2ed573;
                }
                .dot.disconnected { background: #ff4757; }
                .main-layout {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 16px;
                    flex: 1;
                }
                @media (max-width: 768px) {
                    .main-layout { grid-template-columns: 1fr; }
                }
                .panel {
                    background: var(--card);
                    border: 1px solid var(--card-border);
                    border-radius: 14px;
                    padding: 16px;
                    display: flex;
                    flex-direction: column;
                    gap: 12px;
                }
                .panel-title {
                    font-size: 13px;
                    font-weight: 600;
                    color: var(--text-secondary);
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                }
                .script-view {
                    flex: 1;
                    background: #090a0d;
                    border: 1px solid var(--card-border);
                    border-radius: 10px;
                    padding: 16px;
                    font-size: 17px;
                    line-height: 1.6;
                    overflow-y: auto;
                    max-height: 480px;
                }
                .word { transition: color 0.15s, background 0.15s; padding: 1px 2px; border-radius: 3px; }
                .word.highlight { color: #000; background: var(--highlight); font-weight: 600; }
                .word.read { color: #57606f; }
                textarea {
                    flex: 1;
                    background: #090a0d;
                    border: 1px solid var(--card-border);
                    border-radius: 10px;
                    padding: 14px;
                    font-size: 15px;
                    color: var(--text);
                    resize: vertical;
                    min-height: 240px;
                    font-family: inherit;
                    line-height: 1.5;
                }
                textarea:focus { outline: none; border-color: var(--accent); }
                .controls {
                    display: flex;
                    gap: 10px;
                    flex-wrap: wrap;
                }
                button {
                    background: rgba(255, 255, 255, 0.08);
                    border: 1px solid var(--card-border);
                    color: var(--text);
                    padding: 10px 18px;
                    border-radius: 10px;
                    font-size: 14px;
                    font-weight: 600;
                    cursor: pointer;
                    display: inline-flex;
                    align-items: center;
                    gap: 6px;
                    transition: background 0.2s, transform 0.1s;
                }
                button:hover { background: rgba(255, 255, 255, 0.14); }
                button:active { transform: scale(0.98); }
                button.primary { background: var(--accent); border-color: var(--accent); color: white; }
                button.primary:hover { background: #ff6b81; }
                .progress-wrap {
                    display: flex;
                    flex-direction: column;
                    gap: 4px;
                }
                .progress-bar {
                    height: 6px;
                    background: rgba(255, 255, 255, 0.1);
                    border-radius: 3px;
                    overflow: hidden;
                }
                .progress-fill {
                    height: 100%;
                    background: var(--accent);
                    width: 0%;
                    transition: width 0.2s;
                }
            </style>
        </head>
        <body>
            <header>
                <div class="logo">
                    <span>Vorssaint</span>
                    <span class="badge">Director</span>
                </div>
                <div class="status-pill">
                    <div id="dot" class="dot disconnected"></div>
                    <span id="statusText">Connecting...</span>
                </div>
            </header>

            <div class="progress-wrap">
                <div class="progress-bar">
                    <div id="progressFill" class="progress-fill"></div>
                </div>
            </div>

            <div class="main-layout">
                <div class="panel">
                    <div class="panel-title">Live Presenter Stream</div>
                    <div id="scriptDisplay" class="script-view">Waiting for prompter to start...</div>
                    <div class="controls">
                        <button onclick="sendCommand('prevPage')">⏮ Prev Page</button>
                        <button onclick="sendCommand('nextPage')">⏭ Next Page</button>
                        <button onclick="sendCommand('stop')">⏹ Stop Prompter</button>
                    </div>
                </div>

                <div class="panel">
                    <div class="panel-title">Live Script Editor (Push to Presenter)</div>
                    <textarea id="scriptInput" placeholder="Edit the presenter's script live here..."></textarea>
                    <div class="controls">
                        <button class="primary" onclick="pushUpdatedScript()">Push Script Update</button>
                        <button onclick="syncFromPresenter()">Copy Presenter Script</button>
                    </div>
                </div>
            </div>

            <script>
                const wsUrl = `ws://${window.location.hostname}:\(wsPort)`;
                const AUTH_TOKEN = "\(authToken)";
                let ws = null;
                let currentWords = [];
                let currentHighlightedChars = 0;

                function connect() {
                    ws = new WebSocket(wsUrl);
                    ws.binaryType = "arraybuffer";

                    ws.onopen = () => {
                        ws.send(JSON.stringify({type: 'auth', text: AUTH_TOKEN}));
                        document.getElementById('dot').className = 'dot';
                        document.getElementById('statusText').innerText = 'Connected to Presenter';
                    };

                    ws.onclose = () => {
                        document.getElementById('dot').className = 'dot disconnected';
                        document.getElementById('statusText').innerText = 'Disconnected, retrying...';
                        setTimeout(connect, 2000);
                    };

                    ws.onmessage = (event) => {
                        try {
                            const decoder = new TextDecoder();
                            const json = decoder.decode(event.data);
                            const state = JSON.parse(json);
                            renderState(state);
                        } catch(e) {}
                    };
                }

                function renderState(state) {
                    currentWords = state.words || [];
                    currentHighlightedChars = state.highlightedCharCount || 0;

                    if (!state.isActive || currentWords.length === 0) {
                        document.getElementById('scriptDisplay').innerHTML = '<span style="color:#747d8c">Prompter is idle.</span>';
                        document.getElementById('progressFill').style.width = '0%';
                        return;
                    }

                    let cumulative = 0;
                    let html = '';
                    for (const word of currentWords) {
                        const wordLen = word.length + 1;
                        if (cumulative + wordLen <= currentHighlightedChars) {
                            html += `<span class="word read">${escapeHtml(word)} </span>`;
                        } else if (cumulative <= currentHighlightedChars) {
                            html += `<span class="word highlight">${escapeHtml(word)} </span>`;
                        } else {
                            html += `<span class="word">${escapeHtml(word)} </span>`;
                        }
                        cumulative += wordLen;
                    }
                    document.getElementById('scriptDisplay').innerHTML = html;

                    const percent = state.totalCharCount > 0
                        ? Math.min(100, Math.round((currentHighlightedChars / state.totalCharCount) * 100))
                        : 0;
                    document.getElementById('progressFill').style.width = percent + '%';
                }

                function escapeHtml(text) {
                    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                }

                function sendCommand(type, payload = {}) {
                    if (!ws || ws.readyState !== WebSocket.OPEN) return;
                    const cmd = JSON.stringify({ type, ...payload });
                    ws.send(cmd);
                }

                function pushUpdatedScript() {
                    const text = document.getElementById('scriptInput').value;
                    sendCommand('updateText', { text: text, readCharCount: currentHighlightedChars });
                }

                function syncFromPresenter() {
                    document.getElementById('scriptInput').value = currentWords.join(' ');
                }

                connect();
            </script>
        </body>
        </html>
        """
    }
}
