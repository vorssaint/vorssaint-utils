// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every day's spending by model, kept after the logs it was read from are
/// gone: Claude Code removes its own after thirty days, and the app reads
/// thirteen weeks back at most. Only amounts per day and model are saved, no
/// folder, session, prompt or reply. Unlike the progress archive it lives in
/// Application Support, since no log could rebuild it.
///
/// A day the logs still hold replaces what was kept for it when it holds as
/// much or more, so a response that streams in or is priced again counts in
/// full; a day whose logs were removed, wholly or in part, keeps its larger
/// amount.
final class AgentUsageLedger {
    struct Entry: Codable, Equatable {
        var provider: String
        var name: String
        var cost: Double
        var input: Int
        var cacheWrite: Int
        var cacheRead: Int
        var output: Int
        var reasoning: Int
        var requests: Int
        var unpriced: Int

        init(provider: AgentProvider, name: String, totals: AgentTotals) {
            self.provider = provider.rawValue
            self.name = name
            cost = totals.cost
            input = totals.tokens.input
            cacheWrite = totals.tokens.cacheWrite
            cacheRead = totals.tokens.cacheRead
            output = totals.tokens.output
            reasoning = totals.tokens.reasoning
            requests = totals.requests
            unpriced = totals.unpriced
        }

        var totals: AgentTotals {
            AgentTotals(tokens: AgentTokens(input: input, cacheWrite: cacheWrite, cacheRead: cacheRead,
                                            output: output, reasoning: reasoning),
                        cost: cost, requests: requests, unpriced: unpriced)
        }

        /// Whether `other` holds at least what this entry does.
        func isCovered(by other: Entry) -> Bool {
            other.cost != cost ? other.cost > cost
                : other.input + other.cacheWrite + other.cacheRead + other.output
                    >= input + cacheWrite + cacheRead + output
        }
    }

    private struct File: Codable {
        var version: Int
        /// "yyyy-MM-dd" to model ID to amounts.
        var days: [String: [String: Entry]]
    }

    private static let fileName = "agent-ledger.json"
    private static let version = 1

    private(set) var days: [String: [String: Entry]] = [:]
    /// Changed since it was loaded or saved.
    private(set) var unsaved = false
    private let url: URL?

    init(url: URL? = AgentUsageLedger.defaultURL) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.version == Self.version else { return }
        days = file.days
    }

    static var defaultURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("AgentUsage", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Takes in what the snapshot's days hold. Returns whether anything changed.
    @discardableResult
    func merge(_ snapshot: AgentUsageSnapshot, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        var changed = false
        for (index, models) in snapshot.dayModels.enumerated() where index < snapshot.days.count && !models.isEmpty {
            let key = Self.key(snapshot.days[index].start, calendar: calendar)
            var kept = days[key] ?? [:]
            for (id, share) in models {
                guard let provider = share.provider else { continue }
                let entry = Entry(provider: provider, name: share.name, totals: share.totals)
                if let old = kept[id], old == entry || !old.isCovered(by: entry) { continue }
                kept[id] = entry
                changed = true
            }
            days[key] = kept
        }
        if changed { unsaved = true }
        return changed
    }

    /// Everything kept for `providers`, with its models sorted as a period's are.
    func usage(providers: Set<AgentProvider>) -> AgentPeriodUsage {
        var usage = AgentPeriodUsage()
        var models: [String: AgentShare] = [:]
        for day in days.values {
            for (id, entry) in day {
                guard let provider = AgentProvider(rawValue: entry.provider), providers.contains(provider) else { continue }
                let totals = entry.totals
                usage.total += totals
                usage.byProvider[provider, default: AgentTotals()] += totals
                models[id, default: AgentShare(id: id, name: entry.name, provider: provider, totals: AgentTotals())]
                    .totals += totals
            }
        }
        usage.models = AgentUsageSummary.sorted(Array(models.values), byCost: usage.fullyPriced)
        return usage
    }

    func save() {
        guard unsaved, let url else { return }
        let folder = url.deletingLastPathComponent()
        guard PrivateFileStore.createDirectory(at: folder),
              let data = try? JSONEncoder().encode(File(version: Self.version, days: days)),
              PrivateFileStore.write(data, to: url) else { return }
        unsaved = false
    }

    static func key(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
