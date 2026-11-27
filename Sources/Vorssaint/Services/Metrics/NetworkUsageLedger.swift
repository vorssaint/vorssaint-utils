// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Bytes moved on one local calendar day.
struct NetworkUsageDay: Codable, Equatable {
    /// Local calendar day as `yyyy-MM-dd`.
    let day: String
    var down: UInt64
    var up: UInt64
}

/// Per-day network usage kept on disk. Pure value type: it never reads the
/// clock or the counters itself, so every rule here is testable.
///
/// Only dates and byte counts are stored. Nothing about apps, hosts or
/// addresses, and nothing ever leaves the Mac.
struct NetworkUsageLedger: Codable, Equatable {
    static let retentionDays = 90

    var version = 1
    /// Oldest first, at most one entry per day.
    private(set) var days: [NetworkUsageDay] = []
    /// The last cumulative counters seen, so a restart of the app keeps counting
    /// from where it stopped instead of losing the traffic in between.
    var lastReceived: UInt64?
    var lastSent: UInt64?
    var lastInterfaces: [String]?
    /// Boot time of the Mac when the counters above were read. The kernel
    /// counters start at zero on every boot.
    var lastBootTime: TimeInterval?

    /// Feeds one reading of the cumulative interface counters.
    ///
    /// - First reading, or a different set of interfaces (Wi-Fi ↔ Ethernet):
    ///   only becomes the new baseline, so a change of connection never shows
    ///   up as a burst of traffic.
    /// - The Mac rebooted (boot time changed, or the counters went backwards):
    ///   the counters restarted at zero, so everything they hold now is new.
    /// - Otherwise the difference is added to `day`.
    mutating func record(received: UInt64, sent: UInt64, interfaces: Set<String>,
                         bootTime: TimeInterval?, day: String) {
        let sortedInterfaces = interfaces.sorted()
        defer {
            lastReceived = received
            lastSent = sent
            lastInterfaces = sortedInterfaces
            lastBootTime = bootTime
        }
        guard let previousReceived = lastReceived, let previousSent = lastSent,
              lastInterfaces == sortedInterfaces else { return }

        let rebooted = (bootTime != nil && lastBootTime != nil && bootTime != lastBootTime)
            || received < previousReceived || sent < previousSent
        let down = rebooted ? received : received - previousReceived
        let up = rebooted ? sent : sent - previousSent
        add(down: down, up: up, day: day)
    }

    mutating func add(down: UInt64, up: UInt64, day: String) {
        guard down > 0 || up > 0 else { return }
        if let index = days.lastIndex(where: { $0.day == day }) {
            days[index].down = Self.saturatingAdd(days[index].down, down)
            days[index].up = Self.saturatingAdd(days[index].up, up)
        } else {
            days.append(NetworkUsageDay(day: day, down: down, up: up))
            days.sort { $0.day < $1.day }
        }
    }

    /// Drops days older than `retentionDays` before `today`.
    mutating func prune(today: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -(Self.retentionDays - 1),
                                         to: calendar.startOfDay(for: today)) else { return }
        let cutoffKey = Self.dayKey(cutoff, calendar: calendar)
        days.removeAll { $0.day < cutoffKey }
    }

    mutating func resetUsage() {
        days = []
    }

    /// One entry per day for the `count` days ending on `today` (oldest first);
    /// days without traffic are zero.
    func daily(lastDays count: Int, today: Date, calendar: Calendar = .current) -> [NetworkUsageDay] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: today)
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let key = Self.dayKey(date, calendar: calendar)
            return byDay[key] ?? NetworkUsageDay(day: key, down: 0, up: 0)
        }
    }

    /// Total over the `count` days ending on `today`, today included.
    func total(lastDays count: Int, today: Date, calendar: Calendar = .current) -> (down: UInt64, up: UInt64) {
        daily(lastDays: count, today: today, calendar: calendar).reduce((down: 0, up: 0)) {
            (Self.saturatingAdd($0.down, $1.down), Self.saturatingAdd($0.up, $1.up))
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? .max : result.partialValue
    }
}
