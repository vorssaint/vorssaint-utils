// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// The Kilo Code card's reading of Kilo's own database, and where the card
/// and Codex's Resets card sit on the AI page.
enum AgentKiloTests {
    static func run(_ suite: TestSuite) {
        reader(suite)
        layout(suite)
    }

    private static func reader(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory.appending(path: "vorssaint-kilo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let since = Date(timeIntervalSince1970: 1_790_000_000)
        let missing = AgentKiloReader.read(home: home, since: since)
        suite.expect(missing == AgentKiloSummary(), "without Kilo the card has nothing installed and nothing to count")

        try? FileManager.default.createDirectory(at: AgentKiloReader.dataFolder(home: home), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(AgentKiloReader.database(home: home).path, &db) == SQLITE_OK else {
            suite.expect(false, "a Kilo database can be made for the test")
            return
        }
        let ms = { (seconds: TimeInterval) in Int64((since.timeIntervalSince1970 + seconds) * 1000) }
        let sql = """
            CREATE TABLE account_state (id integer PRIMARY KEY, active_account_id text, active_org_id text);
            CREATE TABLE session (id text PRIMARY KEY, parent_id text, title text NOT NULL DEFAULT 'secret',
                cost real NOT NULL DEFAULT 0, tokens_input integer NOT NULL DEFAULT 0, tokens_output integer NOT NULL DEFAULT 0,
                tokens_reasoning integer NOT NULL DEFAULT 0, tokens_cache_read integer NOT NULL DEFAULT 0,
                tokens_cache_write integer NOT NULL DEFAULT 0, model text, time_created integer NOT NULL, time_updated integer NOT NULL);
            INSERT INTO session VALUES ('old', NULL, 't', 9, 900, 0, 0, 0, 0, 'kilo/old-model', \(ms(-90_000)), \(ms(-86_400)));
            INSERT INTO session VALUES ('a', NULL, 't', 1.25, 100, 50, 10, 30, 10, 'anthropic/claude-sonnet-5-5', \(ms(60)), \(ms(120)));
            INSERT INTO session VALUES ('b', 'a', 't', 0.25, 20, 5, 0, 0, 0, NULL, \(ms(70)), \(ms(130)));
            INSERT INTO session VALUES ('c', NULL, 't', 0.5, 10, 10, 0, 0, 0, '{"providerID":"kilo","modelID":"gpt-6"}', \(ms(200)), \(ms(300)));
            """
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)

        let read = AgentKiloReader.read(home: home, since: since)
        suite.expect(read.installed && !read.signedIn && read.sessions == 2,
                     "top-level sessions of the period count; a subagent's session and older ones do not")
        suite.expect(abs(read.cost - 2.0) < 0.000_001 && read.tokens == 100 + 50 + 10 + 30 + 10 + 25 + 20,
                     "cost and tokens add every session of the period, subagents' included")
        suite.expect(read.model == "gpt-6" && read.lastUsed == Date(timeIntervalSince1970: since.timeIntervalSince1970 + 300),
                     "the most recent session names the model, whichever way Kilo stored it")

        sqlite3_open(AgentKiloReader.database(home: home).path, &db)
        sqlite3_exec(db, "INSERT INTO account_state VALUES (1, 'acct', NULL)", nil, nil, nil)
        sqlite3_close(db)
        suite.expect(AgentKiloReader.read(home: home, since: since).signedIn,
                     "an active Kilo account reads as signed in without its tokens being read")
        suite.expect(AgentKiloReader.read(home: home, since: since.addingTimeInterval(10_000)).sessions == 0,
                     "a period after the last session is empty")
        suite.expect(AgentKiloReader.modelName("openrouter/meta/llama-5") == "llama-5"
                        && AgentKiloReader.modelName(" ") == nil,
                     "a model path shows only the model's own name")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day: Int = 1_790_000_000 / 86_400
        let noon = Date(timeIntervalSince1970: TimeInterval(day * 86_400 + 43_200))
        suite.expect(AgentKiloReader.start(of: .today, now: noon, calendar: calendar) == calendar.startOfDay(for: noon)
                        && AgentKiloReader.start(of: .week, now: noon, calendar: calendar)
                            == calendar.startOfDay(for: noon).addingTimeInterval(-6 * 86_400),
                     "a period starts at midnight, today or six days before")
    }

    private static func layout(_ suite: TestSuite) {
        let cards: [NotchAgentCard] = [.limits, .spend, .live, .trend, .models, .projects, .activity, .resets, .kilo]
        let tiles = NotchAgentSupport.tiles(cards: cards, providers: [.claude, .codex, .opencode, .copilot])
        let wide: CGFloat = 520
        guard let lead = NotchAgentSupport.lead(tiles, width: wide) else {
            suite.expect(false, "a wide page leads with Claude's card")
            return
        }
        suite.expect(lead.stack.first?.card == .kilo && !lead.stack.contains { $0.card == .resets },
                     "the Kilo Code card takes the top spot beside Claude's card")
        let rows = NotchAgentSupport.rows(lead.rest, width: wide)
        let resetsRow = rows.first { $0.contains { $0.card == .resets } }
        suite.expect(resetsRow?.count == 2 && resetsRow?.first?.card == .live
                        && rows.allSatisfy { row in row.count == 2 || row.contains(where: \.card.fullWidth) },
                     "the Resets card fills the half row beside Live, under Spending, and no half row is left empty")
        suite.expect(NotchAgentSupport.rows(lead.rest, width: 300).allSatisfy { $0.count == 1 },
                     "a narrow page still gives every card a row")

        let withoutKilo = NotchAgentSupport.tiles(cards: cards.filter { $0 != .kilo }, providers: [.claude, .codex])
        suite.expect(NotchAgentSupport.lead(withoutKilo, width: wide)?.stack.first?.card == .resets,
                     "without the Kilo Code card the Resets card keeps its place beside Claude's")
        let noGap = NotchAgentSupport.tiles(cards: [.spend, .live, .resets], providers: [.codex])
        suite.expect(NotchAgentSupport.rows(noGap, width: wide).map { $0.map(\.card) } == [[.spend, .live], [.resets]],
                     "with no gap to fill the Resets card keeps its place in the order")
    }
}
