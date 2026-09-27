// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Keeps synchronous window-server calls off Swift's cooperative executor.
/// Cancellation releases the caller, but an in-flight system call keeps its
/// place until it actually returns. A cancelled queued request never captures.
final class WindowServerCaptureQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vorssaint.window-capture", qos: .userInitiated)
    private let lock = NSLock()
    private var pendingCount = 0

    func capture<Value>(waitingForOtherCaptures: Bool = true,
                        _ operation: @escaping () -> Value?) async -> Value? {
        guard !Task.isCancelled else { return nil }
        let request = Request<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request.install(continuation) else { return }
                let accepted = lock.withLock {
                    guard waitingForOtherCaptures || pendingCount == 0 else { return false }
                    pendingCount += 1
                    return true
                }
                guard accepted else {
                    request.finish(nil)
                    return
                }
                queue.async {
                    let value = request.isFinished ? nil : autoreleasepool(invoking: operation)
                    self.lock.withLock { self.pendingCount -= 1 }
                    request.finish(value)
                }
            }
        } onCancel: {
            request.finish(nil)
        }
    }

    private final class Request<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value?, Never>?
        private var finished = false

        var isFinished: Bool { lock.withLock { finished } }

        func install(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
            let installed = lock.withLock {
                guard !finished else { return false }
                self.continuation = continuation
                return true
            }
            if !installed { continuation.resume(returning: nil) }
            return installed
        }

        func finish(_ value: Value?) {
            let continuation = lock.withLock {
                finished = true
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume(returning: value)
        }
    }
}
