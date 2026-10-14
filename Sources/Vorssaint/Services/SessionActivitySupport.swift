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

    /// What a tap's callback owes a tap that was just reported as disabled.
    enum DisabledTapRecovery: Equatable {
        /// The system switched it off and it is still wanted: switch it back on.
        case rearm
        /// It may no longer run: tear it down, then sync from preferences.
        case tearDown
        /// Its owner already let go of it. Nothing to recover.
        case leaveStopped
    }

    /// Reads a disabled-tap notice for a tap whose callback runs away from
    /// the thread that stops it.
    ///
    /// Switching a tap off is reported to its callback like any other
    /// disable, so the notice alone does not say the system took the tap
    /// away. An owner that no longer holds the port stopped it on purpose
    /// (Cleaning Mode, quit, a permission reset): syncing from preferences
    /// there would start the feature again under that suspension.
    static func disabledTapRecovery(tapHeld: Bool, tapShouldRun: Bool) -> DisabledTapRecovery {
        guard tapHeld else { return .leaveStopped }
        return tapShouldRun ? .rearm : .tearDown
    }
}
