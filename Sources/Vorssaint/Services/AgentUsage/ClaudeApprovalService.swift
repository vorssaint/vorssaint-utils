// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

/// Listens for the `--claude-hook` and `--codex-hook` relays and holds at most one request. A new
/// request releases the one before it, and so do the deadline, `stop()` and an
/// answer given in the terminal. Releasing closes the connection without a
/// reply, which Claude Code reads as "no decision", so its own prompt stays in
/// charge. All socket and file work runs on one serial queue; `pending` is
/// published on the main queue.
final class ClaudeApprovalService: ObservableObject {
    static let shared = ClaudeApprovalService(
        socketPath: PrivateFileStore.containerURL.flatMap(ClaudeApprovalSupport.socketPath(container:)))

    @Published private(set) var pending: ClaudeApprovalRequest?

    let socketPath: String?
    let settingsURL: URL
    let codexSettingsURL: URL
    var pendingSeconds = ClaudeApprovalSupport.pendingSeconds
    var transcriptInterval: TimeInterval = 0.5

    private static let payloadLimit = 4 << 20
    private static let transcriptLookback: UInt64 = 256 << 10

    private let queue = DispatchQueue(label: "vorssaint.claude-approvals")
    private var listener: DispatchSourceRead?
    private var listenerFD: Int32 = -1
    private var connections: [Int32: Connection] = [:]
    private var current: Connection?
    private var nextID = 0

    private final class Connection {
        let fd: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        var request: ClaudeApprovalRequest?
        var deadline: DispatchSourceTimer?
        var transcript: DispatchSourceTimer?
        var transcriptOffset: UInt64 = 0
        var toolUseID: String?
        init(fd: Int32) { self.fd = fd }
    }

    init(socketPath: String?, settingsURL: URL = ClaudeApprovalSupport.settingsURL(for: .claude),
         codexSettingsURL: URL = ClaudeApprovalSupport.settingsURL(for: .codex)) {
        self.socketPath = socketPath
        self.settingsURL = settingsURL
        self.codexSettingsURL = codexSettingsURL
    }

    // MARK: Lifecycle

    func syncWithPreferences() {
        ClaudeApprovalSupport.isEnabled() ? start() : stop()
    }

