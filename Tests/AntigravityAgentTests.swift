// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

enum AntigravityAgentTests {
    static func run(_ suite: TestSuite) {
        let root = AgentLogRoot.canonical(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appending(path: "vorssaint-antigravity-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            let brain = root.appending(path: ".gemini/antigravity/brain", directoryHint: .isDirectory)
            let sessionDir = brain.appending(path: "conv-123", directoryHint: .isDirectory)
            let logsDir = sessionDir.appending(path: ".system_generated/logs", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

            let transcript = logsDir.appending(path: "transcript.jsonl")
            let fullTranscript = logsDir.appending(path: "transcript_full.jsonl")
            let scratch = sessionDir.appending(path: "scratch/temp.jsonl")
            try FileManager.default.createDirectory(at: scratch.deletingLastPathComponent(), withIntermediateDirectories: true)

            try Data("{\"step_index\":0,\"type\":\"USER_INPUT\",\"status\":\"DONE\",\"created_at\":\"2026-11-19T12:00:00Z\"}\n".utf8)
                .write(to: transcript)
            try Data("{}".utf8).write(to: fullTranscript)
            try Data("{}".utf8).write(to: scratch)

            let dbURL = root.appending(path: ".gemini/antigravity/conversation_summaries.db")
            try createDatabase(at: dbURL, conversationID: "conv-123", workspaceURI: "file:///Users/demo/work/vorssaint-utils")

            let roots = AgentLogRoot.all(home: root).filter { $0.provider == .antigravity }
            suite.expect(roots.count == 1 && roots[0].exists, "Antigravity log root resolves under .gemini/antigravity/brain")

            let agRoot = roots[0]
            suite.expect(agRoot.accepts(transcript.path), "accepts compact transcript.jsonl")
            suite.expect(!agRoot.accepts(fullTranscript.path), "rejects transcript_full.jsonl")
            suite.expect(!agRoot.accepts(scratch.path), "rejects scratch files")
            suite.expect(!AgentLogReader.isLog(fullTranscript.path), "isLog skips transcript_full.jsonl")

            let discovered = AgentLogReader.discover(roots, since: .distantPast)
            suite.expect(discovered.count == 1 && discovered[0].path == transcript.path && discovered[0].provider == .antigravity,
                         "discover locates only transcript.jsonl for Antigravity")

            let cursor = AgentLogCursor(path: transcript.path, provider: .antigravity)
            suite.expect(cursor.state.session == "conv-123" && cursor.state.project == "vorssaint-utils",
                         "cursor resolves Antigravity session ID and project from read-only SQLite database")

            var state = cursor.state
            let now = Date(timeIntervalSince1970: 1_790_000_000)
            let store = AgentUsageStore()
            let u1 = Data(#"{"step_index":0,"type":"USER_INPUT","status":"DONE","created_at":"2026-09-21T16:00:00Z","content":"ignored"}"#.utf8)
            let r1 = Data(#"{"step_index":1,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-09-21T16:00:05Z","model":"gemini-4-neon-medium","input_tokens":1200,"cache_read_tokens":300,"output_tokens":80,"tool_calls":[{"name":"bash"}]}"#.utf8)
            let r2 = Data(#"{"step_index":2,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-09-21T16:00:10Z","model":"gemini-4-neon-medium","input_tokens":400,"cache_read_tokens":500,"output_tokens":60}"#.utf8)
            var entries: [AgentLogEntry] = []
            entries += AntigravityReader().parse(u1, state: &state, now: now)
            entries += AntigravityReader().parse(r1, state: &state, now: now)
            entries += AntigravityReader().parse(r2, state: &state, now: now)

            store.apply(entries, file: transcript.path, provider: .antigravity, tracksTurns: true, modified: now, now: now)
            let summary = store.snapshot(plans: [:], providers: [.antigravity], now: now)
            let total = store.records.reduce(0) { $0 + $1.tokens.total }
            suite.expect(store.records.count == 2 && total == 1200 + 300 + 80 + 400 + 500 + 60,
                         "Antigravity aggregates input, cache_read, and output tokens across planner steps")
            suite.expect(store.turns.isEmpty && !state.turnOpen && summary.seen.contains(.antigravity)
                            && store.records.contains { $0.project == "vorssaint-utils" },
                         "finished Antigravity session retains project attribution and closes live turn")
        } catch {
            suite.expect(false, "Antigravity fixture failed: \(error)")
        }
    }

    private static func createDatabase(at url: URL, conversationID: String, workspaceURI: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db else {
            throw NSError(domain: "AntigravityAgentTests", code: 1)
        }
        defer { sqlite3_close(db) }
        let ddl = "CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY, workspace_uris TEXT);"
        guard sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "AntigravityAgentTests", code: 2)
        }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO conversation_summaries (conversation_id, workspace_uris) VALUES (?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "AntigravityAgentTests", code: 3)
        }
        defer { sqlite3_finalize(stmt) }
        let jsonArray = "[\"\(workspaceURI)\"]"
        _ = conversationID.withCString { sqlite3_bind_text(stmt, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        _ = jsonArray.withCString { sqlite3_bind_text(stmt, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "AntigravityAgentTests", code: 4)
        }
    }
}
