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
        suite.expect(focus.id != shortBreak.id && focus.id != longBreak.id && shortBreak.id != longBreak.id,
                     "pomodoro phase ids are distinct")
        suite.expect(!focus.id.isEmpty && !shortBreak.id.isEmpty && !longBreak.id.isEmpty,
                     "pomodoro phase ids are non-empty")

        // MARK: - PomodoroState
        let idle = PomodoroState.idle
        let running = PomodoroState.running
        let paused = PomodoroState.paused
        let completed = PomodoroState.completed

        suite.expect(!idle.isRunning && running.isRunning && !paused.isRunning && !completed.isRunning,
                     "isRunning accurately reports running state")
        suite.expect(!idle.isPaused && !running.isPaused && paused.isPaused && !completed.isPaused,
                     "isPaused accurately reports paused state")
        suite.expect(idle != running && idle != paused && idle != completed
                     && running != paused && running != completed && paused != completed,
                     "all pomodoro states are distinct")

        // MARK: - PomodoroSupport.sanitizedDuration
        suite.expect(PomodoroSupport.sanitizedDuration(0) >= 1,
                     "sanitizedDuration(0) returns at least 1 (minimum bound)")
        suite.expect(PomodoroSupport.sanitizedDuration(-5) >= 1,
                     "sanitizedDuration(-5) clamps to minimum bound")
        suite.expect(PomodoroSupport.sanitizedDuration(1) == 1,
                     "sanitizedDuration(1) returns 1")
        suite.expect(PomodoroSupport.sanitizedDuration(25) == 25,
                     "sanitizedDuration(25) returns 25 unchanged")
        suite.expect(PomodoroSupport.sanitizedDuration(120) == 120,
                     "sanitizedDuration(120) returns 120 unchanged")
        suite.expect(PomodoroSupport.sanitizedDuration(200) <= 120,
                     "sanitizedDuration(200) clamps to maximum bound (120)")
        suite.expect(PomodoroSupport.sanitizedDuration(Double.nan) >= 1,
                     "sanitizedDuration(NaN) falls back to a valid minimum")
        suite.expect(PomodoroSupport.sanitizedDuration(Double.infinity) <= 120,
                     "sanitizedDuration(+infinity) clamps to maximum bound")
        suite.expect(PomodoroSupport.sanitizedDuration(-Double.infinity) >= 1,
                     "sanitizedDuration(-infinity) clamps to minimum bound")

        // MARK: - PomodoroSupport.duration
        let focusDuration = PomodoroSupport.duration(for: .focus)
        let shortBreakDuration = PomodoroSupport.duration(for: .shortBreak)
        let longBreakDuration = PomodoroSupport.duration(for: .longBreak)

        suite.expect(focusDuration > 0, "focus duration is positive")
        suite.expect(shortBreakDuration > 0, "short break duration is positive")
        suite.expect(longBreakDuration > 0, "long break duration is positive")
        suite.expect(focusDuration == 1500, "focus duration is 1500 seconds (25 min)")
        suite.expect(shortBreakDuration == 300, "short break duration is 300 seconds (5 min)")
        suite.expect(longBreakDuration == 900, "long break duration is 900 seconds (15 min)")
        suite.expect(focusDuration != shortBreakDuration, "focus and short break durations differ")
        suite.expect(focusDuration != longBreakDuration, "focus and long break durations differ")
        suite.expect(shortBreakDuration != longBreakDuration, "short and long break durations differ")

        // MARK: - PomodoroSupport.nextPhase
        // Full sequence: 4 focus cycles with short breaks, then long break, then back to focus
        var phase: PomodoroPhase = .focus
        var focusCount: Int = 0

        // 1st focus completes -> short break
        let next1 = PomodoroSupport.nextPhase(from: phase, focusCount: focusCount)
        suite.expect(next1 == .shortBreak, "after 1st focus, next phase is shortBreak")
        focusCount = 1
        phase = next1

        // 1st short break completes -> focus
        let next2 = PomodoroSupport.nextPhase(from: phase, focusCount: focusCount)
        suite.expect(next2 == .focus, "after 1st short break, next phase is focus")
        phase = next2

        // 2nd focus completes -> short break
        let next3 = PomodoroSupport.nextPhase(from: phase, focusCount: focusCount)
        suite.expect(next3 == .shortBreak, "after 2nd focus, next phase is shortBreak")
        focusCount = 2
        phase = next3

        // 2nd short break completes -> focus
        let next4 = PomodoroSupport.nextPhase(from: phase, focusCount: focusCount)
        suite.expect(next4 == .focus, "after 2nd short break, next phase is focus")
        phase = next4

        // 3rd focus completes -> short break
        let next5 = PomodoroSupport.nextPhase(from: phase, focusCount: focusCount)
        suite.expect(next5 == .shortBreak, "after 3rd focus, next phase is shortBreak")
        focusCount = 3
        phase = next5

        // 3rd short break completes -> focus
        let next6 = PomodoroSupport.nextPhase(from: phase, focusCount: focusCount)
        suite.expect(next6 == .focus, "after 3rd short break, next phase is focus")
        phase = next6

        // 4th focus completes -> long break
        let next7 = PomodoroSupport.nextPhase(from: phase, focusCount: focusCount)
        suite.expect(next7 == .longBreak, "after 4th focus, next phase is longBreak")
        focusCount = 4
        phase = next7

        // Long break completes -> focus (cycle resets)
        let next8 = PomodoroSupport.nextPhase(from: phase, focusCount: focusCount)
        suite.expect(next8 == .focus, "after long break, next phase is focus (cycle resets)")

        // MARK: - PomodoroSupport.formattedTime
        suite.expect(PomodoroSupport.formattedTime(1500) == "25:00",
                     "formattedTime(1500) is '25:00'")
        suite.expect(PomodoroSupport.formattedTime(299) == "04:59",
                     "formattedTime(299) is '04:59'")
        suite.expect(PomodoroSupport.formattedTime(0) == "00:00",
                     "formattedTime(0) is '00:00'")
        suite.expect(PomodoroSupport.formattedTime(-1) == "00:00",
                     "formattedTime(-1) clamps to '00:00'")
        suite.expect(PomodoroSupport.formattedTime(Double.nan) == "00:00",
                     "formattedTime(NaN) returns '00:00'")
        suite.expect(PomodoroSupport.formattedTime(Double.infinity) == "00:00",
                     "formattedTime(+infinity) returns '00:00'")
        suite.expect(PomodoroSupport.formattedTime(-Double.infinity) == "00:00",
                     "formattedTime(-infinity) returns '00:00'")
        suite.expect(PomodoroSupport.formattedTime(60) == "01:00",
                     "formattedTime(60) is '01:00'")
        suite.expect(PomodoroSupport.formattedTime(3600) == "60:00",
                     "formattedTime(3600) is '60:00'")

        // MARK: - PomodoroSupport.progress
        suite.expect(PomodoroSupport.progress(remaining: 0, total: 100) == 1.0,
                     "progress with 0 remaining and 100 total is 1.0")
        suite.expect(abs(PomodoroSupport.progress(remaining: 50, total: 100) - 0.5) < 0.001,
                     "progress with 50 remaining and 100 total is 0.5")
        suite.expect(PomodoroSupport.progress(remaining: 100, total: 100) == 0.0,
                     "progress with total remaining equals total is 0.0")
        suite.expect(PomodoroSupport.progress(remaining: 50, total: 0) == 0.0,
                     "progress with zero total is 0.0")
        suite.expect(PomodoroSupport.progress(remaining: 50, total: -10) == 0.0,
                     "progress with negative total is 0.0")
        suite.expect(PomodoroSupport.progress(remaining: 150, total: 100) == 0.0,
                     "progress with remaining > total clamps to 0.0")
        suite.expect(PomodoroSupport.progress(remaining: -10, total: 100) == 1.0,
                     "progress with negative remaining clamps to 1.0")
        suite.expect(PomodoroSupport.progress(remaining: Double.nan, total: 100) == 0.0,
                     "progress with NaN remaining returns 0.0")
        suite.expect(PomodoroSupport.progress(remaining: 50, total: Double.nan) == 0.0,
                     "progress with NaN total returns 0.0")
        suite.expect(PomodoroSupport.progress(remaining: Double.infinity, total: 100) == 0.0,
                     "progress with +infinity remaining clamps to 0.0")
        suite.expect(PomodoroSupport.progress(remaining: 50, total: Double.infinity) == 0.0,
                     "progress with +infinity total returns 0.0")

        // MARK: - PomodoroSupport.menuBarTitle
        suite.expect(PomodoroSupport.menuBarTitle(state: .idle, phase: .focus, remaining: 1500).isEmpty,
                     "menuBarTitle is empty when state is idle")
        suite.expect(PomodoroSupport.menuBarTitle(state: .completed, phase: .focus, remaining: 0).isEmpty,
                     "menuBarTitle is empty when state is completed")
        let activeTitle = PomodoroSupport.menuBarTitle(state: .running, phase: .focus, remaining: 1500)
        suite.expect(!activeTitle.isEmpty, "menuBarTitle is non-empty when running")
        suite.expect(activeTitle.contains(focus.emoji),
                     "menuBarTitle contains phase emoji when active")
        suite.expect(activeTitle.contains("25:00"),
                     "menuBarTitle contains formatted time when active")
        let pausedTitle = PomodoroSupport.menuBarTitle(state: .paused, phase: .shortBreak, remaining: 299)
        suite.expect(!pausedTitle.isEmpty, "menuBarTitle is non-empty when paused")
        suite.expect(pausedTitle.contains(shortBreak.emoji),
                     "menuBarTitle contains shortBreak emoji when paused")
        suite.expect(pausedTitle.contains("04:59"),
                     "menuBarTitle contains formatted time when paused")

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

            // No unescaped straight double-quotes in localized strings
            suite.expect(!s.title.contains("\""),
                         "pomodoro title has no unescaped straight quotes (\(lang.rawValue))")
            suite.expect(!s.hubDescription.contains("\""),
                         "pomodoro hubDescription has no unescaped straight quotes (\(lang.rawValue))")
            suite.expect(!s.notificationFocusFinishedTitle.contains("\""),
                         "pomodoro focus finished notification title has no unescaped straight quotes (\(lang.rawValue))")
            suite.expect(!s.notificationBreakFinishedTitle.contains("\""),
                         "pomodoro break finished notification title has no unescaped straight quotes (\(lang.rawValue))")
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
