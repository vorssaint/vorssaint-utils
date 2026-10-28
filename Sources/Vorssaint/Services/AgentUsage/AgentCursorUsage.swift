// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreFoundation
import Foundation

/// Reduces Cursor's dashboard responses to usage counters. No chat content or
/// account identifiers are retained. Cursor's desktop usage service keeps its
/// readings in memory, rather than in a local usage-history file.
enum AgentCursorUsage {
    static let bundleIdentifier = "com.todesktop.230313mzl4w4u92"
    static let downloadURL = URL(string: "https://cursor.com/downloads")!
    static let freshness: TimeInterval = 10 * 60
    static let maximumSize = 8 << 20

    struct Summary: Equatable {
        let limits: AgentLimits
        let plan: AgentPlan?
    }

    static func summary(_ data: Data, now: Date) -> Summary? {
        guard let json = object(data),
              let end = date(json["billingCycleEnd"]), end > now,
              let start = date(json["billingCycleStart"]), start <= now, start < end,
              end.timeIntervalSince(start) <= 366 * 86_400,
              let individual = json["individualUsage"] as? [String: Any] else { return nil }
        var windows: [AgentLimitWindow] = []
        // A personal overall cap, when supplied, is the account's binding allowance.
        for key in ["overall", "plan"] {
            guard let plan = individual[key] as? [String: Any], plan["enabled"] as? Bool != false,
                  let limit = number(plan["limit"]), limit > 0,
                  let used = number(plan["used"]), used >= 0 else { continue }
            let percent = key == "plan" ? number(plan["totalPercentUsed"]) ?? used / limit * 100 : used / limit * 100
            guard percent.isFinite, percent >= 0 else { continue }
            windows.append(AgentLimitWindow(id: "cursor.\(key)", kind: .other,
                minutes: Int(end.timeIntervalSince(start) / 60), scope: nil,
                usedPercent: min(100, percent), resetsAt: end))
            break
        }
        guard !windows.isEmpty else { return nil }
        let name = (json["membershipType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Summary(limits: AgentLimits(provider: .cursor, windows: windows, observedAt: now, source: .account),
                       plan: name.map { AgentPlan(name: $0.prefix(1).uppercased() + $0.dropFirst(), monthlyPrice: nil) })
    }

    struct Page {
        let total: Int
        let records: [AgentUsageRecord]
    }

    /// Rows are not silently discarded: a partial page must never replace a
    /// complete reading with a smaller total. Identical responses can be real
    /// separate requests, so pagination is validated before replacing history.
    static func page(_ data: Data, since: Date, until: Date) -> Page? {
        guard let json = object(data) else { return nil }
        if json.isEmpty { return Page(total: 0, records: []) }
        guard let count = integer(json["totalUsageEventsCount"]) else { return nil }
        if json.count == 1 { return Page(total: count, records: []) }
        guard let rows = json["usageEventsDisplay"] as? [[String: Any]], rows.count <= 1_000 else { return nil }
        var records: [AgentUsageRecord] = []
        for row in rows {
            guard let milliseconds = number(row["timestamp"]), milliseconds > 0,
                  let usage = row["tokenUsage"] as? [String: Any],
                  let input = integer(usage["inputTokens"]), let output = integer(usage["outputTokens"]),
                  let read = integer(usage["cacheReadTokens"]), let write = integer(usage["cacheWriteTokens"]),
                  [input, output, read, write].reduce(0.0, { $0 + Double($1) }) < Double(Int.max) else { return nil }
            let moment = Date(timeIntervalSince1970: milliseconds / 1_000)
            guard moment >= since, moment <= until else { return nil }
            let cents = number(usage["totalCents"])
            let cost = cents.flatMap { $0 >= 0 ? $0 / 100 : nil }
            records.append(AgentUsageRecord(provider: .cursor, date: moment, model: row["model"] as? String ?? "",
                project: "", session: "", tokens: AgentTokens(input: input, cacheWrite: write, cacheRead: read, output: output),
                cost: cost, savings: 0, reportedCost: true))
        }
        return Page(total: count, records: records)
    }

    private static func object(_ data: Data) -> [String: Any]? {
        guard data.count <= maximumSize else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite {
            return number.doubleValue
        }
        if let string = value as? String, let number = Double(string), number.isFinite { return number }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number >= 0, number < Double(Int.max), number.rounded(.down) == number else { return nil }
        return Int(number)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
