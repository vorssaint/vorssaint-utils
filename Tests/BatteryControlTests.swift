// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BatteryControlTests {
    static func reading(_ percent: Int, temperature: Double? = 30, plugged: Bool = true,
                        full: Bool = false, closed: Bool = false) -> BatteryTelemetry {
        .init(percent: percent, temperature: temperature, adapterConnected: plugged, charging: !full,
              full: full, clamshell: closed)
    }
    static func run(_ t: TestSuite) {
        var c = BatteryConfiguration(); c.enabled = true
        var p = BatteryPolicy()
        t.expect(p.evaluate(c, reading: reading(60)).state == .charging, "charges below the limit")
        t.expect(p.evaluate(c, reading: reading(80)).state == .holding, "holds at the limit")
        t.expect(p.evaluate(c, reading: reading(78)).state == .sailing, "does not recharge small dips")
        t.expect(p.evaluate(c, reading: reading(75)).state == .charging, "recharges at the lower boundary")
        t.expect(!p.evaluate(c, reading: reading(90)).disconnectAdapter, "a normal charge hold never drains the battery")
        t.expect(p.evaluate(c, reading: reading(70, temperature: 35)).state == .heatProtection, "temperature boundary pauses")
        t.expect(p.evaluate(c, reading: reading(70, temperature: 34)).state == .heatProtection, "temperature hysteresis prevents chatter")
        t.expect(p.evaluate(c, reading: reading(70, temperature: 33)).state == .charging, "resumes after cooling")
        t.expect(p.evaluate(c, reading: reading(70, temperature: nil)).state == .unavailable, "missing temperature cannot defeat enabled protection")
        t.expect(p.evaluate(c, reading: nil).state == .unavailable, "missing battery telemetry fails closed")
        t.expect(p.evaluate(c, reading: reading(101)).state == .unavailable, "invalid percent is rejected")
        c.enabled = false
        t.expect(p.evaluate(c, reading: reading(70)).state == .disabled, "disabled control returns to system")
        c.enabled = true
        t.expect(p.perform(.discharge, value: 60, configuration: &c, reading: reading(80), now: Date()), "manual discharge starts")
        t.expect(p.evaluate(c, reading: reading(70)).disconnectAdapter, "manual discharge drains above its target")
        t.expect(!p.evaluate(c, reading: reading(70, closed: true)).disconnectAdapter, "clamshell discharge is opt-in")
        c.dischargeInClamshell = true
        t.expect(p.evaluate(c, reading: reading(70, closed: true)).disconnectAdapter, "explicit clamshell permission allows discharge")
        t.expect(!p.evaluate(c, reading: reading(60)).disconnectAdapter && p.mode == .automatic, "reconnects at discharge target")
        _ = p.perform(.discharge, value: 60, configuration: &c, reading: reading(80), now: Date())
        t.expect(p.evaluate(c, reading: reading(75, plugged: false)).state == .onBattery && p.mode == .automatic, "unplug cancels discharge")
        _ = p.perform(.topUp, value: 80, configuration: &c, reading: reading(80), now: Date())
        t.expect(p.evaluate(c, reading: reading(99)).limit == 100, "top-up temporarily requests full charge")
        t.expect(p.evaluate(c, reading: reading(100, full: false)).state == .topUp, "displayed 100 alone is not completion")
        t.expect(p.evaluate(c, reading: reading(100, full: true)).limit == 80 && p.mode == .automatic, "full battery restores saved limit")
        t.expect(c.limit == 80, "temporary actions never overwrite saved limit")
        _ = p.perform(.calibrate, value: 80, configuration: &c, reading: reading(60), now: Date())
        t.expect(p.evaluate(c, reading: reading(60)).limit == 100 && p.phase == .firstCharge, "calibration charges first")
        t.expect(p.evaluate(c, reading: reading(100, full: true)).disconnectAdapter && p.phase == .drain, "full charge advances to controlled drain")
        t.expect(!p.evaluate(c, reading: reading(10)).disconnectAdapter && p.phase == .finalCharge, "calibration reconnects at 10 percent")
        t.expect(p.evaluate(c, reading: reading(70, temperature: 40)).state == .heatProtection, "calibration retains thermal protection")
        t.expect(p.evaluate(c, reading: reading(100, full: true)).disconnectAdapter && p.phase == .returnToLimit, "second full charge returns to saved limit")
        t.expect(!p.evaluate(c, reading: reading(80)).disconnectAdapter && p.mode == .automatic, "calibration finishes at the saved limit")
        _ = p.perform(.calibrate, value: 80, configuration: &c, reading: reading(60), now: Date())
        _ = p.evaluate(c, reading: reading(100, full: true))
        _ = p.perform(.cancel, value: 80, configuration: &c, reading: reading(90), now: Date())
        t.expect(!p.evaluate(c, reading: reading(90)).disconnectAdapter, "cancel promptly reconnects the adapter")
        _ = p.perform(.discharge, value: 60, configuration: &c, reading: reading(90), now: Date())
        t.expect(!p.evaluate(c, reading: reading(85), sleeping: true).disconnectAdapter, "sleep always ends forced adapter disconnection")
        let old = Date().addingTimeInterval(-49 * 3600)
        _ = p.perform(.topUp, value: 80, configuration: &c, reading: reading(50), now: old)
        _ = p.evaluate(c, reading: reading(60))
        t.expect(p.mode == .automatic, "abandoned temporary operation expires")
        c.automaticDischarge = true
        t.expect(p.evaluate(c, reading: reading(90)).disconnectAdapter, "automatic discharge is explicit opt-in")
        t.expect(!p.evaluate(c, reading: reading(10)).disconnectAdapter, "automatic discharge cannot drain below limit")

        // All combinations must preserve valid native limits and the adapter floor.
        for limit in stride(from: 20, through: 100, by: 5) {
            c.limit = limit
            for percent in 0...100 {
                for temperature in [20.0, 35, 45] {
                    var policy = BatteryPolicy()
                    let decision = policy.evaluate(c, reading: reading(percent, temperature: temperature))
                    t.expect((20...100).contains(decision.limit), "native requests stay bounded")
                    t.expect(!decision.disconnectAdapter || percent > 10, "never disconnect at battery safety floor")
                    t.expect(temperature < 35 || !decision.disconnectAdapter, "thermal pause reconnects adapter")
                }
            }
        }
        c.limit = 101; t.expect(!c.valid, "reject invalid configured limit")
        c.limit = 20; c.sailing = 20; t.expect(!c.valid, "reject sailing range below floor")
        c.sailing = 5; c.maximumTemperature = 100; t.expect(!c.valid, "reject invalid thermal threshold")
        c = BatteryConfiguration(); c.sailing = 20
        _ = p.perform(.setLimit, value: 20, configuration: &c, reading: reading(50), now: Date())
        t.expect(c.valid && c.sailing == 10, "a scheduled limit change preserves a valid recharge range")
        c = BatteryConfiguration()
        c.schedules = Array(repeating: BatterySchedule(), count: 2)
        t.expect(!c.valid, "reject duplicated schedule identities")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9))!
        var schedule = BatterySchedule(date: friday, repetition: .weekdays)
        t.expect(schedule.next(after: friday, calendar: calendar) == monday, "weekday schedule skips weekend")
        schedule.repetition = .once
        t.expect(schedule.next(after: friday, calendar: calendar) == nil, "one-shot schedules do not repeat")
        for repetition in BatteryRepeat.allCases where repetition != .once {
            schedule.repetition = repetition
            t.expect(schedule.next(after: friday.addingTimeInterval(400 * 86400), calendar: calendar)! > friday.addingTimeInterval(400 * 86400), "missed schedules advance beyond now")
        }
        let expected = Set(BatteryControlStrings.values(.enUS).keys)
        for language in AppLanguage.allCases {
            t.expect(Set(BatteryControlStrings.values(language).keys) == expected, "all battery controls have locale coverage")
            t.expect(BatteryControlStrings.values(language).values.allSatisfy { !$0.isEmpty }, "battery translations are populated")
        }
    }
}
