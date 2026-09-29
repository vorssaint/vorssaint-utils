// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let available = max(0, limit - data.count)
        if available > 0 { data.append(chunk.prefix(available)) }
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Cancellation owns one process launch; the lock closes the gap between
/// cancelling a queued request and that request launching its child.
final class BoundedProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let child = process
        lock.unlock()
        guard let child, child.isRunning else { return }
        child.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    fileprivate func launch(_ child: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, process == nil else { throw CancellationError() }
        try child.run()
        process = child
    }

    fileprivate func release(_ child: Process) {
        lock.lock()
        defer { lock.unlock() }
        if process === child { process = nil }
    }
}

/// What the bounded wait needs from a child, however it was started.
private struct BoundedChild {
    let pid: pid_t
    let terminate: () -> Void
    let status: () -> Int32
}

/// The raw wait status, written before the exit is signalled and read only
/// after that signal has been received.
private final class BoundedExitStatus: @unchecked Sendable {
    var raw: Int32 = 0
}

enum BoundedProcessRunner {
    struct Result {
        let status: Int32
        let output: Data
        let timedOut: Bool
    }

    static func run(_ path: String,
                    _ arguments: [String],
                    timeout: TimeInterval,
                    maxOutputBytes: Int,
                    environment: [String: String]? = nil,
                    cancellation: BoundedProcessCancellation? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        defer { cancellation?.release(process) }
        return collect(from: pipe, timeout: timeout, maxOutputBytes: maxOutputBytes) { finished in
            // The child is watched through its termination handler. A blocking
            // `waitUntilExit()` has to be parked on a thread of its own, and the
            // timeout below makes `run` walk away from it while it still holds one
            // worker of the shared 64-thread pool. Those abandoned waits pile up
            // faster than they drain, and a full pool starves every later user of
            // it, the main thread's window walk included (issue #971). It also
            // starves this runner, which then reports timeouts for commands that
            // exited at once and abandons another wait doing it. A termination
            // handler occupies no thread, so none of that accumulates.
            process.terminationHandler = { _ in finished.signal() }
            if let cancellation { try cancellation.launch(process) }
            else { try process.run() }
            return BoundedChild(pid: process.processIdentifier,
                                terminate: { process.terminate() },
                                status: { process.terminationStatus })
        }
    }

    /// Runs the child as the leader of a session of its own, with no
    /// controlling terminal and stdin from /dev/null, which is what it has when
    /// the app is launched from Finder. `Process` leaves a child the terminal
    /// the app was started from but puts it in a process group of its own, so
    /// an interactive shell that tries to take that terminal over is stopped
    /// and only ends at the timeout. This path takes no cancellation.
    static func runInNewSession(_ path: String,
                                _ arguments: [String],
                                timeout: TimeInterval,
                                maxOutputBytes: Int,
                                environment: [String: String]? = nil) -> Result {
        let pipe = Pipe()
        return collect(from: pipe, timeout: timeout, maxOutputBytes: maxOutputBytes) { finished in
            // Only the child keeps the write end, so its exit reaches the reader as EOF.
            defer { try? pipe.fileHandleForWriting.close() }
            let pid = try spawnInNewSession(path, arguments, environment: environment,
                                            output: pipe.fileHandleForWriting.fileDescriptor)
            // Watched by a process source for the reason `run` gives, on a
            // serial queue so a starved global pool cannot hold back the reap.
            let exitStatus = BoundedExitStatus()
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit,
                                                          queue: exitQueue)
            source.setEventHandler {
                var raw: Int32 = 0
                while waitpid(pid, &raw, 0) == -1 && errno == EINTR {}
                exitStatus.raw = raw
                source.cancel()
                finished.signal()
            }
            source.resume()
            return BoundedChild(pid: pid,
                                terminate: { kill(pid, SIGTERM) },
                                status: {
                                    // What `Process.terminationStatus` reports: the
                                    // exit code, or the signal that ended the child.
                                    let signal = exitStatus.raw & 0x7f
                                    return signal == 0 ? (exitStatus.raw >> 8) & 0xff : signal
                                })
        }
    }

    private static let exitQueue = DispatchQueue(label: "BoundedProcessRunner.exit")

    private static func collect(from pipe: Pipe,
                                timeout: TimeInterval,
                                maxOutputBytes: Int,
                                launch: (DispatchSemaphore) throws -> BoundedChild) -> Result {
        let output = BoundedProcessOutput(limit: maxOutputBytes)
        let drained = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                drained.signal()
            } else {
                // Keep draining after the retained prefix is full so the child
                // can never block on a full pipe or turn output into memory use.
                output.append(chunk)
            }
        }

        let finished = DispatchSemaphore(value: 0)
        let child: BoundedChild
        do {
            child = try launch(finished)
        } catch {
            reader.readabilityHandler = nil
            try? reader.close()
            return Result(status: -1, output: Data(), timedOut: false)
        }

        var didFinish = finished.wait(timeout: .now() + max(0, timeout)) == .success
        let timedOut = !didFinish
        if timedOut {
            child.terminate()
            didFinish = finished.wait(timeout: .now() + 0.5) == .success
            if !didFinish {
                kill(child.pid, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
        }

        // A child may inherit stdout after the command itself exits. Give an
        // ordinary EOF a moment to deliver the tail, then close our descriptor
        // so that inherited handle cannot leave a reader alive indefinitely.
        _ = drained.wait(timeout: .now() + 0.2)
        reader.readabilityHandler = nil
        try? reader.close()

        return Result(status: timedOut ? -1 : child.status(),
                      output: output.value(),
                      timedOut: timedOut)
    }

    /// No descriptor of the app reaches the child besides the three set here,
    /// and signal handling starts from the defaults, as it does under `Process`.
    private static func spawnInNewSession(_ path: String,
                                          _ arguments: [String],
                                          environment: [String: String]?,
                                          output: Int32) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                    | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        sigdelset(&defaultSignals, SIGKILL)
        sigdelset(&defaultSignals, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output, STDERR_FILENO)

        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envp = (environment ?? ProcessInfo.processInfo.environment)
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let error = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        guard error == 0 else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EINVAL) }
        return pid
    }
}
