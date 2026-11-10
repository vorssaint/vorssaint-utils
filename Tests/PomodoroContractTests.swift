// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PomodoroContractTests {
    static func run(_ suite: TestSuite) {
        // MARK: - PomodoroPhase
        let focus = PomodoroPhase.focus
        let shortBreak = PomodoroPhase.shortBreak
        let longBreak = PomodoroPhase.longBreak

        suite.expect(focus != shortBreak && focus != longBreak && shortBreak != longBreak,
                     "pomodoro phases are distinct")
        suite.expect(!focus.symbol.isEmpty && !shortBreak.symbol.isEmpty && !longBreak.symbol.isEmpty,
                     "pomodoro phase symbols are non-empty")
        suite.expect(!focus.emoji.isEmpty && !shortBreak.emoji.isEmpty && !longBreak.emoji.isEmpty,
                     "pomodoro phase emojis are non-empty")

        // MARK: - PomodoroState
        let idle = PomodoroState.idle
        let running = PomodoroState.running
        let paused = PomodoroState.paused
        let completed = PomodoroState.completed

        suite.expect(!idle.isRunning && running.isRunning && !paused.isRunning && !completed.isRunning,
                     "isRunning accurately reports running state")
        suite.expect(!idle.isPaused && !running.isPaused && paused.isPaused && !completed.isPaused,
                     "isPaused accurately reports paused state")

        // MARK: - Localization (all 15 languages)
        suite.expect(AppLanguage.allCases.count == 15, "all 15 languages are defined")
        for lang in AppLanguage.allCases {
            let s = FeatureStrings.pomodoro(lang)
            suite.expect(!s.title.isEmpty, "pomodoro title is localized (\(lang.rawValue))")
            suite.expect(!s.hubDescription.isEmpty, "pomodoro hubDescription is localized (\(lang.rawValue))")
            suite.expect(!s.notificationFocusFinishedTitle.isEmpty,
                         "pomodoro focus finished notification title is localized (\(lang.rawValue))")
            suite.expect(!s.notificationBreakFinishedTitle.isEmpty,
                         "pomodoro break finished notification title is localized (\(lang.rawValue))")
        }

        // MARK: - AppFeature metadata
        let feature = AppFeature.pomodoro
        suite.expect(feature.group == .tools, "pomodoro feature belongs to .tools")
        suite.expect(feature.symbolName == "timer", "pomodoro symbolName is 'timer'")
        suite.expect(feature.permissions == [.notifications], "pomodoro permissions are [.notifications]")
        suite.expect(!feature.installedByDefault, "pomodoro installedByDefault is false")
        suite.expect(feature.availabilityKey == "featureAvailable.pomodoro", "pomodoro availability key is accurate")

        // MARK: - GlobalShortcutRole
        let role = GlobalShortcutRole.pomodoro
        suite.expect(role.defaultShortcut == .pomodoroDefault, "pomodoro role default shortcut is pomodoroDefault")
        suite.expect(role.requiredEnableKeys == [DefaultsKey.pomodoroEnabled],
                     "pomodoro role requiredEnableKeys requires pomodoroEnabled")
        suite.expect(role.feature == .pomodoro, "pomodoro role feature is .pomodoro")
        suite.expect(role.storageKey == DefaultsKey.pomodoroShortcut, "pomodoro role storageKey matches DefaultsKey")

        // MARK: - Release Change Aliases
        suite.expect(!ReleaseChangeAliases.aliases(for: .pomodoro).isEmpty,
                     "pomodoro feature has release change aliases")
    }
}
