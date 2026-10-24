// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production timer, Escape and teardown methods with a controllable timer
/// and main queue. Tests never install an input tap or lock the real keyboard.
enum CleaningModeTimerTests {
    enum UserDefaults {
        static var current: Foundation.UserDefaults!
        static var standard: Foundation.UserDefaults { current }
    }
    final class Timer {
        let fireDate: Date
        let repeats: Bool
        let callback: (Timer) -> Void
        var invalidated = false
        init(fire date: Date, interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) {
            fireDate = date
            self.repeats = repeats
            callback = block
        }
        func invalidate() { invalidated = true }
        // Deliver even after cancellation to test stale callback protection.
        func fire() { callback(self) }
    }
    enum RunLoop {
        enum Mode { case common }
        static var main = Loop()
        final class Loop {
            var timers: [Timer] = []
            func add(_ timer: Timer, forMode: Mode) { timers.append(timer) }
        }
    }
    enum DispatchQueue {
        static var main = Queue()
        final class Queue {
            var jobs: [() -> Void] = []
            func async(_ job: @escaping () -> Void) { jobs.append(job) }
            func drain() {
                let pending = jobs
                jobs.removeAll()
                pending.forEach { $0() }
            }
        }
    }
    final class Work { func cancel() {} }
    class Fixture {
        var isActive = true
        var autoUnlockDate: Date?
        var autoUnlockTimer: Timer?
        var releaseDeadline: Work?
        var mouseReleaseGate = CleaningMouseReleaseGate()
        var unlock = CleaningUnlockCounter(requiredKeyCode: 53, threshold: 5, pressWindow: 6)
        var unlockProgress = 0
        var shouldRestoreSuspendedFeaturesOnSessionReturn = false
        var teardowns = 0
        var resumes = 0
        func armReleaseDeadline() { releaseDeadline = Work() }
        func removeTap() { teardowns += 1 }
        func removeScreenObserver() {}
        func hideOverlays() {}
        func resumeSuspendedFeatures() { resumes += 1 }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.cleaning-timer"
        let defaults = Foundation.UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defaults.register(defaults: Defaults.registeredDefaults)
        UserDefaults.current = defaults
        defer {
            UserDefaults.current = nil
            defaults.removePersistentDomain(forName: domain)
            RunLoop.main = RunLoop.Loop()
            DispatchQueue.main = DispatchQueue.Queue()
        }
        suite.expect(defaults.integer(forKey: DefaultsKey.cleaningModeAutoUnlockSeconds) == 0,
                     "automatic unlock is off by default")
        suite.expect(!defaults.bool(forKey: DefaultsKey.cleaningModeAutoUnlockUsesUntil)
                     && defaults.double(forKey: DefaultsKey.cleaningModeAutoUnlockTime) == 0,
                     "Until is off with no saved time by default")
        suite.expect(CleaningModeTimerSupport.durations == DurationPicker.choices.map { $0 * 60 },
                     "Cleaning Mode offers exactly the Keep Awake presets in the same order")
        for invalid in [-1, 1, 31, 59, 301, Int.max] {
            defaults.set(invalid, forKey: DefaultsKey.cleaningModeAutoUnlockSeconds)
            let service = Service()
            service.startAutoUnlockTimer()
            suite.expect(service.autoUnlockTimer == nil && service.autoUnlockDate == nil,
                         "unsupported timer duration \(invalid) safely leaves automatic unlock off")
        }
        for seconds in CleaningModeTimerSupport.durations {
            defaults.set(seconds, forKey: DefaultsKey.cleaningModeAutoUnlockSeconds)
            let service = Service()
            let before = Date()
            service.startAutoUnlockTimer()
            guard seconds > 0 else {
                suite.expect(service.autoUnlockTimer == nil && service.autoUnlockDate == nil,
                             "infinity does not schedule a timer or show a countdown")
                continue
            }
            let timer = service.autoUnlockTimer!
            suite.expect(!timer.repeats && timer.fireDate == service.autoUnlockDate
                         && abs(timer.fireDate.timeIntervalSince(before) - Double(seconds)) < 1,
                         "\(seconds) seconds schedules one timer at the countdown deadline")
            suite.expect(RunLoop.main.timers.last === timer,
                         "auto-unlock remains scheduled in the common run-loop modes")
            timer.fire()
            suite.expect(service.isActive && service.mouseReleaseGate.deactivationPending,
                         "expiry queues the existing safe unlock path")
            DispatchQueue.main.drain()
            suite.expect(!service.isActive && service.teardowns == 1 && service.resumes == 1
                         && service.autoUnlockDate == nil && timer.invalidated,
                         "expiry unlocks and cancels the timer and countdown")
        }

