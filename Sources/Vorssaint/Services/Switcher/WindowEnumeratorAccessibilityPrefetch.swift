// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Foundation

/// One app's Accessibility window query, asked while the enumeration's
/// preparation is still going on.
///
/// The application level `kAXWindows` read is the one call in an
/// Accessibility batch that can take a whole messaging timeout: an app that
/// does not answer holds the whole batch for that timeout. The switcher paid
/// for it after every other preparation step, so the timeout landed on the
/// time the user waited after letting go of the shortcut. Asking the source
/// app after WindowServer has fixed its candidate IDs lets that wait run beside
/// metadata collection and preparation. The batch consumes this same answer
/// instead of asking the app a second time.
///
/// Window IDs are captured before Accessibility; full metadata and the per
/// window classification still meet in the batch. Per-window reads retain the
/// original normal-level, screen-frame and bundle-identity inputs.
///
/// The read runs at most once, whatever the number of callers that wait for
/// it. A read that was given up before it started never runs, so a caller
/// that asks the app itself afterwards never asks an app that is still being
/// asked. A read that is already in flight is not interrupted: an
/// Accessibility call cannot be taken back, and the answer it produces is
/// reported as it came.
final class WindowEnumeratorAccessibilityPrefetch<Element> {
    /// The application level answer: the window list the app reported and the
    /// error the read came with.
    struct Query {
        let windows: [Element]?
        let error: AXError
    }

    /// The app this read is about.
    let pid: pid_t

    private let lock = NSCondition()
    private var storedAnswer: Query?
    private var started = false
    private var abandoned = false
    private var readOperation: BlockOperation?
    private let read: () -> Query

    init(pid: pid_t, read: @escaping () -> Query) {
        self.pid = pid
        self.read = read
    }

    /// Asks the app on `queue`. The read runs at most once.
    func start(on queue: OperationQueue, beforeRead: @escaping () -> Bool = { true }) {
        lock.lock()
        guard !abandoned, readOperation == nil else {
            lock.unlock()
            return
        }
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self, let operation, !operation.isCancelled else { return }
            self.lock.lock()
            // A read that was given up before it started never asks the app.
            guard !self.abandoned else {
                self.lock.unlock()
                return
            }
            self.started = true
            self.lock.unlock()
            let answer = beforeRead() ? self.read() : Query(
                windows: nil, error: .cannotComplete)
            self.lock.lock()
            self.storedAnswer = answer
            self.lock.broadcast()
            self.lock.unlock()
        }
        self.readOperation = operation
        lock.unlock()
        queue.addOperation(operation)
    }

    /// The answer, waiting for the read when it is in flight.
    ///
    /// A read that has not started is given up: it never got a worker, and
    /// the caller asks the app itself, exactly as it would have without the
    /// early read. The read is cancelled with it, so the app is never asked
    /// twice. A read that is in flight is waited for, because an
    /// Accessibility call cannot be taken back.
    func answer() -> Query? {
        lock.lock()
        while true {
            if let storedAnswer {
                lock.unlock()
                return storedAnswer
            }
            if abandoned {
                lock.unlock()
                return nil
            }
            guard started else {
                // The read never got a worker. Give it up so the caller asks
                // the app itself instead of waiting behind a full queue.
                abandoned = true
                readOperation?.cancel()
                lock.unlock()
                return nil
            }
            // The read is in flight: its answer is waited for.
            lock.wait()
        }
    }

    /// Gives up a read that has not started yet.
    ///
    /// The walk that owns this read calls this when it gives the read up, so
    /// a read that is still queued is taken out of the shared queue instead
    /// of asking the app for an answer nobody waits for.
    func abandon() {
        lock.lock()
        if !started, storedAnswer == nil {
            abandoned = true
            readOperation?.cancel()
        }
        lock.broadcast()
        lock.unlock()
    }

    /// The read's handle, so the walk that owns this read can cancel it with
    /// the rest of its Accessibility work. A read that is already in flight
    /// cannot be taken back; cancelling the handle keeps a read that is still
    /// queued from asking an app nobody waits for.
    var operation: BlockOperation? {
        lock.lock()
        defer { lock.unlock() }
        return readOperation
    }
}

extension WindowEnumeratorAccessibilityPrefetch where Element == AXUIElement {
    /// Asks the app for its Accessibility window list.
    ///
    /// The read runs on the shared Accessibility queue, so it takes one of the
    /// same bounded workers a batch takes, and it is bounded by the same
    /// messaging timeout.
    static func start(for pid: pid_t,
                       timeout: Float,
                       queue: OperationQueue,
                       isCancelled: @escaping () -> Bool,
                       beforeRead: @escaping () -> Bool = { true }) -> WindowEnumeratorAccessibilityPrefetch<AXUIElement> {
        let prefetch = WindowEnumeratorAccessibilityPrefetch<AXUIElement>(pid: pid) {
            guard !isCancelled() else {
                return WindowEnumeratorAccessibilityPrefetch<AXUIElement>.Query(
                    windows: nil, error: .cannotComplete)
            }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, timeout)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
            let windows = error == .success ? value as? [AXUIElement] : nil
            return WindowEnumeratorAccessibilityPrefetch<AXUIElement>.Query(windows: windows,
                                                                             error: error)
        }
        prefetch.start(on: queue, beforeRead: beforeRead)
        return prefetch
    }
}
