// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

struct AgentAskQuestion: Identifiable {
    struct Option: Identifiable { let id = UUID(); let label: String; let detail: String }
    let id = UUID()
    let text: String
    let header: String
    let options: [Option]
    let multiSelect: Bool
}

/// One question or permission request from a coding agent, held until the
/// person answers on the island. The agent's hook is waiting on `fd`.
final class AgentAskRequest: Identifiable {
    enum Kind {
        case questions([AgentAskQuestion])
        case permission(tool: String, summary: String)
    }
    let id = UUID()
    let agent: String
    let project: String
    let kind: Kind
    /// The tool's own input, sent back with the answers added.
    let toolInput: [String: Any]
    fileprivate let fd: Int32
    fileprivate var watcher: DispatchSourceRead?
    fileprivate var timeout: DispatchWorkItem?

    fileprivate init(agent: String, project: String, kind: Kind, toolInput: [String: Any], fd: Int32) {
        self.agent = agent; self.project = project; self.kind = kind; self.toolInput = toolInput; self.fd = fd
    }
}

/// Questions from Claude Code, as pop-ups on the island. A hook in Claude
/// Code's settings sends each question to this socket and waits; the answer
/// clicked on the island goes back through it, and Claude Code carries on as
/// if it had been answered in the terminal. "Answer in terminal" hands the
/// question back untouched. Every request stays on this Mac, in a socket only
/// the person's own account can open.
final class AgentAskService: ObservableObject {
    static let shared = AgentAskService()

    @Published private(set) var current: AgentAskRequest?
    private var queue: [AgentAskRequest] = []
    private var listener: DispatchSourceRead?
    private var space: NotchOverlaySpace?
    private var panel: NotchLockScreenPanel?
    private var closeWork: DispatchWorkItem?

    private static let panelSize = CGSize(width: 580, height: 520)
    private static let patience: TimeInterval = 100

