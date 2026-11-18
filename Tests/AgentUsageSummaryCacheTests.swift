// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentUsageSummaryCacheTests {
    static func run(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // The day before the spring DST transition, including future entries.
        var now = AgentTimestamp.parse("2026-03-07T23:55:00Z")!
        let cache = AgentUsageSummaryCache()
        var records: [AgentUsageRecord] = (0..<6_000).map { index -> AgentUsageRecord in
            let provider: AgentProvider = index % 2 == 0 ? .claude : .codex
            let date = now.addingTimeInterval(-Double(index) * 1_400 + 900)
            let model = index % 2 == 0 ? "claude-opus-5-5" : "gpt-6-sol"
            let tokens = AgentTokens(input: index + 1, output: 10)
            let cost: Double? = index % 13 == 0 ? nil : Double(index % 11) / 8
            return AgentUsageRecord(provider: provider, date: date, model: model, project: "p\(index % 7)",
                                    session: "s", tokens: tokens, cost: cost, savings: 0.125)
        }
        var providers = Set(AgentProvider.allCases)
        var live: [AgentLiveSession] = []
        var limits: [AgentProvider: AgentLimits] = [:]
        var plans: [AgentProvider: AgentPlan] = [:]
        func check(_ message: String) {
            let actual = cache.snapshot(records: records, limits: limits, live: live, plans: plans,
                                        providers: providers, now: now, calendar: calendar)
            let expected = AgentUsageSummary.snapshot(records: records, limits: limits, live: live, plans: plans,
                                                       providers: providers, now: now, calendar: calendar)
            suite.expect(actual == expected, message)
        }
        check("cached history matches every field of the full summary")
        suite.expect(cache.accumulatedRecords == records.count, "the first snapshot accumulates history once")
        live = [AgentLiveSession(id: "live", provider: .codex, started: now, lastActivity: now,
                                 model: "gpt-6-sol", project: "p", tokens: AgentTokens(), cost: 0)]
        check("live sessions update without changing historical usage")
        suite.expect(cache.accumulatedRecords == 0, "live-only publications accumulate no historical records")
        limits[.codex] = AgentLimits(provider: .codex, windows: [], observedAt: now, source: .sessionLog)
        plans[.codex] = AgentPlan(name: "Pro", monthlyPrice: 200)
        check("plan and limit changes update independently from historical totals")
        suite.expect(cache.accumulatedRecords == 0, "metadata-only publications accumulate no historical records")
        let appended = AgentUsageRecord(provider: .codex, date: now, model: "gpt-6-sol", project: "new",
            session: "s", tokens: AgentTokens(input: 50, output: 10), cost: 0.25, savings: 0.125)
        records.append(appended)
        cache.recordChanged(at: records.count - 1, previous: nil)
        check("an appended response updates all periods, buckets and breakdowns")
        suite.expect(cache.accumulatedRecords == 1, "one appended response does not rescan the history")
        for _ in 0..<3 {
            let position = records.count - 1
            cache.recordChanged(at: position, previous: records[position])
            records[position].tokens.output += 5
            records[position].cost! += 0.125
        }
        check("several streamed corrections use the original response exactly once")
        suite.expect(cache.accumulatedRecords == 1, "a streamed response only accumulates one delta")
        // A response can be appended and revised within the same publication.
        cache.recordChanged(at: records.count, previous: nil)
        records.append(appended)
        cache.recordChanged(at: records.count - 1, previous: appended)
        records[records.count - 1].tokens.output += 1
        check("a response appended and revised before publication is not subtracted twice")
        let late = AgentUsageRecord(provider: .claude, date: now.addingTimeInterval(-20 * 86_400),
            model: "unknown", project: "late", session: "s", tokens: AgentTokens(output: 5), cost: nil, savings: 0)
        cache.recordChanged(at: records.count, previous: nil)
        records.append(late)
        check("a newly discovered old response updates history without entering sliding windows")
        // Exercise an unpriced response becoming priced through a correction.
        cache.recordChanged(at: 13, previous: records[13])
        records[13].cost = 0.5
        records[13].tokens.output += 2
        check("streaming updates unpriced counts and model sort weights")
        now = now.addingTimeInterval(3_600)
        check("sliding windows expire and future responses become current without a history scan")
        suite.expect(cache.accumulatedRecords == 0, "clock-only updates leave historical totals cached")
        live = []
        providers = [.claude]
        check("disabling a provider removes its usage, limits and live sessions")
        providers = Set(AgentProvider.allCases)
        check("reenabling a provider rebuilds its historical totals")
        now = now.addingTimeInterval(86_400)
        check("midnight across DST rebuilds daily and hourly boundaries")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        check("a time-zone change rebuilds the date buckets")
        now = now.addingTimeInterval(-90_000)
        check("a backwards clock restores entries that left the sliding windows")
        records.removeFirst(20)
        cache.invalidate()
        check("pruning rebuilds positions and totals without stale recent entries")
        for index in records.indices { records[index].cost = 0.5 }
        cache.invalidate()
        check("repricing rebuilds cost, savings and unpriced totals")
        customRange(suite)
        allTime(suite, now: now, calendar: calendar)
        storeIntegration(suite, now: now, calendar: calendar)
    }

    private static func customRange(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let range = AgentDateRange(from: start, through: start, calendar: calendar)
        let interval = range.interval(calendar: calendar)!
        suite.expect(interval.duration == 23 * 3600, "an inclusive one-day range follows the DST calendar day")
        suite.expect(AgentDateRange.restore(range.storageValue) == range,
                     "custom date choices round-trip through a single saved preference")
        var east = calendar
        east.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let moved = range.interval(calendar: east)!
        suite.expect(east.component(.day, from: moved.start) == 8 && east.component(.hour, from: moved.start) == 0,
                     "saved calendar dates keep the selected day when the time zone changes")
        suite.expect(AgentDateRange(from: interval.end, through: start, calendar: calendar).interval(calendar: calendar) == nil,
                     "a reversed range is invalid")
        suite.expect(AgentDateRange.restore("invalid") == nil
                        && AgentDateRange.restore(#"{"from":"2026-02-30","through":"2026-03-08"}"#) == nil,
                     "malformed preferences and impossible dates are rejected")
        let now = interval.end.addingTimeInterval(10 * 86_400)
        var records: [AgentUsageRecord] = [
            (start.addingTimeInterval(-1), AgentProvider.claude, 1.0, "before"),
            (start, .claude, 2.0, "inside"),
            (interval.end.addingTimeInterval(-1), .codex, 4.0, "inside"),
            (interval.end, .claude, 8.0, "after")
        ].map { date, provider, cost, project in
            AgentUsageRecord(provider: provider, date: date, model: provider.rawValue, project: project,
                session: "s", tokens: AgentTokens(input: 10), cost: cost, savings: 0)
        }
        let cache = AgentUsageSummaryCache()
        let providers: Set<AgentProvider> = [.claude, .codex]
        func snapshot(_ selected: DateInterval?) -> AgentUsageSnapshot {
            cache.snapshot(records: records, limits: [:], live: [], plans: [:], providers: providers,
                           now: now, customRange: selected, calendar: calendar)
        }
        var result = snapshot(interval)
        suite.expect(result.usage(.custom).total.cost == 6 && result.usage(.custom).total.tokens.total == 20,
                     "custom totals include both boundary days and exclude the following midnight")
        suite.expect(result.usage(.custom).projects.map(\.name) == ["inside"]
                        && result.usage(.custom).models.count == 2,
                     "custom model and project shares use the same date filter")
        suite.expect(result.trendBuckets(.custom).count == 1
                        && result.trendBuckets(.custom).reduce(0) { $0 + $1.total.cost } == 6,
                     "a single-day custom chart preserves the selected totals")
        suite.expect(result.usage(.allTime).total.cost == 15 && result.usage(.month).total.cost == 15,
                     "custom filtering does not change preset totals")
        _ = snapshot(interval)
        suite.expect(cache.accumulatedRecords == 0, "an unchanged custom range reuses cached history")
        let emptyRange = DateInterval(start: interval.end.addingTimeInterval(86_400), end: now)
        suite.expect(snapshot(emptyRange).usage(.custom).total.tokens.total == 0,
                     "changing to an empty custom range clears its previous totals")
        cache.recordChanged(at: records.count, previous: nil)
        records.append(AgentUsageRecord(provider: .claude, date: now.addingTimeInterval(-3600), model: "m",
            project: "new", session: "s", tokens: AgentTokens(input: 5), cost: 1, savings: 0))
        result = snapshot(emptyRange)
        suite.expect(result.usage(.custom).total.cost == 1 && cache.accumulatedRecords == 1,
                     "new activity updates a selected range incrementally")
        result = snapshot(interval)
        suite.expect(result.usage(.custom).total.cost == 6
                        && result == AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
                            providers: providers, now: now, customRange: interval, calendar: calendar),
                     "changing ranges rebuilds the cache and matches the complete summary")
        let filtered = AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
            providers: [.claude], now: now, customRange: interval, calendar: calendar)
        suite.expect(filtered.usage(.custom).total.cost == 2, "custom ranges respect provider visibility")
    }

    private static func allTime(_ suite: TestSuite, now: Date, calendar: Calendar) {
        let cache = AgentUsageSummaryCache()
        var records = [AgentUsageRecord(provider: .claude, date: now, model: "m", project: "recent",
            session: "s", tokens: AgentTokens(input: 10), cost: 1, savings: 0)]
        func snapshot() -> AgentUsageSnapshot {
            cache.snapshot(records: records, limits: [:], live: [], plans: [:],
                           providers: [.claude], now: now, calendar: calendar)
        }
        _ = snapshot()
        let old = AgentUsageRecord(provider: .claude,
            date: calendar.date(byAdding: .day, value: -400, to: now)!, model: "m", project: "old",
            session: "s", tokens: AgentTokens(input: 10), cost: 4, savings: 0)
        cache.recordChanged(at: records.count, previous: nil)
        records.append(old)
        let result = snapshot()
        suite.expect(result.usage(.allTime).total.cost == 5, "all time includes responses older than 91 days")
        suite.expect(result.usage(.month).total.cost == 1, "all time does not widen the 30-day filter")
        suite.expect(result.usage(.allTime).projects.contains { $0.name == "old" }, "all time includes historical projects")
        suite.expect(result == AgentUsageSummary.snapshot(records: records, limits: [:], live: [], plans: [:],
            providers: [.claude], now: now, calendar: calendar), "late older history rebuilds the cache correctly")
        let bars = result.trendBuckets(.allTime)
        suite.expect(bars.count <= 30 && bars.reduce(0) { $0 + $1.total.cost } == 5,
                     "all-time trend stays readable without losing historical cost")
        cache.recordChanged(at: 1, previous: records[1])
        records[1].cost = 6
        suite.expect(snapshot().usage(.allTime).total.cost == 7, "historical corrections update all-time totals once")
        suite.expect(result.trendBuckets(.month).count == 30, "month trend keeps thirty daily bars")
        let checkpoint = AgentUsageRecord(provider: .copilot, date: old.date, model: "m", project: "checkpoint",
            session: "s", requests: 0, tokens: AgentTokens(input: 25), cost: 2, savings: 0)
        let checkpointSnapshot = AgentUsageSummary.snapshot(records: [checkpoint], limits: [:], live: [], plans: [:],
            providers: [.copilot], now: now, calendar: calendar)
        let checkpointBars = checkpointSnapshot.trendBuckets(.allTime)
        suite.expect(checkpointBars.reduce(0) { $0 + $1.total.tokens.total } == 25
                        && checkpointBars.reduce(0) { $0 + $1.total.cost } == 2,
                     "all-time trend retains token checkpoints with no additional requests")
        suite.expect(checkpointBars.first?.start == calendar.startOfDay(for: old.date),
                     "all-time trend starts at the first recorded usage, including zero-request checkpoints")
        let empty = AgentUsageSummary.snapshot(records: [], limits: [:], live: [], plans: [:],
            providers: [.claude], now: now, calendar: calendar)
        suite.expect(empty.trendBuckets(.allTime).isEmpty, "all-time trend is empty when no history is available")
    }

    private static func storeIntegration(_ suite: TestSuite, now: Date, calendar: Calendar) {
        let store = AgentUsageStore()
        let providers = Set(AgentProvider.allCases)
        func check(_ message: String) {
            let actual = store.snapshot(plans: [:], providers: providers, now: now, calendar: calendar)
            let expected = AgentUsageSummary.snapshot(records: store.records, limits: store.limits, live: store.live,
                                                       plans: [:], providers: providers, now: now, calendar: calendar)
            suite.expect(actual == expected, message)
        }
        check("the store starts with a valid empty summary")
        func apply(output: Int, key: String, age: TimeInterval = 0) {
            let tokens = AgentTokens(input: 100, output: output)
            let billable = AgentBillable(tokens: tokens)
            let price = AgentPricing.cost(billable, model: "gpt-6-sol")
            let record = AgentUsageRecord(provider: .codex, date: now.addingTimeInterval(-age), model: "gpt-6-sol",
                project: "project", session: "s", tokens: tokens, cost: price.cost, savings: price.savings)
            store.apply([.usage(key: key, record: record, billable: billable)], file: "f", provider: .codex,
                        tracksTurns: false, modified: now, now: now)
        }
        apply(output: 5, key: "first")
        check("store insertion invalidates the cached summary")
        apply(output: 15, key: "first")
        apply(output: 15, key: "first")
        check("store streaming and duplicate records preserve summary totals")
        apply(output: 5, key: "old", age: 80 * 86_400)
        check("late historical responses update their own date buckets")
        store.reprice()
        check("store repricing invalidates every cached total")
        store.dropRecords(before: now.addingTimeInterval(-86_400))
        check("store pruning invalidates cached record positions")
    }
}
