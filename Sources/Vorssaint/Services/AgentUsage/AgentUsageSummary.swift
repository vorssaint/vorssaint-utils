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

/// Whose account paid for a response or a turn.
enum AgentAccount: Equatable {
    /// The agent's own sign-in on this Mac.
    case own(AgentProvider)
    /// Some other service stood between. `hub` is the added hub it went
    /// through, and `account` the kind of account that served it, each nil
    /// while the evidence cannot say.
    case proxy(hub: String?, account: AgentProvider?)

    /// The provider whose totals take the response. Nil for an account the
    /// evidence cannot name.
    var paidBy: AgentProvider? {
        switch self {
        case .own(let provider): return provider
        case .proxy(_, let account): return account
        }
    }

    var isProxy: Bool {
        if case .proxy = self { return true }
        return false
    }
}

/// What ties a turn to a hub and to one of its accounts.
struct AgentHubContext: Equatable {
    /// Codex model providers, each with the hub its address reaches.
    var codexRoutes: [String: String] = [:]
    /// The hub Claude Code's settings send it to.
    var claudeHub: String?
    /// The kinds of account each hub serves a model with, by hub and by
    /// lowercased model id.
    var served: [String: [String: Set<AgentProvider>]] = [:]

    init(codexRoutes: [String: String] = [:], claudeHub: String? = nil,
         served: [String: [String: Set<AgentProvider>]] = [:]) {
        self.codexRoutes = codexRoutes
        self.claudeHub = claudeHub
        self.served = served
    }

    /// Builds the served models from each hub's account listing.
    init(codexRoutes: [String: String], claudeHub: String?, accounts: [AgentHubAccount]) {
        var served: [String: [String: Set<AgentProvider>]] = [:]
        for account in accounts {
            for model in account.models { served[account.hub, default: [:]][model, default: []].insert(account.provider) }
        }
        self.init(codexRoutes: codexRoutes, claudeHub: claudeHub, served: served)
    }

    /// The one kind of account `hub` serves `model` with. When the hub lists
    /// several or none, a response's issuer can still settle it, as long as
    /// the hub does not rule that kind out.
    func account(serving model: String, on hub: String, issuer: AgentProvider?) -> AgentProvider? {
        let kinds = served[hub]?[model.lowercased()] ?? []
        if kinds.count == 1 { return kinds.first }
        guard let issuer, kinds.isEmpty || kinds.contains(issuer) else { return nil }
        return issuer
    }
}

struct AgentPeriodUsage: Equatable {
    var total = AgentTotals()
    /// Use by whose account paid for it. A response through a hub counts
    /// under the kind of account that served it, whichever agent asked.
    var byProvider: [AgentProvider: AgentTotals] = [:]
    /// The part of `byProvider` that went through a proxy rather than the
    /// agent's own sign-in. Every response has one log, so nothing here
    /// counts twice.
    var viaHub: [AgentProvider: AgentTotals] = [:]
    /// Use through a proxy whose account the logs and the hub cannot name.
    /// It is inside `total` but under neither provider.
    var unattributed = AgentTotals()
    var models: [AgentShare] = []
    var projects: [AgentShare] = []

    /// Whether every response in the period could be priced.
    var fullyPriced: Bool { total.unpriced == 0 }

    mutating func add(_ delta: AgentTotals, paidBy account: AgentAccount) {
        total += delta
        guard let provider = account.paidBy else { unattributed += delta; return }
        byProvider[provider, default: AgentTotals()] += delta
        if account.isProxy { viaHub[provider, default: AgentTotals()] += delta }
    }

    /// What an agent spent on its own sign-in, the use its plan pays for.
    func own(_ provider: AgentProvider) -> AgentTotals {
        var own = byProvider[provider] ?? AgentTotals()
        guard let hub = viaHub[provider] else { return own }
        own.tokens = AgentTokens(input: own.tokens.input - hub.tokens.input,
                                 cacheWrite: own.tokens.cacheWrite - hub.tokens.cacheWrite,
                                 cacheRead: own.tokens.cacheRead - hub.tokens.cacheRead,
                                 output: own.tokens.output - hub.tokens.output,
                                 reasoning: own.tokens.reasoning - hub.tokens.reasoning)
        own.cost -= hub.cost
        own.savings -= hub.savings
        own.requests -= hub.requests
        own.unpriced -= hub.unpriced
        return own
    }
}

