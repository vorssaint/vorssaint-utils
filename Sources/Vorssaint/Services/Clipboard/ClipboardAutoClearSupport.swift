// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the auto clear poll should do with the change count it just read.
enum ClipboardAutoClearDecision: Equatable {
    case noteChange
    case clear
    case wait
}

/// The auto clear timing rule, kept apart from the service so the unit harness
/// pins it without a pasteboard: the service does the I/O and holds the state,
/// this decides what the state means.
enum ClipboardAutoClearSupport {
    static func clearIsAuthorized(enqueuedGeneration: Int,
                                  currentGeneration: Int,
                                  featureIsAvailable: Bool,
                                  triggerIsEnabled: Bool) -> Bool {
        enqueuedGeneration == currentGeneration && featureIsAvailable && triggerIsEnabled
    }

    /// - Parameters:
    ///   - changeCount: the count just read from the pasteboard.
    ///   - lastChangeCount: the count this service last acted on.
    ///   - lastClearedChangeCount: the count our own clear produced.
    ///   - lastChangeDate: when `lastChangeCount` was first seen.
    ///   - delay: seconds of stillness before content is cleared.
    static func decide(changeCount: Int,
                       lastChangeCount: Int,
                       lastClearedChangeCount: Int,
                       lastChangeDate: Date,
                       now: Date,
                       delay: TimeInterval) -> ClipboardAutoClearDecision {
        guard changeCount == lastChangeCount else { return .noteChange }
        // Our own clear bumps the change count. Without this, the next delay
        // would read that bump as fresh content and clear again, forever.
        guard changeCount != lastClearedChangeCount else { return .wait }
        return now.timeIntervalSince(lastChangeDate) >= delay ? .clear : .wait
    }

    /// Another part of the app replaced the content the countdown is timing
    /// with an equivalent copy (the image optimizer). The countdown carries on
    /// from the original copy; content the poll has not seen yet is left to it.
    static func changeCountAfterOwnRewrite(lastChangeCount: Int, from: Int, to: Int) -> Int {
        lastChangeCount == from ? to : lastChangeCount
    }
}
