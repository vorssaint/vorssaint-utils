// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Claude Code keeps the plan's limits it last fetched in `~/.claude.json`,
/// every few minutes while it runs, so they stay current without the Claude
/// app. The field is Claude Code's own and undocumented: anything this reader
/// does not know is left out rather than guessed, and nothing is sent.
enum AgentClaudeCodeUsage {
    /// Each window keeps the id the Claude app reader gives it, so an alert
    /// sees the same window when the newer reading switches source.
    private static let windows: [(key: String, id: String, kind: AgentLimitWindow.Kind, minutes: Int, scope: String?)] = [
        ("five_hour", "fh", .session, 300, nil), ("seven_day", "sd", .weekly, 10_080, nil),
        ("seven_day_opus", "so", .weekly, 10_080, "Opus"), ("seven_day_sonnet", "sn", .weekly, 10_080, "Sonnet")]

    static func profileURL(home: URL) -> URL {
        home.appending(path: ".claude.json", directoryHint: .notDirectory)
    }

    /// When Claude Code last fetched its limits, straight from the file.
    static func lastCheck(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Date? {
        guard let data = try? Data(contentsOf: profileURL(home: home), options: .mappedIfSafe),
              let profile = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return reading(from: profile)?.observedAt
    }

    /// The cached reading as Claude Code saved it; nil when it is missing,
    /// malformed or belongs to an account Claude Code has since left.
    static func reading(from profile: [String: Any]) -> AgentLimits? {
        guard let cache = profile["cachedUsageUtilization"] as? [String: Any],
              let milliseconds = (cache["fetchedAtMs"] as? NSNumber)?.doubleValue, milliseconds.isFinite,
              milliseconds > 0, let utilization = cache["utilization"] as? [String: Any] else { return nil }
        let account = (profile["oauthAccount"] as? [String: Any])?["accountUuid"] as? String
        if let cached = cache["accountUuid"] as? String, cached != account { return nil }
        var result: [AgentLimitWindow] = []
        for window in windows {
            guard let entry = utilization[window.key] as? [String: Any],
                  let number = entry["utilization"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else { continue }
            result.append(AgentLimitWindow(id: "claude.\(window.id)", kind: window.kind, minutes: window.minutes,
                                           scope: window.scope, usedPercent: min(100, max(0, number.doubleValue)),
                                           resetsAt: (entry["resets_at"] as? String).flatMap(AgentTimestamp.parse)))
        }
        guard !result.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: result,
                           observedAt: Date(timeIntervalSince1970: milliseconds / 1_000), source: .claudeCode)
    }

    /// What of a reading still holds at `now`: a window that renewed since
    /// has spent an unknown amount, as has an undated one after its length
    /// or, for a week, a day.
    static func limits(_ reading: AgentLimits?, now: Date) -> AgentLimits? {
        guard var reading, reading.observedAt <= now.addingTimeInterval(300) else { return nil }
        let age = now.timeIntervalSince(reading.observedAt)
        reading.windows = reading.windows.filter { window in
            if let resets = window.resetsAt { return resets > now }
            return age < (window.kind == .session ? TimeInterval(window.minutes ?? 0) * 60 : 86_400)
        }
        return reading.windows.isEmpty ? nil : reading
    }

    /// The newer of two readings, with any window only the older one knows,
    /// such as a model's own week, kept from it. A window both cover keeps
    /// Claude Code's renewal time: the app's falls on the hour of its history
    /// while the cache holds the account's own, so following whichever saved
    /// last would make the countdown jump and `crossings` see a renewed
    /// window every few minutes.
    static func combined(_ first: AgentLimits?, _ second: AgentLimits?) -> AgentLimits? {
        guard let first, let second else { return first ?? second }
        let firstIsNewer = first.observedAt >= second.observedAt
        var newer = firstIsNewer ? first : second
        let older = firstIsNewer ? second : first
        let key = { (window: AgentLimitWindow) in "\(window.kind.rawValue):\(window.scope ?? "")" }
        let known = Set(newer.windows.map(key))
        if older.source == .claudeCode {
            let renewals = Dictionary(older.windows.compactMap { window in window.resetsAt.map { (key(window), $0) } },
                                      uniquingKeysWith: { first, _ in first })
            newer.windows = newer.windows.map { window in
                guard let renewal = renewals[key(window)] else { return window }
                return AgentLimitWindow(id: window.id, kind: window.kind, minutes: window.minutes, scope: window.scope,
                                        usedPercent: window.usedPercent, resetsAt: renewal)
            }
        }
        newer.windows += older.windows.filter { !known.contains(key($0)) }
        return newer
    }
}
