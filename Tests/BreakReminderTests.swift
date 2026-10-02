// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakReminderTests {
    static func run(_ suite: TestSuite) {
        rotation(suite)
        policy(suite)
        schedule(suite)
        presence(suite)
        coordinator(suite)
        store(suite)
        hardening(suite)
        holdOffs(suite)
        activitySymbols(suite)
        sounds(suite)
        strings(suite)
    }

    static func store(_ suite: TestSuite) {
        let d = UserDefaults(suiteName: "com.vorssaint.tests.break-reminders")!
        d.removePersistentDomain(forName: "com.vorssaint.tests.break-reminders")
        defer { d.removePersistentDomain(forName: "com.vorssaint.tests.break-reminders") }
        d.register(defaults: Defaults.registeredDefaults)
        let s = BreakSettingsStore.load(d, language: .enUS)
        suite.expect(s.eyes.interval == 1200 && s.eyes.breakLength == 20 && s.eyes.style == .notification,
                     "eyes defaults: 20 min, 20 s, notification")
        suite.expect(s.movement.interval == 3000 && s.movement.breakLength == 120 && s.movement.style == .escalating,
                     "movement defaults: 50 min, 2 min, escalating")
        suite.expect(s.eyes.activities.map(\.seconds) == [20, 10, 10] && s.movement.activities.count == 4,
                     "seeded activities")
        suite.expect(s.pausedUntil == nil && !s.hours.enabled, "no pause and no working hours by default")
        let edited = [BreakActivity(id: UUID(), text: "x", seconds: 7)]
        d.set(BreakSettingsStore.encode(edited), forKey: DefaultsKey.breakRemindersEyesActivities)
        suite.expect(BreakSettingsStore.load(d, language: .enUS).eyes.activities == edited, "edited lists round-trip")
        for key in [DefaultsKey.breakRemindersEyesActivities, DefaultsKey.breakRemindersPausedUntil,
                    DefaultsKey.breakRemindersWorkingDays, DefaultsKey.notchBreakReminders] {
            suite.expect(Defaults.registeredDefaults[key] != nil, "\(key) is registered so backup includes it")
        }
        var changed = s
        changed.eyes.interval = 600
        changed.movement.style = .overlay
        changed.pausedUntil = Date(timeIntervalSince1970: 5000)
        BreakSettingsStore.save(changed, to: d)
        let back = BreakSettingsStore.load(d, language: .enUS)
        suite.expect(back.eyes.interval == 600 && back.movement.style == .overlay
                     && back.pausedUntil == Date(timeIntervalSince1970: 5000), "save then load round-trips settings")
        var r = ActivityRotation(); r.advance(.eyes, count: 3)
        BreakSettingsStore.saveRotation(r, to: d)
        suite.expect(BreakSettingsStore.loadRotation(d).indices[.eyes] == r.indices[.eyes]
                     && BreakSettingsStore.loadRotation(d).indices[.movement] == 0, "rotation round-trips")
    }

    static func hardening(_ suite: TestSuite) {
        var r = ActivityRotation()
        suite.expect(!BreakSettingsStore.rotationNeedsSave(old: r, new: r), "an unchanged rotation is not saved")
        var r2 = r; r2.advance(.eyes, count: 3)
        suite.expect(BreakSettingsStore.rotationNeedsSave(old: r, new: r2), "an advanced rotation is saved")
        r = r2
        var s = settings()
        suite.expect(s.needsTick, "enabled kinds need the tick")
        s.eyes.enabled = false
        suite.expect(s.needsTick, "one enabled kind still needs the tick")
        s.movement.enabled = false
        suite.expect(!s.needsTick, "no enabled kind needs no tick")
        for key in [DefaultsKey.breakRemindersPausedUntil, DefaultsKey.breakRemindersEyesRotationIndex,
                    DefaultsKey.breakRemindersMovementRotationIndex] {
            suite.expect(SettingsBackupSupport.machineStateKeys.contains(key)
                         && !SettingsBackupSupport.exportKeys().contains(key),
                         "\(key) is machine state and never travels in a backup")
        }
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let sunday = 0b0000001
        let hours = WorkingHours(enabled: true, days: sunday, startMinutes: 540, endMinutes: 1080)
        let sat = ny.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        suite.expect(BusyPolicy.pauseUntilTomorrow(now: sat, hours: hours, calendar: ny)
                        == ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9)),
                     "pause across the spring-forward day lands at 09:00 local")
    }

    static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let s = FeatureStrings.breakReminders(language)
            suite.expect(s.defaultEyes.count == 3 && s.defaultMovement.count == 4,
                         "\(language) seeds the same number of activities")
            let all = Mirror(reflecting: s).children.compactMap { $0.value as? String }
                + s.defaultEyes + s.defaultMovement
            suite.expect(all.allSatisfy { !$0.isEmpty }, "\(language) has no empty break string")
            suite.expect(all.allSatisfy { !$0.contains("%") }, "\(language) break strings contain no raw percent")
        }
    }

    static func activity(_ text: String, _ seconds: Int = 20) -> BreakActivity {
        BreakActivity(id: UUID(), text: text, seconds: seconds)
    }

    static func settings(hours: WorkingHours = WorkingHours(enabled: false, days: 0, startMinutes: 540, endMinutes: 1080),
                         paused: Date? = nil) -> BreakSettings {
        BreakSettings(
            eyes: KindSettings(enabled: true, interval: 1200, breakLength: 20, style: .notification, activities: []),
            movement: KindSettings(enabled: true, interval: 3000, breakLength: 120, style: .escalating, activities: []),
            escalateAfter: 120, hours: hours, pausedUntil: paused)
    }

    static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    /// 2026-09-30 is a Wednesday (weekday 4).
    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        gregorian.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    static func rotation(_ suite: TestSuite) {
        let list = [activity("a"), activity("b"), activity("c")]
        var r = ActivityRotation()
        suite.expect(r.current(.eyes, in: list)?.text == "a", "rotation starts at the first activity")
        r.advance(.eyes, count: 3); r.advance(.eyes, count: 3)
        suite.expect(r.current(.eyes, in: list)?.text == "c", "rotation advances in order")
        r.advance(.eyes, count: 3)
        suite.expect(r.current(.eyes, in: list)?.text == "a", "rotation wraps")
        suite.expect(r.current(.movement, in: list)?.text == "a", "kinds rotate independently")

        r.indices[.eyes] = 2
        let shorter = Array(list.prefix(2))
        suite.expect(r.current(.eyes, in: shorter)?.text == "b", "deleting clamps to the last item")
        r.advance(.eyes, count: 2)
        suite.expect(r.current(.eyes, in: shorter)?.text == "a", "advance after a clamp wraps to the start")

        suite.expect(r.current(.eyes, in: []) == nil, "empty list returns nil")
        r.advance(.eyes, count: 0)
        suite.expect(r.indices[.eyes] == 0, "advancing an empty list resets the index")
    }

    static func sounds(_ suite: TestSuite) {
        let a = UUID(), b = UUID()
        var s = BreakSoundState()
        suite.expect(s.start(a), "a new break plays its start sound")
        suite.expect(!s.start(a), "a break escalating to another surface does not replay it")
        suite.expect(s.end(a), "the end sound plays once")
        suite.expect(!s.end(a), "Done after the countdown already ended does not replay it")
        suite.expect(s.start(b) && !s.end(a), "a later break replaces the earlier one")
        s.cancel(b)
        suite.expect(!s.end(b), "a snoozed or skipped break never plays its end sound")
        var fresh = BreakSoundState()
        suite.expect(!fresh.end(a), "no end sound for a break that never started")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.breakRemindersStartSound] as? String == "Tink"
                     && Defaults.registeredDefaults[DefaultsKey.breakRemindersEndSound] as? String == "Glass",
                     "start and end sounds default to Tink and Glass")
    }

    static func activitySymbols(_ suite: TestSuite) {
        let seeded = BreakSettingsStore.activities("", seed: ["a", "b"], seconds: [10, 20], symbols: ["eye"])
        suite.expect(seeded.map { $0.symbol } == ["eye", nil], "seeds take their symbols by position")
        let legacy = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"x","seconds":7}]"#
        let decoded = BreakSettingsStore.activities(legacy, seed: [], seconds: [])
        suite.expect(decoded.count == 1 && decoded[0].symbol == nil && decoded[0].text == "x",
                     "a list saved before symbols existed still loads")
        let roundTrip = BreakSettingsStore.activities(BreakSettingsStore.encode(seeded), seed: [], seconds: [])
        suite.expect(roundTrip == seeded, "symbols survive a save")
        suite.expect(BreakSettingsStore.usesBreakLength("[]"), "an emptied list falls back to the break length")
        suite.expect(!BreakSettingsStore.usesBreakLength("") && !BreakSettingsStore.usesBreakLength(legacy),
                     "seeded or saved activities set their own length")
        suite.expect(BreakSettingsStore.eyesSeedSymbols.count == BreakSettingsStore.eyesSeedSeconds.count
                     && BreakSettingsStore.movementSeedSymbols.count == BreakSettingsStore.movementSeedSeconds.count,
                     "every seeded activity has a symbol")
    }

    static func holdOffs(_ suite: TestSuite) {
        let cal = gregorian
        let now = date(30, 10)
        var s = settings()
        let busy = BreakSignals(micInUse: true, cameraInUse: true, fullscreenFrontmost: true)
        s.holdOffs = HoldOffs(mic: false, camera: false, fullscreen: false, resetWhenAway: true)
        suite.expect(BusyPolicy.verdict(busy, settings: s, now: now, calendar: cal) == .active,
                     "with every hold-off off, mic, camera and fullscreen never defer")
        s.holdOffs.camera = true
        suite.expect(BusyPolicy.verdict(busy, settings: s, now: now, calendar: cal) == .busy,
                     "each hold-off counts on its own")
        s.holdOffs = HoldOffs(mic: false, camera: true, fullscreen: true, resetWhenAway: true)
        suite.expect(BusyPolicy.verdict(BreakSignals(micInUse: true), settings: s, now: now, calendar: cal) == .active,
                     "the mic alone does not defer when its hold-off is off")

        var keep = settings()
        keep.eyes.interval = 100
        keep.movement.enabled = false
        keep.holdOffs.resetWhenAway = false
        var c = BreakCoordinator(rotation: ActivityRotation())
        c.forceState(.eyes, .counting(50))
        _ = c.tick(now: now, dt: 5, verdict: .idle, idleSeconds: 600, awayFor: 900, settings: keep, newID: { UUID() })
        suite.expect(c.schedules[.eyes]?.state == .counting(55),
                     "with the away reset off, an absence keeps the countdown")
        keep.holdOffs.resetWhenAway = true
        _ = c.tick(now: now, dt: 5, verdict: .idle, idleSeconds: 600, awayFor: 900, settings: keep, newID: { UUID() })
        suite.expect(c.schedules[.eyes]?.state == .counting(0), "with the away reset on, an absence restarts it")
    }

    static func policy(_ suite: TestSuite) {
        let cal = gregorian
        let now = date(30, 10)
        func v(_ s: BreakSignals, _ set: BreakSettings = settings()) -> BusyVerdict {
            BusyPolicy.verdict(s, settings: set, now: now, calendar: cal)
        }
        suite.expect(v(BreakSignals()) == .active, "no signals is active")
        suite.expect(v(BreakSignals(micInUse: true)) == .busy, "mic is busy")
        suite.expect(v(BreakSignals(cameraInUse: true)) == .busy, "camera is busy")
        suite.expect(v(BreakSignals(fullscreenFrontmost: true)) == .busy, "fullscreen is busy")
        suite.expect(v(BreakSignals(micInUse: true, idleSeconds: 60)) == .idle, "idle outranks busy")
        suite.expect(v(BreakSignals(idleSeconds: 59)) == .active, "59 s idle is still active")
        suite.expect(v(BreakSignals(idleSeconds: 60), settings(paused: now.addingTimeInterval(1))) == .off,
                     "pause outranks idle")
        suite.expect(v(BreakSignals(), settings(paused: now)) == .active, "a pause ending now has expired")

        let weekdays = 0b0111110 // Mon-Fri
        let work = WorkingHours(enabled: true, days: weekdays, startMinutes: 540, endMinutes: 1080)
        suite.expect(work.contains(date(30, 9), calendar: cal), "start is inclusive")
        suite.expect(!work.contains(date(30, 18), calendar: cal), "end is exclusive")
        suite.expect(!work.contains(date(27, 10), calendar: cal), "Sunday is bit 0 and off")
        suite.expect(BusyPolicy.verdict(BreakSignals(), settings: settings(hours: work), now: date(30, 20), calendar: cal) == .off,
                     "outside hours is off")
        let noDays = WorkingHours(enabled: true, days: 0, startMinutes: 540, endMinutes: 1080)
        let flat = WorkingHours(enabled: true, days: weekdays, startMinutes: 600, endMinutes: 600)
        suite.expect(noDays.contains(date(30, 20), calendar: cal) && flat.contains(date(30, 20), calendar: cal),
                     "degenerate working hours treated as disabled")

        suite.expect(BusyPolicy.pauseUntilTomorrow(now: date(30, 8), hours: work, calendar: cal)
                        == cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9)),
                     "until tomorrow skips a pre-start morning and lands on the next working start")
        let fri = cal.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        suite.expect(BusyPolicy.pauseUntilTomorrow(now: fri, hours: work, calendar: cal)
                        == cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)),
                     "Friday pauses until Monday start")
        suite.expect(BusyPolicy.pauseUntilTomorrow(now: date(30, 15), hours: settings().hours, calendar: cal)
                        == cal.date(from: DateComponents(year: 2026, month: 10, day: 1)),
                     "without working hours, until tomorrow is midnight")
    }

    static func schedule(_ suite: TestSuite) {
        let k = KindSettings(enabled: true, interval: 100, breakLength: 20, style: .overlay, activities: [])
        let t0 = date(30, 10)
        let id = UUID()
        func tick(_ s: inout BreakSchedule, _ v: BusyVerdict, dt: TimeInterval = 5, idle: TimeInterval = 0,
                  away: TimeInterval? = nil, kind: KindSettings = k, now: Date = t0) -> [BreakSchedule.Event] {
            s.tick(dt: dt, verdict: v, idleSeconds: idle, awayFor: away, settings: kind, now: now, newID: { id })
        }

        var s = BreakSchedule()
        _ = tick(&s, .active, dt: 50)
        suite.expect(s.state == .counting(50), "active time counts")
        _ = tick(&s, .busy, dt: 10); _ = tick(&s, .idle, dt: 10, idle: 60)
        suite.expect(s.state == .counting(70), "busy and short idle count as screen time")
        _ = tick(&s, .off, dt: 10)
        suite.expect(s.state == .counting(70), "off freezes the countdown")
        let crossing = tick(&s, .active, dt: 30)
        suite.expect(s.state == .due && crossing.isEmpty, "crossing the interval goes due and emits nothing")
        _ = tick(&s, .off)
        suite.expect(s.state == .due, "due holds while off")
        _ = tick(&s, .busy)
        suite.expect(s.state == .deferred(0), "due while busy defers")
        _ = tick(&s, .active, dt: 25)
        suite.expect(s.state == .deferred(25), "deferred counts active grace")
        _ = tick(&s, .busy)
        suite.expect(s.state == .deferred(0), "busy restarts the grace")
        _ = tick(&s, .active, dt: 25)
        let fired = tick(&s, .active, dt: 5)
        suite.expect(fired == [.prompt(id)], "30 s of active grace prompts")
        suite.expect(s.state == .prompting(id: id, seen: false, deadline: nil), "prompting starts unseen")

        // The tick that crosses the interval while the mic is live does not prompt.
        var m = BreakSchedule(state: .counting(99))
        let crossBusy = tick(&m, .active, dt: 5)
        suite.expect(crossBusy.isEmpty && m.state == .due, "the crossing tick never prompts on unsampled signals")
        _ = tick(&m, .busy)
        suite.expect(m.state == .deferred(0), "the next tick sees the mic and defers")

        // Due while active prompts on the next tick.
        var d = BreakSchedule(state: .due)
        suite.expect(tick(&d, .active) == [.prompt(id)], "due while active prompts")

        // Deadlines start at present time.
        var p = BreakSchedule(state: .prompting(id: id, seen: false, deadline: nil))
        _ = tick(&p, .active, now: t0.addingTimeInterval(10_000))
        suite.expect(p.state == .prompting(id: id, seen: false, deadline: nil), "no deadline before present")
        p.presented(id: id, deadline: t0.addingTimeInterval(80))
        suite.expect(tick(&p, .active, now: t0.addingTimeInterval(79)).isEmpty, "before the deadline nothing ends")
        suite.expect(tick(&p, .active, now: t0.addingTimeInterval(80)) == [.ended(id, advance: true)],
                     "the deadline ends a seen prompt and advances")
        suite.expect(p.state == .counting(0), "timeout returns to counting")

        // Busy and off while prompting.
        var b = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(tick(&b, .busy) == [.ended(id, advance: false)] && b.state == .deferred(0),
                     "a call starting mid-prompt dismisses and defers")
        var o = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(tick(&o, .off) == [.ended(id, advance: false)] && o.state == .counting(0),
                     "pause mid-prompt dismisses and resets")

        // Responses.
        var r = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(r.respond(id: UUID(), action: .done, now: t0).isEmpty, "a stale id is ignored")
        suite.expect(r.respond(id: id, action: .snooze, now: t0) == [.ended(id, advance: false)],
                     "snooze dismisses without advancing")
        suite.expect(r.state == .snoozed(until: t0.addingTimeInterval(300)), "snooze lasts 5 minutes")
        _ = tick(&r, .busy, now: t0.addingTimeInterval(100))
        suite.expect(r.state == .snoozed(until: t0.addingTimeInterval(300)), "snoozed ignores busy before it ends")
        _ = tick(&r, .active, now: t0.addingTimeInterval(300))
        suite.expect(r.state == .due, "snooze end goes due")
        var sOff = BreakSchedule(state: .snoozed(until: t0.addingTimeInterval(300)))
        _ = tick(&sOff, .off)
        suite.expect(sOff.state == .counting(0), "off while snoozed resets")
        var done = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(done.respond(id: id, action: .done, now: t0) == [.ended(id, advance: true)]
                        && done.state == .counting(0), "done advances and resets")

        // Absence.
        var a = BreakSchedule(state: .counting(90))
        _ = tick(&a, .idle, idle: 119)
        suite.expect(a.state == .counting(95), "an idle stretch under the threshold still counts")
        _ = tick(&a, .idle, idle: 120)
        suite.expect(a.state == .counting(0), "idle at max(breakLength, 2 min) resets")
        for i in 0..<300 { _ = tick(&a, .idle, idle: 125 + Double(i) * 5) }
        suite.expect(a.state == .counting(0), "25 minutes idle holds the countdown at zero")
        var aw = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        suite.expect(tick(&aw, .active, away: 180) == [.ended(id, advance: true)] && aw.state == .counting(0),
                     "an absence while a seen prompt is up counts as taken")
        var aw2 = BreakSchedule(state: .prompting(id: id, seen: false, deadline: nil))
        suite.expect(tick(&aw2, .active, away: 180) == [.ended(id, advance: false)],
                     "an absence over an unseen prompt does not advance")
        var shortAway = BreakSchedule(state: .counting(50))
        _ = tick(&shortAway, .active, away: 60)
        suite.expect(shortAway.state == .counting(55), "a short absence does not reset")

        // Disable and settings change.
        var off = BreakSchedule(state: .prompting(id: id, seen: true, deadline: nil))
        var disabled = k; disabled.enabled = false
        suite.expect(tick(&off, .active, kind: disabled) == [.ended(id, advance: false)] && off.state == .counting(0),
                     "disabling mid-prompt dismisses and resets")
        var longer = k; longer.interval = 200
        var keep = BreakSchedule(state: .counting(150))
        _ = tick(&keep, .active, kind: longer)
        suite.expect(keep.state == .counting(155), "a longer interval keeps elapsed time")
        var shorter = k; shorter.interval = 50
        var cut = BreakSchedule(state: .counting(60))
        _ = tick(&cut, .active, kind: shorter)
        suite.expect(cut.state == .due, "a shorter interval re-checks due")
    }

    static func presence(_ suite: TestSuite) {
        let t0 = date(30, 10)
        var away = AwayTracker()
        away.begin(.locked, now: t0)
        away.begin(.screensAsleep, now: t0.addingTimeInterval(10))
        suite.expect(away.end(.screensAsleep, now: t0.addingTimeInterval(60)) == nil,
                     "waking the screen while still locked is still away")
        suite.expect(away.end(.locked, now: t0.addingTimeInterval(200)) == 200,
                     "unlock ends the absence once, measured from its first condition")
        suite.expect(!away.isAway && away.end(.locked, now: t0.addingTimeInterval(300)) == nil,
                     "a second unlock reports nothing")

        var lost = AwayTracker()
        lost.begin(.asleep, now: t0)
        suite.expect(lost.watchdog(now: t0.addingTimeInterval(60), screenLocked: false, idleSeconds: 120) == nil,
                     "the watchdog waits for real input")
        suite.expect(lost.watchdog(now: t0.addingTimeInterval(120), screenLocked: true, idleSeconds: 1) == nil,
                     "the watchdog waits for unlock")
        suite.expect(lost.watchdog(now: t0.addingTimeInterval(180), screenLocked: false, idleSeconds: 1) == 180,
                     "a missed wake notification is recovered by the watchdog")

        var clock = TickClock()
        clock.reset(now: t0)
        let normal = clock.step(now: t0.addingTimeInterval(5), interval: 5)
        suite.expect(normal.dt == 5 && normal.gap == nil, "a normal tick counts its time")
        let gap = clock.step(now: t0.addingTimeInterval(605), interval: 5)
        suite.expect(gap.dt == 0 && gap.gap == 600, "a gap over 2x the tick becomes an absence")
        let back = clock.step(now: t0.addingTimeInterval(500), interval: 5)
        suite.expect(back.dt == 0 && back.gap == nil, "negative and huge gaps never count backwards")

        var watch = NotchBreakWatch()
        let id = UUID()
        suite.expect(watch.displaced(id: id, currentCaptureID: UUID(), visible: false, expanded: true, now: t0),
                     "a replaced capture is displaced at once")
        suite.expect(!watch.displaced(id: id, currentCaptureID: id, visible: false, expanded: true, now: t0),
                     "invisibility starts a timer")
        suite.expect(!watch.displaced(id: id, currentCaptureID: id, visible: false, expanded: true,
                                      now: t0.addingTimeInterval(9)), "under 10 s is not displaced")
        suite.expect(watch.displaced(id: id, currentCaptureID: id, visible: false, expanded: true,
                                     now: t0.addingTimeInterval(10)), "10 s invisible while expanded is displaced")
        var collapsed = NotchBreakWatch()
        _ = collapsed.displaced(id: id, currentCaptureID: id, visible: false, expanded: false, now: t0)
        suite.expect(!collapsed.displaced(id: id, currentCaptureID: id, visible: false, expanded: false,
                                          now: t0.addingTimeInterval(60)), "a collapsed island is never the watch's call")
        var seen = NotchBreakWatch()
        _ = seen.displaced(id: id, currentCaptureID: id, visible: false, expanded: true, now: t0)
        _ = seen.displaced(id: id, currentCaptureID: id, visible: true, expanded: true, now: t0.addingTimeInterval(5))
        suite.expect(!seen.displaced(id: id, currentCaptureID: id, visible: false, expanded: true,
                                     now: t0.addingTimeInterval(12)), "becoming visible restarts the timer")
    }

    static func coordinator(_ suite: TestSuite) {
        let t0 = date(30, 10)
        func next() -> UUID { UUID() }
        func base(eyes: DeliveryStyle = .overlay, movement: DeliveryStyle = .overlay) -> BreakSettings {
            var s = settings()
            s.eyes = KindSettings(enabled: true, interval: 100, breakLength: 20, style: eyes,
                                  activities: [activity("look", 20), activity("close", 10)])
            s.movement = KindSettings(enabled: true, interval: 300, breakLength: 120, style: movement,
                                      activities: [activity("stretch", 60)])
            return s
        }
        func run(_ c: inout BreakCoordinator, _ s: BreakSettings, seconds: Int, verdict: BusyVerdict = .active,
                 from start: Date = t0) -> [BreakCoordinator.Output] {
            var out: [BreakCoordinator.Output] = []
            for i in 0..<(seconds / 5) {
                out += c.tick(now: start.addingTimeInterval(Double(i + 1) * 5), dt: 5, verdict: verdict,
                              idleSeconds: 0, awayFor: nil, settings: s, newID: next)
            }
            return out
        }
        func presents(_ o: [BreakCoordinator.Output]) -> [(BreakKind, DeliveryStyle)] {
            o.compactMap { if case let .present(p, via) = $0 { return (p.kind, via) }; return nil }
        }

        // Eyes prompts after its interval plus one decision tick.
        var c = BreakCoordinator(rotation: ActivityRotation())
        let s = base()
        let first = run(&c, s, seconds: 105)
        suite.expect(presents(first).count == 1 && presents(first)[0] == (.eyes, .overlay),
                     "eyes presents via its style after its interval")
        guard let live = c.livePromptID else { suite.expect(false, "a live prompt exists"); return }
        if case let .present(p, _) = first.last! {
            suite.expect(p.activity?.text == "look" && p.seconds == 20, "the prompt carries the current activity")
        }
        c.presented(id: live, via: .overlay, now: t0.addingTimeInterval(105), settings: s)
        let ended = c.respond(id: live, action: .done, now: t0.addingTimeInterval(110), settings: s)
        suite.expect(ended == [.dismiss(live, via: .overlay)], "done dismisses the current sink")
        suite.expect(c.rotation.current(.eyes, in: s.eyes.activities)?.text == "close", "done advances the rotation")
        suite.expect(c.respond(id: live, action: .done, now: t0, settings: s).isEmpty, "a stale id is ignored")

        // Coalescing: movement prompting resets eyes in every state.
        for eyesState in [BreakSchedule.State.due, .deferred(10), .snoozed(until: t0.addingTimeInterval(60)),
                          .counting(45), .prompting(id: UUID(), seen: true, deadline: nil)] {
            var k = BreakCoordinator(rotation: ActivityRotation())
            k.forceState(.eyes, eyesState)
            k.forceState(.movement, .due)
            let out = k.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: base(),
                             newID: next)
            let kinds = presents(out).map { $0.0 }
            suite.expect(kinds == [.movement], "movement prompting absorbs eyes in state \(eyesState)")
            suite.expect(k.schedules[.eyes]?.state == .counting(0), "eyes resets when movement prompts (\(eyesState))")
        }
        // Eyes may not prompt near or during a movement break.
        for moveState in [BreakSchedule.State.due, .deferred(5), .snoozed(until: t0.addingTimeInterval(60)),
                          .counting(250)] {
            var k = BreakCoordinator(rotation: ActivityRotation())
            k.forceState(.eyes, .due)
            k.forceState(.movement, moveState)
            let out = k.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: base(),
                             newID: next)
            suite.expect(presents(out).allSatisfy { $0.0 != .eyes }, "eyes holds off while movement is \(moveState)")
        }
        var tie = BreakCoordinator(rotation: ActivityRotation())
        tie.forceState(.eyes, .due); tie.forceState(.movement, .due)
        let both = tie.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: base(), newID: next)
        suite.expect(presents(both).map { $0.0 } == [.movement], "a same-tick tie goes to movement")

        // Fallback chain.
        var f = BreakCoordinator(rotation: ActivityRotation())
        f.forceState(.eyes, .due)
        let notchFirst = base(eyes: .notch)
        let p0 = f.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: notchFirst, newID: next)
        suite.expect(presents(p0).map { $0.1 } == [.notch], "requested style first")
        let pid = f.livePromptID!
        suite.expect(presents(f.deliveryFailed(id: pid, via: .notch, now: t0, settings: notchFirst)).map { $0.1 } == [.notification],
                     "notch failure falls through to notification")
        suite.expect(presents(f.deliveryFailed(id: pid, via: .notification, now: t0, settings: notchFirst)).map { $0.1 } == [.overlay],
                     "notch failure falls through to notification then overlay")
        var n = BreakCoordinator(rotation: ActivityRotation())
        n.forceState(.eyes, .due)
        let notifFirst = base(eyes: .notification)
        _ = n.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: notifFirst, newID: next)
        suite.expect(presents(n.deliveryFailed(id: n.livePromptID!, via: .notification, now: t0, settings: notifFirst)).map { $0.1 }
                        == [.notch], "a failed notification tries the notch next")

        // Escalation.
        var e = BreakCoordinator(rotation: ActivityRotation())
        e.forceState(.movement, .due)
        let esc = base(movement: .escalating)
        let e0 = e.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: esc, newID: next)
        suite.expect(presents(e0).map { $0.1 } == [.notch], "escalating starts at the notch")
        let eid = e.livePromptID!
        e.presented(id: eid, via: .notch, now: t0, settings: esc)
        let early = e.tick(now: t0.addingTimeInterval(119), dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                           settings: esc, newID: next)
        suite.expect(early.isEmpty, "no escalation before escalateAfter")
        let up = e.tick(now: t0.addingTimeInterval(120), dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                        settings: esc, newID: next)
        suite.expect(up == [.dismiss(eid, via: .notch), .present(e.prompt(eid)!, via: .overlay)],
                     "escalation dismisses the current sink and presents the overlay")
        var dsp = BreakCoordinator(rotation: ActivityRotation())
        dsp.forceState(.movement, .due)
        _ = dsp.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: esc, newID: next)
        let did = dsp.livePromptID!
        dsp.presented(id: did, via: .notch, now: t0, settings: esc)
        suite.expect(presents(dsp.displaced(id: did, via: .notch, now: t0, settings: esc)).map { $0.1 } == [.overlay],
                     "displacement during escalating goes straight to the overlay")

        // Unseen prompts never advance; seen timeouts do.
        var u = BreakCoordinator(rotation: ActivityRotation())
        u.forceState(.eyes, .due)
        _ = u.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let uid = u.livePromptID!
        _ = u.tick(now: t0.addingTimeInterval(5), dt: 5, verdict: .busy, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        suite.expect(u.rotation.current(.eyes, in: s.eyes.activities)?.text == "look", "an unseen prompt does not advance")
        _ = uid

        var to = BreakCoordinator(rotation: ActivityRotation())
        to.forceState(.eyes, .due)
        _ = to.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let tid = to.livePromptID!
        to.presented(id: tid, via: .overlay, now: t0, settings: s)
        let timeout = to.tick(now: t0.addingTimeInterval(80), dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                              settings: s, newID: next)
        suite.expect(timeout == [.dismiss(tid, via: .overlay)], "overlay times out at seconds + 60 from present")
        suite.expect(to.rotation.current(.eyes, in: s.eyes.activities)?.text == "close", "a seen timeout advances")

        // Settings changes.
        var sc = BreakCoordinator(rotation: ActivityRotation())
        sc.forceState(.eyes, .due)
        _ = sc.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let sid = sc.livePromptID!
        sc.presented(id: sid, via: .overlay, now: t0, settings: s)
        let restyled = sc.settingsChanged(from: s, to: base(eyes: .notification))
        suite.expect(restyled.first == .dismiss(sid, via: .overlay) &&
                     presents(restyled).map { $0.1 } == [.notification] && sc.livePromptID == sid,
                     "a style change re-presents the same prompt id with the new style")
        var bothOff = base(); bothOff.eyes.enabled = false; bothOff.movement.enabled = false
        let killed = sc.tick(now: t0.addingTimeInterval(5), dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                             settings: bothOff, newID: next)
        suite.expect(killed == [.dismiss(sid, via: .notification)] && sc.livePromptID == nil,
                     "disabling both kinds dismisses")
        _ = run(&sc, bothOff, seconds: 1000, from: t0.addingTimeInterval(10))
        suite.expect(sc.livePromptID == nil, "nothing re-fires with both kinds disabled")

        var empty = BreakCoordinator(rotation: ActivityRotation())
        var noActivities = base(); noActivities.eyes.activities = []
        empty.forceState(.eyes, .due)
        let generic = empty.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil,
                                 settings: noActivities, newID: next)
        if case let .present(p, _)? = generic.first {
            suite.expect(p.activity == nil && p.seconds == 20, "prompt with empty activity list uses the break length")
        } else { suite.expect(false, "prompt with empty activity list still presents") }

        var stopping = BreakCoordinator(rotation: ActivityRotation())
        stopping.forceState(.eyes, .due)
        _ = stopping.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let sid2 = stopping.livePromptID!
        suite.expect(stopping.stop() == [.dismiss(sid2, via: .overlay)] && stopping.livePromptID == nil,
                     "stop dismisses the live prompt")
        suite.expect(stopping.deliveryFailed(id: sid2, via: .overlay, now: t0, settings: s).isEmpty,
                     "a fallback after stop presents nothing")

        var quiet = BreakCoordinator(rotation: ActivityRotation())
        quiet.forceState(.eyes, .due)
        _ = quiet.tick(now: t0, dt: 5, verdict: .active, idleSeconds: 0, awayFor: nil, settings: s, newID: next)
        let qid = quiet.livePromptID!
        suite.expect(quiet.stopPromptQuietly(id: qid) == [.dismiss(qid, via: .overlay)] &&
                     quiet.schedules[.eyes]?.state == .counting(0) &&
                     quiet.rotation.current(.eyes, in: s.eyes.activities)?.text == "look",
                     "a session close resets without fallback or advance")

        // A long call: deferral fires 30 s after it ends.
        var call = BreakCoordinator(rotation: ActivityRotation())
        call.forceState(.eyes, .counting(0))
        var single = base(); single.movement.enabled = false
        let during = run(&call, single, seconds: 5400, verdict: .busy)
        suite.expect(presents(during).isEmpty, "nothing presents during a 90-minute call")
        let after = run(&call, single, seconds: 35, from: t0.addingTimeInterval(5400))
        suite.expect(presents(after).count == 1, "the deferred break fires 30 s after the call ends")
    }
}
