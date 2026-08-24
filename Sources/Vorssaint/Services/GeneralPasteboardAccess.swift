// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Serializes the app's background observers of the general pasteboard.
/// NSPasteboard keeps a mutable type cache on its shared instance, so reading
/// it from two queues at once can race inside AppKit. Slow reads stay off the
/// main thread while the services that continuously inspect the clipboard use
/// one access lane.
final class GeneralPasteboardAccess {
    static let shared = GeneralPasteboardAccess()

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queueValue: UInt8 = 1

    init(label: String = "Vorssaint.Pasteboard.general") {
        queue = DispatchQueue(label: label, qos: .utility)
        queue.setSpecific(key: queueKey, value: queueValue)
    }

    func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    /// Runs work on the lane and hands its result back on the main queue,
    /// without ever blocking the calling thread. Main-thread callers must use
    /// this instead of `sync`: one read stuck behind a pasteboard provider
    /// that promised data and went quiet holds the whole lane for as long as
    /// it likes, and a synchronous hop from the main thread would freeze the
    /// entire app behind that stranger.
    func async<T>(_ work: @escaping () -> T, then: @escaping (T) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { then(result) }
        }
    }

    func sync<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == queueValue {
            return try work()
        }
        return try queue.sync(execute: work)
    }
}
