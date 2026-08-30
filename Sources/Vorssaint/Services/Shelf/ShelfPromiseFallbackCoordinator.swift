// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Coordinates direct pasteboard fallback content while AppKit fulfills a
/// batch of file promises. A receiver's reader callback is per promised file,
/// not per receiver, so completion must be counted against the file names
/// reported after each receiver is activated.
final class ShelfPromiseFallbackCoordinator<Value> {
    struct CallbackOutcome {
        let discardFallback: [Value]?
        let fallback: [Value]?
        let reportFailure: Bool
    }

    let items: [Value]
    private let lock = NSLock()
    private let receiverCount: Int
    private var registeredReceiverCount = 0
    private var expectedFileCount = 0
    private var completedFileCount = 0
    private var hasSuccess = false
    private var hasFailure = false
    private var fallbackConsumed = false
    private var failureReported = false
    private var registrationFinished = false

    init(items: [Value], receiverCount: Int) {
        self.items = items
        self.receiverCount = receiverCount
    }

    func registerReceiver(expectedFileCount: Int) {
        lock.lock()
        registeredReceiverCount += 1
        // Keep one defensive slot for an unusual receiver that does not
        // publish names, so a failed receiver cannot leave the batch waiting
        // forever. Normal receivers use their exact fileNames.count.
        self.expectedFileCount += max(expectedFileCount, 1)
        lock.unlock()
    }

    func finishRegistration() -> CallbackOutcome? {
        lock.lock()
        defer { lock.unlock() }
        registrationFinished = true
        return completedOutcomeIfReady()
    }

    func recordSuccess() -> CallbackOutcome {
        lock.lock()
        defer { lock.unlock() }
        completedFileCount += 1
        hasSuccess = true
        let discardFallback = consumeFallbackIfNeeded()
        return CallbackOutcome(discardFallback: discardFallback,
                               fallback: nil,
                               reportFailure: reportFailureIfReady())
    }

    func recordFailure() -> CallbackOutcome {
        lock.lock()
        defer { lock.unlock() }
        completedFileCount += 1
        hasFailure = true
        guard let outcome = completedOutcomeIfReady() else {
            return CallbackOutcome(discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: false)
        }
        return outcome
    }

    private func consumeFallbackIfNeeded() -> [Value]? {
        guard !fallbackConsumed else { return nil }
        fallbackConsumed = true
        return items.isEmpty ? nil : items
    }

    private func completedOutcomeIfReady() -> CallbackOutcome? {
        guard registrationFinished,
              registeredReceiverCount == receiverCount,
              completedFileCount >= expectedFileCount else { return nil }
        if hasSuccess {
            return CallbackOutcome(discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: reportFailureIfReady())
        }
        guard !fallbackConsumed else {
            return CallbackOutcome(discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: reportFailureIfReady())
        }
        fallbackConsumed = true
        if items.isEmpty {
            return CallbackOutcome(discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: reportFailureIfReady())
        }
        return CallbackOutcome(discardFallback: nil,
                               fallback: items,
                               reportFailure: false)
    }

    private func reportFailureIfReady() -> Bool {
        guard registrationFinished,
              registeredReceiverCount == receiverCount,
              completedFileCount >= expectedFileCount,
              hasFailure,
              !failureReported else { return false }
        failureReported = true
        return true
    }
}
