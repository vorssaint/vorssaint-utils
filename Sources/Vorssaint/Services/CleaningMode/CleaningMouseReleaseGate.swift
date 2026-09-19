// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Tracks mouse presses that actually began while Cleaning Mode was active.
///
/// The gate never queries global button state and never synthesizes input. A
/// user-requested deactivation that arrives mid-click waits until every tracked
/// press receives its real matching release. Forced lifecycle teardown (session
/// switch, disabled tap) intentionally bypasses this gate in the manager.
struct CleaningMouseReleaseGate {
    private(set) var pressedButtons: Set<Int64> = []
    private(set) var deactivationPending = false

    mutating func buttonDown(_ button: Int64) {
        pressedButtons.insert(button)
    }

    /// Returns true when this release completes a pending deactivation.
    @discardableResult
    mutating func buttonUp(_ button: Int64) -> Bool {
        pressedButtons.remove(button)
        guard deactivationPending, pressedButtons.isEmpty else { return false }
        deactivationPending = false
        return true
    }

    /// Returns true when teardown may be scheduled immediately.
    mutating func requestDeactivation() -> Bool {
        guard !pressedButtons.isEmpty else { return true }
        deactivationPending = true
        return false
    }

    mutating func reset() {
        pressedButtons.removeAll()
        deactivationPending = false
    }
}
