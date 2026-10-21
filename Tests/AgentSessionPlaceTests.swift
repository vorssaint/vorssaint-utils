// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where agents work, what the closed island draws for it, and the month's
/// values the AI page shows beside the limits.
enum AgentSessionPlaceTests {
    static func run(_ suite: TestSuite) {
        claudePlace(suite)
        workingLayout(suite)
        spending(suite)
        resetTime(suite)
        month(suite)
        lifetime(suite)
    }

    private static func claudePlace(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_790_088_100)
        func turn(app: Bool) -> AgentLiveSession? {
            let store = AgentUsageStore()
            let started = Date(timeIntervalSince1970: 1_790_088_000)
            let record = AgentUsageRecord(provider: .claude, date: started.addingTimeInterval(5), model: "claude-opus-4-8",
                                          project: "example", session: "s", tokens: AgentTokens(input: 10, output: 20),
                                          cost: 0.1, savings: 0, claudeApp: app)
            _ = store.apply([.turnBegan(started), .usage(key: "k", record: record, billable: AgentBillable())],
                            file: "claude.jsonl", provider: .claude, tracksTurns: true, modified: now, now: now)
            return store.live.first
        }
        suite.expect(turn(app: true)?.place == .app && turn(app: false)?.place == .terminal,
                     "a Claude turn runs in the app when its responses come from the Claude app, else in the terminal")

