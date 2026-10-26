// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Only this child writes the temporary setting. EOF covers parent exit and
/// SIGKILL; a heartbeat lease also covers an unresponsive parent. On any helper
/// failure the service restores the journal and requires an explicit retry.
final class TrackpadGuardWatchdog: TrackpadGuardLeaseHandle {
    static let argument = "--trackpad-guard-watchdog"
    private let process: Process
    private let input: FileHandle
    private let finished = DispatchSemaphore(value: 0)
    private let token = UUID()
    private var stopped = false

    init?() {
        guard let executable = Bundle.main.executableURL else { return nil }
        let process = Process()
        let input = Pipe()
        let ready = Pipe()
        self.process = process
        self.input = input.fileHandleForWriting
        process.executableURL = executable
        process.arguments = [Self.argument, token.uuidString]
        process.standardInput = input
        process.standardOutput = ready
        process.standardError = FileHandle.nullDevice
        let finished = self.finished
        process.terminationHandler = { _ in finished.signal() }
        // Writing after the child exits must return EPIPE, never kill the app.
        guard fcntl(self.input.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            stopped = true
            return nil
        }
        do { try process.run() } catch {
            stopped = true
            return nil
        }
        var descriptor = pollfd(fd: ready.fileHandleForReading.fileDescriptor,
                                events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 2000) > 0,
              (try? ready.fileHandleForReading.read(upToCount: 1)) == Data([1]) else {
            _ = stop()
            return nil
        }
    }

    func heartbeat() -> Bool {
        guard !stopped, process.isRunning else { return false }
        do { try input.write(contentsOf: Data([1])); return true }
        catch { return false }
    }

    @discardableResult
    func stop() -> Bool {
        guard !stopped else { return !TrackpadGuardRecovery.hasPendingEntry }
        stopped = true
        try? input.close()
        if finished.wait(timeout: .now() + 1.5) != .success {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 0.5)
        }
        return TrackpadGuardRecovery.restorePending(expectedToken: token)
    }

    deinit { if !stopped { _ = stop() } }

    static func runIfRequestedAndExit() {
        guard CommandLine.arguments.contains(argument) else { return }
        guard let raw = CommandLine.arguments.last, let token = UUID(uuidString: raw) else { exit(EXIT_FAILURE) }
        let success = TrackpadGuardRecovery.withLock { () -> Bool in
            guard TrackpadGuardRecovery.restoreLocked(),
                  let original = TrackpadGuardRuntime.read(),
                  TrackpadGuardRecovery.record(original: original, token: token) else { return false }
            guard TrackpadGuardRuntime.set(1) else {
                _ = TrackpadGuardRecovery.restoreLocked(expectedToken: token)
                return false
            }
            _ = fcntl(STDOUT_FILENO, F_SETNOSIGPIPE, 1)
            do { try FileHandle.standardOutput.write(contentsOf: Data([1])) }
            catch { return TrackpadGuardRecovery.restoreLocked(expectedToken: token) }
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            while true {
                let result = poll(&descriptor, 1, 3000)
                if result < 0 && errno == EINTR { continue }
                if result <= 0 { break }
                var bytes = [UInt8](repeating: 0, count: 64)
                if read(STDIN_FILENO, &bytes, bytes.count) <= 0 { break }
            }
            return TrackpadGuardRecovery.restoreLocked(expectedToken: token)
        } ?? false
        exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
