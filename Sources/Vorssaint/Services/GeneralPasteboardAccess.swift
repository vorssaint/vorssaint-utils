// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Serializes every access the app makes to the general pasteboard.
/// NSPasteboard keeps a mutable type cache on its shared instance, so reading
/// it from two queues at once can race inside AppKit, and a read has no time
/// limit: content can be promised and rendered only on demand, so an app that
/// stops answering leaves the reader hanging. Hence one serial lane, off the
/// main thread, and no way to wait for it — a caller waiting on the main
/// thread is a frozen app (issue #887).
final class GeneralPasteboardAccess {
    static let shared = GeneralPasteboardAccess()

    typealias DeadlineScheduler = (_ delay: TimeInterval,
                                   _ action: @escaping () -> Void) -> (() -> Void)

    private let queue: DispatchQueue
    private let now: () -> TimeInterval
    private let scheduleDeadline: DeadlineScheduler

    init(label: String = "Vorssaint.Pasteboard.general",
         now: @escaping () -> TimeInterval = {
             TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
         },
         scheduleDeadline: DeadlineScheduler? = nil) {
        queue = DispatchQueue(label: label, qos: .utility)
        self.now = now
        self.scheduleDeadline = scheduleDeadline ?? { delay, action in
            let item = DispatchWorkItem(block: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        }
    }

    func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    /// Runs `work` on the lane and hands its result to `completion` on the
    /// main queue. The caller returns immediately: a wedged lane delays the
    /// completion, it never blocks whoever asked.
    func async<T>(_ work: @escaping () -> T, then completion: @escaping (T) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// A deadline limits result delivery and prevents expired queued work
    /// from starting. It cannot interrupt an AppKit call already in progress.
    /// `didFinish` runs on main only when the actual queue operation ends,
    /// even if `completion` already received nil at the deadline. Callers use
    /// it to keep admission bounded while a provider is unresponsive.
    func async<T>(timeout: TimeInterval,
                   _ work: @escaping (_ isExpired: () -> Bool) -> T?,
                   then completion: @escaping (T?) -> Void,
                   didFinish: @escaping (T?) -> Void = { _ in }) {
        let deadline = now() + timeout
        let delivery = PasteboardResultDelivery(completion)
        let cancelDeadline = scheduleDeadline(timeout) { delivery.complete(nil) }
        queue.async {
            let isExpired = { self.now() >= deadline }
            let value = isExpired() ? nil : work(isExpired)
            DispatchQueue.main.async {
                cancelDeadline()
                didFinish(value)
                delivery.complete(isExpired() ? nil : value)
            }
        }
    }
}

/// Both deadline and queue completion deliver on main. Clearing the callback
/// before invoking it also makes reentrant callers safe.
private final class PasteboardResultDelivery<Value> {
    private var completion: ((Value?) -> Void)?

    init(_ completion: @escaping (Value?) -> Void) {
        self.completion = completion
    }

    func complete(_ value: Value?) {
        precondition(Thread.isMainThread)
        let callback = completion
        completion = nil
        callback?(value)
    }
}
