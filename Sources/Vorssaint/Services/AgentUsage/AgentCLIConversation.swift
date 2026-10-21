// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// One conversation with an agent CLI over its standard input and output,
/// a JSON message a line. Every answer waits on one deadline, so a server
/// that stalls costs the conversation's time at most. Blocks its caller:
/// run it on a work queue of its own. One given a cancellation also ends
/// as soon as that is cancelled, and is gone once `end()` returns.
class AgentCLIConversation {
    /// Far above any answer here; a server that writes more is not one.
    private static let maximumBuffer = 4 << 20

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: DispatchTime
    private let cancellation: BoundedProcessCancellation?
    private let arrived = DispatchSemaphore(value: 0)
    private let exited = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false

    init?(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval,
          cancellation: BoundedProcessCancellation? = nil) {
        self.cancellation = cancellation
        deadline = .now() + timeout
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // Nothing here needs a folder; the root keeps a project's files, or
        // a protected folder the app was opened from, out of the server's way.
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A server that exits early fails a write instead of ending the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return nil }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil }
            self?.receive(chunk)
        }
        process.terminationHandler = { [exited] _ in exited.signal() }
        do {
            // The cancellation holds the server, so cancelling stops it too.
            if let cancellation { try cancellation.launch(process) } else { try process.run() }
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
    }

    /// Closing its input ends the server; one that lingers is stopped.
    func end() {
        try? input.fileHandleForWriting.close()
        let child = process
        if let cancellation {
            // Whoever holds the cancellation starts its servers one after
            // another, so this one is gone before the next can start.
            let leaves = ProcessInfo.processInfo.systemUptime + 0.3
            while child.isRunning, ProcessInfo.processInfo.systemUptime < leaves { usleep(10_000) }
            if child.isRunning { child.terminate() }
            let stops = ProcessInfo.processInfo.systemUptime + 0.5
            while child.isRunning, ProcessInfo.processInfo.systemUptime < stops { usleep(10_000) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            output.fileHandleForReading.readabilityHandler = nil
            cancellation.release(child)
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            guard child.isRunning else { return }
            child.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    /// After `end()`: waits for the server to exit, so what it saves on its
    /// way out is on disk. False when it is still running at the timeout.
    @discardableResult func waitForExit(timeout: TimeInterval) -> Bool {
        exited.wait(timeout: .now() + timeout) == .success
    }

    func send(_ message: [String: Any]) -> Bool {
        if let cancellation, cancellation.isCancelled || DispatchTime.now() >= deadline { return false }
        guard JSONSerialization.isValidJSONObject(message),
              var line = try? JSONSerialization.data(withJSONObject: message, options: .withoutEscapingSlashes)
        else { return false }
        line.append(0x0A)
        do {
            try input.fileHandleForWriting.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }

    private func receive(_ chunk: Data) {
        lock.withLock {
            if chunk.isEmpty || buffer.count + chunk.count > Self.maximumBuffer { closed = true }
            else { buffer.append(chunk) }
        }
        arrived.signal()
    }

    /// The next message, or nil once the server has ended or time is up.
    func next() -> [String: Any]? {
        while true {
            // A server that keeps talking still ends a cancellable one on time.
            if let cancellation, cancellation.isCancelled || DispatchTime.now() >= deadline { return nil }
            let (line, ended): (Data?, Bool) = lock.withLock {
                guard let newline = buffer.firstIndex(of: 0x0A) else { return (nil, closed) }
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                return (line, false)
            }
            if let line {
                if let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { return message }
                continue
            }
            if ended { return nil }
            if cancellation != nil {
                // Looks at the cancellation every tenth of a second instead of
                // waiting out the whole deadline.
                _ = arrived.wait(timeout: min(deadline, .now() + 0.1))
            } else if arrived.wait(timeout: deadline) == .timedOut { return nil }
        }
    }
}
