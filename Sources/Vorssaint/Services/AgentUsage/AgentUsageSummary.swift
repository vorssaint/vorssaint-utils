// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentPeriod: String, CaseIterable, Identifiable {
    case today, week, month

    var id: String { rawValue }
    var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

struct AgentTotals: Equatable {
    var tokens = AgentTokens()
    var cost = 0.0
    var savings = 0.0
    var requests = 0
    /// Responses from a model without a known price, left out of `cost`.
    var unpriced = 0

    mutating func add(_ record: AgentUsageRecord) {
        tokens += record.tokens
        requests += 1
        savings += record.savings
        if let price = record.cost { cost += price } else { unpriced += 1 }
    }

    static func += (lhs: inout AgentTotals, rhs: AgentTotals) {
        lhs.tokens += rhs.tokens
        lhs.cost += rhs.cost
        lhs.savings += rhs.savings
        lhs.requests += rhs.requests
        lhs.unpriced += rhs.unpriced
    }

    /// Cost when every response had a price, tokens otherwise, so shares
    /// and bars never compare dollars with token counts.
    func weight(byCost: Bool) -> Double { byCost ? cost : Double(tokens.total) }
}

/// One row of a breakdown: a model or a project.
struct AgentShare: Equatable, Identifiable {
    let id: String
    let name: String
    let provider: AgentProvider?
    var totals: AgentTotals
}

struct AgentPeriodUsage: Equatable {
    var total = AgentTotals()
    var byProvider: [AgentProvider: AgentTotals] = [:]
    var models: [AgentShare] = []
    var projects: [AgentShare] = []

    /// Whether every response in the period could be priced.
    var fullyPriced: Bool { total.unpriced == 0 }
}

/// A day or an hour of use.
struct AgentBucket: Equatable, Identifiable {
    let start: Date
    var byProvider: [AgentProvider: AgentTotals] = [:]
    var id: Date { start }

    var total: AgentTotals {
        byProvider.values.reduce(into: AgentTotals()) { $0 += $1 }
    }
}

/// Claude's allowance renews five hours after the first request that
/// follows a renewal. Local activity alone places that window closely.
struct AgentBlock: Equatable {
    let start: Date
    let end: Date
    var totals: AgentTotals
}

struct AgentUsageSnapshot: Equatable {
    static let dayCount = 91

    var loaded = false
    var now = Date.distantPast
    var periods: [AgentPeriod: AgentPeriodUsage] = [:]
    /// Oldest first, ending with today.
    var days: [AgentBucket] = []
    /// Today's hours, from midnight.
    var hours: [AgentBucket] = []
    var limits: [AgentProvider: AgentLimits] = [:]
    var plans: [AgentProvider: AgentPlan] = [:]
    var live: [AgentLiveSession] = []
    /// Every session on the board, working or not.
    var sessions: [AgentSessionRow] = []
    var claudeBlock: AgentBlock?
    /// The last half hour, scaled to an hour.
    var burnRate: [AgentProvider: AgentTotals] = [:]
    var lastActivity: [AgentProvider: Date] = [:]
    /// Providers with anything on disk: usage, limits or a turn.
    var seen: Set<AgentProvider> = []

    func usage(_ period: AgentPeriod) -> AgentPeriodUsage { periods[period] ?? AgentPeriodUsage() }
    func working(_ provider: AgentProvider) -> [AgentLiveSession] { live.filter { $0.provider == provider } }
}

enum AgentUsageSummary {
    static let blockLength: TimeInterval = 5 * 3600
    /// Each window starts where the one before it ended, so a chain cut
    /// short lands on other hours; a day of history covers any real stretch.
    static let blockHistory: TimeInterval = 24 * 3600
    static let burnWindow: TimeInterval = 30 * 60

