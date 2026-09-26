// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A main-thread close invalidates unsent work synchronously. The serial writer
/// checks this locked lifetime at the moment a write starts, not just when the
/// UI enqueues it. A write already in progress cannot be recalled from a pipe.
final class NotchMusicCommandWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let schedule: (@escaping () -> Void) -> Void
    private var generation = UUID()
    private var active = false
    private var queueRequest: UUID?

    init(schedule: @escaping (@escaping () -> Void) -> Void) { self.schedule = schedule }

    func start() { lock.lock(); generation = UUID(); active = true; queueRequest = nil; lock.unlock() }
    func stop() { lock.lock(); generation = UUID(); active = false; queueRequest = nil; lock.unlock() }
    func setQueueRequest(_ id: UUID?) { lock.lock(); queueRequest = id; lock.unlock() }

    @discardableResult
    func submit(_ command: NotchPlaybackCommand, context: NotchPlaybackContext? = nil, write: @escaping (Data) throws -> Void,
                failed: @escaping () -> Void) -> Bool {
        guard let message = NotchPlaybackRequest(command: command, context: context).message else { return false }
        lock.lock()
        let requestedGeneration = generation
        let accepted = active && (command.queueRequest == nil || command.queueRequest == queueRequest)
        lock.unlock()
        guard accepted else { return false }
        let bytes = Data((message + "\n").utf8)
        schedule { [weak self] in
            guard let self, self.isCurrent(requestedGeneration, queueRequest: command.queueRequest) else { return }
            do { try write(bytes) }
            catch {
                if self.isCurrent(requestedGeneration, queueRequest: command.queueRequest) { failed() }
            }
        }
        return true
    }

    private func isCurrent(_ requested: UUID, queueRequest requestedQueue: UUID?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active && generation == requested && (requestedQueue == nil || requestedQueue == queueRequest)
    }
}
