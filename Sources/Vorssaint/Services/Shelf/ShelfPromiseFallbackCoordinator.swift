// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Coordinates direct pasteboard fallback content while AppKit fulfills a
/// batch of file promises. A receiver can represent several files, and its
/// reader callback is normally per file. A receiver error is also allowed to
/// terminate the receiver wholesale, so the remaining advertised files are
/// credited as failed instead of leaving the batch waiting forever.
final class ShelfPromiseFallbackCoordinator<Value> {
    struct CallbackOutcome {
        let acceptFile: Bool
        let discardFallback: [Value]?
        let fallback: [Value]?
        let reportFailure: Bool
    }

    private struct ReceiverState {
        var expectedFileCount: Int
        var completedFileCount = 0
        var isTerminal = false
        var isWholesaleFailure = false
        var isExpectedFileCountFinal: Bool
    }

    let items: [Value]
    private let lock = NSLock()
    private let receiverCount: Int
    private var receivers: [Int: ReceiverState] = [:]
    private var hasSuccess = false
    private var hasFailure = false
    private var fallbackConsumed = false
    private var failureReported = false
    private var registrationFinished = false

    init(items: [Value], receiverCount: Int) {
        self.items = items
        self.receiverCount = receiverCount
    }

    func registerReceiver(_ receiverID: Int,
                          expectedFileCount: Int,
                          isExpectedFileCountFinal: Bool = true) {
        lock.lock()
        receivers[receiverID] = ReceiverState(
            expectedFileCount: max(expectedFileCount, 1),
            isExpectedFileCountFinal: isExpectedFileCountFinal)
        lock.unlock()
    }

    func updateExpectedFileCount(for receiverID: Int, to expectedFileCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard var receiver = receivers[receiverID], !receiver.isWholesaleFailure else { return }
        receiver.expectedFileCount = max(expectedFileCount, 1)
        receiver.isExpectedFileCountFinal = true
        receiver.isTerminal = receiver.completedFileCount >= receiver.expectedFileCount
        receivers[receiverID] = receiver
    }

    func finishRegistration() -> CallbackOutcome? {
        lock.lock()
        defer { lock.unlock() }
        registrationFinished = true
        return completedOutcomeIfReady()
    }

    func recordSuccess(for receiverID: Int) -> CallbackOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard var receiver = receivers[receiverID], !receiver.isWholesaleFailure else {
            // A prior error closes a receiver wholesale. Do not let a late
            // success create a promised tile after the direct fallback was
            // selected, but still let the caller clean a regular file safely.
            return CallbackOutcome(acceptFile: false,
                                   discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: false)
        }
        if receiver.isTerminal {
            // `fileNames` is normally authoritative, but the defensive
            // minimum of one cannot cap a provider that omits its names and
            // then delivers more than one file. Treat the extra callback as
            // evidence that the expected count needs to grow.
            receiver.expectedFileCount = receiver.completedFileCount + 1
            receiver.isTerminal = false
        }
        receiver.completedFileCount += 1
        if receiver.isExpectedFileCountFinal,
           receiver.completedFileCount >= receiver.expectedFileCount {
            receiver.isTerminal = true
        }
        receivers[receiverID] = receiver
        hasSuccess = true
        return CallbackOutcome(acceptFile: true,
                               discardFallback: consumeFallbackIfNeeded(),
                               fallback: nil,
                               reportFailure: reportFailureIfReady())
    }

    func recordFailure(for receiverID: Int) -> CallbackOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard var receiver = receivers[receiverID], !receiver.isWholesaleFailure else {
            return CallbackOutcome(acceptFile: false,
                                   discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: false)
        }
        if receiver.isTerminal {
            // Apply the same overflow rule to a late failure. An omitted or
            // stale file count must not turn a real failed file into silent
            // loss merely because an earlier callback reached the floor.
            receiver.expectedFileCount = receiver.completedFileCount + 1
            receiver.isTerminal = false
        }
        // An error callback may be the receiver's wholesale failure rather
        // than one failed file. Close the receiver and credit every remaining
        // advertised file so the fallback cannot wait forever.
        receiver.completedFileCount = receiver.expectedFileCount
        receiver.isTerminal = true
        receiver.isWholesaleFailure = true
        receivers[receiverID] = receiver
        hasFailure = true
        guard let outcome = completedOutcomeIfReady() else {
            return CallbackOutcome(acceptFile: false,
                                   discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: false)
        }
        return CallbackOutcome(acceptFile: false,
                               discardFallback: outcome.discardFallback,
                               fallback: outcome.fallback,
                               reportFailure: outcome.reportFailure)
    }

    private func consumeFallbackIfNeeded() -> [Value]? {
        guard !fallbackConsumed else { return nil }
        fallbackConsumed = true
        return items.isEmpty ? nil : items
    }

    private func completedOutcomeIfReady() -> CallbackOutcome? {
        guard registrationFinished,
              receivers.count == receiverCount,
              receivers.values.allSatisfy(\.isTerminal) else { return nil }
        if hasSuccess {
            return CallbackOutcome(acceptFile: false,
                                   discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: reportFailureIfReady())
        }
        guard !fallbackConsumed else {
            return CallbackOutcome(acceptFile: false,
                                   discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: reportFailureIfReady())
        }
        fallbackConsumed = true
        if items.isEmpty {
            return CallbackOutcome(acceptFile: false,
                                   discardFallback: nil,
                                   fallback: nil,
                                   reportFailure: reportFailureIfReady())
        }
        return CallbackOutcome(acceptFile: false,
                               discardFallback: nil,
                               fallback: items,
                               reportFailure: false)
    }

    private func reportFailureIfReady() -> Bool {
        guard registrationFinished,
              receivers.count == receiverCount,
              receivers.values.allSatisfy(\.isTerminal),
              hasFailure,
              !failureReported else { return false }
        failureReported = true
        return true
    }
}