    private init() {}

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.agentAskEnabled) }

    // MARK: Switching on and off

    /// At launch and when the switch flips. The first run asks before it edits
    /// Claude Code's settings; declining switches the feature off.
    func sync() {
        guard Self.isEnabled else { stop(); AgentAskInstaller.uninstall(); return }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.agentAskConsentAsked) else {
            DispatchQueue.main.async { [weak self] in self?.askConsent() }
            return
        }
        AgentAskInstaller.install()
        start()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.agentAskEnabled)
        sync()
    }

    private func askConsent() {
        let alert = NSAlert()
        alert.messageText = "Show Claude Code's questions on the island?"
        alert.informativeText = "When Claude Code asks a question or for permission, it can pop up on the island so you can click an answer there. "
            + "To do this Vorssaint adds two hooks to ~/.claude/settings.json and puts a small wrapper in front of your status line, "
            + "which runs your own status line unchanged and lets the AI page show its details. A backup of the file is kept next to it. "
            + "Everything stays on this Mac. You can turn this off any time and your original settings are put back."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)
        let allowed = alert.runModal() == .alertFirstButtonReturn
        UserDefaults.standard.set(true, forKey: DefaultsKey.agentAskConsentAsked)
        UserDefaults.standard.set(allowed, forKey: DefaultsKey.agentAskEnabled)
        sync()
    }

    // MARK: Socket

    static var socketPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.vorssaint.utils", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let path = base.appendingPathComponent("ask.sock").path
        // A socket path has a hard limit of 103 bytes.
        return path.utf8.count < 100 ? path : "/tmp/vorssaint-\(getuid())-ask.sock"
    }

    private func start() {
        guard listener == nil else { return }
        let path = Self.socketPath
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count) { target in
                for (index, byte) in bytes.enumerated() { target[index] = byte }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); return }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { break }
                self?.receive(client)
            }
        }
        source.setCancelHandler { close(fd); unlink(path) }
        source.resume()
        listener = source
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        for request in queue { finish(request, response: nil) }
        queue.removeAll()
        current = nil
        closePanel()
    }

    /// Off the main thread: reads one JSON line from the hook.
    private func receive(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 1_048_576 {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
            if buffer[count - 1] == 10 { break }
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { close(fd); return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { close(fd); return }
            self.enqueue(object, fd: fd)
        }
    }

    // MARK: Requests

    private func enqueue(_ object: [String: Any], fd: Int32) {
        guard Self.isEnabled, let event = object["hook_event_name"] as? String,
              let tool = object["tool_name"] as? String else { reply(fd, nil); return }
        let input = object["tool_input"] as? [String: Any] ?? [:]
        let project = (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let kind: AgentAskRequest.Kind
        if event == "PreToolUse", tool == "AskUserQuestion" {
            let questions = (input["questions"] as? [[String: Any]] ?? []).compactMap { item -> AgentAskQuestion? in
                guard let text = item["question"] as? String else { return nil }
                let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentAskQuestion.Option? in
                    guard let label = option["label"] as? String else { return nil }
                    return AgentAskQuestion.Option(label: label, detail: option["description"] as? String ?? "")
                }
                return AgentAskQuestion(text: text, header: item["header"] as? String ?? "", options: options,
                                        multiSelect: item["multiSelect"] as? Bool == true)
            }
            guard !questions.isEmpty, questions.allSatisfy({ !$0.options.isEmpty }) else { reply(fd, nil); return }
            kind = .questions(questions)
        } else if event == "PermissionRequest", tool != "AskUserQuestion" {
            kind = .permission(tool: tool, summary: Self.summary(of: input))
        } else {
            reply(fd, nil); return
        }
        let request = AgentAskRequest(agent: "Claude Code", project: project, kind: kind, toolInput: input, fd: fd)
        // The hook going away (answered in the terminal, or timed out) drops the pop-up.
        let watcher = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        watcher.setEventHandler { [weak self, weak request] in
            var byte: UInt8 = 0
            if recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0, let self, let request { self.drop(request) }
        }
        watcher.resume()
        request.watcher = watcher
        let work = DispatchWorkItem { [weak self, weak request] in
            if let self, let request { self.finish(request, response: nil); self.advance(removing: request) }
        }
        request.timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.patience, execute: work)
        queue.append(request)
        if current == nil { advance(removing: nil) }
    }

    private static func summary(of input: [String: Any]) -> String {
        for key in ["command", "file_path", "url", "pattern", "path", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty { return String(value.prefix(400)) }
        }
        let data = try? JSONSerialization.data(withJSONObject: input, options: [.withoutEscapingSlashes])
        return String(String(data: data ?? Data(), encoding: .utf8)?.prefix(400) ?? "")
    }

    // MARK: Answering

    func answer(_ request: AgentAskRequest, answers: [String: String]) {
        var input = request.toolInput
        input["answers"] = answers
        let output: [String: Any] = ["hookSpecificOutput": [
            "hookEventName": "PreToolUse", "permissionDecision": "allow",
            "permissionDecisionReason": "Answered on the Vorssaint island", "updatedInput": input]]
        finish(request, response: output)
        advance(removing: request)
    }

    func decide(_ request: AgentAskRequest, allow: Bool) {
        let decision: [String: Any] = allow ? ["behavior": "allow"]
            : ["behavior": "deny", "message": "Denied on the Vorssaint island"]
        finish(request, response: ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
        advance(removing: request)
    }

    /// Hands the question back: the hook says nothing, and the agent asks in
    /// its terminal as it would have without Vorssaint.
    func deferToTerminal(_ request: AgentAskRequest) {
        finish(request, response: nil)
        advance(removing: request)
    }

    private func drop(_ request: AgentAskRequest) {
        finish(request, response: nil)
        advance(removing: request)
    }

    private func finish(_ request: AgentAskRequest, response: [String: Any]?) {
        request.timeout?.cancel(); request.timeout = nil
        request.watcher?.cancel(); request.watcher = nil
        reply(request.fd, response)
    }

    private func reply(_ fd: Int32, _ response: [String: Any]?) {
        if let response, let data = try? JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes]) {
            var line = data
            line.append(10)
            line.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                    if written <= 0 { break }
                    offset += written
                }
            }
        }
        close(fd)
    }

    private func advance(removing request: AgentAskRequest?) {
        if let request { queue.removeAll { $0 === request } }
        current = queue.first
        closeWork?.cancel(); closeWork = nil
        if current != nil { openPanel() } else {
            // The island shrinks back to the camera before its window goes.
            let work = DispatchWorkItem { [weak self] in self?.closePanel() }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    // MARK: Panel

    /// Hangs from the camera like the open island: black, flush with the top
    /// edge, above everything, the lock screen included. The panel is a clear
    /// window larger than the card, and clear pixels let clicks through.
    private func openPanel() {
        guard panel == nil else { return }
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen, let space = NotchOverlaySpace(absoluteLevel: NotchLockScreenSupport.spaceLevel) else { return }
        let size = Self.panelSize
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = NotchLockScreenPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = NotchPanel.normalLevel
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        let inset = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 10
        let host = AgentAskHostingView(rootView: AnyView(AgentAskView(service: self, cameraInset: inset)))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: false)
        space.add(panel)
        panel.orderFrontRegardless()
        NSSound(named: "Tink")?.play()
        self.space = space
        self.panel = panel
    }

    private func closePanel() {
        panel?.orderOut(nil)
        space?.close()
        panel = nil
        space = nil
    }
}