    func start() {
        queue.sync {
            guard listener == nil, let socketPath else { return }
            if let container = PrivateFileStore.containerURL, socketPath.hasPrefix(container.path) {
                PrivateFileStore.createDirectory(at: container)
            }
            guard let fd = Self.listen(at: socketPath) else { return }
            listenerFD = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.accept() }
            source.setCancelHandler { Darwin.close(fd) }
            listener = source
            source.resume()
        }
    }

    func stop() {
        queue.sync {
            release()
            listener?.cancel()
            listener = nil
            if listenerFD >= 0, let socketPath { unlink(socketPath) }
            listenerFD = -1
        }
    }

    // MARK: Answers

    func answer(_ decision: ClaudeApprovalDecision, to request: ClaudeApprovalRequest) {
        queue.async { [self] in
            guard let connection = current, let held = connection.request, held.id == request.id,
                  ClaudeApprovalSupport.accepts(decision, for: held)
            else { return }
            let reply = ClaudeApprovalSupport.reply(decision, for: held)
            _ = reply.withUnsafeBytes { write(connection.fd, $0.baseAddress, $0.count) }
            release()
        }
    }

    // MARK: Socket

    private static func listen(at path: String) -> Int32? {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(fd); return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else { Darwin.close(fd); return nil }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    private func accept() {
        let fd = Darwin.accept(listenerFD, nil, nil)
        guard fd >= 0 else { return }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let connection = Connection(fd: fd)
        connections[fd] = connection
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        connection.source = source
        source.setEventHandler { [weak self] in
            if let connection = self?.connections[fd] { self?.read(connection) }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    private func read(_ connection: Connection) {
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        let count = Darwin.read(connection.fd, &chunk, chunk.count)
        if count < 0, errno == EAGAIN || errno == EINTR { return }
        guard count > 0 else { return drop(connection) }
        // A request is one line; anything after it is ignored.
        guard connection.request == nil else { return }
        let newline = chunk[..<count].firstIndex(of: 0x0A)
        connection.buffer.append(contentsOf: chunk[..<(newline ?? count)])
        guard connection.buffer.count <= Self.payloadLimit else { return drop(connection) }
        guard newline != nil else { return }
        let prefix = Data(ClaudeApprovalRelay.codexPrefix.utf8)
        let codex = connection.buffer.starts(with: prefix)
        guard var request = ClaudeApprovalSupport.parseRequest(codex ? connection.buffer.dropFirst(prefix.count) : connection.buffer,
                                                               agent: codex ? .codex : .claude)
        else { return drop(connection) }
        connection.buffer = Data()
        nextID += 1
        request.id = nextID
        connection.request = request
        release()
        current = connection
        armDeadline(connection)
        watchTranscript(connection)
        publish(request)
    }

    /// The client went away, or sent something that is not a request.
    private func drop(_ connection: Connection) {
        if current === connection { return release() }
        close(connection)
    }

    private func close(_ connection: Connection) {
        connection.deadline?.cancel()
        connection.transcript?.cancel()
        connection.source?.cancel()
        connections[connection.fd] = nil
    }

    private func release() {
        guard let connection = current else { return }
        current = nil
        close(connection)
        publish(nil)
    }

    private func publish(_ request: ClaudeApprovalRequest?) {
        DispatchQueue.main.async { [weak self] in
            if self?.pending != request { self?.pending = request }
        }
    }

    private func armDeadline(_ connection: Connection) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pendingSeconds)
        timer.setEventHandler { [weak self, weak connection] in
            if let connection, self?.current === connection { self?.release() }
        }
        connection.deadline = timer
        timer.resume()
    }

    // MARK: Transcript

    private func watchTranscript(_ connection: Connection) {
        guard let path = connection.request?.transcriptPath,
              let handle = FileHandle(forReadingAtPath: path)
        else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > Self.transcriptLookback ? size - Self.transcriptLookback : 0
        try? handle.seek(toOffset: start)
        var lines = completeLines(handle.readData(ofLength: Int(size - start)), from: start, connection: connection)
        // A lookback that starts mid-line loses only that partial first line.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        if let request = connection.request {
            _ = ClaudeApprovalSupport.scanTranscript(lines, for: request, toolUseID: &connection.toolUseID,
                                                     counting: false)
        }
        // ponytail: polls a single file while one card is up; a vnode source if that ever matters.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + transcriptInterval, repeating: transcriptInterval)
        timer.setEventHandler { [weak self, weak connection] in
            if let connection { self?.pollTranscript(connection, path: path) }
        }
        connection.transcript = timer
        timer.resume()
    }

    private func pollTranscript(_ connection: Connection, path: String) {
        guard current === connection, let request = connection.request,
              let handle = FileHandle(forReadingAtPath: path)
        else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: connection.transcriptOffset)
        let lines = completeLines(handle.readDataToEndOfFile(), from: connection.transcriptOffset, connection: connection)
        if ClaudeApprovalSupport.scanTranscript(lines, for: request, toolUseID: &connection.toolUseID, counting: true) {
            release()
        }
    }

    /// Lines ending in a newline; a line still being written waits for the next poll.
    private func completeLines(_ data: Data, from offset: UInt64, connection: Connection) -> [Substring] {
        guard let last = data.lastIndex(of: 0x0A) else {
            connection.transcriptOffset = offset
            return []
        }
        let complete = data[data.startIndex...last]
        connection.transcriptOffset = offset + UInt64(complete.count)
        return String(decoding: complete, as: UTF8.self).split(separator: "\n")
    }

    // MARK: settings.json and hooks.json

    func settingsURL(for agent: AgentProvider) -> URL {
        agent == .codex ? codexSettingsURL : settingsURL
    }

    func hookCommand(for agent: AgentProvider = .claude) -> String? {
        guard let executable = Bundle.main.executablePath, let socketPath else { return nil }
        return ClaudeApprovalSupport.hookCommand(executable: executable, socket: socketPath, agent: agent)
    }

    private func settingsData(_ agent: AgentProvider) -> Data? {
        try? Data(contentsOf: settingsURL(for: agent))
    }

    func hookStatus(for agent: AgentProvider = .claude) -> ClaudeHookStatus {
        ClaudeApprovalSupport.status(of: settingsData(agent), command: hookCommand(for: agent) ?? "")
    }

    func foreignHooks(for agent: AgentProvider = .claude) -> [String] {
        ClaudeApprovalSupport.parseSettings(settingsData(agent)).map(ClaudeApprovalSupport.foreignPermissionHooks) ?? []
    }

    /// The file as it is and as installing (or uninstalling) would write it.
    /// nil when the file cannot be parsed, in which case nothing is written.
    func proposedSettings(agent: AgentProvider = .claude, installing: Bool) -> (old: String, new: String)? {
        let data = settingsData(agent)
        guard let settings = ClaudeApprovalSupport.parseSettings(data) else { return nil }
        let changed: [String: Any]
        if installing {
            guard let command = hookCommand(for: agent) else { return nil }
            changed = ClaudeApprovalSupport.installing(settings, command: command)
        } else {
            changed = ClaudeApprovalSupport.uninstalling(settings)
        }
        let old = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return (old, String(decoding: ClaudeApprovalSupport.render(changed), as: UTF8.self))
    }

    /// Backs the current file up byte for byte, then writes atomically.
    @discardableResult
    func writeSettings(agent: AgentProvider = .claude, installing: Bool, now: Date = Date()) -> Bool {
        guard let proposed = proposedSettings(agent: agent, installing: installing) else { return false }
        let url = settingsURL(for: agent)
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent(ClaudeApprovalSupport.backupName(file: url.lastPathComponent, date: now))
            guard (try? manager.copyItem(at: url, to: backup)) != nil else { return false }
        } else {
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return (try? Data(proposed.new.utf8).write(to: url, options: .atomic)) != nil
    }
}
