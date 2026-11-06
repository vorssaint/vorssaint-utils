// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import Foundation
import Network

// MARK: - Browser State

struct TeleprompterBrowserState: Codable {
    let words: [String]
    let highlightedCharCount: Int
    let totalCharCount: Int
    let audioLevels: [Double]
    let isListening: Bool
    let isDone: Bool
    let fontColor: String
    let cueColor: String
    let hasNextPage: Bool
    let isActive: Bool
    let highlightWords: Bool
    let lastSpokenText: String
}

// MARK: - Teleprompter Server

final class TeleprompterServer: ObservableObject {
    private var httpListener: NWListener?
    private var wsListener: NWListener?
    private var wsConnections: [NWConnection] = []
    private var broadcastTimer: Timer?

    private var words: [String] = []
    private var totalCharCount: Int = 0
    private var hasNextPage: Bool = false
    private weak var speechRecognizer: SpeechRecognizer?
    private var timerWordProgress: Double = 0
    private var contentActive: Bool = false

    var httpPort: UInt16 {
        let saved = UserDefaults.standard.integer(forKey: DefaultsKey.teleprompterRemoteServerPort)
        return saved > 1024 && saved < 65535 ? UInt16(saved) : 7373
    }
    var wsPort: UInt16 { httpPort + 1 }
    var isRunning: Bool { httpListener != nil }
    var connectedClients: Int { wsConnections.count }

    func start() {
        stop()
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
        contentActive = false
    }

    func showContent(speechRecognizer: SpeechRecognizer, words: [String], totalCharCount: Int, hasNextPage: Bool) {
        self.speechRecognizer = speechRecognizer
        self.words = words
        self.totalCharCount = totalCharCount
        self.hasNextPage = hasNextPage
        self.timerWordProgress = 0
        self.contentActive = true
        startBroadcasting()
    }

    func updateContent(words: [String], totalCharCount: Int, hasNextPage: Bool) {
        self.words = words
        self.totalCharCount = totalCharCount
        self.hasNextPage = hasNextPage
        self.timerWordProgress = 0
    }

