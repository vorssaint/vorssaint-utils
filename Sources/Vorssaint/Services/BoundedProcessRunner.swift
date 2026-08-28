// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

final class CancellationToken: @unchecked Sendable {
    typealias Handler = () -> Void

    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [UUID: Handler] = [:]

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let pendingHandlers = Array(handlers.values)
        handlers.removeAll()
        lock.unlock()
        pendingHandlers.forEach { $0() }
    }

    @discardableResult
    func register(_ handler: @escaping Handler) -> UUID? {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return nil
        }
        let id = UUID()
        handlers[id] = handler
        lock.unlock()
        return id
    }

    func unregister(_ id: UUID?) {
        guard let id else { return }
        lock.lock()
        handlers[id] = nil
        lock.unlock()
    }
}

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

enum BoundedProcessRunner {
    struct Result {
        let status: Int32
        let output: Data
        let timedOut: Bool
    }

    static func run(_ path: String,
                    _ arguments: [String],
                    timeout: TimeInterval?,
                    maxOutputBytes: Int,
                    environment: [String: String]? = nil,
                    cancellationToken: CancellationToken? = nil) -> Result {
        guard cancellationToken?.isCancelled != true else {
            return Result(status: -1, output: Data(), timedOut: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

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

        // The child is watched through its termination handler. A blocking
        // `waitUntilExit()` has to be parked on a thread of its own, and the
        // timeout below makes `run` walk away from it while it still holds one
        // worker of the shared 64-thread pool. Those abandoned waits pile up
        // faster than they drain, and a full pool starves every later user of
        // it, the main thread's window walk included (issue #971). It also
        // starves this runner, which then reports timeouts for commands that
        // exited at once and abandons another wait doing it. A termination
        // handler occupies no thread, so none of that accumulates.
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            try? reader.close()
            return Result(status: -1, output: Data(), timedOut: false)
        }

        let cancellationRegistration = cancellationToken?.register {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        defer { cancellationToken?.unregister(cancellationRegistration) }

        let deadline = timeout.map { DispatchTime.now() + max(0, $0) } ?? .distantFuture
        var didFinish = finished.wait(timeout: deadline) == .success
        let timedOut = !didFinish
        if timedOut {
            process.terminate()
            didFinish = finished.wait(timeout: .now() + 0.5) == .success
            if !didFinish {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
        }

        // A child may inherit stdout after the command itself exits. Give an
        // ordinary EOF a moment to deliver the tail, then close our descriptor
        // so that inherited handle cannot leave a reader alive indefinitely.
        _ = drained.wait(timeout: .now() + 0.2)
        reader.readabilityHandler = nil
        try? reader.close()

        return Result(status: timedOut ? -1 : process.terminationStatus,
                      output: output.value(),
                      timedOut: timedOut)
    }
}
