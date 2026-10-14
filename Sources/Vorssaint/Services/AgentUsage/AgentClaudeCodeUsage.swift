// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Claude Code checks the plan's limits itself while it runs and keeps the
/// last answer in its profile, `~/.claude.json`, with each window's renewal.
/// Only that entry is read: no sign-in is used and nothing is sent. The entry
/// is Claude Code's own and undocumented, so one this reader does not know,
/// or one saved for another account, is left out rather than guessed.
enum AgentClaudeCodeUsage {
    /// Window ids match the Claude app's, so a warned window keeps its warning
    /// whichever of the two read it last.
    private static let windows: [(key: String, id: String, kind: AgentLimitWindow.Kind, minutes: Int, scope: String?)] = [
        ("five_hour", "claude.fh", .session, 300, nil), ("seven_day", "claude.sd", .weekly, 10_080, nil),
        ("seven_day_opus", "claude.so", .weekly, 10_080, "Opus"),
        ("seven_day_sonnet", "claude.sn", .weekly, 10_080, "Sonnet")]

    static func profileURL(home: URL) -> URL {
        home.appending(path: ".claude.json", directoryHint: .notDirectory)
    }

    /// When Claude Code last checked the limits, straight from its profile.
    static func lastCheck(home: URL = FileManager.default.homeDirectoryForCurrentUser, now: Date = Date()) -> Date? {
        guard let data = try? Data(contentsOf: profileURL(home: home), options: .mappedIfSafe),
              let profile = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return validated(reading(from: profile), now: now)?.date
    }

    struct Reading: Equatable {
        let date: Date
        let windows: [AgentLimitWindow]

        /// Each window's renewal by id, for the Claude app's readings of the
        /// same periods.
        var renewals: [String: Date] {
            Dictionary(windows.compactMap { window in window.resetsAt.map { (window.id, $0) } }) { $1 }
        }
    }

    /// The cached reading in the profile, nil when it is missing, malformed or
    /// saved for an account other than the one signed in.
    static func reading(from profile: [String: Any]) -> Reading? {
        guard let cache = profile["cachedUsageUtilization"] as? [String: Any],
              let timestamp = cache["fetchedAtMs"] as? NSNumber, CFGetTypeID(timestamp) != CFBooleanGetTypeID(),
              timestamp.doubleValue.isFinite, timestamp.doubleValue > 0,
              let utilization = cache["utilization"] as? [String: Any] else { return nil }
        let signedIn = (profile["oauthAccount"] as? [String: Any])?["accountUuid"] as? String
        if let account = cache["accountUuid"] as? String, account != signedIn { return nil }
        var result: [AgentLimitWindow] = []
        for window in windows {
            guard let entry = utilization[window.key] as? [String: Any],
                  let number = entry["utilization"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else { continue }
            let resets = (entry["resets_at"] as? String).flatMap(AgentTimestamp.parse)
            result.append(AgentLimitWindow(id: window.id, kind: window.kind, minutes: window.minutes, scope: window.scope,
                                           usedPercent: min(100, max(0, number.doubleValue)), resetsAt: resets))
        }
        guard !result.isEmpty else { return nil }
        return Reading(date: Date(timeIntervalSince1970: timestamp.doubleValue / 1_000), windows: result)
    }

    /// The reading's windows that still hold at `now`. One that renewed since
    /// has spent an unknown amount; without a date, a session is kept for its
    /// length and a week for a day, as with the Claude app's readings.
    static func limits(from reading: Reading?, now: Date) -> AgentLimits? {
        guard let reading = validated(reading, now: now) else { return nil }
        let windows = current(reading, now: now)
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: windows, observedAt: reading.date, source: .claudeCode)
    }

    /// The newer of the Claude app's limits and Claude Code's reading of the
    /// same account, whole: a window from the older one would pass for as
    /// recent as the newer, and one the newer saw renew would come back. The
    /// app's should be read with this reading's `renewals`, so the countdown
    /// does not move as the two take turns.
    static func merged(app: AgentLimits?, code reading: Reading?, now: Date) -> AgentLimits? {
        guard let reading = validated(reading, now: now) else { return app }
        guard let app, app.observedAt >= reading.date else { return limits(from: reading, now: now) }
        return app
    }

    /// Validate before sharing renewal dates with the app source, as well as
    /// before showing the cache itself or its last-check time in Settings.
    static func validated(_ reading: Reading?, now: Date) -> Reading? {
        guard let reading, reading.date <= now.addingTimeInterval(300) else { return nil }
        return reading
    }

    static func limits(app samples: [AgentClaudeAppUsage.Sample], code reading: Reading?, now: Date,
                       sessionStart: Date? = nil, organization: String? = nil) -> AgentLimits? {
        let reading = validated(reading, now: now)
        let app = AgentClaudeAppUsage.limits(from: samples, now: now, sessionStart: sessionStart,
                                             organization: organization, renewals: reading?.renewals ?? [:])
        return merged(app: app, code: reading, now: now)
    }

    private static func current(_ reading: Reading, now: Date) -> [AgentLimitWindow] {
        let age = now.timeIntervalSince(reading.date)
        return reading.windows.filter { window in
            if let resets = window.resetsAt { return resets > now }
            return age < (window.kind == .session ? TimeInterval(window.minutes ?? 300) * 60 : 86_400)
        }
    }
}