        let store = AgentUsageStore()
        let started = Date(timeIntervalSince1970: 1_790_088_000)
        _ = store.apply([.turnBegan(started), .turnPlace(.app)], file: "codex.jsonl", provider: .codex,
                        tracksTurns: true, modified: now, now: now)
        suite.expect(store.live.first?.place == .app, "a Codex turn takes the place its thread names")
    }

    private static func workingLayout(_ suite: TestSuite) {
        func session(_ provider: AgentProvider, _ place: AgentSessionPlace, _ seconds: TimeInterval) -> AgentLiveSession {
            AgentLiveSession(id: UUID().uuidString, provider: provider, started: Date(timeIntervalSince1970: seconds),
                             lastActivity: Date(timeIntervalSince1970: seconds), model: "", project: "",
                             tokens: AgentTokens(), cost: 0, place: place)
        }
        // Oldest first, as the snapshot keeps them.
        let live = [session(.claude, .terminal, 0), session(.codex, .app, 10), session(.claude, .terminal, 20),
                    session(.claude, .app, 30)]
        let layout = NotchAgentWorkingLayout(live, budget: 20)
        suite.expect(layout?.provider == .claude && layout?.terminal == 2 && layout?.app == 1 && layout?.stacked == true,
                     "the island follows the longest-working agent and counts its sessions by place")
        suite.expect(NotchAgentWorkingLayout([], budget: 20) == nil, "nothing working draws no mark")
        if let layout {
            suite.expect(layout.width > layout.ring
                            && layout.badgeWidth(.terminal, count: 2) > layout.badgeWidth(.terminal, count: 1)
                            && layout.badgeWidth(.app, count: 1) == layout.badgeHeight,
                         "a count widens its badge, and a lone session's badge is a square tile")
            suite.expect(layout.anchor(.terminal).y < layout.anchor(.app).y
                            && layout.anchor(.terminal).x == layout.anchor(.app).x
                            && layout.badgeHeight < layout.ring / 2,
                         "with both places working the terminal sits above the app on the ring, both smaller")
        }
        let alone = NotchAgentWorkingLayout(provider: .codex, terminal: 0, app: 1, budget: 30)
        suite.expect(alone.ring == 22 && !alone.stacked && alone.width <= 44 - 11
                        && alone.anchor(.app).x > alone.ring / 2 && alone.anchor(.app).y > alone.ring / 2,
                     "the ring never outgrows the wing, and a lone badge sits at 4:30 inside a 44-point wing")
    }

    private static func spending(_ suite: TestSuite) {
        suite.expect(AgentFormat.spendLevel(0) == .low && AgentFormat.spendLevel(99.99) == .low
                        && AgentFormat.spendLevel(100) == .medium && AgentFormat.spendLevel(499.99) == .medium
                        && AgentFormat.spendLevel(500) == .high,
                     "spending is green under $100, yellow to $500 and red from there")
    }

    private static func resetTime(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 11, minute: 33))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 16, minute: 26))!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15, minute: 33))!
        let later = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        let sameDay = AgentFormat.resetTime(today, now: now, locale: locale, calendar: calendar)
        let thisWeek = AgentFormat.resetTime(saturday, now: now, locale: locale, calendar: calendar)
        let beyond = AgentFormat.resetTime(later, now: now, locale: locale, calendar: calendar)
        suite.expect(sameDay == "16:26", "a reset later today reads as a 24-hour clock time, even in a 12-hour region: \(sameDay)")
        suite.expect(thisWeek.contains("Sat") && thisWeek.contains("15:33") && !thisWeek.contains("PM"),
                     "a reset within the week names its day and its 24-hour time: \(thisWeek)")
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 22))!
        let resting = NotchAgentSupport.restingReset(
            AgentLimitWindow(id: "s", kind: .session, minutes: 300, scope: nil, usedPercent: 40, resetsAt: evening),
            now: now, locale: locale, calendar: calendar)
        suite.expect(resting?.full == "22:00" && resting?.short == "22:00"
                        && AgentFormat.resetTime(evening, now: now, locale: locale, calendar: calendar) == "22:00",
                     "the resting island and the open island name the same 24-hour time: \(String(describing: resting))")
        suite.expect(beyond.contains("Nov"), "a reset beyond the week names its date")
    }

    private static func month(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        func day(_ month: Int, _ day: Int, claude: Double, api: Double, codex: Double) -> AgentBucket {
            var bucket = AgentBucket(start: calendar.date(from: DateComponents(year: 2026, month: month, day: day))!)
            bucket.byProvider[.claude] = AgentTotals(cost: claude)
            bucket.byProvider[.codex] = AgentTotals(cost: codex)
            bucket.claudeAPI = AgentTotals(cost: api)
            return bucket
        }
        var snapshot = AgentUsageSnapshot()
        snapshot.days = [day(9, 30, claude: 100, api: 0, codex: 100), day(10, 1, claude: 30, api: 10, codex: 5),
                         day(10, 2, claude: 20, api: 5, codex: 1)]
        suite.expect(NotchAgentSupport.monthDays(snapshot, now: now, calendar: calendar).count == 2,
                     "the month starts on its first day, not thirty days back")
        suite.expect(NotchAgentSupport.claudePlanMonth(snapshot, splitsBilling: true, now: now, calendar: calendar) == 35
                        && NotchAgentSupport.claudePlanMonth(snapshot, splitsBilling: false, now: now, calendar: calendar) == 50,
                     "the plan's month leaves out what the API key paid for, and counts everything without one")
        suite.expect(NotchAgentSupport.monthTotal(snapshot, providers: [.claude, .codex], now: now, calendar: calendar) == 56
                        && NotchAgentSupport.monthTotal(snapshot, providers: [.claude], now: now, calendar: calendar) == 50,
                     "Spending counts every agent shown this month")
        let start = Date(timeIntervalSince1970: 0)
        snapshot.claudeBlock = AgentBlock(start: start, end: start.addingTimeInterval(18_000), totals: AgentTotals(cost: 9))
        snapshot.claudeAppBlock = AgentBlock(start: start, end: start.addingTimeInterval(18_000), totals: AgentTotals(cost: 4))
        suite.expect(NotchAgentSupport.claudeSessionValue(snapshot, splitsBilling: true) == 4
                        && NotchAgentSupport.claudeSessionValue(snapshot, splitsBilling: false) == 9,
                     "this session counts the app's share when an API key pays for the terminal")
        snapshot.claudeBlock = nil
        suite.expect(NotchAgentSupport.claudeSessionValue(snapshot, splitsBilling: false) == nil,
                     "with no window open there is no session to value")
    }

    private static func lifetime(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func snapshot(_ days: [(Int, Double, Double)]) -> AgentUsageSnapshot {
            var snapshot = AgentUsageSnapshot()
            for (day, opus, codex) in days {
                snapshot.days.append(AgentBucket(start: calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!))
                var models: [String: AgentShare] = [:]
                if opus > 0 {
                    models["claude:Opus"] = AgentShare(id: "claude:Opus", name: "Opus", provider: .claude,
                                                       totals: AgentTotals(tokens: AgentTokens(input: Int(opus)), cost: opus))
                }
                if codex > 0 {
                    models["codex:GPT"] = AgentShare(id: "codex:GPT", name: "GPT", provider: .codex,
                                                     totals: AgentTotals(tokens: AgentTokens(input: Int(codex)), cost: codex))
                }
                snapshot.dayModels.append(models)
            }
            return snapshot
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-ledger-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("agent-ledger.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = AgentUsageLedger(url: url)
        ledger.merge(snapshot([(1, 100, 10), (2, 50, 0)]), calendar: calendar)
        // Day 1's logs are gone and day 2 lost a log; today keeps streaming.
        ledger.merge(snapshot([(2, 20, 0), (3, 30, 5)]), calendar: calendar)
        ledger.merge(snapshot([(2, 20, 0), (3, 40, 5)]), calendar: calendar)
        let usage = ledger.usage(providers: [.claude, .codex])
        suite.expect(usage.total.cost == 205 && usage.byProvider[.claude]?.cost == 190 && usage.byProvider[.codex]?.cost == 15,
                     "the lifetime keeps days whose logs are gone and takes the latest of a growing day: \(usage.total.cost)")
        suite.expect(usage.models.map(\.name) == ["Opus", "GPT"] && usage.models.first?.totals.cost == 190,
                     "lifetime models add up every day, largest first")
        suite.expect(ledger.usage(providers: [.codex]).total.cost == 15, "the lifetime counts only the agents asked for")
        ledger.save()
        suite.expect(AgentUsageLedger(url: url).usage(providers: [.claude, .codex]) == usage,
                     "the lifetime survives a relaunch")
    }
}
