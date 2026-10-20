// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// The Hermes reader's turns, straight from the rows its database reader hands
/// over.
enum HermesAgentTests {
    static func run(_ suite: TestSuite) {
        let reader = AgentProvider.hermes.reader
        let began = Date(timeIntervalSince1970: 1_790_088_000)
        var state = AgentLogState()
        let context = AgentLogEntry.turnContext(model: "nousresearch/hermes-4", project: "Fix the build")
        let prompt = line(#"{"id":"1","session_id":"s","role":"user","time_created":1790088000,"title":"Fix the build","model":"nousresearch/hermes-4"}"#)
        suite.expect(reader.parse(prompt, state: &state, now: began) == [context, .turnBegan(began)],
                     "a Hermes prompt opens its turn with the session's model and title")
        let tool = line(#"{"id":"2","session_id":"s","role":"tool","time_created":1790088020}"#)
        suite.expect(reader.parse(tool, state: &state, now: began)
                        == [context, .turnActive(Date(timeIntervalSince1970: 1_790_088_020))],
                     "a tool result keeps the turn going")
        let call = line(#"{"id":"3","session_id":"s","role":"assistant","time_created":1790088040,"finish":"tool_calls"}"#)
        suite.expect(reader.parse(call, state: &state, now: began).last
                        == .turnActive(Date(timeIntervalSince1970: 1_790_088_040)),
                     "a reply that calls a tool keeps the turn going")
        let done = line(#"{"id":"4","session_id":"s","role":"assistant","time_created":1790088100,"finish":"stop"}"#)
        suite.expect(reader.parse(done, state: &state, now: began).last
                        == .turnEnded(Date(timeIntervalSince1970: 1_790_088_100), completed: true, duration: 100),
                     "a finished reply ends the turn with its real duration")
        suite.expect(reader.parse(tool, state: &state, now: began).isEmpty,
                     "a tool result outside a turn is nothing")
        let streaming = line(#"{"id":"5","session_id":"s","role":"assistant","time_created":1790088200}"#)
        suite.expect(reader.parse(streaming, state: &state, now: began).last
                        == .turnBegan(Date(timeIntervalSince1970: 1_790_088_200)),
                     "a reply that arrives without a prompt, as one written when the reading began, opens a turn")
        let meta = line(#"{"id":"6","session_id":"s","role":"session_meta","time_created":1790088210}"#)
        suite.expect(reader.parse(meta, state: &state, now: began).isEmpty,
                     "session metadata holds no turn")
        let other = line(#"{"id":"7","session_id":"t","role":"user","time_created":1790088300,"directory":"/Users/me/code/app"}"#)
        suite.expect(reader.parse(other, state: &state, now: began).last == .turnBegan(Date(timeIntervalSince1970: 1_790_088_300))
                        && state.hermesSessions["t"]?.project == "app",
                     "a second session tracks its own turn beside the first, named by its folder")
        suite.expect(reader.parse(line(#"{"type":"reset"}"#), state: &state, now: began) == [.reset(began)]
                        && state.hermesSessions.isEmpty,
                     "a replaced database forgets its sessions")
        readsUsage(suite)
        if ProcessInfo.processInfo.environment["VORSSAINT_HERMES_LIVE_CHECK"] == "1" { liveUsage(suite) }
    }

    private static func liveUsage(_ suite: TestSuite) {
        let path = AgentLogRoot.hermesHome().appending(path: "state.db").path
        let cursor = AgentLogCursor(path: path, provider: .hermes)
        let store = AgentUsageStore()
        AgentHermesReader.readAppended(cursor) { data in
            let entries = AgentProvider.hermes.reader.parse(data, state: &cursor.state, now: Date())
            for entry in entries {
                if case .usageSnapshot = entry {
                    store.apply([entry], file: path, provider: .hermes, tracksTurns: true, modified: Date())
                }
            }
        }
        let tokens = store.records.reduce(into: AgentTokens()) { $0 += $1.tokens }
        let snapshot = store.snapshot(plans: [:], providers: [.hermes], now: Date())
        print("LIVE HERMES: records=\(store.records.count) input=\(tokens.input) output=\(tokens.output) cache_read=\(tokens.cacheRead) cache_write=\(tokens.cacheWrite) reasoning=\(tokens.reasoning) total=\(tokens.total) requests=\(store.records.reduce(0) { $0 + $1.requests })")
        print("LIVE HERMES UI SUMMARY: seen=\(snapshot.seen.contains(.hermes)) month_tokens=\(snapshot.usage(.month).total.tokens.total) hourly_burn=\(snapshot.burnRate[.hermes] != nil)")
        suite.expect(!store.records.isEmpty && tokens.total > 0 && snapshot.seen.contains(.hermes),
                     "opt-in live check: stored counters reach the production summary")
        var db: OpaquePointer?
        sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let query = "SELECT SUM(input_tokens + output_tokens + cache_read_tokens + cache_write_tokens) FROM session_model_usage"
        let prepared = sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK
        defer { sqlite3_finalize(statement) }
        suite.expect(prepared && sqlite3_step(statement) == SQLITE_ROW
                     && sqlite3_column_int64(statement, 0) == Int64(tokens.total),
                     "opt-in live check: production counters equal the actual database total")
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
        let stamp = now.timeIntervalSince1970
        let schema = """
        CREATE TABLE sessions (id TEXT PRIMARY KEY, title TEXT, display_name TEXT, cwd TEXT,
            parent_session_id TEXT, model TEXT, started_at REAL, last_activity_at REAL);
        CREATE TABLE messages (id INTEGER PRIMARY KEY, session_id TEXT, role TEXT, timestamp REAL, finish_reason TEXT);
        CREATE TABLE session_model_usage (session_id TEXT, model TEXT, billing_provider TEXT,
            billing_base_url TEXT, billing_mode TEXT, task TEXT, api_call_count INTEGER,
            input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER,
            cache_write_tokens INTEGER, reasoning_tokens INTEGER, estimated_cost_usd REAL,
            actual_cost_usd REAL, cost_status TEXT, first_seen REAL, last_seen REAL);
        INSERT INTO sessions VALUES ('s', 'Usage task', '', '/work/project', NULL, 'test-model', \(stamp), \(stamp));
        INSERT INTO session_model_usage VALUES ('s', 'test-model', 'openai-codex', '',
            'subscription_included', '', 3, 100, 20, 10, 0, 5, 0, 0, 'included', \(stamp), \(stamp));
        """
        suite.expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK, "Hermes usage fixture creates real tables")
        let cursor = AgentLogCursor(path: path, provider: .hermes)
        let store = AgentUsageStore()
        func read() {
            AgentLogReader.readAppended(cursor, since: now.addingTimeInterval(-86_400)) { data in
                let entries = AgentProvider.hermes.reader.parse(data, state: &cursor.state, now: now)
                let file = cursor.state.session.isEmpty ? path : path + "#" + cursor.state.session
                store.apply(entries, file: file, provider: .hermes, tracksTurns: true, modified: now, now: now)
            }
        }
        read()
        suite.expect(store.records.count == 1 && store.records.first?.tokens == AgentTokens(
            input: 100, cacheWrite: 0, cacheRead: 10, output: 20, reasoning: 5),
            "Hermes session/model counters reach usage cards without reading conversation text")
        suite.expect(store.records.first?.requests == 3 && store.records.first?.tokens.total == 130,
                     "cache is separate from input and reasoning is not added to output again")
        suite.expect(store.records.first?.cost == nil && store.live.isEmpty,
                     "included subscription usage is neither an API charge nor a new live task")
        read()
        suite.expect(store.records.count == 1 && store.records.first?.tokens.total == 130,
                     "polling cumulative counters twice does not double usage")
        sqlite3_exec(db, "UPDATE session_model_usage SET input_tokens=150, api_call_count=4, last_seen=\(stamp + 1)", nil, nil, nil)
        read()
        suite.expect(store.records.count == 1 && store.records.first?.tokens.input == 150 && store.records.first?.requests == 4,
                     "counters updated without a new message replace the previous snapshot")
        let totals = store.snapshot(plans: [:], providers: [.hermes], now: now.addingTimeInterval(2))
        suite.expect(totals.seen.contains(.hermes) && totals.usage(.today).byProvider[.hermes]?.tokens.total == 180,
                     "idle Hermes usage is visible in the actual summary shown by cards")
        suite.expect(totals.burnRate[.hermes] == nil,
                     "cumulative session totals cannot masquerade as an hourly burn rate")
        store.reprice()
        suite.expect(store.records.first?.cost == nil, "price refresh cannot turn subscription usage into API charges")
        suite.expect(store.saved.records.isEmpty, "Hermes snapshots are re-read, never restored as stale archived counters")
        sqlite3_exec(db, "DELETE FROM session_model_usage", nil, nil, nil)
        read()
        suite.expect(store.records.isEmpty, "deleted usage rows disappear rather than leaving phantom usage")
        let legacy = """
        ALTER TABLE sessions ADD COLUMN input_tokens INTEGER DEFAULT 0;
        ALTER TABLE sessions ADD COLUMN output_tokens INTEGER DEFAULT 0;
        ALTER TABLE sessions ADD COLUMN api_call_count INTEGER DEFAULT 0;
        UPDATE sessions SET input_tokens=40, output_tokens=2, api_call_count=1;
        """
        suite.expect(sqlite3_exec(db, legacy, nil, nil, nil) == SQLITE_OK, "a legacy session gains aggregate counters")
        read()
        suite.expect(store.records.count == 1 && store.records.first?.tokens.total == 42,
                     "older sessions without model rows fall back to session counters")
        sqlite3_exec(db, "INSERT INTO session_model_usage VALUES ('s', 'other-model', 'openrouter', '', 'api', '', 2, 60, 4, 20, 3, 1, 0.25, 0, 'estimated', \(stamp), \(stamp))", nil, nil, nil)
        read()
        suite.expect(store.records.count == 1 && store.records.first?.model == "other-model"
                     && store.records.first?.tokens.total == 87 && store.records.first?.cost == 0.25,
                     "model rows replace legacy totals rather than double-counting them")
        let second = folder.appending(path: "profile/state.db").path
        var stateForProfile = AgentLogState()
        let entries = AgentProvider.hermes.reader.parse(line("""
        {"type":"usage_snapshot","records":[{"session_id":"s","model":"other-model","time_created":\(stamp),"input_tokens":7,"requests":1}]}
        """), state: &stateForProfile, now: now)
        store.apply(entries, file: second, provider: .hermes, tracksTurns: true, modified: now, now: now)
        suite.expect(store.records.count == 2 && store.records.reduce(0, { $0 + $1.tokens.total }) == 94,
                     "profiles with equal session/model IDs remain distinct")
        store.apply([.usageSnapshot([])], file: second, provider: .hermes, tracksTurns: true, modified: now, now: now)
        suite.expect(store.records.count == 1, "an empty profile snapshot removes only its own counters")
    }

    private static func line(_ json: String) -> Data { Data(json.utf8) }
}