/// A day or an hour of use.
struct AgentBucket: Equatable, Identifiable {
    let start: Date
    var byProvider: [AgentProvider: AgentTotals] = [:]
    var unattributed = AgentTotals()
    var id: Date { start }

    var total: AgentTotals {
        byProvider.values.reduce(into: unattributed) { $0 += $1 }
    }

    mutating func add(_ delta: AgentTotals, paidBy provider: AgentProvider?) {
        if let provider { byProvider[provider, default: AgentTotals()] += delta } else { unattributed += delta }
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
    var claudeBlock: AgentBlock?
    /// The last half hour, scaled to an hour.
    var burnRate: [AgentProvider: AgentTotals] = [:]
    var lastActivity: [AgentProvider: Date] = [:]
    /// Providers with anything on disk: usage, limits or a turn.
    var seen: Set<AgentProvider> = []
    /// Accounts pooled by the CLIProxyAPI hubs the person added, apart from
    /// the one signed in on this Mac, which keeps its own tile.
    var accounts: [AgentHubAccount] = []
    /// Every hub account, including one folded into this Mac's Claude tile.
    var pool: [AgentHubAccount] = []
    /// What ties a turn to a hub and to one of its accounts. Nil until the
    /// person adds a hub.
    var hubs: AgentHubContext?

    func usage(_ period: AgentPeriod) -> AgentPeriodUsage { periods[period] ?? AgentPeriodUsage() }
    func working(_ provider: AgentProvider) -> [AgentLiveSession] { live.filter { $0.provider == provider } }
}

enum AgentUsageSummary {
    static let blockLength: TimeInterval = 5 * 3600
    /// Each window starts where the one before it ended, so a chain cut
    /// short lands on other hours; a day of history covers any real stretch.
    static let blockHistory: TimeInterval = 24 * 3600
    static let burnWindow: TimeInterval = 30 * 60

    /// Whose account paid for a response, from evidence alone.
    ///
    /// The connection comes from configuration. A Codex session names its
    /// model provider, and Codex's config says which hub that reaches.
    /// Claude Code logs no address, so only a base URL in its settings ties
    /// it to a hub. The account comes from the hub, which lists the models
    /// each account serves, or from the id of a Claude Code response, which
    /// the upstream API issued. A model's name decides nothing, because a hub
    /// can serve aliases and providers of its own. Whatever the evidence
    /// cannot settle stays unknown.
    static func account(provider: AgentProvider, model: String, route: String, issuer: AgentProvider?,
                        hubs: AgentHubContext?) -> AgentAccount {
        guard let hubs else { return .own(provider) }
        switch provider {
        case .codex:
            guard !route.isEmpty else { return .own(.codex) }
            // A model provider that reaches no added hub is some other service.
            guard let hub = hubs.codexRoutes[route] else { return .proxy(hub: nil, account: nil) }
            return .proxy(hub: hub, account: hubs.account(serving: model, on: hub, issuer: nil))
        case .claude:
            if let hub = hubs.claudeHub {
                return .proxy(hub: hub, account: hubs.account(serving: model, on: hub, issuer: issuer))
            }
            // Anthropic issued the response, and no setting sends Claude Code
            // anywhere else, so this is the sign-in on this Mac.
            if issuer == .claude { return .own(.claude) }
            return .proxy(hub: nil, account: issuer)
        }
    }

