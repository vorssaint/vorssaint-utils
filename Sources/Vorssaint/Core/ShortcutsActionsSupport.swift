// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules behind the actions Vorssaint offers to the Shortcuts app.
enum ShortcutsActionsSupport {
    enum Refusal: Equatable {
        /// The person has not allowed Shortcuts to run Vorssaint actions.
        case disabled
        /// The feature the action belongs to is uninstalled in the hub.
        case featureNotInstalled
    }

    /// Why an action must not run, or nil when it may. Checked when the
    /// action runs, since the metadata Shortcuts reads is fixed at build time.
    static func refusal(actionsEnabled: Bool, featureInstalled: Bool) -> Refusal? {
        if !actionsEnabled { return .disabled }
        if !featureInstalled { return .featureNotInstalled }
        return nil
    }

    /// What a shortcut asks of a feature's switch.
    enum SwitchChoice: Equatable {
        case on, off, toggle
    }

    /// The value the switch ends up with. Toggle reads the state at the moment
    /// the action runs, so the same shortcut can be run again to flip it back.
    static func switchValue(_ choice: SwitchChoice, current: Bool) -> Bool {
        switch choice {
        case .on: return true
        case .off: return false
        case .toggle: return !current
        }
    }

    /// Whether a feature's on/off can be set from Shortcuts without guessing:
    /// it has exactly one plain switch. A feature with several switches would
    /// leave the question of which one "on" means, and one with none works on
    /// demand, so neither is offered.
    static func offersPowerSwitch(enabledKeyCount: Int) -> Bool {
        enabledKeyCount == 1
    }

    /// Quick toggles offered to Shortcuts, by the raw value of their panel
    /// action. Only the ones that neither confirm nor destroy: emptying the
    /// Trash with nothing asked is an accident with a name, and ejecting disks
    /// belongs to someone who is looking at them.
    static let quickToggleIDs = ["darkMode", "lockScreen", "displayOff", "screenSaver"]

    /// Minutes a timer or Pomodoro can be started with from Shortcuts: the
    /// range the Dynamic Island ruler offers. Anything else is refused rather
    /// than bent into range, since a typo of 0 or 1000 is not a wish for 1 or 180.
    static let timerMinutesRange = 1...180

    static func timerMinutes(_ value: Int) -> Int? {
        timerMinutesRange.contains(value) ? value : nil
    }

    /// An app's volume from a percent, where 100 is the app's own level. The
    /// mixer can also boost past it, which is left to the panel.
    static func appVolume(percent: Int) -> Double {
        Double(min(max(percent, 0), 100)) / 100
    }

    /// The Keep Awake durations the panel offers, 0 meaning until stopped. A
    /// value outside the list would otherwise fall back to "until stopped" in
    /// `Defaults.sanitizedDefaultDuration`, which is the opposite of a short
    /// session, so it is refused instead.
    static func keepAwakeMinutes(_ value: Int) -> Int? {
        Defaults.allowedDurations.contains(value) ? value : nil
    }
}
