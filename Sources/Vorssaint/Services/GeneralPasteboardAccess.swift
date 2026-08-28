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

    private let queue: DispatchQueue

    init(label: String = "Vorssaint.Pasteboard.general") {
        queue = DispatchQueue(label: label, qos: .utility)
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
}