    static func snapshot(records: [AgentUsageRecord], limits: [AgentProvider: AgentLimits],
                         live: [AgentLiveSession], plans: [AgentProvider: AgentPlan],
                         providers: Set<AgentProvider>, hubs: AgentHubContext? = nil, now: Date,
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
            let paid = account(provider: record.provider, model: record.model, route: record.route,
                               issuer: record.issuer, hubs: hubs)
            var delta = AgentTotals()
            delta.add(record)
            days[day].add(delta, paidBy: paid.paidBy)
            if day == lastDay, let hour = index(of: record.date, in: hourStarts) {
                hours[hour].add(delta, paidBy: paid.paidBy)
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
            let modelID = (paid.paidBy?.rawValue ?? "?") + ":" + name
            for period in AgentPeriod.allCases where day > lastDay - period.days {
                periods[period, default: AgentPeriodUsage()].add(delta, paidBy: paid)
                models[period, default: [:]][modelID, default: AgentShare(
                    id: modelID, name: name.isEmpty ? "?" : name, provider: paid.paidBy, totals: AgentTotals())]
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
    }

    static func sorted(_ shares: [AgentShare], byCost: Bool) -> [AgentShare] {
        // A hub can put one model under both accounts, so equal weight and
        // name still need the account to give one order every time.
        shares.sorted {
            let left = $0.totals.weight(byCost: byCost), right = $1.totals.weight(byCost: byCost)
            if left != right { return left > right }
            return $0.name != $1.name ? $0.name < $1.name : $0.id < $1.id
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

    /// Windows start on the hour of the first request after the previous
    /// one ended, the way the service counts them: the hour in UTC, as the
    /// Claude app's readings are placed.
    static func currentBlock(_ records: [AgentUsageRecord], now: Date) -> AgentBlock? {
        var block: AgentBlock?
        // Sorting positions moves no strings: a day of records is thousands.
        for position in records.indices.sorted(by: { records[$0].date < records[$1].date }) {
            let record = records[position]
            if let current = block, record.date < current.end {
                block?.totals.add(record)
                continue
            }
            let hour = AgentClaudeAppUsage.hour(of: record.date)
            var next = AgentBlock(start: hour, end: hour.addingTimeInterval(blockLength), totals: AgentTotals())
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
    /// What ties responses to hubs and accounts. Nil until the person adds a hub.
    private var hubs: AgentHubContext?
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
                  providers: Set<AgentProvider>, hubs: AgentHubContext? = nil, now: Date,
                  calendar: Calendar = .current) -> AgentUsageSnapshot {
        accumulatedRecords = 0
        // A hub added or removed, or a hub serving other models, moves past
        // responses between accounts, so the totals start over.
        let rebuild = history == nil || self.calendar != calendar || self.providers != providers
            || self.hubs != hubs || now < lastTime || !calendar.isDate(lastTime, inSameDayAs: now)
        if rebuild {
            self.calendar = calendar
            self.providers = providers
            self.hubs = hubs
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
        // The same response keeps its model and route when it streams again,
        // so its earlier reading sat under the same account.
        let paid = AgentUsageSummary.account(provider: record.provider, model: record.model, route: record.route,
                                             issuer: record.issuer, hubs: hubs)
        history!.days[day].add(delta, paidBy: paid.paidBy)
        if day == starts.count - 1, let hour = AgentUsageSummary.index(of: record.date, in: hourStarts) {
            history!.hours[hour].add(delta, paidBy: paid.paidBy)
        }
        let name = names[record.model] ?? AgentPricing.displayName(record.model)
        names[record.model] = name
        let modelID = (paid.paidBy?.rawValue ?? "?") + ":" + name
        for period in AgentPeriod.allCases where day > starts.count - 1 - period.days {
            history!.periods[period]!.add(delta, paidBy: paid)
            models[period, default: [:]][modelID, default: AgentShare(
                id: modelID, name: name.isEmpty ? "?" : name, provider: paid.paidBy, totals: AgentTotals())].totals += delta
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

    /// The same reading with each window named by what it covers, meaning
    /// its kind, length and model. Readings of one account from different
    /// sources then compare window by window.
    static func canonical(_ limits: AgentLimits) -> AgentLimits {
        var result = limits
        result.windows = limits.windows.map { window in
            AgentLimitWindow(id: "\(limits.provider.rawValue).\(window.kind.rawValue).\(window.minutes ?? 0)."
                                + (window.scope?.lowercased() ?? ""),
                             kind: window.kind, minutes: window.minutes, scope: window.scope,
                             usedPercent: window.usedPercent, resetsAt: window.resetsAt)
        }
        return result
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
