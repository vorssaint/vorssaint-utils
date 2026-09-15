// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchActivityTests {
    static func run(expect: (Bool, String) -> Void) {
        timerContracts(expect: expect)
        alertContracts(expect: expect)
        pomodoroContracts(expect: expect)
        rulerContracts(expect: expect)
        compactTimerContracts(expect: expect)
        accessoryContracts(expect: expect)
        PeripheralBatteryLifecycleTests.run(expect: expect)
        gateContracts(expect: expect)
    }

    private static func alertContracts(expect: (Bool, String) -> Void) {
        let suite = "com.vorssaint.tests.timer-alert"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(NotchTimerSupport.isSoundEnabled(in: defaults), "timer sound is enabled by default")
        for enabled in [false, true] {
            defaults.set(enabled, forKey: DefaultsKey.notchTimerSoundEnabled)
            expect(NotchTimerSupport.isSoundEnabled(in: defaults) == enabled,
                   "the sound preference survives reload")
        }
        expect(Defaults.registeredDefaults[DefaultsKey.notchTimerSoundEnabled] as? Bool == true
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchTimerSoundEnabled),
               "the sound preference is registered and included in settings backup")
        expect(NotchTimerAlert.maximumDuration == .seconds(300), "an alarm is limited to five minutes")
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
        expect(sounds == 0, "a timer completed with sound disabled stays silent")
        alert.start(enabled: true)
        expect(sounds == 1, "an enabled sound alarm alerts immediately")
        alert.start(enabled: true)
        expect(sounds == 1, "preference synchronization does not duplicate a pending alarm")
        wait { sounds >= 3 }
        expect(sounds >= 3, "an unacknowledged sound alarm repeats")
        alert.start(enabled: false)
        let mutedSounds = sounds
        settle()
        expect(sounds == mutedSounds && stops > 0, "disabling sound stops current playback and repetition")
        elapsed = .seconds(299)
        alert.start(enabled: true)
        expect(sounds == mutedSounds + 1, "sound can resume within the original alarm budget")
        alert.suspend()
        let suspendedSounds = sounds
        settle()
        expect(sounds == suspendedSounds, "suspension cancels sound playback")
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
        expect(stops > expirationStops && sounds == expiredSounds,
               "five minutes stop playback; preference changes and suspension cannot restart an expired alarm")
        alert.stop()
        alert.start(enabled: true)
        expect(sounds == expiredSounds + 1, "a new timer phase gets a fresh alert budget")
        alert.stop()
        let cancelledSounds = sounds
        settle()
        expect(sounds == cancelledSounds, "dismissal prevents delayed playback")
    }

    private static func timerContracts(expect: (Bool, String) -> Void) {
        var session = NotchTimerSession()
        expect(!session.hasSession, "an unused timer has no active session")
        session.start(mode: .timer, minutes: 5, now: 100)
        expect(session.remaining(at: 101.25) == 298.75, "countdown uses an absolute deadline, including fractional elapsed time")
        session.start(mode: .pomodoro, minutes: 25, now: 105)
        expect(session.mode == .timer && session.deadline == 400, "starting twice cannot replace an active timer")
        session.pause(at: 160)
        expect(session.isPaused && session.remaining(at: 10_000) == 240, "paused time stays fixed across sleep")
        session.resume(at: 10_000)
        expect(session.deadline == 10_240 && session.remaining(at: 10_100) == 140, "resume preserves only the remaining duration")
        expect(!session.finishIfDue(at: 10_239.999), "fractional time before the deadline is not complete")
        expect(session.finishIfDue(at: 100_000) && session.completed, "returning from sleep finishes an overdue timer once")
        expect(!session.finishIfDue(at: 100_001), "repeated callbacks cannot announce the same completion twice")
        session.cancel()
        expect(!session.hasSession && session.completedFocuses == 0, "cancel discards the entire session")
        session.start(mode: .timer, minutes: 0, now: 0)
        expect(session.duration == 60, "timer input cannot create an immediately expired session")
        session.pause(at: 60)
        expect(session.completed && !session.isPaused, "pausing at the deadline completes instead of preserving a zero timer")
        session.cancel()
        session.start(mode: .timer, minutes: Int.max, now: 0)
        expect(session.duration == 10_800, "corrupt duration input stays within three hours")
        expect(NotchTimerSupport.clockText(0.01) == "00:01" && NotchTimerSupport.clockText(-1) == "00:00"
               && NotchTimerSupport.clockText(.nan) == "00:00", "display rounds up and safely handles invalid remaining time")
        let clockCases: [(TimeInterval, String)] = [
            (59, "00:59"), (60, "01:00"), (3599, "59:59"), (3599.01, "1:00:00"),
            (3600, "1:00:00"), (3601, "1:00:01"), (8580, "2:23:00"),
            (10800, "3:00:00"), (.greatestFiniteMagnitude, "3:00:00"), (.infinity, "00:00")
        ]
        for (seconds, expected) in clockCases {
            expect(NotchTimerSupport.clockText(seconds) == expected,
                   "timer clocks show hours at the hour boundary while preserving seconds: \(seconds)")
        }
        let locale = Locale(identifier: "en_US")
        expect(NotchTimerSupport.compactText(870, locale: locale) == "14m"
               && NotchTimerSupport.compactText(60, locale: locale) == "1m",
               "compact timers show whole remaining minutes without overstating a partial minute")
        expect(NotchTimerSupport.compactText(59, locale: locale) == "59s"
               && NotchTimerSupport.compactText(0.01, locale: locale) == "1s",
               "compact timers switch to seconds for the final minute and never finish early")
        let compactCases: [(TimeInterval, String)] = [
            (3599, "59m"), (3599.01, "1h"), (3600, "1h"), (3659, "1h"),
            (3660, "1h 1m"), (8580, "2h 23m"), (10800, "3h")
        ]
        for (seconds, expected) in compactCases {
            expect(NotchTimerSupport.compactText(seconds, locale: locale) == expected,
                   "compact timers and focus durations show hours and whole minutes: \(seconds)")
        }
        for invalid in [Double.nan, .infinity, -1, 0] {
            expect(NotchTimerSupport.compactText(invalid, locale: locale) == "0s",
                   "invalid or expired compact times remain safe to display")
        }
        expect(NotchTimerSupport.compactText(.greatestFiniteMagnitude, locale: locale) == "3h",
               "compact duration formatting preserves the timer's upper limit")
        for language in AppLanguage.allCases {
            expect(!NotchTimerSupport.compactText(870, locale: Locale(identifier: language.rawValue)).isEmpty,
                   "remaining time has a compact unit in every supported language")
            expect(!NotchTimerSupport.compactText(8580, locale: Locale(identifier: language.rawValue)).isEmpty,
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
                expect(geometry.contentSize(for: setup).height >= 202
                       && geometry.contentSize(for: active).height >= 96 && active.height < setup.height,
                       "timer setup has room for its ruler and active controls use a shorter horizontal surface")
                expect(screen.contains(geometry.frame(for: setup)) && screen.contains(geometry.frame(for: active))
                       && geometry.frame(for: setup).maxY == geometry.frame(for: active).maxY,
                       "starting a timer preserves the screen's top edge and keeps both sizes on screen")
            }
        }
        session.cancel()
        session.start(mode: .pomodoro, minutes: 5, now: 0, configuration: NotchPomodoroConfiguration(totalSessions: 5))
        var now: TimeInterval = 0
        for round in 1...4 {
            expect(session.phase == .focus && session.duration == 1500, "each focus phase lasts 25 minutes")
            now += 1500
            expect(session.finishIfDue(at: now), "each focus deadline completes")
            expect(session.completedFocuses == round && !session.isRunning, "focus completion waits for explicit continuation")
            expect(session.nextPhase == (round == 4 ? .longBreak : .shortBreak), "the fourth completed focus schedules a long break")
            session.startNext(at: now)
            let breakDuration: TimeInterval = round == 4 ? 900 : 300
            expect(session.duration == breakDuration, "break durations distinguish the short and long phases")
            now += breakDuration
            _ = session.finishIfDue(at: now)
            expect(session.nextPhase == .focus, "a completed break returns to focus")
            session.startNext(at: now)
        }
        now += 100_000
        expect(session.finishIfDue(at: now) && session.completedFocuses == 5 && session.completed,
               "a long sleep never manufactures unattended pomodoro cycles")
        let request = CameraPreviewRequest()
        expect(!request.isCancelled, "a new camera request can configure the shared capture session")
        request.cancel(); request.cancel()
        expect(request.isCancelled, "closing a mirror cancels queued configuration idempotently")
    }

    private static func pomodoroContracts(expect: (Bool, String) -> Void) {
        let config = NotchPomodoroConfiguration(focusMinutes: 10, shortBreakMinutes: 2,
                                              longBreakMinutes: 7, longBreakInterval: 2, totalSessions: 3)
        var session = NotchTimerSession()
        session.start(mode: .pomodoro, minutes: 1, now: 0, configuration: config)
        expect(session.duration == 600 && session.sessionNumber == 1 && !session.canStartNext,
               "custom focus duration starts the first session and cannot be skipped while active")
        session.pause(at: 100)
        session.resume(at: 1_000)
        expect(session.deadline == 1_500 && session.configuration == config,
               "pause and resume preserve the cycle configuration and remaining focus time")
        var now = 1_500.0
        for round in 1...3 {
            expect(session.finishIfDue(at: now) && session.completedFocuses == round,
                   "each configured focus session counts exactly once")
            expect(session.sessionNumber == round && !session.finishIfDue(at: now + 1),
                   "completed phases retain their progress and reject duplicate completion")
            if round == 3 { break }
            expect(session.canStartNext && !session.cycleFinished, "unfinished cycles offer explicit continuation")
            session.startNext(at: now)
            let expectedBreak = round == 1 ? 120.0 : 420.0
            expect(session.duration == expectedBreak && session.phase == (round == 1 ? .shortBreak : .longBreak),
                   "configured interval chooses the correct short or long break duration")
            now += expectedBreak
            _ = session.finishIfDue(at: now)
            expect(session.completedFocuses == round, "breaks do not count toward the focus-session goal")
            session.startNext(at: now)
            expect(session.phase == .focus && session.duration == 600 && session.sessionNumber == round + 1,
                   "each new focus uses the same configuration and advances visible progress")
            now += 600
        }
        expect(session.cycleFinished && !session.canStartNext && !session.isRunning,
               "the final focus ends the cycle without an extra break")
        let finished = session
        session.startNext(at: now + 1)
        expect(session == finished, "continuation cannot restart a finished cycle")
        session.cancel()
        session.start(mode: .pomodoro, minutes: 1, now: 0,
                      configuration: NotchPomodoroConfiguration(longBreakInterval: 1, totalSessions: 1))
        _ = session.finishIfDue(at: 100_000)
        expect(session.cycleFinished && session.completedFocuses == 1 && !session.canStartNext,
               "a one-session goal ends at focus completion even when a long break would otherwise be due")
        let bounded = NotchPomodoroConfiguration(focusMinutes: Int.max, shortBreakMinutes: Int.min,
            longBreakMinutes: Int.max, longBreakInterval: 0, totalSessions: Int.max)
        expect(bounded.focusMinutes == 180 && bounded.shortBreakMinutes == 1 && bounded.longBreakMinutes == 60
               && bounded.longBreakInterval == 1 && bounded.totalSessions == 24,
               "restored out-of-range values cannot overflow deadlines or create invalid cycle intervals")
        let suite = "com.vorssaint.tests.pomodoro"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys: Set<String> = [DefaultsKey.notchPomodoroFocusMinutes, DefaultsKey.notchPomodoroShortBreakMinutes,
            DefaultsKey.notchPomodoroLongBreakMinutes, DefaultsKey.notchPomodoroLongBreakInterval,
            DefaultsKey.notchPomodoroTotalSessions, DefaultsKey.notchTimerMode]
        expect(keys.isSubset(of: Set(Defaults.registeredDefaults.keys))
               && keys.isSubset(of: SettingsBackupSupport.exportKeys()),
               "all Pomodoro choices, including the selected mode, are registered and included in settings backup")
        defaults.set(45, forKey: DefaultsKey.notchPomodoroFocusMinutes)
        defaults.set(8, forKey: DefaultsKey.notchPomodoroShortBreakMinutes)
        defaults.set(20, forKey: DefaultsKey.notchPomodoroLongBreakMinutes)
        defaults.set(3, forKey: DefaultsKey.notchPomodoroLongBreakInterval)
        defaults.set(6, forKey: DefaultsKey.notchPomodoroTotalSessions)
        let saved = NotchPomodoroConfiguration.load(in: defaults)
        expect(saved == NotchPomodoroConfiguration(focusMinutes: 45, shortBreakMinutes: 8,
            longBreakMinutes: 20, longBreakInterval: 3, totalSessions: 6), "saved choices restore the whole cycle")
        session.cancel()
        session.start(mode: .pomodoro, minutes: 1, now: 0, configuration: saved)
        defaults.set(1, forKey: DefaultsKey.notchPomodoroFocusMinutes)
        expect(session.configuration == saved && session.duration == 2_700,
               "changes to saved preferences never rewrite an already running cycle")
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32, cameraWidth: 180)
        let setup = geometry.expandedSize(module: .timer, timerShowsPomodoro: true)
        let active = geometry.expandedSize(module: .timer, timerHasSession: true, timerShowsPomodoro: true)
        expect(geometry.contentSize(for: setup).height >= 370 && geometry.contentSize(for: active).height >= 118,
               "the Pomodoro setup and progress row receive their own content budget")
    }

    private static func rulerContracts(expect: (Bool, String) -> Void) {
        for (minute, expected) in [(1, "1"), (55, "55"), (60, "1:00"), (65, "1:05"),
                                   (140, "2:20"), (143, "2:23"), (180, "3:00")] {
            expect(NotchTimerRulerScale.label(for: minute) == expected,
                   "ruler labels show hours and minutes for selections of an hour or more")
        }
        for minute in [1, 15, 90, 180] {
            expect(NotchTimerRulerScale.offset(of: minute, selected: minute) == 0,
                   "the chosen minute stays under the center pointer, including the initial value and both endpoints")
        }
        expect(NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: 14)) == 14
               && NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: -14)) == 16,
               "dragging the ruler by one tick changes one minute in the matching direction")
        for minute in [1, 5, 15, 30, 180] {
            let offset = NotchTimerRulerScale.offset(of: minute, selected: 15)
            expect(NotchTimerRulerScale.minute(NotchTimerRulerScale.moving(15, by: -offset)) == minute,
                   "clicking a drawn tick selects its own minute, with the same spacing used by dragging")
        }
        var value = 15.0
        for _ in 0..<3 { value = NotchTimerRulerScale.moving(value, by: 2) }
        expect(NotchTimerRulerScale.minute(value) == 15, "small movements do not repeatedly change the selected tick")
        value = NotchTimerRulerScale.moving(value, by: 2)
        expect(NotchTimerRulerScale.minute(value) == 14, "fine scroll and drag deltas accumulate until crossing a tick")
        value = NotchTimerRulerScale.moving(1, by: 10_000)
        expect(value == 1 && NotchTimerRulerScale.moving(value, by: -14) == 2,
               "dragging beyond the minimum does not leave a dead zone when reversing")
        value = NotchTimerRulerScale.moving(180, by: -10_000)
        expect(value == 180 && NotchTimerRulerScale.moving(value, by: 14) == 179,
               "dragging beyond the maximum allows an immediate reversal")
        expect(NotchTimerRulerScale.minute(.nan) == 1 && NotchTimerRulerScale.minute(.infinity) == 1
               && NotchTimerRulerScale.minute(.greatestFiniteMagnitude) == 180,
               "invalid or excessive ruler values cannot escape the supported duration range")
    }

    private static func compactTimerContracts(expect: (Bool, String) -> Void) {
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
                            if room.isFinite && room >= 72 {
                                expect(!compact.compactActivityUsesFooter
                                       && compact.compactActivityWingWidth == min(room, downloads ? 80 : 72).rounded(.down),
                                       "timer wings keep their readable width around larger cameras, including simultaneous downloads")
                                expect(compact.compactActivityCameraGap == original.cameraWidth
                                       && compact.compactActivityContentHeight == original.menuBarHeight,
                                       "narrower timer wings still clear the camera and preserve the menu bar height")
                            } else if notched {
                                expect(!compact.compactActivityUsesFooter && compact.compactActivityWingWidth == 0,
                                       "unavailable menu space retracts timer wings without drawing over adjacent menus")
                                expect(compact.activationArea(in: compact.compactActivitySize, hasHeader: false,
                                                             compactActivity: true).size == compact.compactActivitySize,
                                       "a retracted timer keeps the whole camera region available to open its controls")
                            } else {
                                expect(!compact.compactActivityUsesFooter,
                                       "a simulated timer never falls back below the menu bar")
                                expect(compact.compactActivityWingWidth == 0
                                       && compact.compactActivitySize.height == original.menuBarHeight,
                                       "a simulated timer with no side room keeps only the camera profile within the menu bar")
                            }
                            let positioned = compact.frame(for: compact.compactActivitySize)
                            expect(screen.contains(positioned), "compact timer placement stays within the screen")
                            if notched {
                                expect(positioned.maxY == screen.maxY && positioned.height == original.menuBarHeight
                                       && compact.compactActivityTopPadding == 0,
                                       "timer and simultaneous downloads stay beside the camera through menu-space changes")
                            }
                        }
                    }
                }
            }
        }
    }

    private static func accessoryContracts(expect: (Bool, String) -> Void) {
        func device(_ percent: Int, id: String = "HID:1", name: String = "Keyboard") -> PeripheralBatteryDevice {
            PeripheralBatteryDevice(id: id, name: name, percent: percent, kind: .keyboard)
        }
        var battery = NotchAccessoryBatteryState()
        expect(battery.consume([device(19)]).isEmpty, "enabling accessory alerts establishes a silent baseline even when already low")
        expect(battery.consume([device(18)]).isEmpty && battery.consume([]).isEmpty,
               "the same low episode and missing readings do not create another warning")
        expect(battery.consume([device(25)]).isEmpty, "a measured recharge rearms the low battery warning")
        expect(battery.consume([device(20)]).count == 1, "dropping to 20 percent warns once")
        expect(battery.consume([device(21)]).isEmpty && battery.consume([device(20)]).isEmpty,
               "threshold noise cannot repeatedly alert")
        expect(battery.consume([device(18, id: "Bluetooth:1")]).isEmpty,
               "switching telemetry sources for the same accessory preserves its low episode")
        expect(battery.consume([device(101)]).isEmpty && battery.consume([device(20)]).isEmpty,
               "invalid telemetry cannot masquerade as a recharge")
        _ = battery.consume([device(30)])
        expect(battery.consume([device(10)]).count == 1, "a new discharge after actual recharge can warn again")
        var connections = NotchAccessoryConnectionState()
        connections.establishBaseline(["AA:01"])
        expect(!connections.connected("AA:01"), "initially connected accessories do not replay connection banners")
        expect(connections.connected("AA:02") && !connections.connected("AA:02"),
               "duplicate system callbacks produce one connection event")
        expect(!connections.connected(""), "an unidentified connection cannot enter shared state")
        connections.disconnected("AA:01")
        expect(connections.connected("AA:01"), "only a real disconnection rearms a connection banner")
    }

    private static func gateContracts(expect: (Bool, String) -> Void) {
        let suite = "com.vorssaint.tests.notch-activities"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        expect(NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "on-demand timer is available by default while camera and accessory monitoring remain opt-in")
        let preferenceKeys = [DefaultsKey.notchTimerEnabled, DefaultsKey.notchCameraEnabled, DefaultsKey.notchAccessoriesEnabled]
        for key in preferenceKeys { defaults.set(true, forKey: key) }
        expect(NotchTimerSupport.isEnabled(in: defaults) && NotchCameraSupport.isEnabled(in: defaults)
               && NotchAccessorySupport.isEnabled(in: defaults), "each explicit opt-in enables its activity")
        expect(NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: false,
            captureControls: false, in: defaults), "the mirror can start only on its selected, expanded surface")
        expect(!NotchCameraSupport.canPresent(expanded: false, selected: .camera, appPanel: false,
            captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .music, appPanel: false,
                captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: true,
                captureControls: false, in: defaults)
            && !NotchCameraSupport.canPresent(expanded: true, selected: .camera, appPanel: false,
                captureControls: true, in: defaults), "collapse, section changes and replacement surfaces all stop embedded capture")
        defaults.set("timer,camera", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults),
               "hidden activity modules release their resources")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        for feature in [AppFeature.notchTimer, .cameraPreview, .notchAccessories, .monitorPower] {
            defaults.set(false, forKey: feature.availabilityKey)
        }
        expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "the feature hub gates the owner of each activity")
        for feature in [AppFeature.notchTimer, .cameraPreview, .notchAccessories, .monitorPower] {
            defaults.set(true, forKey: feature.availabilityKey)
        }
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        expect(!NotchTimerSupport.isEnabled(in: defaults) && !NotchCameraSupport.isEnabled(in: defaults)
               && !NotchAccessorySupport.isEnabled(in: defaults), "the notch master switch gates all activities")
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: Set(preferenceKeys + [
            AppFeature.notchTimer.availabilityKey, AppFeature.notchAccessories.availabilityKey])),
               "activity preferences and feature availability round-trip through settings backup")
        expect(!Defaults.registeredDefaults.keys.contains(where: { $0 == "notchTimerSession" || $0 == "notchCameraSession" }),
               "live countdown and capture sessions are not persisted as settings")
        for language in AppLanguage.allCases {
            for child in Mirror(reflecting: FeatureStrings.notchActivities(language)).children {
                if let value = child.value as? String {
                    expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !value.contains("—"),
                           "activity copy is present and human-readable for \(language.rawValue) \(child.label ?? "")")
                }
            }
        }
    }
}
