// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NetworkUsageTests {
    static func run(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ text: String) -> Date {
            let parts = text.split(separator: "-").map { Int($0)! }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
        }
        let wifi: Set<String> = ["en0"]

        // First reading is only a baseline.
        var ledger = NetworkUsageLedger()
        ledger.record(received: 1_000, sent: 500, interfaces: wifi, bootTime: 100, day: "2026-11-28")
        suite.expect(ledger.days.isEmpty, "first reading only sets the baseline")

        // Normal deltas accumulate into the day.
        ledger.record(received: 3_000, sent: 700, interfaces: wifi, bootTime: 100, day: "2026-11-28")
        ledger.record(received: 4_000, sent: 1_000, interfaces: wifi, bootTime: 100, day: "2026-11-28")
        suite.expect(ledger.days == [NetworkUsageDay(day: "2026-11-28", down: 3_000, up: 500)],
                     "deltas add up within a day: \(ledger.days)")

        // Midnight starts a new day.
        ledger.record(received: 5_000, sent: 1_100, interfaces: wifi, bootTime: 100, day: "2026-11-29")
        suite.expect(ledger.days.count == 2 && ledger.days[1] == NetworkUsageDay(day: "2026-11-29", down: 1_000, up: 100),
                     "a new day gets its own entry")

        // Reboot: counters restart at zero, what they hold now is new traffic.
        ledger.record(received: 200, sent: 50, interfaces: wifi, bootTime: 900, day: "2026-11-29")
        suite.expect(ledger.days[1] == NetworkUsageDay(day: "2026-11-29", down: 1_200, up: 150),
                     "reboot counts the new counters, never a negative or huge delta")

        // Counters that went backwards without a known boot time are a reset too.
        ledger.record(received: 100, sent: 10, interfaces: wifi, bootTime: nil, day: "2026-11-29")
        suite.expect(ledger.days[1].down == 1_300 && ledger.days[1].up == 160,
                     "counters going backwards count as a reset")

        // Switching interfaces only rebaselines.
        ledger.record(received: 9_999_999, sent: 9_999_999, interfaces: ["en1"], bootTime: 900, day: "2026-11-29")
        suite.expect(ledger.days[1].down == 1_300, "an interface change is not a traffic spike")

        // Totals and daily series, missing days as zero.
        let today = date("2026-11-29")
        let total7 = ledger.total(lastDays: 7, today: today, calendar: calendar)
        suite.expect(total7.down == 4_300 && total7.up == 660, "7-day total: \(total7)")
        let todayTotal = ledger.total(lastDays: 1, today: today, calendar: calendar)
        suite.expect(todayTotal.down == 1_300, "today's total")
        let series = ledger.daily(lastDays: 30, today: today, calendar: calendar)
        suite.expect(series.count == 30 && series.last?.day == "2026-11-29" && series.first?.day == "2026-10-31",
                     "30-day series ends today and covers 30 days")
        suite.expect(series.filter { $0.down == 0 && $0.up == 0 }.count == 28, "days without traffic are zero")

        // Retention keeps only the last 90 days.
        var old = NetworkUsageLedger()
        old.add(down: 1, up: 1, day: "2026-01-01")
        old.add(down: 2, up: 2, day: "2026-11-01")
        old.prune(today: today, calendar: calendar)
        suite.expect(old.days.map(\.day) == ["2026-11-01"], "days older than 90 are dropped")

        // Out-of-order insert keeps days sorted; saturating add never wraps.
        old.add(down: 1, up: 0, day: "2026-10-15")
        suite.expect(old.days.map(\.day) == ["2026-10-15", "2026-11-01"], "days stay sorted")
        old.add(down: .max, up: 0, day: "2026-11-01")
        suite.expect(old.days[1].down == .max, "totals saturate instead of overflowing")

        // Survives a save and load.
        let data = try? JSONEncoder().encode(ledger)
        let decoded = data.flatMap { try? JSONDecoder().decode(NetworkUsageLedger.self, from: $0) }
        suite.expect(decoded == ledger, "ledger round-trips through JSON")

        ledger.resetUsage()
        suite.expect(ledger.days.isEmpty && ledger.lastReceived != nil, "reset clears usage but keeps the baseline")

        suite.expect(NetworkUsageLedger.dayKey(date("2026-03-07"), calendar: calendar) == "2026-03-07", "day key format")
    }
}