private final class AgentAskHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Hooks in Claude Code's settings

/// Adds and removes Vorssaint's two hooks in ~/.claude/settings.json: one for
/// AskUserQuestion, one for permission requests. Everything else in the file
/// is kept, and a backup is written beside it the first time.
enum AgentAskInstaller {
    private static let marker = "vorssaint-ask-hook"

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.vorssaint.utils/hooks", isDirectory: true)
    }
    private static var scriptURL: URL { supportDirectory.appendingPathComponent("\(marker).pl") }
    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Talks to the socket and prints the answer. Silent on any failure, so
    /// Claude Code just asks in its terminal.
    private static let script = """
    use strict; use IO::Socket::UNIX;
    my $s = IO::Socket::UNIX->new(Peer => $ARGV[0]) or exit 0;
    local $/; my $in = <STDIN>; $in = '' unless defined $in; $in =~ s/\\s+\\z//;
    print $s "$in\\n"; $s->flush;
    $/ = "\\n"; my $out = <$s>; print $out if defined $out;
    exit 0;
    """

    private static func command() -> String {
        "/usr/bin/perl '\(scriptURL.path)' '\(AgentAskService.socketPath)'"
    }

    static func install() {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            var settings = readSettings() ?? [:]
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            for (event, matcher) in [("PreToolUse", "AskUserQuestion"), ("PermissionRequest", "*")] {
                var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
                groups.append(["matcher": matcher,
                               "hooks": [["type": "command", "command": command(), "timeout": 120]]])
                hooks[event] = groups
            }
            settings["hooks"] = hooks
            // The Claude card on the AI page reads the status line's data.
            try ClaudeStatusInstaller.install(into: &settings)
            try write(settings)
        } catch {
            NSLog("Vorssaint: could not install the Claude Code hooks: \(error)")
        }
    }

    static func uninstall() {
        guard var settings = readSettings() else { return }
        let before = NSDictionary(dictionary: settings)
        ClaudeStatusInstaller.uninstall(from: &settings)
        if var hooks = settings["hooks"] as? [String: Any] {
            for event in ["PreToolUse", "PermissionRequest"] {
                guard let groups = hooks[event] as? [[String: Any]] else { continue }
                let kept = groups.filter { !isOurs($0) }
                hooks[event] = kept.isEmpty ? nil : kept
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
        }
        // Nothing of ours was there: the person's file is left exactly as it was.
        guard !before.isEqual(to: settings) else { return }
        try? write(settings)
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func write(_ settings: [String: Any]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = settingsURL.appendingPathExtension("vorssaint-backup")
        if fileManager.fileExists(atPath: settingsURL.path), !fileManager.fileExists(atPath: backup.path) {
            try fileManager.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
