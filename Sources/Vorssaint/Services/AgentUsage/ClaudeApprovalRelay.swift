// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin

/// The `--claude-hook <socket>` mode Claude Code runs for a PermissionRequest,
/// and `--codex-hook <socket>`, its twin for Codex.
/// It hands the hook payload to the running app over a Unix socket and copies
/// the app's reply to stdout. Every failure exits 0 with no output, which
/// Claude Code reads as "no decision" and answers with its own prompt. It runs
/// before anything else in `main`, touches no Foundation or bundle state, and
/// so costs Claude Code a process launch and nothing more.
enum ClaudeApprovalRelay {
    static let argument = "--claude-hook"
    static let codexArgument = "--codex-hook"
    /// Marks a Codex payload on the shared socket; the rest of the line is the same JSON.
    static let codexPrefix = "codex "
    private static let inputLimit = 4 << 20
    private static let replyLimit = 64 << 10
    private static let deadlineSeconds = 115

    static func runIfRequestedAndExit() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(where: { $0 == argument || $0 == codexArgument }) else { return }
        guard arguments.indices.contains(index + 1) else { exit(0) }
        relay(socketPath: arguments[index + 1], codex: arguments[index] == codexArgument)
        exit(0)
    }

    private static func relay(socketPath: String, codex: Bool) {
        guard var payload = readAll(STDIN_FILENO, limit: inputLimit) else { return }
        // The app reads one line; raw line breaks never appear inside valid JSON.
        payload.removeAll { $0 == 0x0A || $0 == 0x0D }
        payload.append(0x0A)
        if codex { payload.insert(contentsOf: codexPrefix.utf8, at: 0) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return }

        // No half-close: the app reads one line, and EOF on its side means
        // Claude Code killed this process, which clears the card.
        guard writeAll(fd, payload) else { return }

        let deadline = time(nil) + deadlineSeconds
        var reply: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 16 << 10)
        while reply.count <= replyLimit {
            let remaining = deadline - time(nil)
            guard remaining > 0 else { return }
            var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollFD, 1, Int32(remaining) * 1000)
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { return }
            let count = read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            reply.append(contentsOf: buffer[..<count])
        }
        guard !reply.isEmpty, reply.count <= replyLimit else { return }
        _ = writeAll(STDOUT_FILENO, reply)
    }

    private static func readAll(_ fd: Int32, limit: Int) -> [UInt8]? {
        var data: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 << 10)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { return nil }
            if count == 0 { return data }
            data.append(contentsOf: buffer[..<count])
            if data.count > limit { return nil }
        }
    }

    private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let count = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
}
