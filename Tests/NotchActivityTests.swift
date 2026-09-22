// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import SwiftUI

enum NotchActivityTests {
    static func run(_ suite: TestSuite) {
        timerContracts(suite)
        alertContracts(suite)
        pomodoroContracts(suite)
        stopwatchContracts(suite)
        modePickerContracts(suite)
        rulerContracts(suite)
        compactTimerContracts(suite)
        compactMarginContracts(suite)
        accessoryContracts(suite)
        PeripheralBatteryLifecycleTests.run(suite)
        gateContracts(suite)
    }

    private static func alertContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.timer-alert"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchTimerSupport.isSoundEnabled(in: defaults), "timer sound is enabled by default")
        for enabled in [false, true] {
            defaults.set(enabled, forKey: DefaultsKey.notchTimerSoundEnabled)
            suite.expect(NotchTimerSupport.isSoundEnabled(in: defaults) == enabled,
                   "the sound preference survives reload")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchTimerSoundEnabled] as? Bool == true
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchTimerSoundEnabled),
               "the sound preference is registered and included in settings backup")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchCoversMenus] as? Bool == false
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchCoversMenus),
               "covering the menus stays off by default and travels with settings backups")
        suite.expect(NotchTimerAlert.maximumDuration == .seconds(300), "an alarm is limited to five minutes")
        var sounds = 0, stops = 0
        var elapsed: Duration = .zero
        let alert = NotchTimerAlert(interval: .milliseconds(5), now: { .now.advanced(by: elapsed) },
                                   sound: { sounds += 1 }, stopSound: { stops += 1 })
        defer { alert.stop() }
        func wait(until predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(1)
            while !predicate() && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.002))
            }
        }
        func settle() {
            let end = Date().addingTimeInterval(0.04)
            wait { Date() >= end }
        }
        alert.start(enabled: false)
        settle()
        suite.expect(sounds == 0, "a timer completed with sound disabled stays silent")
        alert.start(enabled: true)
        suite.expect(sounds == 1, "an enabled sound alarm alerts immediately")
        alert.start(enabled: true)
        suite.expect(sounds == 1, "preference synchronization does not duplicate a pending alarm")
        wait { sounds >= 3 }
        suite.expect(sounds >= 3, "an unacknowledged sound alarm repeats")
        alert.start(enabled: false)
        let mutedSounds = sounds
        settle()
        suite.expect(sounds == mutedSounds && stops > 0, "disabling sound stops current playback and repetition")
        elapsed = .seconds(299)
        alert.start(enabled: true)
        suite.expect(sounds == mutedSounds + 1, "sound can resume within the original alarm budget")
        alert.suspend()
        let suspendedSounds = sounds
        settle()
        suite.expect(sounds == suspendedSounds, "suspension cancels sound playback")
        alert.start(enabled: true)
        elapsed = .seconds(301)
        let expirationStops = stops
        wait { stops > expirationStops }
        let expiredSounds = sounds
        alert.start(enabled: false)
        alert.start(enabled: true)
        alert.suspend()
        alert.start(enabled: true)
        settle()
        suite.expect(stops > expirationStops && sounds == expiredSounds,
               "five minutes stop playback; preference changes and suspension cannot restart an expired alarm")
        alert.stop()
        alert.start(enabled: true)
        suite.expect(sounds == expiredSounds + 1, "a new timer phase gets a fresh alert budget")
        alert.stop()
        let cancelledSounds = sounds
        settle()
        suite.expect(sounds == cancelledSounds, "dismissal prevents delayed playback")
    }

    private static func timerContracts(_ suite: TestSuite) {
        var session = NotchTimerSession()
        suite.expect(!session.hasSession, "an unused timer has no active session")
        session.start(mode: .timer, minutes: 5, now: 100)
        suite.expect(session.reading(at: 101.25) == 298.75, "countdown uses an absolute deadline, including fractional elapsed time")
        session.start(mode: .pomodoro, minutes: 25, now: 105)
        suite.expect(session.mode == .timer && session.deadline == 400, "starting twice cannot replace an active timer")
        session.pause(at: 160)
        suite.expect(session.isPaused && session.reading(at: 10_000) == 240, "paused time stays fixed across sleep")
        session.resume(at: 10_000)
        suite.expect(session.deadline == 10_240 && session.reading(at: 10_100) == 140, "resume preserves only the remaining duration")
        suite.expect(!session.finishIfDue(at: 10_239.999), "fractional time before the deadline is not complete")
        suite.expect(session.finishIfDue(at: 100_000) && session.completed, "returning from sleep finishes an overdue timer once")
        suite.expect(!session.finishIfDue(at: 100_001), "repeated callbacks cannot announce the same completion twice")
        session.cancel()
        suite.expect(!session.hasSession && session.completedFocuses == 0, "cancel discards the entire session")
        session.start(mode: .timer, minutes: 0, now: 0)
        suite.expect(session.duration == 60, "timer input cannot create an immediately expired session")
        session.pause(at: 60)
        suite.expect(session.completed && !session.isPaused, "pausing at the deadline completes instead of preserving a zero timer")
        session.cancel()
        session.start(mode: .timer, minutes: Int.max, now: 0)
        suite.expect(session.duration == 10_800, "corrupt duration input stays within three hours")
        suite.expect(NotchTimerSupport.clockText(0.01) == "00:01" && NotchTimerSupport.clockText(-1) == "00:00"
               && NotchTimerSupport.clockText(.nan) == "00:00", "display rounds up and safely handles invalid remaining time")
        let clockCases: [(TimeInterval, String)] = [
            (59, "00:59"), (60, "01:00"), (3599, "59:59"), (3599.01, "1:00:00"),
            (3600, "1:00:00"), (3601, "1:00:01"), (8580, "2:23:00"),
            (10800, "3:00:00"), (.greatestFiniteMagnitude, "3:00:00"), (.infinity, "00:00")
        ]
        for (seconds, expected) in clockCases {
            suite.expect(NotchTimerSupport.clockText(seconds) == expected,
                   "timer clocks show hours at the hour boundary while preserving seconds: \(seconds)")
        }
        let locale = Locale(identifier: "en_US")
        suite.expect(NotchTimerSupport.compactText(870, locale: locale) == "14m"
               && NotchTimerSupport.compactText(60, locale: locale) == "1m",
               "compact timers show whole remaining minutes without overstating a partial minute")
        suite.expect(NotchTimerSupport.compactText(59, locale: locale) == "59s"
               && NotchTimerSupport.compactText(0.01, locale: locale) == "1s",
               "compact timers switch to seconds for the final minute and never finish early")
        let compactCases: [(TimeInterval, String)] = [
            (3599, "59m"), (3599.01, "1h"), (3600, "1h"), (3659, "1h"),
            (3660, "1h 1m"), (8580, "2h 23m"), (10800, "3h")
        ]
        for (seconds, expected) in compactCases {
            suite.expect(NotchTimerSupport.compactText(seconds, locale: locale) == expected,
                   "compact timers and focus durations show hours and whole minutes: \(seconds)")
        }
        for invalid in [Double.nan, .infinity, -1, 0] {
            suite.expect(NotchTimerSupport.compactText(invalid, locale: locale) == "0s",
                   "invalid or expired compact times remain safe to display")
        }
        suite.expect(NotchTimerSupport.compactText(.greatestFiniteMagnitude, locale: locale) == "3h",
               "compact duration formatting preserves the timer's upper limit")
        let hourCases: [(TimeInterval, String)] = [
            (3600, "1h00"), (3659.9, "1h00"), (3660, "1h01"), (5700, "1h35"),
            (8580, "2h23"), (10800, "3h00"), (.greatestFiniteMagnitude, "3h00"), (.nan, "0h00")
        ]
        for (seconds, expected) in hourCases {
            suite.expect(NotchTimerSupport.compactHoursText(seconds) == expected,
                   "the compact strip writes hours as 1h35, never as a colon that reads like minutes and seconds: \(seconds)")
        }
        for language in AppLanguage.allCases {
            suite.expect(!NotchTimerSupport.compactText(870, locale: Locale(identifier: language.rawValue)).isEmpty,
                   "remaining time has a compact unit in every supported language")
            suite.expect(!NotchTimerSupport.compactText(8580, locale: Locale(identifier: language.rawValue)).isEmpty,
                   "hour and minute units are available in every supported language")
        }
        for width: CGFloat in [320, 480, 560] {
            for notched in [false, true] {
                let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
                let geometry = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                             cameraWidth: notched ? 180 : 0,
                                             layout: .custom, customWidth: width, customHeight: 400)
                let setup = geometry.expandedSize(module: .timer)
                let active = geometry.expandedSize(module: .timer, timerHasSession: true)
                suite.expect(geometry.contentSize(for: setup).height
                       == NotchLayout.timer(mode: .timer, hasSession: false, width: geometry.contentWidth, height: geometry.contentBudget)
                       && geometry.contentSize(for: setup).height >= NotchLayout.timerTopRowHeight + NotchLayout.timerRowSpacing + NotchLayout.timerMinimumRulerHeight
                       && geometry.contentSize(for: active).height >= 96 && active.height < setup.height,
                       "timer setup has room for its mode row, ruler and start row; active controls use a shorter horizontal surface")
                suite.expect(screen.contains(geometry.frame(for: setup)) && screen.contains(geometry.frame(for: active))
                       && geometry.frame(for: setup).maxY == geometry.frame(for: active).maxY,
                       "starting a timer preserves the screen's top edge and keeps both sizes on screen")
            }
        }
        session.cancel()
        session.start(mode: .pomodoro, minutes: 5, now: 0, configuration: NotchPomodoroConfiguration(totalSessions: 5))
        var now: TimeInterval = 0
        for round in 1...4 {
            suite.expect(session.phase == .focus && session.duration == 1500, "each focus phase lasts 25 minutes")
            now += 1500
            suite.expect(session.finishIfDue(at: now), "each focus deadline completes")
            suite.expect(session.completedFocuses == round && !session.isRunning, "focus completion waits for explicit continuation")
            suite.expect(session.nextPhase == (round == 4 ? .longBreak : .shortBreak), "the fourth completed focus schedules a long break")
            session.startNext(at: now)
            let breakDuration: TimeInterval = round == 4 ? 900 : 300
            suite.expect(session.duration == breakDuration, "break durations distinguish the short and long phases")
            now += breakDuration
            _ = session.finishIfDue(at: now)
            suite.expect(session.nextPhase == .focus, "a completed break returns to focus")
            session.startNext(at: now)
        }
        now += 100_000
        suite.expect(session.finishIfDue(at: now) && session.completedFocuses == 5 && session.completed,
               "a long sleep never manufactures unattended pomodoro cycles")
        let request = CameraPreviewRequest()
        suite.expect(!request.isCancelled, "a new camera request can configure the shared capture session")
        request.cancel(); request.cancel()
        suite.expect(request.isCancelled, "closing a mirror cancels queued configuration idempotently")
    }

    private static func pomodoroContracts(_ suite: TestSuite) {
        let config = NotchPomodoroConfiguration(focusMinutes: 10, shortBreakMinutes: 2,
                                              longBreakMinutes: 7, longBreakInterval: 2, totalSessions: 3)
        var session = NotchTimerSession()
        session.start(mode: .pomodoro, minutes: 1, now: 0, configuration: config)
        suite.expect(session.duration == 600 && session.sessionNumber == 1 && !session.canStartNext,
               "custom focus duration starts the first session and cannot be skipped while active")
        session.pause(at: 100)
        session.resume(at: 1_000)
        suite.expect(session.deadline == 1_500 && session.configuration == config,
               "pause and resume preserve the cycle configuration and remaining focus time")
        var now = 1_500.0
        for round in 1...3 {
            suite.expect(session.finishIfDue(at: now) && session.completedFocuses == round,
                   "each configured focus session counts exactly once")
            suite.expect(session.sessionNumber == round && !session.finishIfDue(at: now + 1),
                   "completed phases retain their progress and reject duplicate completion")
            if round == 3 { break }
            suite.expect(session.canStartNext && !session.cycleFinished, "unfinished cycles offer explicit continuation")
            session.startNext(at: now)
            let expectedBreak = round == 1 ? 120.0 : 420.0
            suite.expect(session.duration == expectedBreak && session.phase == (round == 1 ? .shortBreak : .longBreak),
                   "configured interval chooses the correct short or long break duration")
            now += expectedBreak
            _ = session.finishIfDue(at: now)
            suite.expect(session.completedFocuses == round, "breaks do not count toward the focus-session goal")
            session.startNext(at: now)
            suite.expect(session.phase == .focus && session.duration == 600 && session.sessionNumber == round + 1,
                   "each new focus uses the same configuration and advances visible progress")
            now += 600
        }
        suite.expect(session.cycleFinished && !session.canStartNext && !session.isRunning,
               "the final focus ends the cycle without an extra break")
        let finished = session
        session.startNext(at: now + 1)
        suite.expect(session == finished, "continuation cannot restart a finished cycle")
        session.cancel()
        session.start(mode: .pomodoro, minutes: 1, now: 0,
                      configuration: NotchPomodoroConfiguration(longBreakInterval: 1, totalSessions: 1))
        _ = session.finishIfDue(at: 100_000)
        suite.expect(session.cycleFinished && session.completedFocuses == 1 && !session.canStartNext,
               "a one-session goal ends at focus completion even when a long break would otherwise be due")
        let bounded = NotchPomodoroConfiguration(focusMinutes: Int.max, shortBreakMinutes: Int.min,
            longBreakMinutes: Int.max, longBreakInterval: 0, totalSessions: Int.max)
        suite.expect(bounded.focusMinutes == 180 && bounded.shortBreakMinutes == 1 && bounded.longBreakMinutes == 60
               && bounded.longBreakInterval == 1 && bounded.totalSessions == 24,
               "restored out-of-range values cannot overflow deadlines or create invalid cycle intervals")
        let domain = "com.vorssaint.tests.pomodoro"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let keys: Set<String> = [DefaultsKey.notchPomodoroFocusMinutes, DefaultsKey.notchPomodoroShortBreakMinutes,
            DefaultsKey.notchPomodoroLongBreakMinutes, DefaultsKey.notchPomodoroLongBreakInterval,
            DefaultsKey.notchPomodoroTotalSessions, DefaultsKey.notchTimerMode]
        suite.expect(keys.isSubset(of: Set(Defaults.registeredDefaults.keys))
               && keys.isSubset(of: SettingsBackupSupport.exportKeys()),
               "all Pomodoro choices, including the selected mode, are registered and included in settings backup")
        defaults.set(45, forKey: DefaultsKey.notchPomodoroFocusMinutes)
        defaults.set(8, forKey: DefaultsKey.notchPomodoroShortBreakMinutes)
        defaults.set(20, forKey: DefaultsKey.notchPomodoroLongBreakMinutes)
        defaults.set(3, forKey: DefaultsKey.notchPomodoroLongBreakInterval)
        defaults.set(6, forKey: DefaultsKey.notchPomodoroTotalSessions)
        let saved = NotchPomodoroConfiguration.load(in: defaults)
        suite.expect(saved == NotchPomodoroConfiguration(focusMinutes: 45, shortBreakMinutes: 8,
            longBreakMinutes: 20, longBreakInterval: 3, totalSessions: 6), "saved choices restore the whole cycle")
        session.cancel()
        session.start(mode: .pomodoro, minutes: 1, now: 0, configuration: saved)
        defaults.set(1, forKey: DefaultsKey.notchPomodoroFocusMinutes)
        suite.expect(session.configuration == saved && session.duration == 2_700,
               "changes to saved preferences never rewrite an already running cycle")
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32, cameraWidth: 180)
        let setup = geometry.expandedSize(module: .timer, timerMode: .pomodoro)
        let active = geometry.expandedSize(module: .timer, timerHasSession: true, timerMode: .pomodoro)
        suite.expect(geometry.contentSize(for: setup).height
               == NotchLayout.timer(mode: .pomodoro, hasSession: false, width: geometry.contentWidth, height: geometry.contentBudget)
               && geometry.contentSize(for: setup).height <= geometry.contentBudget
               && geometry.contentSize(for: active).height >= 118,
               "the Pomodoro setup fits the strip with its readouts under the ruler, and the progress row keeps its own budget")
    }

    private static func stopwatchContracts(_ suite: TestSuite) {
        var session = NotchTimerSession()
        suite.expect(session.reading(at: 5) == 300 && !session.countsUp, "an idle page still previews the countdown it would start")
        session.start(mode: .stopwatch, minutes: 15, now: 100)
        suite.expect(session.countsUp && session.phase == .stopwatch && session.isRunning && session.deadline == nil
               && session.duration == 0, "a stopwatch runs from zero with no deadline or preset duration")
        suite.expect(session.reading(at: 100) == 0 && session.reading(at: 161.25) == 61.25,
               "elapsed time grows from the anchor, including fractional seconds")
        suite.expect(session.reading(at: 99) == 0, "a clock that reads before its anchor never shows negative time")
        suite.expect(!session.finishIfDue(at: 1_000_000) && session.isRunning && !session.completed,
               "a stopwatch never completes on its own, however long it runs")
        session.start(mode: .timer, minutes: 5, now: 200)
        suite.expect(session.countsUp && session.anchor == 100, "starting twice cannot replace a running stopwatch")
        session.pause(at: 160)
        suite.expect(session.isPaused && !session.isRunning && session.reading(at: 10_000) == 60,
               "pausing holds the elapsed reading across sleep")
        session.pause(at: 170)
        suite.expect(session.reading(at: 10_000) == 60, "pausing a paused stopwatch changes nothing")
        session.resume(at: 10_000)
        suite.expect(session.isRunning && session.reading(at: 10_040.5) == 100.5,
               "resuming continues from the held reading, never from the wall clock gap")
        session.resume(at: 20_000)
        suite.expect(session.reading(at: 20_000) == 10_060, "resuming a running stopwatch changes nothing")
        session.pause(at: .nan)
        suite.expect(session.isRunning, "an invalid clock cannot pause a stopwatch")
        session.cancel()
        suite.expect(!session.hasSession && session.reading(at: 0) == 300 && !session.countsUp,
               "cancel discards the stopwatch and returns the page to its countdown preview")

        var countdown = NotchTimerSession()
        countdown.start(mode: .timer, minutes: 1, now: 0)
        for (elapsed, expected) in [(0.0, 1.0), (0.25, 0.75), (0.999, 0.001)] {
            let offset = NotchTimerSupport.secondBoundaryOffset(for: countdown, at: elapsed)
            suite.expect(abs(offset - expected) < 1e-9, "countdown ticks align to whole remaining seconds: \(elapsed)")
        }
        var stopwatch = NotchTimerSession()
        stopwatch.start(mode: .stopwatch, minutes: 1, now: 0)
        for (elapsed, expected) in [(0.0, 1.0), (0.25, 0.75), (61.999, 0.001)] {
            let offset = NotchTimerSupport.secondBoundaryOffset(for: stopwatch, at: elapsed)
            suite.expect(abs(offset - expected) < 1e-9, "stopwatch ticks align to whole elapsed seconds: \(elapsed)")
        }
        for (session, name) in [(countdown, "countdown"), (stopwatch, "stopwatch")] {
            for now in stride(from: 0.0, through: 59.0, by: 0.37) {
                let offset = NotchTimerSupport.secondBoundaryOffset(for: session, at: now)
                let before = NotchTimerSupport.clockText(for: session, at: now + offset - 0.001)
                let after = NotchTimerSupport.clockText(for: session, at: now + offset + 0.001)
                suite.expect(offset > 0 && offset <= 1 && before != after,
                       "the next tick lands just after the \(name) reading changes: \(now)")
            }
        }
        suite.expect(NotchTimerSupport.secondBoundaryOffset(for: countdown, at: -.infinity) == 0,
               "an unreadable clock schedules an immediate tick instead of an invalid date")
        // A timeline renders the first entry of its schedule at once and wakes
        // only at the next one, so the boundary ahead has to be the second
        // entry, with the first already behind now.
        let reference = Date()
        for (session, name) in [(countdown, "countdown"), (stopwatch, "stopwatch")] {
            for now in stride(from: 0.0, through: 3.0, by: 0.23) {
                let boundary = NotchTimerSupport.secondBoundaryOffset(for: session, at: now)
                let start = reference.addingTimeInterval(NotchTimerSupport.tickScheduleOffset(for: session, at: now))
                var entries = PeriodicTimelineSchedule(from: start, by: 1).entries(from: reference, mode: .normal).makeIterator()
                let first = entries.next()?.timeIntervalSince(reference) ?? .nan
                let second = entries.next()?.timeIntervalSince(reference) ?? .nan
                let third = entries.next()?.timeIntervalSince(reference) ?? .nan
                suite.expect(first <= 0 && first > -1 && abs(second - boundary) < 1e-6 && abs(third - boundary - 1) < 1e-6,
                       "the clock's schedule starts behind now, so its first wake lands on the \(name) boundary "
                       + "instead of skipping it: \(now)")
            }
        }

        let stopwatchCases: [(TimeInterval, String)] = [
            (0, "00:00"), (0.999, "00:00"), (1, "00:01"), (59.9, "00:59"), (60, "01:00"),
            (3599.99, "59:59"), (3600, "1:00:00"), (3661, "1:01:01"), (10_800, "3:00:00"),
            (86_399, "23:59:59"), (359_999, "99:59:59"), (400_000, "99:59:59"),
            (.greatestFiniteMagnitude, "99:59:59"), (-1, "00:00"), (.nan, "00:00"), (.infinity, "00:00")
        ]
        for (seconds, expected) in stopwatchCases {
            suite.expect(NotchTimerSupport.stopwatchText(seconds) == expected,
                   "elapsed clocks round down, grow past the timer's three hours and saturate safely: \(seconds)")
        }
        let compactStopwatchCases: [(TimeInterval, String)] = [
            (0, "00:00"), (42.7, "00:42"), (599, "09:59"), (754, "12:34"), (3599.9, "59:59"),
            (3600, "1h00"), (3720, "1h02"), (5700, "1h35"), (36_000, "10h00"),
            (.greatestFiniteMagnitude, "99h59"), (-1, "00:00"), (.nan, "00:00")
        ]
        for (seconds, expected) in compactStopwatchCases {
            suite.expect(NotchTimerSupport.compactStopwatchText(seconds) == expected,
                   "the compact strip keeps a stopwatch's seconds until hours take their place: \(seconds)")
        }
        let locale = Locale(identifier: "en_US")
        suite.expect(NotchTimerSupport.clockText(for: stopwatch, at: 61.9) == "01:01"
               && NotchTimerSupport.clockText(for: countdown, at: 0.1) == "01:00",
               "session clocks read elapsed time up and remaining time down")
        suite.expect(NotchTimerSupport.compactText(for: stopwatch, at: 61.9, locale: locale) == "01:01"
               && NotchTimerSupport.compactText(for: countdown, at: 0.1, locale: locale) == "1m",
               "compact session readings keep each mode's own notation")
        var hours = NotchTimerSession()
        hours.start(mode: .timer, minutes: 120, now: 0)
        suite.expect(NotchTimerSupport.compactText(for: hours, at: 1, locale: locale) == "1h59"
               && NotchTimerSupport.compactText(for: hours, at: 3600, locale: locale) == "1h00"
               && NotchTimerSupport.compactText(for: hours, at: 3601, locale: locale) == "59m",
               "compact countdowns still switch from hours to minutes at the hour boundary")

        let domain = "com.vorssaint.tests.timer-mode"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchTimerSupport.savedMode(in: defaults) == .timer, "a fresh install opens the countdown")
        for mode in NotchTimerMode.allCases {
            defaults.set(mode.rawValue, forKey: DefaultsKey.notchTimerMode)
            suite.expect(NotchTimerSupport.savedMode(in: defaults) == mode, "the chosen mode survives reload: \(mode)")
        }
        defaults.set("countdown", forKey: DefaultsKey.notchTimerMode)
        suite.expect(NotchTimerSupport.savedMode(in: defaults) == .timer, "an unknown saved mode falls back to the countdown")
        suite.expect(NotchTimerMode.allCases.last == .stopwatch && NotchTimerMode.allCases.first == .timer,
               "the stopwatch joins the mode row after the existing modes, keeping their positions")

        for width: CGFloat in [360, 480, 560] {
            let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32,
                                         cameraWidth: 180, layout: .custom, customWidth: width, customHeight: 400)
            let setup = geometry.expandedSize(module: .timer, timerMode: .stopwatch)
            let active = geometry.expandedSize(module: .timer, timerHasSession: true, timerMode: .stopwatch)
            suite.expect(geometry.contentSize(for: setup).height
                   == NotchLayout.timer(mode: .stopwatch, hasSession: false, width: geometry.contentWidth, height: geometry.contentBudget)
                   && setup.height == geometry.expandedSize(module: .timer).height,
                   "the stopwatch keeps its clock in the countdown's ruler row, so switching between them never resizes the island")
            suite.expect(active == geometry.expandedSize(module: .timer, timerHasSession: true),
                   "a running stopwatch shares the countdown's control row")
        }
    }

    /// The mode row sizes each label to its word. Its contract is that the
    /// three translated modes fit the narrowest island, with a legacy scroll bar.
    private static func modePickerContracts(_ suite: TestSuite) {
        let layout = NotchTimerSupport.ModePicker.self
        let font = NSFont.systemFont(ofSize: layout.labelSize, weight: .medium)
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32,
                                     cameraWidth: 180, layout: .custom, customWidth: NotchSize.widthRange.lowerBound,
                                     customHeight: NotchSize.heightRange.lowerBound)
        let available = geometry.contentSize(for: geometry.expandedSize(module: .timer)).width
            - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        suite.expect(layout.height > layout.labelSize + 2 && layout.labelPadding > 0,
               "every mode label keeps room for its underline and around its text")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchActivities(language)
            let labels = [text.timer, text.pomodoro, text.stopwatch]
            suite.expect(Set(labels).count == 3 && labels.allSatisfy { !$0.isEmpty },
                   "each mode has its own name: \(language)")
            let width = labels.reduce(0) { $0 + ($1 as NSString).size(withAttributes: [.font: font]).width + layout.labelPadding * 2 }
                + layout.spacing * CGFloat(labels.count - 1)
            suite.expect(width <= available, "the three modes fit the narrowest island in \(language): \(Int(width)) of \(Int(available))")
            let startFont = NSFont.systemFont(ofSize: NotchTimerSupport.StartButton.labelSize, weight: .semibold)
            let start = (text.start as NSString).size(withAttributes: [.font: startFont]).width + NotchTimerSupport.StartButton.padding * 2
            suite.expect(width + 12 + start <= NotchLayout.timerWideWidth,
                   "Start sits beside the mode row from the wide layout's width on in \(language): \(Int(width + 12 + start)) of \(Int(NotchLayout.timerWideWidth))")
        }
        suite.expect(NotchPomodoroOption.focus.range == 1...180
                     && NotchPomodoroOption.shortBreak.range == 1...60
                     && NotchPomodoroOption.longBreak.range == 1...60
                     && NotchPomodoroOption.longBreakInterval.range == 1...24
                     && NotchPomodoroOption.totalSessions.range == 1...24,
                     "Pomodoro menus preserve every minute and session count accepted by the saved configuration")
        let defaults = NotchPomodoroConfiguration()
        suite.expect(NotchPomodoroOption.focus.range.contains(defaults.focusMinutes)
               && NotchPomodoroOption.shortBreak.range.contains(defaults.shortBreakMinutes)
               && NotchPomodoroOption.longBreak.range.contains(defaults.longBreakMinutes)
               && NotchPomodoroOption.longBreakInterval.range.contains(defaults.longBreakInterval)
               && NotchPomodoroOption.totalSessions.range.contains(defaults.totalSessions),
               "the default cycle is always on the menus")
    }

    private static func rulerContracts(_ suite: TestSuite) {
        for (minute, expected) in [(1, "1"), (55, "55"), (60, "1h00"), (65, "1h05"),
                                   (140, "2h20"), (143, "2h23"), (180, "3h00")] {
            suite.expect(NotchTimerRulerScale.label(for: minute) == expected,
                   "ruler labels write hours with an h, so an hour mark never reads like the minute clock")
        }
        for minute in [1, 15, 90, 180] {
            suite.expect(NotchTimerRulerScale.offset(of: minute, selected: minute) == 0,
                   "the chosen minute stays under the center pointer, including the initial value and both endpoints")
        }
        suite.expect(NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: 14)) == 14
               && NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: -14)) == 16,
               "dragging the ruler by one tick changes one minute in the matching direction")
        for minute in [1, 5, 15, 30, 180] {
            let offset = NotchTimerRulerScale.offset(of: minute, selected: 15)
            suite.expect(NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: -offset)) == minute,
                   "clicking a drawn tick selects its own minute, with the same spacing used by dragging")
        }
        var value = 15.0
        for _ in 0..<3 { value = NotchTimerRulerScale.moving(value, by: 2) }
        suite.expect(NotchTimerRulerScale.minute(value) == 15, "small movements do not repeatedly change the selected tick")
        value = NotchTimerRulerScale.moving(value, by: 2)
        suite.expect(NotchTimerRulerScale.minute(value) == 14, "fine scroll and drag deltas accumulate until crossing a tick")
        value = NotchTimerRulerScale.moving(1, by: 10_000)
        suite.expect(value == 1 && NotchTimerRulerScale.moving(value, by: -14) == 2,
               "dragging beyond the minimum does not leave a dead zone when reversing")
        value = NotchTimerRulerScale.moving(180, by: -10_000)
        suite.expect(value == 180 && NotchTimerRulerScale.moving(value, by: 14) == 179,
               "dragging beyond the maximum allows an immediate reversal")
        suite.expect(NotchTimerRulerScale.minute(.nan) == 1 && NotchTimerRulerScale.minute(.infinity) == 1
               && NotchTimerRulerScale.minute(.greatestFiniteMagnitude) == 180,
               "invalid or excessive ruler values cannot escape the supported duration range")
    }

    private static func compactTimerContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        for barHeight: CGFloat in [16, 22, 24, 32, 40, 64] {
            for notched in [false, true] {
                for layout in NotchSize.allCases {
                    for room: CGFloat in [-1, 0, 27, 36, 43, 44, 52, 64, 71, 72, 72.9, 79, 80, 100, 200, .nan, .infinity] {
                        let original = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                                     cameraWidth: notched ? 180 : 0, layout: layout,
                                                     menuBarHeight: barHeight, compactSideRoom: room)
                        for downloads in [false, true] {
                            let compact = original.compactTimerGeometry(showsDownloads: downloads)
                            if room.isFinite && room >= 64 {
                                suite.expect(!compact.compactActivityUsesFooter
                                       && compact.compactActivityWingWidth == min(room, downloads ? 80 : 64).rounded(.down),
                                       "timer wings keep their readable width around larger cameras, including simultaneous downloads")
                                suite.expect(compact.compactActivityCameraGap == original.cameraWidth
                                       && compact.compactActivityContentHeight == original.stripHeight,
                                       "narrower timer wings still clear the camera and keep the cutout's height")
                            } else if notched {
                                suite.expect(!compact.compactActivityUsesFooter && compact.compactActivityWingWidth == 0,
                                       "unavailable menu space retracts timer wings without drawing over adjacent menus")
                                suite.expect(compact.activationArea(in: compact.compactActivitySize, hasHeader: false,
                                                             compactActivity: true).size == compact.compactActivitySize,
                                       "a retracted timer keeps the whole camera region available to open its controls")
                            } else {
                                suite.expect(!compact.compactActivityUsesFooter,
                                       "a simulated timer never falls back below the menu bar")
                                suite.expect(compact.compactActivityWingWidth == 0
                                       && compact.compactActivitySize.height == original.menuBarHeight,
                                       "a simulated timer with no side room keeps only the camera profile within the menu bar")
                            }
                            let positioned = compact.frame(for: compact.compactActivitySize)
                            suite.expect(screen.contains(positioned), "compact timer placement stays within the screen")
                            if notched {
                                suite.expect(positioned.maxY == screen.maxY && positioned.height == original.cameraHeight
                                       && compact.compactActivityTopPadding == 0,
                                       "timer and simultaneous downloads stay beside the camera through menu-space changes")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Compact strips measure their margins from the silhouette rather than
    /// from a flat padding, so the promise is geometric: whatever a wing draws
    /// keeps the shared gap from the curve, and the download reading still
    /// fits the narrowest wing in every language.
    private static func compactMarginContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let gap = NotchLayout.compactEdgeGap
        /// Distance from a centred box, anchored at `inset`, to the silhouette.
        func clearance(_ geometry: NotchGeometry, inset: CGFloat, boxHeight: CGFloat, radius: CGFloat) -> CGFloat {
            let surface = geometry.compactActivitySize
            let shoulder = geometry.compactActivityShoulder
            let corner = min(NotchLayout.surfaceRadius(height: surface.height),
                             (surface.width - shoulder * 2) / 2)
            let centre = CGPoint(x: shoulder + corner, y: surface.height - corner)
            let x = inset + geometry.compactActivityHorizontalPadding + radius
            let y = surface.height - (geometry.compactActivityContentHeight - boxHeight) / 2 - radius
            if y <= centre.y { return x - radius - shoulder }
            if x >= centre.x { return surface.height - y - radius }
            return corner - hypot(x - centre.x, y - centre.y) - radius
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NotchDownloadSupport.percentSize, weight: .medium)
        for barHeight: CGFloat in [24, 32, 37, 40, 44, 64] {
            for room: CGFloat in [44, 52, 56, 72, 100, 200] {
                for notched in [true, false] {
                    let geometry = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                                 cameraWidth: notched ? 180 : 160, layout: .compact,
                                                 menuBarHeight: barHeight, compactSideRoom: room)
                    let wing = geometry.compactActivityWingWidth
                    suite.expect(wing == 0 || wing >= 44,
                           "a compact strip either retracts its wings or keeps them wide enough to fill")
                    // Cover, equalizer bar, timer icon, download arrow and the
                    // ink of a percentage. A box too tall for the strip has no
                    // inset that can clear the curve, and keeps the flat margin.
                    for (box, radius) in [(26.0, 26.0 * 0.28), (16.0, 0.9), (20.0, 10.0), (17.0, 8.5),
                                          (NotchDownloadSupport.percentSize * 0.72, 0.0)] {
                        let side = min(box, geometry.compactActivityContentHeight - gap * 2)
                        guard side > 0 else { continue }
                        let corner = min(radius, side / 2)
                        let inset = geometry.compactActivityEdgeInset(boxHeight: side, radius: corner)
                        suite.expect(clearance(geometry, inset: inset, boxHeight: side, radius: corner) >= gap - 0.01,
                               "compact strip content keeps its breathing room from the curved edge")
                    }
                    guard wing >= 44 else { continue }
                    let inset = NotchDownloadSupport.percentInset(in: geometry)
                    for language in AppLanguage.allCases {
                        let reading = (1.0).formatted(NotchDownloadSupport.percentFormat(language)) as NSString
                        let width = reading.size(withAttributes: [.font: font]).width
                        suite.expect(wing - inset >= width * NotchDownloadSupport.percentMinimumScale,
                               "a download reading its last percent keeps one whole line in every language")
                    }
                }
            }
        }
    }

    private static func accessoryContracts(_ suite: TestSuite) {
        for (name, symbol) in [("airpods", "airpods"), ("AIRPODS PRO", "airpodspro"),
                               ("My airpods pro 2", "airpodspro"), ("airpods max", "airpodsmax"),
                               ("Max's airpods", "airpods"), ("Wireless Headphones", "headphones")] {
            suite.expect(NotchAccessorySupport.symbol(for: .audio, name: name) == symbol,
                   "recognized headset families use their native symbol, with generic audio as fallback")
        }
        suite.expect(NotchAccessorySupport.symbol(for: .keyboard, name: "Keyboard") == "keyboard"
               && NotchAccessorySupport.symbol(for: .device, name: "Device") == "dot.radiowaves.left.and.right"
               && NotchAccessorySupport.symbol(for: .device, name: "Alex’s Magic Trackpad") == "rectangle.and.hand.point.up.left",
               "model-specific audio symbols preserve other accessory types")
        for kind: PeripheralBatteryKind in [.audio, .keyboard, .mouse, .trackpad, .device] {
            let symbol = NotchAccessorySupport.symbol(for: kind, name: "Device")
            suite.expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                         "accessory indicators use symbols available on this macOS version")
        }
        func device(_ percent: Int, id: String = "HID:1", name: String = "Keyboard") -> PeripheralBatteryDevice {
            PeripheralBatteryDevice(id: id, name: name, percent: percent, kind: .keyboard)
        }
        var battery = NotchAccessoryBatteryState()
        suite.expect(battery.consume([device(19)]).isEmpty, "enabling accessory alerts establishes a silent baseline even when already low")
        suite.expect(battery.consume([device(18)]).isEmpty && battery.consume([]).isEmpty,
               "the same low episode and missing readings do not create another warning")
        suite.expect(battery.consume([device(25)]).isEmpty, "a measured recharge rearms the low battery warning")
        suite.expect(battery.consume([device(20)]).count == 1, "dropping to 20 percent warns once")
        suite.expect(battery.consume([device(21)]).isEmpty && battery.consume([device(20)]).isEmpty,
               "threshold noise cannot repeatedly alert")
        suite.expect(battery.consume([device(18, id: "Bluetooth:1")]).isEmpty,
               "switching telemetry sources for the same accessory preserves its low episode")
        suite.expect(battery.consume([device(101)]).isEmpty && battery.consume([device(20)]).isEmpty,
               "invalid telemetry cannot masquerade as a recharge")
        _ = battery.consume([device(30)])
        suite.expect(battery.consume([device(10)]).count == 1, "a new discharge after actual recharge can warn again")
        var connections = NotchAccessoryConnectionState()
        connections.establishBaseline(["AA:01"])
        suite.expect(!connections.connected("AA:01"), "initially connected accessories do not replay connection banners")
        suite.expect(connections.connected("AA:02") && !connections.connected("AA:02"),
               "duplicate system callbacks produce one connection event")
        suite.expect(!connections.connected(""), "an unidentified connection cannot enter shared state")
        connections.disconnected("AA:01")
        suite.expect(connections.connected("AA:01"), "only a real disconnection rearms a connection banner")
    }

    private static func gateContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-activities"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "on-demand timer is available by default while camera and accessory monitoring remain opt-in")
        let preferenceKeys = [DefaultsKey.notchTimerEnabled, DefaultsKey.notchCameraEnabled, DefaultsKey.notchAccessoriesEnabled]
        for key in preferenceKeys { defaults.set(true, forKey: key) }
        suite.expect(NotchTimerSupport.isEnabled(in: defaults) && NotchCameraSupport.isEnabled(in: defaults)
               && NotchAccessorySupport.isEnabled(in: defaults), "each explicit opt-in enables its activity")
        suite.expect(NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: false,
            captureControls: false, in: defaults), "the mirror can start only on its selected, expanded surface")
        suite.expect(!NotchCameraSupport.canPresent(expanded: false, selected: .camera, appPanel: false,
            captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .music, appPanel: false,
                captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: true,
                captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: false,
                captureControls: true, in: defaults), "collapse, section changes and replacement surfaces all stop embedded capture")
        defaults.set("timer,camera", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults),
               "hidden activity modules release their resources")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        for feature in [AppFeature.notchTimer, .cameraPreview, .notchAccessories, .monitorPower] {
            defaults.set(false, forKey: feature.availabilityKey)
        }
        suite.expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "the feature hub gates the owner of each activity")
        for feature in [AppFeature.notchTimer, .cameraPreview, .notchAccessories, .monitorPower] {
            defaults.set(true, forKey: feature.availabilityKey)
        }
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "the notch master switch gates all activities")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: Set(preferenceKeys + [
            AppFeature.notchTimer.availabilityKey, AppFeature.notchAccessories.availabilityKey])),
               "activity preferences and feature availability round-trip through settings backup")
        suite.expect(!Defaults.registeredDefaults.keys.contains(where: { $0 == "notchTimerSession" || $0 == "notchCameraSession" }),
               "live countdown and capture sessions are not persisted as settings")
        for language in AppLanguage.allCases {
            for child in Mirror(reflecting: FeatureStrings.notchActivities(language)).children {
                if let value = child.value as? String {
                    suite.expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !value.contains("—"),
                           "activity copy is present and human-readable for \(language.rawValue) \(child.label ?? "")")
                }
            }
        }
    }
}
