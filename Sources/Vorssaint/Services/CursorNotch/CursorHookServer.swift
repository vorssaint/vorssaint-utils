// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import os

struct CursorHookServerConfiguration: Sendable {
    var socketPath: String
    var maxConnections: Int = 32
    var maxHeldApprovals: Int = 8
    var overflowReply = CursorHookReply(stdout: CursorHookProtocol.deniedStdout(), exitCode: 0)
    var stopReply = CursorHookReply(stdout: CursorHookProtocol.deniedStdout(), exitCode: 0)
    /// Per-hook answers used when the queue is full or the app quits mid-wait.
    var overflow: (@Sendable (CursorHookMessage) -> CursorHookReply)? = nil
    var stopped: (@Sendable (CursorHookMessage) -> CursorHookReply)? = nil
    var decide: @Sendable (CursorHookMessage) -> CursorHookReply?
    /// A held approval's id, so a later decision can finish that connection.
    var onHold: @Sendable (UUID, CursorHookMessage) -> Void = { _, _ in }
    var onOverflow: @Sendable () -> Void = {}
    /// Every accepted hook, delivered on the main queue.
    var onMessage: @Sendable (CursorHookMessage) -> Void = { _ in }
}

/// Owner-only Unix socket. Accepts on its own queue and only hops to the main
/// actor when an approval cannot be held.
final class CursorHookServer: @unchecked Sendable {
    private struct Held {
        var fd: Int32
        var hook: String
        var stopReply: CursorHookReply
    }

    private struct State {
        var running = false
        var listenFD: Int32 = -1
        var wakeRead: Int32 = -1
        var wakeWrite: Int32 = -1
        var connections = 0
        var held: [UUID: Held] = [:]
        var configuration: CursorHookServerConfiguration?
        var stopped = DispatchSemaphore(value: 0)
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "com.vorssaint.cursor-hook")

    func start(_ configuration: CursorHookServerConfiguration) -> Bool {
        let already = state.withLock { current -> Bool in
            current.running && current.configuration?.socketPath == configuration.socketPath
        }
        if already {
            state.withLock { $0.configuration = configuration }
            return true
        }
        if state.withLock(\.running) { stop() }
        let parent = URL(fileURLWithPath: configuration.socketPath).deletingLastPathComponent().path
        guard CursorHookProtocol.createOwnerOnlyDirectory(parent),
              removeStaleSocket(configuration.socketPath),
              let listening = listen(at: configuration.socketPath) else { return false }
        var ends: [Int32] = [-1, -1]
        guard pipe(&ends) == 0 else {
            _ = Darwin.close(listening)
            return false
        }
        for end in ends { _ = fcntl(end, F_SETFD, FD_CLOEXEC) }
        let wakeRead = ends[0]
        let wakeWrite = ends[1]
        let stopped = DispatchSemaphore(value: 0)
        state.withLock { current in
            current.running = true
            current.listenFD = listening
            current.wakeRead = wakeRead
            current.wakeWrite = wakeWrite
            current.connections = 0
            current.held = [:]
            current.configuration = configuration
            current.stopped = stopped
        }
        queue.async { [weak self] in self?.loop(stopped: stopped) }
        return true
    }

    func heldApprovals() -> Int {
        state.withLock { $0.held.count }
    }

    func complete(_ id: UUID, reply: CursorHookReply) {
        let held = state.withLock { current -> Held? in
            guard let held = current.held.removeValue(forKey: id) else { return nil }
            current.connections = max(0, current.connections - 1)
            return held
        }
        guard let held else { return }
        write(reply, hook: held.hook, fd: held.fd)
        _ = Darwin.close(held.fd)
    }

    func stop() {
        let snapshot = state.withLock { current -> (Bool, Int32, DispatchSemaphore) in
            let running = current.running
            current.running = false
            return (running, current.wakeWrite, current.stopped)
        }
        guard snapshot.0 else { return }
        var byte: UInt8 = 1
        _ = Darwin.write(snapshot.1, &byte, 1)
        _ = snapshot.2.wait(timeout: .now() + 2)
    }

    private func loop(stopped: DispatchSemaphore) {
        defer { stopped.signal() }
        while state.withLock(\.running) {
            let fds = state.withLock { ($0.listenFD, $0.wakeRead) }
            var polls = [
                pollfd(fd: fds.0, events: Int16(POLLIN), revents: 0),
                pollfd(fd: fds.1, events: Int16(POLLIN), revents: 0),
            ]
            let ready = polls.withUnsafeMutableBufferPointer { pointer -> Int32 in
                guard let base = pointer.baseAddress else { return -1 }
                return poll(base, nfds_t(pointer.count), -1)
            }
            if ready < 0 { if errno == EINTR { continue }; break }
            if polls[1].revents != 0 || !state.withLock(\.running) { break }
            if polls[0].revents != 0 { acceptOne() }
        }
        let snapshot = state.withLock { current -> (Int32, Int32, Int32, [Held]) in
            let held = Array(current.held.values)
            current.held = [:]
            current.connections = 0
            let listen = current.listenFD
            let wakeRead = current.wakeRead
            let wakeWrite = current.wakeWrite
            current.listenFD = -1
            current.wakeRead = -1
            current.wakeWrite = -1
            current.running = false
            return (listen, wakeRead, wakeWrite, held)
        }
        for held in snapshot.3 {
            write(held.stopReply, hook: held.hook, fd: held.fd)
            _ = Darwin.close(held.fd)
        }
        if snapshot.0 >= 0 { _ = Darwin.close(snapshot.0) }
        if snapshot.1 >= 0 { _ = Darwin.close(snapshot.1) }
        if snapshot.2 >= 0 { _ = Darwin.close(snapshot.2) }
    }