        defaults.set(900, forKey: DefaultsKey.cleaningModeAutoUnlockSeconds)
        let early = Service()
        early.startAutoUnlockTimer()
        let oldTimer = early.autoUnlockTimer!
        for i in 1...5 {
            early.registerUnlockKeyDown(code: 53, isRepeat: false)
            if i < 5 {
                suite.expect(!early.mouseReleaseGate.deactivationPending,
                             "the timer does not reduce the five-Escape requirement")
            }
        }
        DispatchQueue.main.drain()
        suite.expect(!early.isActive && oldTimer.invalidated && early.autoUnlockDate == nil,
                     "five Escapes unlock early and cancel automatic unlock")
        early.isActive = true
        early.startAutoUnlockTimer()
        oldTimer.fire()
        DispatchQueue.main.drain()
        suite.expect(early.isActive && !early.mouseReleaseGate.deactivationPending,
                     "a previous session's callback cannot unlock a new session")
        early.deactivate()
        DispatchQueue.main.drain()
        suite.expect(!early.isActive && early.autoUnlockTimer == nil,
                     "the Unlock button's action also cancels a timed session")

        let held = Service()
        held.startAutoUnlockTimer()
        held.mouseReleaseGate.buttonDown(0)
        held.autoUnlockTimer!.fire()
        DispatchQueue.main.drain()
        suite.expect(held.isActive && held.mouseReleaseGate.deactivationPending,
                     "timer expiry waits for a mouse press that began during cleaning")
        if held.mouseReleaseGate.buttonUp(0) { held.scheduleUserDeactivation() }
        DispatchQueue.main.drain()
        suite.expect(!held.isActive && held.teardowns == 1,
                     "the real mouse release completes the timed unlock")

        let switchedAway = Service()
        switchedAway.startAutoUnlockTimer()
        let abandonedTimer = switchedAway.autoUnlockTimer!
        switchedAway.finishDeactivation(restoreSuspendedFeatures: false)
        abandonedTimer.fire()
        DispatchQueue.main.drain()
        suite.expect(abandonedTimer.invalidated && switchedAway.autoUnlockDate == nil
                     && switchedAway.teardowns == 1 && switchedAway.resumes == 0,
                     "session teardown cancels expiry without resuming suspended features")

        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23,
                                                             hour: 10, minute: 30, second: 15))!
        let later = Calendar.current.date(bySettingHour: 14, minute: 20, second: 0, of: now)!
        let past = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: past)!
        suite.expect(CleaningModeTimerSupport.deadline(seconds: 900, usesUntil: true,
                         savedUntilTime: later.timeIntervalSinceReferenceDate, now: now) == later,
                     "Until takes precedence over a saved preset and selects a later time today")
        suite.expect(CleaningModeTimerSupport.deadline(seconds: 0, usesUntil: true,
                         savedUntilTime: past.timeIntervalSinceReferenceDate, now: now) == tomorrow,
                     "an Until time already past today uses tomorrow, like Keep Awake")
        suite.expect(CleaningModeTimerSupport.deadline(seconds: 900, usesUntil: false,
                         savedUntilTime: later.timeIntervalSinceReferenceDate, now: now)
                         == now.addingTimeInterval(900),
                     "selecting a preset uses its duration even after Until was configured")
        suite.expect(CleaningModeTimerSupport.deadline(seconds: 0, usesUntil: false,
                         savedUntilTime: later.timeIntervalSinceReferenceDate, now: now) == nil,
                     "selecting infinity disables automatic unlock after an Until session")

        defaults.set(true, forKey: DefaultsKey.cleaningModeAutoUnlockUsesUntil)
        for invalid in [0.0, -1, Double.nan, .infinity, .greatestFiniteMagnitude] {
            defaults.set(invalid, forKey: DefaultsKey.cleaningModeAutoUnlockTime)
            let invalidUntil = Service()
            invalidUntil.startAutoUnlockTimer()
            suite.expect(invalidUntil.autoUnlockTimer == nil && invalidUntil.autoUnlockDate == nil,
                         "invalid saved Until time leaves manual unlock available")
        }
        let picked = Date().addingTimeInterval(3600)
        defaults.set(picked.timeIntervalSinceReferenceDate, forKey: DefaultsKey.cleaningModeAutoUnlockTime)
        let expectedEnd = KeepAwakeAutomationSupport.resolvedUntilDate(picked: picked, now: Date())
        let until = Service()
        until.startAutoUnlockTimer()
        suite.expect(until.autoUnlockDate == expectedEnd && until.autoUnlockTimer?.fireDate == expectedEnd,
                     "the custom Until choice schedules its resolved wall-clock deadline")
        until.autoUnlockTimer!.fire()
        DispatchQueue.main.drain()
        suite.expect(!until.isActive && until.autoUnlockTimer == nil && until.autoUnlockDate == nil,
                     "the Until timer automatically unlocks through the existing release gate")

        for language in AppLanguage.allCases {
            let text = FeatureStrings.cleaningMode(language)
            suite.expect(!text.autoUnlockAfter.isEmpty && !text.timerCaption.isEmpty,
                         "timer controls have localized text in \(language.rawValue)")
            for seconds in CleaningModeTimerSupport.durations {
                suite.expect(CleaningModeTimerSupport.title(seconds: seconds, language: language)
                             == DurationPicker.shortTitle(for: seconds / 60, Strings.localized(language), language),
                             "timer choice \(seconds) uses Keep Awake's label in \(language.rawValue)")
            }
        }
    }
}
