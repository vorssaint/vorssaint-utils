// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentClaudeBillingTests {
    static func run(_ suite: TestSuite) {
        detection(suite)
        credits(suite)
        layout(suite)
    }

    private static func detection(_ suite: TestSuite) {
        let helper = Data(#"{"apiKeyHelper":"~/bin/key","env":{}}"#.utf8)
        let environment = Data(#"{"env":{"ANTHROPIC_API_KEY":"sk-ant-x"}}"#.utf8)
        let none = Data(#"{"apiKeyHelper":"","env":{"DISABLE_TELEMETRY":"1"}}"#.utf8)
        suite.expect(AgentClaudeBilling.detected(settings: helper) && AgentClaudeBilling.detected(settings: environment)
                        && !AgentClaudeBilling.detected(settings: none)
                        && !AgentClaudeBilling.detected(settings: Data("not json".utf8)),
                     "an API key in Claude Code's user settings means its sessions bill the key")

        let domain = "com.vorssaint.tests.claude-billing"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let home = FileManager.default.temporaryDirectory.appending(path: "vorssaint-claude-billing-\(UUID().uuidString)")
        let folder = home.appending(path: ".claude")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        suite.expect(AgentClaudeBilling.chosen(in: defaults) == .automatic
                        && !AgentClaudeBilling.usesAPI(in: defaults, home: home),
                     "with no settings file, Claude Code is taken to use the plan")
        try? helper.write(to: folder.appending(path: "settings.json"))
        suite.expect(AgentClaudeBilling.usesAPI(in: defaults, home: home), "automatic follows Claude Code's settings")
        defaults.set(AgentClaudeBilling.subscription.rawValue, forKey: DefaultsKey.notchAgentsClaudeBilling)
        suite.expect(!AgentClaudeBilling.usesAPI(in: defaults, home: home), "a choice in Settings wins over detection")
        defaults.set(AgentClaudeBilling.api.rawValue, forKey: DefaultsKey.notchAgentsClaudeBilling)
        suite.expect(AgentClaudeBilling.usesAPI(in: defaults, home: FileManager.default.temporaryDirectory),
                     "choosing the API key needs no settings file")
    }

    private static func credits(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = Date(timeIntervalSince1970: 1_790_000_000)
        let start = calendar.startOfDay(for: first)
        func day(_ offset: Int, claude: Double, codex: Double = 0) -> AgentBucket {
            var bucket = AgentBucket(start: calendar.date(byAdding: .day, value: offset, to: start)!)
            bucket.byProvider[.claude] = AgentTotals(cost: claude)
            bucket.byProvider[.codex] = AgentTotals(cost: codex)
            return bucket
        }
        var days = [day(0, claude: 3), day(1, claude: 2, codex: 9)]
        let domain = "com.vorssaint.tests.claude-credits"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        let entered = calendar.date(byAdding: .hour, value: 12, to: start)!
        AgentClaudeCredits.store(balance: 50, now: entered, days: days, in: defaults, calendar: calendar)
        let stored = AgentClaudeCredits.stored(in: defaults)
        suite.expect(stored?.balance == 50 && stored?.baseline == 3 && stored?.since == entered,
                     "a balance keeps what its day had already spent")
        suite.expect(stored?.remaining(days: days, calendar: calendar) == 48,
                     "only Claude's spending after the balance was entered is taken from it")
        days[0].byProvider[.claude]?.cost = 4
        suite.expect(stored?.remaining(days: days, calendar: calendar) == 47,
                     "later spending on the day it was entered counts")
        suite.expect(stored?.remaining(days: Array(days.dropFirst()), calendar: calendar) == nil,
                     "a balance older than the days kept no longer says what is left")
        suite.expect(AgentClaudeCredits(balance: 5, since: entered, baseline: 0)
                        .remainingFraction(days: days, calendar: calendar) == 0,
                     "an overspent balance reads as empty, never negative")
        AgentClaudeCredits.store(balance: 0, now: entered, days: days, in: defaults, calendar: calendar)
        suite.expect(AgentClaudeCredits.stored(in: defaults) == nil, "saving no balance clears it")
    }

    private static func layout(_ suite: TestSuite) {
        let tiles = NotchAgentSupport.tiles(cards: [.limits, .spend, .live], providers: [.claude, .codex],
                                            claudeUsesAPI: true)
        suite.expect(tiles.first?.splitsBilling == true && tiles.first?.fullWidth == true
                        && tiles.dropFirst().allSatisfy { !$0.splitsBilling },
                     "only Claude's limits card splits when an API key pays for Claude Code")
        let rows = NotchAgentSupport.rows(tiles, width: 600)
        suite.expect(rows.map(\.count) == [1, 2, 1] && rows.first?.first?.splitsBilling == true,
                     "the split card takes a row of its own")
        suite.expect(NotchAgentSupport.height(of: rows[0], width: 600) == NotchAgentSupport.splitHeight
                        && NotchAgentSupport.height(of: rows[0], width: 300) == NotchAgentSupport.stackedSplitHeight
                        && NotchAgentSupport.height(of: rows[1], width: 600) == NotchAgentSupport.cardHeight,
                     "the split card stacks its halves, and grows, where cards do not pair")
        suite.expect(NotchAgentSupport.tiles(cards: [.limits], providers: [.claude]).first?.splitsBilling == false,
                     "without an API key Claude keeps its usual card")
    }
}
