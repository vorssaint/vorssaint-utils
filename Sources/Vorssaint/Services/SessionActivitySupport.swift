// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Reading whether a login session is the one on screen.
enum SessionActivitySupport {
    /// The console flag out of a session dictionary.
    ///
    /// Starting from the notifications alone is not enough: a process launched
    /// into a session that is already switched away is told so between
    /// `willFinishLaunching` and `didFinishLaunching`, which is before the
    /// services that own a tap exist to hear it. The flag is therefore read
    /// once at startup. Anything unreadable counts as on screen because a
    /// mistaken off state is permanent: an already-active session gets no
    /// become-active notification. A mistaken on state is bounded by the
    /// next switch, when the resign notification arrives.
    static func isOnConsole(_ session: [String: Any]?) -> Bool {
        guard let value = session?[kCGSessionOnConsoleKey as String] else { return true }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return true
    }

    /// Whether an event tap should be in the event chain at all.
    ///
    /// Fast user switching adds the third condition. A tap created here keeps
    /// its place while this login session is switched away, so the window
    /// server still routes every event through a process that cannot answer
    /// and waits out the tap timeout on each one — the account on screen
    /// stalls. Both the preference sync and the timeout
    /// re-arm ask this, so a tap handed back cannot be re-armed into a session
    /// that is no longer on screen.
    static func tapShouldRun(featureWanted: Bool,
                             accessibilityGranted: Bool,
                             sessionIsActive: Bool) -> Bool {
        featureWanted && accessibilityGranted && sessionIsActive
    }
}
