// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

enum OhMyPiAgentTests {
    private final class Log {
        let now = AgentTimestamp.parse("2026-09-27T15:10:00Z")!
        var state = AgentLogState()
        let store = AgentUsageStore()

        init() { store.reportsTransitions = true }

        private func milliseconds(_ seconds: TimeInterval) -> Int64 {
            Int64((now.timeIntervalSince1970 + seconds) * 1000)
        }

        @discardableResult
        func feed(_ json: [String: Any], at seconds: TimeInterval = 0) -> [AgentUsageEvent] {
            store.apply(AgentLogParser.parseOhMyPi(data(json), state: &state, now: now),
                        file: "stats.db#demo", provider: .omp, tracksTurns: true, modified: now, now: now)
        }

        func user(at seconds: TimeInterval = 0, model: String? = nil) -> [AgentUsageEvent] {
            var json: [String: Any] = ["type": "user", "id": "u\(Int(seconds))", "session": "demo",
                                       "folder": "-rice-cycling", "timestamp": milliseconds(seconds)]
            if let model { json["model"] = model }
            return feed(json, at: seconds)
        }

        func assistant(id: String, at seconds: TimeInterval, stop: String = "stop", error: Bool = false,
                       agent: String = "main", model: String = "omp-test-model", cost: Double = 0.25,
                       unpriced: Bool = false, input: Int = 10, output: Int = 5) -> [AgentUsageEvent] {
            feed(["type": "assistant", "id": id, "session": "demo", "folder": "-rice-cycling",
                  "model": model, "timestamp": milliseconds(seconds), "stop": stop, "error": error,
                  "tokens": ["input": input, "output": output, "cacheRead": 2, "cacheWrite": 1],
                  "cost": cost, "unpriced": unpriced, "agent": agent], at: seconds)
        }

        func data(_ json: [String: Any]) -> Data {
            try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
    }

    static func run(_ suite: TestSuite) {
        turns(suite)
        costs(suite)
        subagents(suite)
        projects(suite)
        database(suite)
    }

    private static func turns(_ suite: TestSuite) {
        let log = Log()
        _ = log.user(at: -120)
        suite.expect(log.store.live.count == 1 && log.store.live.first?.provider == .omp,
                     "an Oh My Pi prompt opens its turn")
        _ = log.assistant(id: "a1", at: -100, stop: "toolUse")
        suite.expect(log.store.live.count == 1 && log.store.records.count == 1,
                     "a reply that called tools counts and keeps the turn going")
        let finished = log.assistant(id: "a2", at: -60)
        suite.expect(log.store.live.isEmpty && log.store.records.count == 2
                        && finished == [.finished(provider: .omp, duration: 60, cost: 0.5,
                                                  tokens: 36, project: "cycling")],
                     "a reply that stopped ends the turn and reports what it used")
        let record = log.store.records.first
        suite.expect(record?.provider == .omp && record?.model == "omp-test-model"
                        && record?.project == "cycling" && record?.session == "demo"
                        && record?.tokens == AgentTokens(input: 10, cacheWrite: 1, cacheRead: 2, output: 5),
                     "an Oh My Pi reply keeps its model, project, session and counters")

        let failed = Log()
        _ = failed.user(at: -30)
        let failure = failed.assistant(id: "a1", at: -10, stop: "error", error: true)
        suite.expect(failed.store.live.isEmpty && failure.isEmpty,
                     "a failed reply ends its turn without a finish to report")

        // A session killed mid-turn leaves the next prompt to start over.
        let killed = Log()
        _ = killed.user(at: -7200)
        _ = killed.assistant(id: "a1", at: -7190, stop: "toolUse")
        _ = killed.user(at: -60)
        suite.expect(killed.store.live.count == 1
                        && killed.store.live.first?.started == killed.now.addingTimeInterval(-60),
                     "a prompt long after a quiet session starts a turn of its own")
    }

    private static func costs(_ suite: TestSuite) {
        let log = Log()
        _ = log.user(at: -120)
        _ = log.assistant(id: "a1", at: -100)
        suite.expect(log.store.records.first?.cost == 0.25 && log.store.records.first?.reportedCost == true,
                     "a model the price list does not know keeps the cost Oh My Pi recorded")

        let unpriced = Log()
        _ = unpriced.user(at: -120)
        _ = unpriced.assistant(id: "a1", at: -100, cost: 0, unpriced: true)
        suite.expect(unpriced.store.records.first?.cost == nil
                        && unpriced.store.records.first?.reportedCost == false,
                     "a reply neither list nor agent could price stays unpriced, not free")

        let local = Log()
        _ = local.user(at: -120)
        _ = local.assistant(id: "a1", at: -100, cost: 0)
        suite.expect(local.store.records.first?.cost == 0 && local.store.records.first?.reportedCost == false,
                     "a local model that recorded no cost stays an estimate of zero")
    }