    func hideContent() {
        contentActive = false
        broadcastTimer?.invalidate()
        broadcastTimer = nil
        broadcastInactive()
    }

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
        let html = Self.generateHTML(wsPort: wsPort)
        let body = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }

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
        conn.start(queue: .main)
        wsConnections.append(conn)
        receiveWSMessage(conn)

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.wsConnections.removeAll { $0 === conn }
            default: break
            }
        }
    }

    private func receiveWSMessage(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] _, _, _, error in
            if error != nil { conn.cancel(); return }
            self?.receiveWSMessage(conn)
        }
    }

    private func startBroadcasting() {
        broadcastTimer?.invalidate()
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.broadcastCurrentState()
        }
    }

    private func broadcastCurrentState() {
        guard contentActive, !wsConnections.isEmpty else { return }

        let charCount: Int
        let (mode, scrollSpeed) = MainActor.assumeIsolated {
            (TeleprompterService.shared.guidanceMode, TeleprompterService.shared.scrollSpeed)
        }
        let scrollDone = totalCharCount > 0 && charOffsetForWordProgress(timerWordProgress) >= totalCharCount

        switch mode {
        case .wordTracking:
            charCount = speechRecognizer?.recognizedCharCount ?? 0
        case .classic:
            if !scrollDone {
                timerWordProgress += scrollSpeed * 0.1
            }
            charCount = charOffsetForWordProgress(timerWordProgress)
        case .voiceActivated:
            if !scrollDone && speechRecognizer?.isListening == true && (speechRecognizer?.isSpeaking ?? false) {
                timerWordProgress += scrollSpeed * 0.1
            }
            charCount = charOffsetForWordProgress(timerWordProgress)
        }

        let effective = min(charCount, totalCharCount)
        let rawDone = totalCharCount > 0 && effective >= totalCharCount
        let isDone = rawDone && (mode == .wordTracking || hasNextPage)
        let highlightWords = mode == .wordTracking

        let state = TeleprompterBrowserState(
            words: words,
            highlightedCharCount: effective,
            totalCharCount: totalCharCount,
            audioLevels: (speechRecognizer?.audioLevels ?? []).map { Double($0) },
            isListening: speechRecognizer?.isListening ?? false,
            isDone: isDone,
            fontColor: MainActor.assumeIsolated { TeleprompterService.shared.highlightColor.hexString },
            cueColor: "#FFFFFF",
            hasNextPage: hasNextPage,
            isActive: true,
            highlightWords: highlightWords,
            lastSpokenText: speechRecognizer?.lastSpokenText ?? ""
        )
        broadcast(state)
    }

    private func broadcastInactive() {
        let state = TeleprompterBrowserState(
            words: [], highlightedCharCount: 0, totalCharCount: 0,
            audioLevels: [], isListening: false, isDone: false,
            fontColor: "#ffffff", cueColor: "#ffffff", hasNextPage: false, isActive: false,
            highlightWords: true, lastSpokenText: ""
        )
        broadcast(state)
    }

    private func broadcast(_ state: TeleprompterBrowserState) {
        guard !wsConnections.isEmpty, let data = try? JSONEncoder().encode(state) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "ws", metadata: [meta])
        for conn in wsConnections {
            conn.send(content: data, contentContext: ctx, completion: .idempotent)
        }
    }

    private func charOffsetForWordProgress(_ progress: Double) -> Int {
        let wholeWord = Int(progress)
        let frac = progress - Double(wholeWord)
        var offset = 0
        for i in 0..<min(wholeWord, words.count) {
            offset += words[i].count + 1
        }
        if wholeWord < words.count {
            offset += Int(Double(words[wholeWord].count) * frac)
        }
        return min(offset, totalCharCount)
    }

    static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferred: String?
        var fallback: String?

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee
            guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: addr.ifa_name)

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }
            let ip = String(cString: hostname)
            guard ip != "127.0.0.1" else { continue }

            if name == "en0" || name == "en1" {
                preferred = ip
            } else if fallback == nil {
                fallback = ip
            }
        }
        return preferred ?? fallback
    }

    static func generateHTML(wsPort: UInt16) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
        <title>Vorssaint Teleprompter</title>
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        html,body{height:100%;overflow:hidden;background:#000;color:#fff;
          font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Helvetica Neue',system-ui,sans-serif}
        body{display:flex;flex-direction:column}
        #waiting{flex:1;display:flex;flex-direction:column;align-items:center;
          justify-content:center;gap:16px}
        #waiting .icon{font-size:48px}
        #waiting .title{font-size:20px;font-weight:600;color:rgba(255,255,255,.6);
          animation:pulse 2s ease-in-out infinite}
        #waiting .sub{font-size:14px;color:rgba(255,255,255,.3);text-align:center;
          max-width:320px;line-height:1.5}
        #waiting .url{font-size:12px;color:rgba(255,255,255,.15);margin-top:8px;
          font-family:ui-monospace,monospace}
        @keyframes pulse{0%,100%{opacity:.6}50%{opacity:1}}
        #main{display:none;flex-direction:column;height:100%}
        #prompter-wrap{flex:1;position:relative;overflow:hidden}
        #prompter-wrap::before,#prompter-wrap::after{
          content:'';position:absolute;left:0;right:0;z-index:2;pointer-events:none}
        #prompter-wrap::before{top:0;height:8%;
          background:linear-gradient(to bottom,#000,transparent)}
        #prompter-wrap::after{bottom:0;height:8%;
          background:linear-gradient(to top,#000,transparent)}
        #prompter{height:100%;overflow-y:auto;
          padding:20px max(40px,8%);
          -webkit-overflow-scrolling:touch;scroll-behavior:smooth}
        #prompter::-webkit-scrollbar{display:none}
        #text-container{
          font-size:clamp(44px,calc(100vw / 14),92px);
          font-weight:600;line-height:1.4;word-wrap:break-word}
        .w{display:inline;transition:color .12s ease}
        .w.ann{font-style:italic}
        #bar{flex-shrink:0;padding:12px max(40px,8%) 40px;
          display:flex;align-items:center;gap:16px}
        #waveform{width:240px;height:32px;display:flex;align-items:center;gap:1.5px}
        .wf{width:3px;background:rgba(255,255,255,.15);border-radius:1.5px;
          min-height:3px;transition:height .08s ease,background .12s ease;align-self:center}
        #spoken{font-size:18px;font-weight:500;color:rgba(255,255,255,.5);
          flex:1;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;
          direction:rtl;text-align:left}
        </style>
        </head>
        <body>
        <div id="waiting">
          <div class="icon">🎙️</div>
          <div class="title">Waiting for script…</div>
          <div class="sub">Open Teleprompter in Vorssaint and start speaking or play the script.</div>
          <div class="url" id="conn-url"></div>
        </div>
        <div id="main">
          <div id="prompter-wrap">
            <div id="prompter">
              <div id="text-container"></div>
            </div>
          </div>
          <div id="bar">
            <div id="waveform"></div>
            <div id="spoken"></div>
          </div>
        </div>
        <script>
        (function(){
          const host=location.hostname||'localhost';
          const wsUrl='ws://'+host+':\(wsPort)';
          document.getElementById('conn-url').textContent=location.host;
          const wfBox=document.getElementById('waveform');
          for(let i=0;i<30;i++){const b=document.createElement('div');b.className='wf';wfBox.appendChild(b)}
          const bars=wfBox.children;
          let ws,currentWords=[];
          function connect(){
            ws=new WebSocket(wsUrl);
            ws.onmessage=e=>{try{render(JSON.parse(e.data))}catch(err){}};
            ws.onclose=()=>setTimeout(connect,1000);
          }
          function render(s){
            const wait=document.getElementById('waiting');
            const main=document.getElementById('main');
            if(!s.isActive){wait.style.display='flex';main.style.display='none';return}
            wait.style.display='none';main.style.display='flex';
            const tc=document.getElementById('text-container');
            if(JSON.stringify(currentWords)!==JSON.stringify(s.words)){
              currentWords=s.words;
              tc.innerHTML=s.words.map((w,i)=>'<span class="w" id="w'+i+'">'+w+' </span>').join('');
            }
            let charAcc=0;
            for(let i=0;i<s.words.length;i++){
              const el=document.getElementById('w'+i);
              if(!el)continue;
              charAcc+=s.words[i].length+1;
              if(charAcc<=s.highlightedCharCount){
                el.style.color=s.fontColor;
                el.style.opacity='1';
              } else {
                el.style.color='#fff';
                el.style.opacity='0.25';
              }
            }
            if(s.audioLevels){
              for(let i=0;i<bars.length;i++){
                const lvl=s.audioLevels[i]||0;
                bars[i].style.height=Math.max(3,lvl*32)+'px';
              }
            }
            document.getElementById('spoken').textContent=s.lastSpokenText||'';
          }
          connect();
        })();
        </script>
        </body>
        </html>
        """
    }
}