    static func snapshot(records: [AgentUsageRecord], limits: [AgentProvider: AgentLimits],
                         live: [AgentLiveSession], plans: [AgentProvider: AgentPlan],
                         providers: Set<AgentProvider>, now: Date,
                         calendar: Calendar = .autoupdatingCurrent) -> AgentUsageSnapshot {
        var snapshot = AgentUsageSnapshot(loaded: true, now: now)
        snapshot.limits = limits.filter { providers.contains($0.key) }
        snapshot.plans = plans.filter { providers.contains($0.key) }
        snapshot.live = live.filter { providers.contains($0.provider) }.sorted { $0.started < $1.started }
        snapshot.seen = Set(snapshot.limits.keys).union(snapshot.live.map(\.provider))

        let today = calendar.startOfDay(for: now)
        let starts: [Date] = (0..<AgentUsageSnapshot.dayCount).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let hourStarts: [Date] = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: today) }
        var days = starts.map { AgentBucket(start: $0) }
        var hours = hourStarts.map { AgentBucket(start: $0) }
        var periods: [AgentPeriod: AgentPeriodUsage] = [:]
        var models: [AgentPeriod: [String: AgentShare]] = [:]
        var projects: [AgentPeriod: [String: AgentShare]] = [:]
        var claude: [AgentUsageRecord] = []
        var names: [String: String] = [:]
        let recent = now.addingTimeInterval(-burnWindow)
        let lastDay = starts.count - 1

        for record in records where providers.contains(record.provider) {
            snapshot.seen.insert(record.provider)
            snapshot.lastActivity[record.provider] = max(snapshot.lastActivity[record.provider] ?? .distantPast, record.date)
            if record.provider == .claude, record.date > now.addingTimeInterval(-blockHistory), record.date <= now {
                claude.append(record)
            }
            if record.date >= recent, record.date <= now {
                snapshot.burnRate[record.provider, default: AgentTotals()].add(record)
            }
            guard let first = starts.first, record.date >= first, record.date < tomorrow,
                  let day = index(of: record.date, in: starts) else { continue }
            days[day].byProvider[record.provider, default: AgentTotals()].add(record)
            if day == lastDay, let hour = index(of: record.date, in: hourStarts) {
                hours[hour].byProvider[record.provider, default: AgentTotals()].add(record)
            }
            // One name per model string, not per response: the history can
            // hold tens of thousands of them.
            let name: String
            if let known = names[record.model] {
                name = known
            } else {
                name = AgentPricing.displayName(record.model)
                names[record.model] = name
            }
            let modelID = record.provider.rawValue + ":" + name
            for period in AgentPeriod.allCases where day > lastDay - period.days {
                periods[period, default: AgentPeriodUsage()].total.add(record)
                periods[period, default: AgentPeriodUsage()].byProvider[record.provider, default: AgentTotals()].add(record)
                models[period, default: [:]][modelID, default: AgentShare(
                    id: modelID, name: name.isEmpty ? "?" : name, provider: record.provider, totals: AgentTotals())]
                    .totals.add(record)
                if !record.project.isEmpty {
                    projects[period, default: [:]][record.project, default: AgentShare(
                        id: record.project, name: record.project, provider: nil, totals: AgentTotals())]
                        .totals.add(record)
                }
            }
        }
        for period in AgentPeriod.allCases {
            var usage = periods[period] ?? AgentPeriodUsage()
            let byCost = usage.fullyPriced
            usage.models = sorted(models[period].map { Array($0.values) } ?? [], byCost: byCost)
            usage.projects = sorted(projects[period].map { Array($0.values) } ?? [], byCost: byCost)
            periods[period] = usage
        }
        for provider in Array(snapshot.burnRate.keys) {
            guard var rate = snapshot.burnRate[provider] else { continue }
            let scale = 3600 / burnWindow
            rate.cost *= scale
            rate.savings *= scale
            rate.tokens = AgentTokens(input: Int(Double(rate.tokens.input) * scale),
                                      cacheWrite: Int(Double(rate.tokens.cacheWrite) * scale),
                                      cacheRead: Int(Double(rate.tokens.cacheRead) * scale),
                                      output: Int(Double(rate.tokens.output) * scale),
                                      reasoning: Int(Double(rate.tokens.reasoning) * scale))
            snapshot.burnRate[provider] = rate
        }
        snapshot.periods = periods
        snapshot.days = days
        snapshot.hours = hours
        snapshot.claudeBlock = currentBlock(claude, now: now)
        return snapshot
    }

    /// Whether a snapshot reads differently at `now` with nothing new read:
    /// the last half hour slides, a Claude window can end and a new day
    /// moves every total. The rest changes only with what the logs say.
    static func movesWithClock(_ snapshot: AgentUsageSnapshot, now: Date,
                               calendar: Calendar = .autoupdatingCurrent) -> Bool {
        !snapshot.burnRate.isEmpty || snapshot.claudeBlock != nil || !calendar.isDate(snapshot.now, inSameDayAs: now)
            || AgentSessionBoard.movesWithClock(snapshot.sessions, from: snapshot.now, to: now)
    }

    static func sorted(_ shares: [AgentShare], byCost: Bool) -> [AgentShare] {
        shares.sorted {
            let left = $0.totals.weight(byCost: byCost), right = $1.totals.weight(byCost: byCost)
            return left != right ? left > right : $0.name < $1.name
        }
    }

    /// The last start at or before `date`, by bisection.
    static func index(of date: Date, in starts: [Date]) -> Int? {
        guard let first = starts.first, date >= first else { return nil }
        var low = 0, high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= date { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Windows start at the first request after the previous one ended and
    /// last five hours from that moment, the renewal time the provider's own
    /// usage page shows.
    static func currentBlock(_ records: [AgentUsageRecord], now: Date) -> AgentBlock? {
        var block: AgentBlock?
        // Sorting positions moves no strings: a day of records is thousands.
        for position in records.indices.sorted(by: { records[$0].date < records[$1].date }) {
            let record = records[position]
            if let current = block, record.date < current.end {
                block?.totals.add(record)
                continue
            }
            var next = AgentBlock(start: record.date, end: record.date.addingTimeInterval(blockLength), totals: AgentTotals())
            next.totals.add(record)
            block = next
        }
        guard let block, block.end > now else { return nil }
        return block
    }
}

/// Queue-confined history totals. Ordinary log updates add only new responses
/// or the difference from a streamed response. Calendar changes, pruning and
/// repricing rebuild from the authoritative store instead of trying to undo
/// old buckets. The short sliding windows are evaluated at publication time.
final class AgentUsageSummaryCache {
    private var history: AgentUsageSnapshot?
    private var calendar: Calendar?
    private var providers: Set<AgentProvider> = []
    private var models: [AgentPeriod: [String: AgentShare]] = [:]
    private var projects: [AgentPeriod: [String: AgentShare]] = [:]
    private var names: [String: String] = [:]
    private var starts: [Date] = []
    private var hourStarts: [Date] = []
    private var tomorrow = Date.distantPast
    private struct Change { let previous: AgentUsageRecord? }
    private var changes: [Int: Change] = [:]
    private var recentPositions: Set<Int> = []
    private var lastTime = Date.distantPast
    /// Records accumulated on the last publication, for performance contracts.
    private(set) var accumulatedRecords = 0

    func invalidate() {
        history = nil
        changes.removeAll(keepingCapacity: true)
        recentPositions.removeAll(keepingCapacity: true)
    }

    func recordChanged(at position: Int, previous: AgentUsageRecord?) {
        guard history != nil, changes[position] == nil else { return }
        // Keep the value before the first change, including a response added
        // and streamed again before the next publication.
        changes[position] = Change(previous: previous)
    }

    func snapshot(records: [AgentUsageRecord], limits: [AgentProvider: AgentLimits],
                  live: [AgentLiveSession], plans: [AgentProvider: AgentPlan],
                  providers: Set<AgentProvider>, now: Date,
                  calendar: Calendar = .current) -> AgentUsageSnapshot {
        accumulatedRecords = 0
        let rebuild = history == nil || self.calendar != calendar || self.providers != providers
            || now < lastTime || !calendar.isDate(lastTime, inSameDayAs: now)
        if rebuild {
            self.calendar = calendar
            self.providers = providers
            models.removeAll(keepingCapacity: true)
            projects.removeAll(keepingCapacity: true)
            names.removeAll(keepingCapacity: true)
            recentPositions.removeAll(keepingCapacity: true)
            history = AgentUsageSummary.snapshot(records: [], limits: [:], live: [], plans: [:],
                                                 providers: providers, now: now, calendar: calendar)
            starts = history!.days.map(\.start)
            hourStarts = history!.hours.map(\.start)
            let today = calendar.startOfDay(for: now)
            tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
            for position in records.indices {
                accumulate(records[position], previous: nil)
                if isRecent(records[position], now: now) { recentPositions.insert(position) }
            }
        } else {
            for position in changes.keys.sorted() {
                accumulate(records[position], previous: changes[position]?.previous)
                if isRecent(records[position], now: now) { recentPositions.insert(position) }
            }
        }
        if rebuild || !changes.isEmpty {
            for period in AgentPeriod.allCases {
                let byCost = history!.periods[period]!.fullyPriced
                history!.periods[period]!.models = AgentUsageSummary.sorted(
                    models[period].map { Array($0.values) } ?? [], byCost: byCost)
                history!.periods[period]!.projects = AgentUsageSummary.sorted(
                    projects[period].map { Array($0.values) } ?? [], byCost: byCost)
            }
        }
        changes.removeAll(keepingCapacity: true)
        lastTime = now
        var result = history!
        result.now = now
        result.limits = limits.filter { providers.contains($0.key) }
        result.plans = plans.filter { providers.contains($0.key) }
        result.live = live.filter { providers.contains($0.provider) }.sorted { $0.started < $1.started }
        result.seen.formUnion(result.limits.keys)
        result.seen.formUnion(result.live.map(\.provider))
        var claude: [AgentUsageRecord] = []
        // Stable store order also preserves the original accumulation order.
        for position in recentPositions.sorted() {
            let record = records[position]
            guard isRecent(record, now: now) else { recentPositions.remove(position); continue }
            guard record.date <= now else { continue }
            if record.provider == .claude { claude.append(record) }
            if record.date >= now.addingTimeInterval(-AgentUsageSummary.burnWindow) {
                result.burnRate[record.provider, default: AgentTotals()].add(record)
            }
        }
        for provider in Array(result.burnRate.keys) {
            let total = result.burnRate[provider]!
            // Scale amounts, not the number of responses or unpriced entries.
            result.burnRate[provider]!.tokens += total.tokens
            result.burnRate[provider]!.cost *= 2
            result.burnRate[provider]!.savings *= 2
        }
        result.claudeBlock = AgentUsageSummary.currentBlock(claude, now: now)
        return result
    }

    private func isRecent(_ record: AgentUsageRecord, now: Date) -> Bool {
        guard providers.contains(record.provider) else { return false }
        return record.provider == .claude
            ? record.date > now.addingTimeInterval(-AgentUsageSummary.blockHistory)
            : record.date >= now.addingTimeInterval(-AgentUsageSummary.burnWindow)
    }

    private func accumulate(_ record: AgentUsageRecord, previous: AgentUsageRecord?) {
        guard providers.contains(record.provider) else { return }
        accumulatedRecords += 1
        history!.seen.insert(record.provider)
        history!.lastActivity[record.provider] = max(history!.lastActivity[record.provider] ?? .distantPast, record.date)
        guard record.date < tomorrow, let day = AgentUsageSummary.index(of: record.date, in: starts) else { return }
        var delta = AgentTotals()
        delta.add(record)
        if let previous {
            delta.tokens += AgentTokens(input: -previous.tokens.input, cacheWrite: -previous.tokens.cacheWrite,
                                        cacheRead: -previous.tokens.cacheRead, output: -previous.tokens.output,
                                        reasoning: -previous.tokens.reasoning)
            delta.cost -= previous.cost ?? 0
            delta.savings -= previous.savings
            delta.requests -= 1
            delta.unpriced -= previous.cost == nil ? 1 : 0
        }
        history!.days[day].byProvider[record.provider, default: AgentTotals()] += delta
        if day == starts.count - 1, let hour = AgentUsageSummary.index(of: record.date, in: hourStarts) {
            history!.hours[hour].byProvider[record.provider, default: AgentTotals()] += delta
        }
        let name = names[record.model] ?? AgentPricing.displayName(record.model)
        names[record.model] = name
        let modelID = record.provider.rawValue + ":" + name
        for period in AgentPeriod.allCases where day > starts.count - 1 - period.days {
            history!.periods[period]!.total += delta
            history!.periods[period]!.byProvider[record.provider, default: AgentTotals()] += delta
            models[period, default: [:]][modelID, default: AgentShare(
                id: modelID, name: name.isEmpty ? "?" : name, provider: record.provider, totals: AgentTotals())].totals += delta
            if !record.project.isEmpty {
                projects[period, default: [:]][record.project, default: AgentShare(
                    id: record.project, name: record.project, provider: nil, totals: AgentTotals())].totals += delta
            }
        }
    }
}

/// How spending compares with the time a window has left.
struct AgentPace: Equatable {
    /// How much of the window's time has passed, from 0 to 1.
    let elapsed: Double
}

enum AgentLimitSupport {
    /// A window that renewed since it was read has nothing spent on it yet.
    static func current(_ window: AgentLimitWindow, at now: Date) -> AgentLimitWindow {
        guard let resets = window.resetsAt, resets <= now else { return window }
        return AgentLimitWindow(id: window.id, kind: window.kind, minutes: window.minutes,
                                scope: window.scope, usedPercent: 0, resetsAt: nil)
    }

    static func pace(for window: AgentLimitWindow, now: Date) -> AgentPace? {
        guard let minutes = window.minutes, minutes > 0, let resets = window.resetsAt, resets > now else { return nil }
        let length = TimeInterval(minutes) * 60
        let elapsed = now.timeIntervalSince(resets.addingTimeInterval(-length))
        guard elapsed > 0 else { return nil }
        return AgentPace(elapsed: min(1, elapsed / length))
    }

    /// The window that will stop work first: the most spent, and on a tie the
    /// one renewing last.
    static func binding(_ limits: AgentLimits?, now: Date) -> AgentLimitWindow? {
        limits?.windows.map { current($0, at: now) }.max {
            $0.usedPercent != $1.usedPercent ? $0.usedPercent < $1.usedPercent
                : ($0.resetsAt ?? .distantPast) < ($1.resetsAt ?? .distantPast)
        }
    }

    /// Windows that reached `threshold` percent between two readings of the
    /// same account. A renewed window starts again from zero.
    static func crossings(previous: AgentLimits?, current: AgentLimits, threshold: Double) -> [AgentLimitWindow] {
        guard threshold > 0 else { return [] }
        return current.windows.filter { window in
            guard window.usedPercent >= threshold else { return false }
            guard let before = previous?.windows.first(where: { $0.id == window.id }) else { return false }
            if let was = before.resetsAt, let now = window.resetsAt, now.timeIntervalSince(was) > 60 { return true }
            return before.usedPercent < threshold
        }
    }
}
