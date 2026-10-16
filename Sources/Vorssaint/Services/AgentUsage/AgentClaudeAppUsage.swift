// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Claude app checks the plan's limits itself and keeps a month of them on
/// this Mac, a percentage for each window every few minutes, while its menu
/// bar icon is on. That file is all Vorssaint reads for them: no sign-in is
/// used and nothing is sent. The format is the app's own, so a version or an
/// entry this reader does not know is left out rather than guessed.
enum AgentClaudeAppUsage {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"
    static let downloadURL = URL(string: "https://claude.ai/download")!
    /// The app checks every five to fifteen minutes; a reading older than
    /// this has missed a check.
    static let freshness: TimeInterval = 30 * 60
    private static let maximumSize = 4 << 20

    static func historyURL(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Claude/plan-usage-history.json", directoryHint: .notDirectory)
    }

    /// When the app last saved its limits, straight from the file.
    static func lastCheck(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Date? {
        (try? Data(contentsOf: historyURL(home: home))).flatMap(samples)?.last?.date
    }

    struct Sample: Equatable {
        let date: Date
        let organization: String?
        /// Percent used, by the file's key for each window.
        let used: [String: Double]
    }

    private static let windows: [(key: String, kind: AgentLimitWindow.Kind, minutes: Int, scope: String?)] = [
        ("fh", .session, 300, nil), ("sd", .weekly, 10_080, nil),
        ("so", .weekly, 10_080, "Opus"), ("sn", .weekly, 10_080, "Sonnet")]

    /// Readings oldest first; nil for a file this reader does not know.
    static func samples(from data: Data) -> [Sample]? {
        guard data.count <= maximumSize,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = (json["version"] as? NSNumber)?.intValue, version == 1 || version == 2,
              let entries = json["samples"] as? [[String: Any]] else { return nil }
        var result: [Sample] = []
        for entry in entries {
            guard let milliseconds = (entry["t"] as? NSNumber)?.doubleValue, milliseconds.isFinite,
                  milliseconds > 0 else { continue }
            // The first version kept its two windows beside the time.
            let values = version == 1 ? entry : (entry["u"] as? [String: Any] ?? [:])
            var used: [String: Double] = [:]
            for window in windows {
                guard let number = values[window.key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite else { continue }
                used[window.key] = min(100, max(0, number.doubleValue))
            }
            result.append(Sample(date: Date(timeIntervalSince1970: milliseconds / 1_000),
                                 organization: entry["org"] as? String, used: used))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// The latest reading as limit windows. The file keeps percentages, not
    /// renewal times: a session renews five hours after its first request,
    /// which the history brackets and Claude Code's own first request can
    /// narrow, and a week renews every seven days at the moment of the
    /// last drop the history saw.
    static func limits(from samples: [Sample], now: Date, sessionStart: Date? = nil,
                       organization: String? = nil) -> AgentLimits? {
        let samples = readings(samples, organization: organization)
        guard let latest = samples.last, latest.date <= now.addingTimeInterval(300),
              now.timeIntervalSince(latest.date) < 7 * 86_400 else { return nil }
        let history = samples.filter { $0.organization == latest.organization }
        var result: [AgentLimitWindow] = []
        for window in windows {
            guard let used = latest.used[window.key] else { continue }
            let length = TimeInterval(window.minutes) * 60
            // An old reading says nothing about a session that renewed since.
            if window.kind == .session, now.timeIntervalSince(latest.date) >= length { continue }
            let session = window.kind == .session
                ? sessionEnd(history, used: used, start: sessionStart, length: length) : nil
            let resets = window.kind == .session
                ? session?.latest
                : renewal(history, key: window.key, length: length, after: latest.date)
            // A window that renewed after the reading has spent an unknown
            // amount since, and without a date a day-old week may have too.
            if let resets, resets <= now { continue }
            if resets == nil, now.timeIntervalSince(latest.date) >= 86_400 { continue }
            result.append(AgentLimitWindow(id: "claude.\(window.key)", kind: window.kind, minutes: window.minutes,
                                           scope: window.scope, usedPercent: used, resetsAt: resets,
                                           estimatedResetsAt: session?.estimate))
        }
        guard !result.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: result, observedAt: latest.date, source: .claudeApp)
    }

    /// Where Claude Code's own first request places the session the newest
    /// reading saw. Taken at that reading rather than now, so a session that
    /// has since ended keeps its renewal instead of moving to five hours after
    /// the reading that first saw it.
    static func sessionStart(_ records: [AgentUsageRecord], samples: [Sample], organization: String? = nil) -> Date? {
        guard let reading = readings(samples, organization: organization).last?.date else { return nil }
        let recent = records.filter {
            $0.provider == .claude && $0.date <= reading && reading.timeIntervalSince($0.date) < AgentUsageSummary.blockHistory
        }
        return AgentUsageSummary.currentBlock(recent, now: reading)?.start
    }

    /// The app may be signed in to another account than Claude Code; its
    /// limits say nothing about this one.
    private static func readings(_ samples: [Sample], organization: String?) -> [Sample] {
        organization.map { account in samples.filter { $0.organization == nil || $0.organization == account } } ?? samples
    }

    private static func sessionEnd(_ history: [Sample], used: Double, start: Date?, length: TimeInterval)
        -> (latest: Date, estimate: Date?)? {
        guard used > 0, var first = history.indices.last else { return nil }
        // The run of readings above zero that ends with the latest one. A drop
        // is a renewal too: work that goes on across one never reads zero.
        while first > 0, let before = history[first - 1].used["fh"], before > 0,
              before <= (history[first].used["fh"] ?? 0) + 1,
              history[first].date.timeIntervalSince(history[first - 1].date) < length {
            first -= 1
        }
        let latest = history[first].date
        let earliest = first > 0 ? history[first - 1].date : latest.addingTimeInterval(-length)
        if let start, start > earliest, start <= latest {
            return (start.addingTimeInterval(length), nil)
        }
        let estimate = unseenStart(earliest: earliest, latest: latest, bracketed: first > 0, length: length)
        // The midpoint can precede the real renewal. Keep the latest possible
        // end for expiring usage and alerts; only the card uses the estimate.
        return (latest.addingTimeInterval(length), estimate < latest ? estimate.addingTimeInterval(length) : nil)
    }

    /// Where a session began when only the readings place it. Readings a few
    /// minutes apart bracket it closely, so the first one above zero stands.
    /// A longer gap means the app missed checks, with the Mac asleep or the
    /// app closed, and the session began somewhere in it, though no more than
    /// a session's length before the reading that still sees it. That first
    /// reading is the latest the start can be, so it puts the renewal as late
    /// as it can be, by hours after a long gap. The middle of the range is
    /// still an estimate, off by up to half of it and able to fall before the
    /// real renewal, but it halves the worst error.
    private static func unseenStart(earliest: Date, latest: Date, bracketed: Bool, length: TimeInterval) -> Date {
        guard bracketed, latest.timeIntervalSince(earliest) > freshness else { return latest }
        let lower = max(earliest, latest.addingTimeInterval(-length))
        return lower.addingTimeInterval(latest.timeIntervalSince(lower) / 2)
    }

    /// The first renewal after `reading`, from the last drop the history saw.
    private static func renewal(_ history: [Sample], key: String, length: TimeInterval, after reading: Date) -> Date? {
        for index in history.indices.dropFirst().reversed() {
            guard let before = history[index - 1].used[key], let after = history[index].used[key],
                  after + 1 < before else { continue }
            // Allowances renew on the hour, when the gap between readings holds one.
            let next = hour(of: history[index - 1].date).addingTimeInterval(3_600)
            var moment = next <= history[index].date ? next : history[index].date
            while moment <= reading { moment.addTimeInterval(length) }
            return moment
        }
        return nil
    }

    /// Allowances renew on the hour in UTC, which a half-hour time zone
    /// sees at half past.
    static func hour(of date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }
}
