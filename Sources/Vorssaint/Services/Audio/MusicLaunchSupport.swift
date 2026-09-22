// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Only an observed media key can explain an automatic music-app launch.
/// Absence of a click is not evidence: voice, automation and login can all
/// open an app intentionally without a keyboard or pointer gesture.
enum MusicLaunchSupport {
    static let systemDefinedEventTypeRawValue: UInt32 = 14
    static let auxiliaryControlButtonsSubtype = 8
    static let keyDownState = 10
    /// Launch Services needs a moment after the key to start the app.
    static let launchArmWindow: TimeInterval = 2.0
    static let playPauseKeyCode: UInt16 = 16
    static let nextTrackKeyCode: UInt16 = 17
    static let previousTrackKeyCode: UInt16 = 18
    static let fastForwardKeyCode: UInt16 = 19
    static let rewindKeyCode: UInt16 = 20

    static let musicLaunchKeyCodes: Set<UInt16> = [
        playPauseKeyCode, nextTrackKeyCode, previousTrackKeyCode,
        fastForwardKeyCode, rewindKeyCode
    ]

    /// True for the key-down of a media key that would otherwise open the
    /// music app. Releases, auto-repeat and volume or brightness keys do not
    /// count, so those never arm the blocker.
    static func isMusicLaunchTrigger(subtype: Int, data1: Int) -> Bool {
        guard subtype == auxiliaryControlButtonsSubtype else { return false }
        let raw = UInt32(truncatingIfNeeded: data1)
        let state = Int((raw >> 8) & 0xFF)
        guard state == keyDownState, (raw & 0x1) == 0 else { return false }
        let keyCode = UInt16((raw >> 16) & 0xFFFF)
        return musicLaunchKeyCodes.contains(keyCode)
    }

    /// A newer click or key press takes precedence over a media key. Invalid
    /// or expired evidence always leaves the launch alone. An infinite gesture
    /// age means the session has never seen one, and still needs a real key.
    static func shouldBlockLaunch(now: TimeInterval,
                                  lastTriggerAt: TimeInterval?,
                                  secondsSinceUserGesture: TimeInterval) -> Bool {
        guard now.isFinite, now >= 0, let lastTriggerAt,
              lastTriggerAt.isFinite, lastTriggerAt >= 0,
              !secondsSinceUserGesture.isNaN, secondsSinceUserGesture >= 0 else { return false }
        let elapsed = now - lastTriggerAt
        return (0...launchArmWindow).contains(elapsed) && secondsSinceUserGesture > elapsed
    }
}
