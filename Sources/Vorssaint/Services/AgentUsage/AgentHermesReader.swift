// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import SQLite3

/// Reads Hermes Agent's usage counters from its session database. Hermes is
/// a harness: the tokens it spends belong to the account each model runs on,
/// so Anthropic usage counts toward Claude and ChatGPT usage toward Codex.
/// Hermes keeps one database per profile; the default home and every profile
/// under `profiles/` are read. Only counters, model names, session ids and
/// folders are handed over; prompts, replies and tool output never leave the
/// database.
enum AgentHermesReader {
    static let database = "state.db"

    /// The card a Hermes billing route's usage belongs to. Routes on other
    /// accounts, like OpenRouter or Nous, have no card of their own.
    static func provider(billing: String) -> AgentProvider? {
        switch billing.lowercased() {
        case "anthropic": return .claude
        case "openai-codex": return .codex
        default: return nil
        }
    }

    /// Reads every counter row again: Hermes keeps running totals, which the
    /// store compares with what it already counted.
    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let identity = UInt64(info.st_ino)
        // A database replaced or recreated starts over.
        if identity != cursor.identity {
            let replaced = cursor.identity != 0
            cursor.identity = identity
            cursor.offset = 0
            cursor.state = AgentLogState()
            if replaced { line(Data(#"{"type":"reset"}"#.utf8)) }
        }
        cursor.modified = AgentOpenCodeReader.modified(cursor.path) ?? cursor.modified

        var db: OpaquePointer?
        // SQLite hands back a connection to close even when opening fails.
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(cursor.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return
        }
        sqlite3_busy_timeout(db, 2000)
        readUsage(db, since: horizon, shouldContinue: shouldContinue, line: line)
    }

    /// Every model/route/task row once, under the key Hermes itself uses for
    /// it, dated by its latest activity. Sessions from before Hermes kept
    /// per-model rows fall back to their own totals.
    private static func readUsage(_ db: OpaquePointer?, since horizon: Date,
                                  shouldContinue: () -> Bool, line: (Data) -> Void) {
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { return }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        let sessionColumns = columns(db, table: "sessions")
        let usageColumns = columns(db, table: "session_model_usage")
        let hasModels = usageColumns.isSuperset(of: ["session_id", "model", "billing_provider", "input_tokens"])
        let hasSessions = sessionColumns.isSuperset(of: ["id", "billing_provider", "input_tokens"])
        guard hasModels || hasSessions else { return }
        func field(_ alias: String, _ name: String, _ available: Set<String>, fallback: String = "NULL") -> String {
            available.contains(name) ? "\(alias).\(name)" : fallback
        }
        let activity = field("s", "last_activity_at", sessionColumns)
        let started = field("s", "started_at", sessionColumns)
        let cwd = field("s", "cwd", sessionColumns, fallback: "''")
        let counters = ["api_call_count", "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens",
                        "reasoning_tokens"]
        // Columns: session, model, folder, time, billing provider, route, then the counters.
        func selection(alias: String, available: Set<String>, time: String, route: String) -> String {
            (["s.id", field(alias, "model", available, fallback: "''"), cwd, time,
              field(alias, "billing_provider", available, fallback: "''"), route]
                + counters.map { field(alias, $0, available, fallback: "0") }).joined(separator: ", ")
        }
        var queries: [String] = []
        if hasModels {
            let time = "coalesce(\(field("u", "last_seen", usageColumns)), \(activity), \(started))"
            let route = ["model", "billing_provider", "billing_base_url", "billing_mode", "task"]
                .map { "coalesce(\(field("u", $0, usageColumns, fallback: "''")), '')" }
                .joined(separator: " || char(31) || ")
            queries.append("SELECT \(selection(alias: "u", available: usageColumns, time: time, route: route)) "
                + "FROM session_model_usage u JOIN sessions s ON s.id = u.session_id WHERE \(time) >= ? ORDER BY u.rowid")
        }
        if hasSessions {
            let time = "coalesce(\(activity), \(started))"
            // Upgraded databases can retain sessions with no per-model rows.
            let missing = hasModels
                ? " AND NOT EXISTS (SELECT 1 FROM session_model_usage u WHERE u.session_id = s.id)" : ""
            queries.append("SELECT \(selection(alias: "s", available: sessionColumns, time: time, route: "'session'")) "
                + "FROM sessions s WHERE \(time) >= ?\(missing) ORDER BY s.id")
        }
        var records: [[String: Any]] = []
        for query in queries {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                sqlite3_finalize(statement); return
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, horizon.timeIntervalSince1970)
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW, shouldContinue() {
                let time = sqlite3_column_double(statement, 3)
                if let session = text(statement, 0), time.isFinite, time > 0,
                   let provider = provider(billing: text(statement, 4) ?? "") {
                    var row: [String: Any] = ["session_id": session, "model": text(statement, 1) ?? "",
                        "directory": text(statement, 2) ?? "", "time_created": time, "provider": provider.rawValue,
                        "key": session + "\u{1F}" + (text(statement, 5) ?? "")]
                    let names = ["requests", "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens",
                                 "reasoning_tokens"]
                    for (index, name) in names.enumerated() {
                        row[name] = max(0, sqlite3_column_int64(statement, Int32(index + 6)))
                    }
                    records.append(row)
                }
                result = sqlite3_step(statement)
            }
            // A partial or cancelled read would look like rows were deleted.
            guard result == SQLITE_DONE, shouldContinue() else { return }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["type": "usage_snapshot", "records": records]) {
            line(data)
        }
    }

    private static func columns(_ db: OpaquePointer?, table: String) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement); return []
        }
        defer { sqlite3_finalize(statement) }
        var found = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, 1) { found.insert(name) }
        }
        return found
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }
}
