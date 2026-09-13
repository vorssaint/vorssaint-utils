// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum FinderTrashKeySupport {
    static let forwardDeleteKeyCode = Int64(kVK_ForwardDelete)

    /// Held together with any of these, ⌦ is somebody else's shortcut and has
    /// to reach the app that owns it.
    ///
    /// Fn is deliberately not in the set. A MacBook has no dedicated ⌦, and
    /// produces the keystroke as Fn+⌫ with the Fn bit still set, so counting
    /// it here would switch the feature off on every portable Mac.
    private static let foreignModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]

    /// Whether this keystroke is the bare forward delete the feature claims.
    /// Answered from the event alone so the event tap can drop every unrelated
    /// key without consulting Finder or the Accessibility API.
    static func claimsKey(enabled: Bool, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard enabled, keyCode == forwardDeleteKeyCode else { return false }
        return flags.intersection(foreignModifiers).isEmpty
    }
}

/// Ties the release of the substituted key to its press.
///
/// The substitution swaps the key code, so the press the system sees is ⌫ and
/// the release it sees is ⌦: nothing releases ⌫, and it stays down as far as
/// the window server is concerned. Every later ⌘⌫ then reads as a repeat of a
/// key already held and does nothing — the user's own ⌘⌫ included, not just
/// the one this substitutes.
///
/// The release is therefore rewritten because the press was, never because
/// the conditions still hold. Re-asking them would leave ⌫ held for anyone who
/// switched app or turned the feature off mid-keystroke.
struct ForwardDeleteKeyPairing {
    private var pressClaimed = false

    mutating func claimPress() {
        pressClaimed = true
    }

    mutating func claimsRelease(keyCode: Int64) -> Bool {
        guard pressClaimed,
              keyCode == FinderTrashKeySupport.forwardDeleteKeyCode
        else { return false }
        pressClaimed = false
        return true
    }
}
