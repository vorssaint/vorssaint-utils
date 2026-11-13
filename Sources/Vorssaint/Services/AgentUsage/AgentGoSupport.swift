// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// OpenCode Go allowances estimated from this Mac's local usage.
///
/// Go meters per-model monthly dollar caps with 20% available per rolling
/// 5 hours and 50% per week. The app never sends usage elsewhere, so the
/// card estimates spend from the same priced records the Spending card
/// uses. Per-model caps come from the bundled table; models without an
/// entry fall back to the plan-wide stacked caps. Unpriced models stay out
/// of the dollar totals, exactly like Spending.
enum AgentGoPlan: String, CaseIterable, Identifiable {
    case go, plus, teams

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .go: return "Go"
        case .plus: return "Go Plus"
        case .teams: return "Go Teams"
        }
    }

    /// Plan-wide stacked caps: rolling 5 hours, week, month, in USD.
    /// Plus doubles Go. Teams gives each member their own allowance a step
    /// above Go; treated here as Go plus one third until per-model tables
    /// ship in the price list.
    var quotas: (rolling: Double, weekly: Double, monthly: Double) {
        switch self {
        case .go: return (12, 30, 60)
        case .plus: return (24, 60, 120)
        case .teams: return (16, 40, 80)
        }
    }
}

enum AgentGoSupport {
    /// Remaining dollars, never below zero.
    static func remaining(used: Double, quota: Double) -> Double {
        guard used.isFinite, quota.isFinite else { return quota.isFinite ? quota : 0 }
        return max(0, quota - max(0, used))
    }

    /// Share of the quota spent, 0 to 1.
    static func usedFraction(used: Double, quota: Double) -> Double {
        guard quota > 0, used.isFinite else { return 0 }
        return min(1, max(0, used) / quota)
    }

    /// Cost in the 5-hour window ending at `now`, from today's hour buckets.
    static func rollingCost(hours: [AgentBucket], now: Date) -> Double {
        let floor = now.addingTimeInterval(-5 * 3600)
        return hours.filter { $0.start >= floor && $0.start <= now }
            .reduce(0) { $0 + ($1.byProvider[.opencode]?.cost ?? 0) }
    }