    private func acceptOne() {
        let listen = state.withLock(\.listenFD)
        var client = sockaddr_un()
        var length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let fd = withUnsafeMutablePointer(to: &client) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.accept(listen, address, &length)
            }
        }
        guard fd >= 0 else { return }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        CursorHookSocket.setNoSigPipe(fd)
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, CursorHookProtocol.peerBelongsToCurrentUser(uid) else {
            _ = Darwin.close(fd)
            return
        }
        let room = state.withLock { current -> Bool in
            guard current.connections < (current.configuration?.maxConnections ?? 32) else { return false }
            current.connections += 1
            return true
        }
        guard room else {
            _ = Darwin.close(fd)
            return
        }
        let wake = state.withLock(\.wakeRead)
        let read = CursorHookSocket.readLine(fd: fd, maxBytes: CursorHookProtocol.maxAcceptedBytes,
                                              timeout: CursorHookProtocol.receiveTimeout, wake: wake)
        guard case .line(let line) = read, let message = CursorHookProtocol.decodeRequest(line) else {
            release(fd)
            return
        }
        handle(message, fd: fd)
    }

    private func handle(_ message: CursorHookMessage, fd: Int32) {
        let configuration = state.withLock(\.configuration)
        guard let configuration else { release(fd); return }
        let messageCopy = message
        DispatchQueue.main.async { configuration.onMessage(messageCopy) }
        // `decide` runs on the socket queue and must stay off the notch's state.
        // A nil reply holds an approval, or a stop hook that is waiting for a reply.
        if let reply = configuration.decide(message) {
            write(reply, hook: message.hook, fd: fd)
            release(fd)
            return
        }
        let kind = CursorHookProtocol.kind(of: message.hook)
        guard kind == .approval || kind == .stop else {
            write(.empty, hook: message.hook, fd: fd)
            release(fd)
            return
        }
        let fallback = configuration.stopped?(message) ?? configuration.stopReply
        let heldID = state.withLock { current -> UUID? in
            if kind == .approval {
                let waiting = current.held.values.filter { CursorHookProtocol.kind(of: $0.hook) == .approval }.count
                guard waiting < (current.configuration?.maxHeldApprovals ?? 8) else { return nil }
            }
            let id = UUID()
            current.held[id] = Held(fd: fd, hook: message.hook, stopReply: fallback)
            return id
        }
        guard let heldID else {
            write(configuration.overflow?(message) ?? configuration.overflowReply, hook: message.hook, fd: fd)
            release(fd)
            DispatchQueue.main.async { configuration.onOverflow() }
            return
        }
        DispatchQueue.main.async { configuration.onHold(heldID, message) }
    }

    private func release(_ fd: Int32) {
        _ = Darwin.close(fd)
        state.withLock { current in
            current.connections = max(0, current.connections - 1)
        }
    }

    private func write(_ reply: CursorHookReply, hook: String, fd: Int32) {
        guard let line = CursorHookProtocol.encodeReply(reply, hook: hook) else { return }
        _ = CursorHookSocket.writeAll(fd: fd, data: line)
    }

    private func listen(at path: String) -> Int32? {
        guard let address = CursorHookSocket.address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        CursorHookSocket.setNoSigPipe(fd)
        let bound = address.storage.withSockAddr { pointer, length in
            Darwin.bind(fd, pointer, length)
        }
        // The mode is set before listen, so nothing connects while the socket is still loose.
        // fchmod is rejected for Unix sockets on macOS, so the path is used.
        guard bound == 0, chmod(path, 0o600) == 0, socketIsOwnerOnly(path), Darwin.listen(fd, 32) == 0 else {
            _ = Darwin.close(fd)
            _ = unlink(path)
            return nil
        }
        return fd
    }

    private func socketIsOwnerOnly(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return info.st_uid == getuid() && (info.st_mode & S_IFMT) == S_IFSOCK && (info.st_mode & mode_t(0o077)) == 0
    }

    private func removeStaleSocket(_ path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) != 0 { return errno == ENOENT }
        let type = info.st_mode & S_IFMT
        guard type == S_IFSOCK, info.st_uid == getuid() else { return false }
        return unlink(path) == 0
    }
}
