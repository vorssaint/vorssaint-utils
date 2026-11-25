// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Vorssaint's own Command-Q when the user wants it held before it quits,
/// the way a browser warns before quitting. It decides from plain values, so
/// what a press, a repeat, a release or the deadline does is testable without
/// a keyboard.
struct OwnQuitHold {
    enum KeyDown: Equatable {
        /// Not this app's Command-Q to hold: let it through untouched.
        case pass
        /// Part of a press already being held, or a repeat: never quits.
        case swallow
        /// A fresh press: show the reminder and start the hold.
        case begin
    }

    enum Tick: Equatable {
        case wait
        /// Released before the deadline. The reminder stays a moment.
        case cancel
        case quit
    }

    static let duration: TimeInterval = QuitProtectionSupport.defaultHoldDurationMilliseconds / 1_000

    private(set) var startedAt: TimeInterval?

    var isHolding: Bool { startedAt != nil }

    /// `confirmedElsewhere` is a press Quit Protection already had held and
    /// now replays; asking for a second hold would make it two.
    mutating func keyDown(isCommandQ: Bool, isRepeat: Bool,
                          confirmedElsewhere: Bool, at time: TimeInterval) -> KeyDown {
        guard isCommandQ, !confirmedElsewhere else { return .pass }
        // A repeat that arrives with no hold running belongs to a press that
        // started before the setting was on, or one that was already let go.
        // Either way it must not reach the Quit menu item.
        if isRepeat || startedAt != nil { return .swallow }
        startedAt = time
        return .begin
    }

    mutating func tick(stillHeld: Bool, at time: TimeInterval) -> Tick {
        guard let startedAt else { return .wait }
        guard stillHeld else {
            self.startedAt = nil
            return .cancel
        }
        guard time - startedAt >= Self.duration else { return .wait }
        self.startedAt = nil
        return .quit
    }
}