    /// Weekly quota renews at the next Monday midnight in the current calendar.
    static func nextWeeklyReset(now: Date, calendar: Calendar = .current) -> Date? {
        var candidate = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
            if calendar.component(.weekday, from: candidate) == 2 { return candidate }
        }
        return nil
    }

    /// Monthly quota renews at midnight on the first of next month.
    static func nextMonthlyReset(now: Date, calendar: Calendar = .current) -> Date? {
        let comps = calendar.dateComponents([.year, .month], from: now)
        guard let monthStart = calendar.date(from: comps),
              let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
        return next
    }

    /// Synthetic limit windows so the island reuses its meters, countdowns
    /// and remaining/used display. Rolling has no fixed reset.
    static func windows(rollingUsed: Double, weeklyUsed: Double, monthlyUsed: Double,
                        plan: AgentGoPlan, now: Date, calendar: Calendar = .current) -> [AgentLimitWindow] {
        let quotas = plan.quotas
        return [
            AgentLimitWindow(id: "opencode.go.rolling", kind: .session, minutes: 300, scope: nil,
                             usedPercent: usedFraction(used: rollingUsed, quota: quotas.rolling) * 100,
                             resetsAt: nil),
            AgentLimitWindow(id: "opencode.go.weekly", kind: .weekly, minutes: 7 * 24 * 60, scope: nil,
                             usedPercent: usedFraction(used: weeklyUsed, quota: quotas.weekly) * 100,
                             resetsAt: nextWeeklyReset(now: now, calendar: calendar)),
            AgentLimitWindow(id: "opencode.go.monthly", kind: .other, minutes: 30 * 24 * 60, scope: nil,
                             usedPercent: usedFraction(used: monthlyUsed, quota: quotas.monthly) * 100,
                             resetsAt: nextMonthlyReset(now: now, calendar: calendar)),
        ]
    }

    /// The footer of the Go token card names the day's tokens, except on
    /// the day view itself, where the week avoids repeating the headline.
    static func tokenFooterPeriod(_ period: AgentPeriod) -> AgentPeriod {
        period == .today ? .week : .today
    }

    /// The three dollar amounts the allowance card shows.
    static func usage(snapshot: AgentUsageSnapshot, now: Date) -> (rolling: Double, weekly: Double, monthly: Double) {
        let weekly = snapshot.usage(.week).byProvider[.opencode]?.cost ?? 0
        let monthly = snapshot.usage(.month).byProvider[.opencode]?.cost ?? 0
        let rolling = rollingCost(hours: snapshot.hours, now: now)
        return (rolling, weekly, monthly)
    }

    // MARK: Per-model caps

    /// Lowercase alphanumeric matching so a display name finds its table
    /// entry: "GPT 6 Luna" and "gpt-6-luna" both key as "gpt6luna", and
    /// "Haiku 5.5" keys as "haiku55" via the model's aliases.
    static func key(_ model: String) -> String {
        model.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// One row of the bundled table: the monthly dollar cap and its variants.
    struct GoModelCap: Decodable {
        let id: String
        let go: Double
        let plus: Double?
        let teams: Double?
        let aliases: [String]

        enum CodingKeys: String, CodingKey {
            case id, go, plus, teams, aliases
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            id = try box.decode(String.self, forKey: .id)
            go = try box.decode(Double.self, forKey: .go)
            plus = try box.decodeIfPresent(Double.self, forKey: .plus)
            teams = try box.decodeIfPresent(Double.self, forKey: .teams)
            aliases = try box.decodeIfPresent([String].self, forKey: .aliases) ?? []
        }

        /// Plus doubles Go and Teams runs 5 USD above Go unless the model
        /// lists its own value.
        func monthly(plan: AgentGoPlan) -> Double {
            switch plan {
            case .go: return go
            case .plus: return plus ?? go * 2
            case .teams: return teams ?? go + 5
            }
        }
    }

    /// The bundled per-model table. Unknown models are nil, and callers
    /// fall back to the plan-wide stacked caps.
    struct GoModelTable: Decodable {
        private let caps: [String: GoModelCap]

        enum CodingKeys: String, CodingKey { case models }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            var caps: [String: GoModelCap] = [:]
            for cap in try box.decode([GoModelCap].self, forKey: .models) {
                caps[AgentGoSupport.key(cap.id)] = cap
                for alias in cap.aliases { caps[AgentGoSupport.key(alias)] = cap }
            }
            self.caps = caps
        }

        init(caps: [String: GoModelCap] = [:]) { self.caps = caps }

        func monthlyCap(model: String, plan: AgentGoPlan) -> Double? {
            caps[AgentGoSupport.key(model)].map { $0.monthly(plan: plan) }
        }

        var isEmpty: Bool { caps.isEmpty }
    }

    static func decodeTable(_ data: Data) -> GoModelTable? {
        try? JSONDecoder().decode(GoModelTable.self, from: data)
    }

    /// The table inside the app; nil in tests, which read the file by path.
    static func bundledTable() -> GoModelTable? {
        guard let url = Bundle.main.url(forResource: "agent-go-limits", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decodeTable(data)
    }

    /// Priced OpenCode cost by model display name for a period.
    static func modelCosts(snapshot: AgentUsageSnapshot, period: AgentPeriod) -> [String: Double] {
        var costs: [String: Double] = [:]
        for share in snapshot.usage(period).models where share.provider == .opencode {
            costs[share.name, default: 0] += share.totals.cost
        }
        return costs
    }

    /// The model closest to its monthly cap; nil while nothing is priced.
    /// Ties read alphabetically so the card is stable.
    static func bindingModel(monthly: [String: Double], plan: AgentGoPlan, table: GoModelTable?) -> String? {
        let priced = monthly.filter { $0.value > 0 }
        guard !priced.isEmpty else { return nil }
        let fallback = plan.quotas.monthly
        return priced.keys.sorted().max {
            let left = $0
            let right = $1
            let leftCap = table?.monthlyCap(model: left, plan: plan) ?? fallback
            let rightCap = table?.monthlyCap(model: right, plan: plan) ?? fallback
            let leftShare = leftCap > 0 ? (priced[left] ?? 0) / leftCap : 0
            let rightShare = rightCap > 0 ? (priced[right] ?? 0) / rightCap : 0
            return leftShare != rightShare ? leftShare < rightShare : left > right
        }
    }

    /// A model's dollar usage per window. Rolling shares the 5-hour total
    /// by monthly share, an estimate, since hour buckets are not split
    /// by model.
    static func modelDollars(model: String, rollingTotal: Double, weekly: [String: Double],
                             monthly: [String: Double]) -> (rolling: Double, weekly: Double, monthly: Double) {
        let monthUsed = monthly[model] ?? 0
        let monthTotal = monthly.values.reduce(0, +)
        let rolling = monthTotal > 0 ? rollingTotal * monthUsed / monthTotal : 0
        return (rolling, weekly[model] ?? 0, monthUsed)
    }
    static func modelWindows(model: String, rollingTotal: Double, weekly: [String: Double],
                             monthly: [String: Double], plan: AgentGoPlan, table: GoModelTable?,
                             now: Date, calendar: Calendar = .current) -> (windows: [AgentLimitWindow], known: Bool) {
        let monthlyCap = table?.monthlyCap(model: model, plan: plan)
        let known = monthlyCap != nil
        let quota = monthlyCap ?? plan.quotas.monthly
        let dollars = modelDollars(model: model, rollingTotal: rollingTotal, weekly: weekly, monthly: monthly)
        let rollingUsed = dollars.rolling
        let weeklyUsed = dollars.weekly
        let monthUsed = dollars.monthly
        let scope = model.isEmpty ? nil : model
        let slug = model.isEmpty ? "all" : key(model)
        return ([
            AgentLimitWindow(id: "opencode.go.\(slug).rolling", kind: .session, minutes: 300, scope: scope,
                             usedPercent: usedFraction(used: rollingUsed, quota: quota * 0.2) * 100,
                             resetsAt: nil),
            AgentLimitWindow(id: "opencode.go.\(slug).weekly", kind: .weekly, minutes: 7 * 24 * 60, scope: scope,
                             usedPercent: usedFraction(used: weeklyUsed, quota: quota * 0.5) * 100,
                             resetsAt: nextWeeklyReset(now: now, calendar: calendar)),
            AgentLimitWindow(id: "opencode.go.\(slug).monthly", kind: .other, minutes: 30 * 24 * 60, scope: scope,
                             usedPercent: usedFraction(used: monthUsed, quota: quota) * 100,
                             resetsAt: nextMonthlyReset(now: now, calendar: calendar)),
        ], known)
    }

    /// What the allowance card shows: the binding model's windows, or the
    /// plan-wide fallback while no priced model ranks.
    static func cardModel(snapshot: AgentUsageSnapshot, now: Date, plan: AgentGoPlan,
                          table: GoModelTable?) -> (model: String?, windows: [AgentLimitWindow], known: Bool) {
        let weekly = modelCosts(snapshot: snapshot, period: .week)
        let monthly = modelCosts(snapshot: snapshot, period: .month)
        let rolling = rollingCost(hours: snapshot.hours, now: now)
        guard let model = bindingModel(monthly: monthly, plan: plan, table: table) else {
            let used = usage(snapshot: snapshot, now: now)
            return (nil, windows(rollingUsed: used.rolling, weeklyUsed: used.weekly,
                                 monthlyUsed: used.monthly, plan: plan, now: now), false)
        }
        let result = modelWindows(model: model, rollingTotal: rolling, weekly: weekly, monthly: monthly,
                                  plan: plan, table: table, now: now)
        return (model, result.windows, result.known)
    }
}