    private static func subagents(_ suite: TestSuite) {
        let log = Log()
        _ = log.user(at: -120)
        _ = log.assistant(id: "a1", at: -100, stop: "toolUse", agent: "review")
        suite.expect(log.state.parentSession == "demo" && log.store.live.count == 1
                        && log.store.live.first?.tokens.total == 18,
                     "a subagent's reply counts toward its session's turn")
        _ = log.assistant(id: "a2", at: -80)
        suite.expect(log.state.parentSession.isEmpty, "a main reply clears the subagent mark")
    }

    private static func projects(_ suite: TestSuite) {
        suite.expect(OhMyPiReader.projectName("-rice-cycling") == "cycling"
                        && OhMyPiReader.projectName("-tmp") == "tmp"
                        && OhMyPiReader.projectName("/Users/me/code/app") == "app"
                        && OhMyPiReader.projectName("") == "",
                     "a session folder names the project it worked in")
    }

    private static func database(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-omp-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "stats.db").path
        let base: Int64 = 1_790_088_000_000

        func create(_ url: String, _ rows: [String]) {
            var db: OpaquePointer?
            guard sqlite3_open(url, &db) == SQLITE_OK, let db else { return }
            sqlite3_exec(db, """
            CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_file TEXT NOT NULL,
                entry_id TEXT NOT NULL, folder TEXT NOT NULL, model TEXT NOT NULL, provider TEXT NOT NULL,
                api TEXT NOT NULL, timestamp INTEGER NOT NULL, stop_reason TEXT NOT NULL, error_message TEXT,
                input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL, cache_write_tokens INTEGER NOT NULL,
                cost_total REAL NOT NULL, cost_unpriced INTEGER NOT NULL DEFAULT 0,
                agent_type TEXT NOT NULL DEFAULT 'main');
            CREATE TABLE user_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_file TEXT NOT NULL,
                entry_id TEXT NOT NULL, folder TEXT NOT NULL, timestamp INTEGER NOT NULL,
                model TEXT, provider TEXT);
            """, nil, nil, nil)
            for row in rows { sqlite3_exec(db, row, nil, nil, nil) }
            sqlite3_close(db)
        }
        func reply(_ id: String, _ at: Int64, _ stop: String = "stop") -> String {
            """
            INSERT INTO messages (session_file, entry_id, folder, model, provider, api, timestamp,
                stop_reason, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, cost_total)
            VALUES ('/sessions/-app/2026-09-27_\(id).jsonl', '\(id)', '-app', 'omp-test-model', 'test',
                'test', \(at), '\(stop)', 10, 5, 2, 1, 0.25);
            """
        }
        create(path, [
            "INSERT INTO user_messages (session_file, entry_id, folder, timestamp) VALUES ('/sessions/-app/2026-09-27_s.jsonl', 'u-old', '-app', \(base - 10_000_000));",
            reply("old", base - 10_000_000),
            "INSERT INTO user_messages (session_file, entry_id, folder, timestamp, model) VALUES ('/sessions/-app/2026-09-27_s.jsonl', 'u1', '-app', \(base), 'omp-test-model');",
            reply("a1", base + 5000, "toolUse"),
            reply("a2", base + 20_000),
        ])

        let horizon = Date(timeIntervalSince1970: TimeInterval(base) / 1000 - 60)
        let cursor = AgentLogCursor(path: path, provider: .omp)
        var lines: [String] = []
        AgentOhMyPiReader.readAppended(cursor, since: horizon) { lines.append(String(decoding: $0, as: UTF8.self)) }
        suite.expect(lines.count == 3 && lines.first?.contains(#""type":"user""#) == true
                        && lines.last?.contains(#""id":"a2""#) == true && cursor.offset == 3,
                     "the statistics reader hands over prompts and replies in order, from the horizon")

        var db: OpaquePointer?
        if sqlite3_open(path, &db) == SQLITE_OK, let db {
            sqlite3_exec(db, reply("a3", base + 30_000), nil, nil, nil)
            sqlite3_close(db)
        } else { suite.expect(false, "reopening the statistics database") }
        lines.removeAll()
        AgentOhMyPiReader.readAppended(cursor, since: horizon) { lines.append(String(decoding: $0, as: UTF8.self)) }
        suite.expect(lines.count == 1 && lines.first?.contains(#""id":"a3""#) == true,
                     "an incremental read returns only replies saved since the last one")

        // A rebuilt statistics database starts again, telling the parser so.
        let rebuilt = folder.appending(path: "rebuilt.db").path
        create(rebuilt, [reply("b1", base)])
        let moved = AgentLogCursor(path: rebuilt, provider: .omp)
        moved.identity = 1
        lines.removeAll()
        AgentOhMyPiReader.readAppended(moved) { lines.append(String(decoding: $0, as: UTF8.self)) }
        suite.expect(lines.first == #"{"type":"reset"}"#,
                     "a replaced statistics database restarts its reading")
    }
}
