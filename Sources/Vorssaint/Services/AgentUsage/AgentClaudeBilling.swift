// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Who pays for Claude Code's own requests. A person can use the plan in the
/// Claude app and an API key in the terminal at once: the plan's limits then
/// come from the account check, while every Claude Code response is spent
/// from the API key's prepaid credits and has nothing to do with the plan.
enum AgentClaudeBilling: String, CaseIterable, Identifiable {
    /// Follows Claude Code's user settings: an API key there wins over a
    /// claude.ai sign-in for its sessions.
    case automatic
    case api
    case subscription

    var id: String { rawValue }

    /// The settings Claude Code reads a key from, by name only; no value is
    /// ever read or kept.
    static let keySettings = ["apiKeyHelper"]
    static let keyEnvironment = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]

    static func chosen(in defaults: UserDefaults = .standard) -> AgentClaudeBilling {
        AgentClaudeBilling(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsClaudeBilling) ?? "") ?? .automatic
    }

    /// Whether Claude Code's sessions bill an API key, as chosen or as its
    /// user settings say.
    static func usesAPI(in defaults: UserDefaults = .standard,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        switch chosen(in: defaults) {
        case .api: return true
        case .subscription: return false
        case .automatic: return detected(home: home)
        }
    }

    private static let lock = NSLock()
    private static var cached: (path: String, modified: Date?, api: Bool)?

    /// Read again only when the settings file changes: views ask on every draw.
    static func detected(home: URL) -> Bool {
        let url = home.appending(path: ".claude/settings.json")
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached = lock.withLock({ cached }), cached.path == url.path, cached.modified == modified {
            return cached.api
        }
        let api = (try? Data(contentsOf: url)).map(detected(settings:)) ?? false
        lock.withLock { cached = (url.path, modified, api) }
        return api
    }

    static func detected(settings data: Data) -> Bool {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        if keySettings.contains(where: { (json[$0] as? String).map { !$0.isEmpty } == true }) { return true }
        let environment = json["env"] as? [String: Any] ?? [:]
        return keyEnvironment.contains { (environment[$0] as? String).map { !$0.isEmpty } == true }
    }
}

/// The API key's prepaid balance. No endpoint reports it, so the person
/// enters it and every Claude Code response since is taken from it.
struct AgentClaudeCredits: Equatable {
    let balance: Double
    let since: Date
    /// What the day of `since` had already spent when the balance was
    /// entered, which the balance already accounts for.
    let baseline: Double

    static func stored(in defaults: UserDefaults = .standard) -> AgentClaudeCredits? {
        let balance = defaults.double(forKey: DefaultsKey.notchAgentsClaudeCredits)
        let since = defaults.double(forKey: DefaultsKey.notchAgentsClaudeCreditsSince)
        guard balance > 0, since > 0 else { return nil }
        return AgentClaudeCredits(balance: balance, since: Date(timeIntervalSince1970: since),
                                  baseline: defaults.double(forKey: DefaultsKey.notchAgentsClaudeCreditsBaseline))
    }

    static func store(balance: Double, now: Date, days: [AgentBucket],
                      in defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        guard balance > 0, balance.isFinite else {
            clear(in: defaults)
            return
        }
        defaults.set(balance, forKey: DefaultsKey.notchAgentsClaudeCredits)
        defaults.set(now.timeIntervalSince1970, forKey: DefaultsKey.notchAgentsClaudeCreditsSince)
        defaults.set(spent(on: now, days: days, calendar: calendar), forKey: DefaultsKey.notchAgentsClaudeCreditsBaseline)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        for key in [DefaultsKey.notchAgentsClaudeCredits, DefaultsKey.notchAgentsClaudeCreditsSince,
                    DefaultsKey.notchAgentsClaudeCreditsBaseline] {
            defaults.removeObject(forKey: key)
        }
    }

    /// The API key's spend on the day `date` falls in: Claude Code outside
    /// the Claude app, whose own sessions the plan pays for.
    static func spent(on date: Date, days: [AgentBucket], calendar: Calendar = .autoupdatingCurrent) -> Double {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.start == start }?.claudeAPI.cost ?? 0
    }

    /// The API key's spend from the first day on, by the days the summary keeps.
    static func spent(from start: Date, days: [AgentBucket]) -> Double {
        days.reduce(0) { $1.start >= start ? $0 + $1.claudeAPI.cost : $0 }
    }

    /// The balance less what Claude Code spent since it was entered; nil once
    /// that day has left the summary's days, which can no longer say.
    func remaining(days: [AgentBucket], calendar: Calendar = .autoupdatingCurrent) -> Double? {
        let start = calendar.startOfDay(for: since)
        guard let first = days.first?.start, start >= first else { return nil }
        return balance - max(0, Self.spent(from: start, days: days) - baseline)
    }

    /// The share of the balance still left, for a meter.
    func remainingFraction(days: [AgentBucket], calendar: Calendar = .autoupdatingCurrent) -> Double? {
        remaining(days: days, calendar: calendar).map { min(1, max(0, $0 / balance)) }
    }
}
