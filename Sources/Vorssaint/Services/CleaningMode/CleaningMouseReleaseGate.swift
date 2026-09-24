// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Tracks mouse presses that actually began while Cleaning Mode was active.
///
/// The gate never queries global button state and never synthesizes input. A
/// user-requested deactivation waits until every tracked press receives its
/// real matching release, including presses seen before queued teardown runs.
/// Forced lifecycle teardown (session switch, permission reset) bypasses this gate.
struct CleaningMouseReleaseGate {
    /// The longest a user unlock waits for a release. A release this tap never
    /// sees, such as from a mouse that disconnects mid-press, must not keep the
    /// keyboard locked with no way back.
    static let releaseWaitLimit: TimeInterval = 5

    private(set) var pressedButtons: Set<Int64> = []
    private(set) var deactivationPending = false

    mutating func buttonDown(_ button: Int64) {
        pressedButtons.insert(button)
    }

    /// Returns true when this release completes a pending deactivation.
    @discardableResult
    mutating func buttonUp(_ button: Int64) -> Bool {
        let wasTracked = pressedButtons.remove(button) != nil
        return wasTracked && deactivationPending && pressedButtons.isEmpty
    }

    /// Returns true when teardown may be scheduled immediately.
    mutating func requestDeactivation() -> Bool {
        deactivationPending = true
        return pressedButtons.isEmpty
    }

    /// A disabled tap may have missed releases, but the user's request survives.
    mutating func invalidateTrackedPresses() {
        pressedButtons.removeAll()
    }

    /// The wait for a pending unlock ran out: stop waiting for the tracked
    /// presses without inventing their releases. False when nothing was asked.
    mutating func releaseWaitExpired() -> Bool {
        guard deactivationPending else { return false }
        pressedButtons.removeAll()
        return true
    }

    mutating func reset() {
        pressedButtons.removeAll()
        deactivationPending = false
    }
}
