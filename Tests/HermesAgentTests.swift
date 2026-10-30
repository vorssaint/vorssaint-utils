// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Hermes is a harness: what it spends counts on the Claude and Codex cards
/// of the accounts its models run on, by what each running total grew.
enum HermesAgentTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        readsUsage(suite)
        keepsDroppedHistory(suite)
        if ProcessInfo.processInfo.environment["VORSSAINT_HERMES_LIVE_CHECK"] == "1" { liveUsage(suite) }
    }

    private static func parsing(_ suite: TestSuite) {
        let reader = AgentProvider.hermes.reader
        let now = Date(timeIntervalSince1970: 1_790_088_000)
        var state = AgentLogState()
        let entries = reader.parse(line("""
        {"type":"usage_snapshot","records":[
         {"key":"s\\u001fa","session_id":"s","model":"claude-opus-5-5","provider":"claude","directory":"/work/app",
          "time_created":1790088000,"requests":2,"input_tokens":10,"output_tokens":4,"cache_read_tokens":3,"cache_write_tokens":1,"reasoning_tokens":2},
         {"key":"s\\u001fb","session_id":"s","model":"gpt-5.6-terra","provider":"codex","time_created":1790088000,"input_tokens":5},
         {"key":"s\\u001fc","session_id":"s","model":"other","provider":"hermes","time_created":1790088000,"input_tokens":9},
         {"session_id":"s","model":"keyless","provider":"claude","time_created":1790088000,"input_tokens":9}]}
        """), state: &state, now: now)
        guard case .usageCounters(let counters)? = entries.first, entries.count == 1 else {
            suite.expect(false, "a Hermes usage snapshot becomes running totals"); return
        }
        suite.expect(counters.map(\.record.provider) == [.claude, .codex],
                     "Hermes totals go to the Claude and Codex cards, never to a card of Hermes")
        suite.expect(counters.first?.record.tokens == AgentTokens(input: 10, cacheWrite: 1, cacheRead: 3, output: 4, reasoning: 2)
                        && counters.first?.record.requests == 2 && counters.first?.record.project == "app",
                     "a total keeps its counters, requests and folder")
        suite.expect(reader.parse(line(#"{"type":"reset"}"#), state: &state, now: now) == [.reset(now)],
                     "a replaced database is announced")
        suite.expect(reader.parse(line(#"{"role":"user","session_id":"s"}"#), state: &state, now: now).isEmpty,
                     "Hermes keeps no turns of its own")
        suite.expect(AgentHermesReader.provider(billing: "anthropic") == .claude
                        && AgentHermesReader.provider(billing: "openai-codex") == .codex
                        && AgentHermesReader.provider(billing: "openrouter") == nil
                        && AgentHermesReader.provider(billing: "") == nil,
                     "only routes on the Claude and ChatGPT accounts have a card")
    }

    private static func readsUsage(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hermes-usage-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "state.db").path
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            suite.expect(false, "Hermes usage fixture opens"); return
        }
        defer { sqlite3_close(db) }
        let now = Date()
        let stamp = now.timeIntervalSince1970 - 600
        let schema = """
        CREATE TABLE sessions (id TEXT PRIMARY KEY, title TEXT, cwd TEXT, model TEXT, billing_provider TEXT,
            started_at REAL, last_activity_at REAL);
        CREATE TABLE messages (id INTEGER PRIMARY KEY, session_id TEXT, role TEXT, content TEXT, timestamp REAL);
        CREATE TABLE session_model_usage (session_id TEXT, model TEXT, billing_provider TEXT NOT NULL DEFAULT '',
            billing_base_url TEXT NOT NULL DEFAULT '', billing_mode TEXT NOT NULL DEFAULT '', task TEXT NOT NULL DEFAULT '',
            api_call_count INTEGER, input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER,
            cache_write_tokens INTEGER, reasoning_tokens INTEGER, first_seen REAL, last_seen REAL);
        INSERT INTO sessions VALUES ('s', 'Usage task', '/work/project', 'claude-opus-5-5', 'anthropic', \(stamp), \(stamp));
        INSERT INTO messages VALUES (1, 's', 'user', 'a prompt that must never be read', \(stamp));
        INSERT INTO session_model_usage VALUES ('s', 'claude-opus-5-5', 'anthropic', '', '', '', 3, 100, 20, 10, 0, 5, \(stamp), \(stamp));
        INSERT INTO session_model_usage VALUES ('s', 'gpt-5.6-terra', 'openai-codex', '', 'subscription_included', '', 1, 40, 2, 0, 0, 0, \(stamp), \(stamp));
        INSERT INTO session_model_usage VALUES ('s', 'upstage/solar-pro4:free', 'nous', '', '', '', 1, 70, 7, 0, 0, 0, \(stamp), \(stamp));
        """
        suite.expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK, "Hermes usage fixture creates real tables")
        let cursor = AgentLogCursor(path: path, provider: .hermes)
        let store = AgentUsageStore()
        func read() {
            AgentLogReader.readAppended(cursor, since: now.addingTimeInterval(-86_400)) { data in
                let entries = AgentProvider.hermes.reader.parse(data, state: &cursor.state, now: now)
                store.apply(entries, file: path, provider: .hermes, tracksTurns: true, modified: now, now: now)
            }
        }
        func tokens(_ provider: AgentProvider) -> Int {
            store.records.filter { $0.provider == provider }.reduce(0) { $0 + $1.tokens.total }
        }
        read()
        suite.expect(store.records.map(\.provider).sorted { $0.rawValue < $1.rawValue } == [.claude, .codex],
                     "Anthropic usage counts on Claude, ChatGPT usage on Codex, and other routes nowhere")
        suite.expect(tokens(.claude) == 130 && tokens(.codex) == 42,
                     "cache is separate from input and reasoning is not added to output again")
        suite.expect(store.records.allSatisfy { !$0.reportedCost } && store.live.isEmpty,
                     "Hermes usage is valued like the agents' own and opens no turn")
        suite.expect(store.takeCounterGrowth() == [.claude, .codex] && store.takeCounterGrowth().isEmpty,
                     "the accounts spent on are told once")
        read()
        suite.expect(store.records.count == 2 && tokens(.claude) == 130,
                     "reading the same running totals again counts nothing")
        suite.expect(store.takeCounterGrowth().isEmpty, "unchanged totals spend on no account")

        let later = stamp + 300
        sqlite3_exec(db, "UPDATE session_model_usage SET input_tokens=150, api_call_count=4, last_seen=\(later) WHERE billing_provider='anthropic'", nil, nil, nil)
        read()
        let growth = store.records.last
        suite.expect(store.records.count == 3 && growth?.provider == .claude && growth?.tokens.input == 50
                        && growth?.tokens.total == 50 && growth?.requests == 1
                        && growth?.date == Date(timeIntervalSince1970: later),
                     "a total that grew counts only what it grew by, at when it grew")
        suite.expect(store.takeCounterGrowth() == [.claude], "only the account that was spent on is told")
        let summary = store.snapshot(plans: [:], providers: [.claude, .codex], now: now)
        suite.expect(summary.usage(.today).byProvider[.claude]?.tokens.total == 180
                        && summary.usage(.today).byProvider[.codex]?.tokens.total == 42
                        && !summary.seen.contains(.hermes),
                     "the Claude and Codex cards show what ran through Hermes, and Hermes has no card")
        suite.expect(summary.burnRate[.claude] != nil, "recent Hermes spending counts in the hourly rate")
        suite.expect(store.saved.records.isEmpty && store.savedRecordCount == 0,
                     "totals are read again at launch, never restored as well")

        sqlite3_exec(db, "UPDATE session_model_usage SET input_tokens=60, api_call_count=1 WHERE billing_provider='anthropic'", nil, nil, nil)
        read()
        suite.expect(store.records.count == 2 && tokens(.claude) == 90,
                     "a total that went down, as after a rewind, replaces what it had given")
        sqlite3_exec(db, "DELETE FROM session_model_usage WHERE billing_provider='openai-codex'", nil, nil, nil)
        read()
        suite.expect(store.records.count == 1 && tokens(.codex) == 0,
                     "a total gone from the database takes back what it gave")

        let legacy = """
        ALTER TABLE sessions ADD COLUMN input_tokens INTEGER DEFAULT 0;
        ALTER TABLE sessions ADD COLUMN output_tokens INTEGER DEFAULT 0;
        ALTER TABLE sessions ADD COLUMN api_call_count INTEGER DEFAULT 0;
        INSERT INTO sessions VALUES ('old', '', '/work/old', 'gpt-5.6-sol', 'openai-codex', \(stamp), \(stamp), 40, 2, 1);
        """
        suite.expect(sqlite3_exec(db, legacy, nil, nil, nil) == SQLITE_OK, "a legacy session gains aggregate counters")
        read()
        suite.expect(tokens(.codex) == 42 && tokens(.claude) == 90,
                     "a session without per-model rows counts by its own totals, the others' rows not twice")

        let profile = folder.appending(path: "profiles/work/state.db").path
        var state = AgentLogState()
        let entries = AgentProvider.hermes.reader.parse(line("""
        {"type":"usage_snapshot","records":[{"key":"s\\u001fsame","session_id":"s","model":"claude-opus-5-5","provider":"claude",
         "time_created":\(stamp),"input_tokens":7,"requests":1}]}
        """), state: &state, now: now)
        store.apply(entries, file: profile, provider: .hermes, tracksTurns: true, modified: now, now: now)
        suite.expect(tokens(.claude) == 97, "profiles with equal sessions keep totals of their own")
        store.apply([.usageCounters([])], file: profile, provider: .hermes, tracksTurns: true, modified: now, now: now)
        suite.expect(tokens(.claude) == 90, "an emptied profile takes back only its own totals")
        store.forget(files: [path])
        suite.expect(store.records.isEmpty, "a database removed takes its totals with it")
    }

    /// A total whose first growth aged out of the history kept is not counted
    /// again the next time it is read.
    private static func keepsDroppedHistory(_ suite: TestSuite) {
        let store = AgentUsageStore()
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        func counter(_ input: Int, at date: Date) -> AgentLogEntry {
            .usageCounters([AgentUsageCounter(key: "s\u{1F}route", record: AgentUsageRecord(
                provider: .claude, date: date, model: "claude-opus-5-5", project: "", session: "s",
                requests: 1, tokens: AgentTokens(input: input), cost: nil, savings: 0))])
        }
        store.apply([counter(100, at: old)], file: "/h/state.db", provider: .hermes, tracksTurns: true, modified: old)
        store.dropRecords(before: old.addingTimeInterval(1))
        let later = old.addingTimeInterval(86_400)
        store.apply([counter(100, at: later)], file: "/h/state.db", provider: .hermes, tracksTurns: true, modified: later)
        suite.expect(store.records.isEmpty, "a total read again after its history aged out is not counted twice")
        store.apply([counter(130, at: later)], file: "/h/state.db", provider: .hermes, tracksTurns: true, modified: later)
        suite.expect(store.records.count == 1 && store.records.first?.tokens.input == 30,
                     "only what it grew by since counts")
    }

    private static func liveUsage(_ suite: TestSuite) {
        let path = AgentLogRoot.hermesHome().appending(path: "state.db").path
        let cursor = AgentLogCursor(path: path, provider: .hermes)
        let store = AgentUsageStore()
        AgentHermesReader.readAppended(cursor) { data in
            let entries = AgentProvider.hermes.reader.parse(data, state: &cursor.state, now: Date())
            store.apply(entries, file: path, provider: .hermes, tracksTurns: true, modified: Date())
        }
        var db: OpaquePointer?
        sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        for (provider, billing) in [(AgentProvider.claude, "anthropic"), (.codex, "openai-codex")] {
            let counted = store.records.filter { $0.provider == provider }.reduce(0) { $0 + $1.tokens.total }
            var statement: OpaquePointer?
            let query = "SELECT coalesce(SUM(input_tokens + output_tokens + cache_read_tokens + cache_write_tokens), 0) "
                + "FROM session_model_usage WHERE billing_provider = '\(billing)'"
            let prepared = sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK
            let expected = prepared && sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : -1
            sqlite3_finalize(statement)
            print("LIVE HERMES \(provider.rawValue): counted=\(counted) database=\(expected)")
            suite.expect(Int64(counted) == expected, "opt-in live check: \(provider.rawValue) counts every \(billing) token")
        }
    }

    private static func line(_ json: String) -> Data { Data(json.utf8) }
}
