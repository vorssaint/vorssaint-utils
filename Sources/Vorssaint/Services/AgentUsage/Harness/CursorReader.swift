// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import SQLite3

/// Reads the finished runs Cursor's Agent SDK records. Cursor keeps one small
/// SQLite index per workspace agent store under
/// `~/.cursor/projects/<project>/sdk-agent-store/<store>/index.db`; each
/// finished run records its model, start and token totals. Prompts, replies
/// and tool output live in other tables and are never read.
struct CursorReader: AgentHarnessReader {
    var provider: AgentProvider { .cursor }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line),
              let session = json["session"] as? String, !session.isEmpty,
              let run = json["run"] as? String, !run.isEmpty else { return [] }
        let tokens = AgentTokens(input: AgentLogParser.int(json["input"]),
                                 cacheWrite: AgentLogParser.int(json["cacheWrite"]),
                                 cacheRead: AgentLogParser.int(json["cacheRead"]),
                                 output: AgentLogParser.int(json["output"]),
                                 reasoning: AgentLogParser.int(json["reasoning"]))
        guard tokens.total > 0 else { return [] }
        let model = AgentLogParser.native(json["model"] as? String ?? "")
        let project = AgentLogParser.projectName(json["project"] as? String ?? "")
        let date = AgentLogParser.seconds(json["createdAt"]) ?? now
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        let record = AgentUsageRecord(provider: .cursor, date: date, model: model, project: project,
                                      session: session, requests: 1, tokens: tokens,
                                      cost: priced.cost, savings: priced.savings)
        return [.usage(key: "cursor:" + run, record: record, billable: billable)]
    }
}

/// Reads one Cursor agent store. The database is small and rewritten in place,
/// so every finished run is read again whenever the file changes; unchanged
/// runs merge back into the same record.
enum AgentCursorReader {
    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        cursor.identity = UInt64(info.st_ino)
        cursor.modified = AgentOpenCodeReader.modified(cursor.path) ?? Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)

        var db: OpaquePointer?
        // SQLite hands back a connection to close even when opening fails.
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(cursor.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return
        }
        sqlite3_busy_timeout(db, 2000)

        // Only the run's counters, model, start and workspace are selected;
        // the run's result and event payloads are never touched.
        let sql = """
            SELECT r.run_id, r.agent_id, r.model, r.usage_json,
                   coalesce(r.started_at, r.created_at), a.workspace_ref
            FROM runs r
            LEFT JOIN agents a ON a.agent_id = r.agent_id
            WHERE r.usage_json IS NOT NULL
            ORDER BY coalesce(r.started_at, r.created_at)
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        while shouldContinue(), sqlite3_step(stmt) == SQLITE_ROW {
            guard let run = text(stmt, 0), !run.isEmpty,
                  let session = text(stmt, 1), !session.isEmpty,
                  let usage = text(stmt, 3),
                  let started = text(stmt, 4), let date = AgentLogParser.timestamp(started),
                  date >= horizon,
                  let counters = counters(usage), counters.total > 0 else { continue }
            let fields: [String: Any] = [
                "session": session,
                "run": run,
                "createdAt": date.timeIntervalSince1970,
                "project": text(stmt, 5) ?? "",
                "model": text(stmt, 2) ?? "",
                "input": counters.input,
                "cacheWrite": counters.cacheWrite,
                "cacheRead": counters.cacheRead,
                "output": counters.output,
                "reasoning": counters.reasoning,
            ]
            if let payload = try? JSONSerialization.data(withJSONObject: fields) { line(payload) }
        }
        // Every run is read each time, so no row offset is kept; the file's
        // identity and fingerprint still tell a resumed launch it is current.
        cursor.offset = 0
        cursor.fingerprintRead()
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: value)
    }

    private static func counters(_ text: String) -> AgentTokens? {
        guard let json = AgentLogParser.object(Data(text.utf8)) else { return nil }
        let tokens = AgentTokens(input: AgentLogParser.int(json["inputTokens"]),
                                 cacheWrite: AgentLogParser.int(json["cacheWriteTokens"]),
                                 cacheRead: AgentLogParser.int(json["cacheReadTokens"]),
                                 output: AgentLogParser.int(json["outputTokens"]),
                                 reasoning: AgentLogParser.int(json["reasoningTokens"]))
        return tokens.total > 0 ? tokens : nil
    }
}
