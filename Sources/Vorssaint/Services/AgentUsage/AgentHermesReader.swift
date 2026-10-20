// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import SQLite3

/// Reads Hermes Agent turns from its session database. Hermes keeps one
/// database per profile; the default home and every profile under `profiles/`
/// are read, all as the one Hermes the person runs. Of each message only its
/// role, its times and the session's title, folder and model are handed over;
/// prompts, replies and tool output never leave the database.
enum AgentHermesReader {
    static let database = "state.db"
    /// A first read starts this far back: turns alone are kept, so there is no
    /// history to rebuild, only a turn already open to find again.
    static let window: TimeInterval = 6 * 3600

    /// Reads the messages saved since the last read. Messages are saved in
    /// order under growing ids, so the id read last is the place to go on
    /// from, and the ids grow along their times.
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
            restart(cursor, announce: replaced, line: line)
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
        guard exists(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'messages'"),
              exists(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sessions'") else { return }
        if cursor.offset == 0 {
            let floor = max(horizon.timeIntervalSince1970, Date().addingTimeInterval(-window).timeIntervalSince1970)
            cursor.offset = UInt64(max(0, firstRow(db, since: floor)))
        }
        var stmt: OpaquePointer?
        // shortcut: named columns of Hermes' own schema; a renamed one turns the read off, <when Hermes moves them>.
        let select = """
        SELECT m.id, m.session_id, m.role, m.timestamp, m.finish_reason, s.title, s.display_name,
            s.cwd, s.parent_session_id, s.model
        FROM messages m JOIN sessions s ON s.id = m.session_id
        WHERE m.id > ? AND m.role IN ('user', 'assistant', 'tool') ORDER BY m.id
        """
        guard sqlite3_prepare_v2(db, select, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(cursor.offset))
        while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
            cursor.offset = UInt64(max(0, sqlite3_column_int64(stmt, 0)))
            handOver(stmt, line: line)
        }
    }

    /// Hermes persists cumulative counters, not a request ledger. Keep every
    /// model/route row (including auxiliary tasks) exactly once, by its latest
    /// activity. This deliberately does not infer daily billing from messages.
    private static func readUsage(_ db: OpaquePointer?, since horizon: Date,
                                  shouldContinue: () -> Bool, line: (Data) -> Void) {
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { return }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        let sessionColumns = columns(db, table: "sessions")
        guard sessionColumns.contains("input_tokens") || exists(db,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_model_usage'") else { return }
        let usageColumns = columns(db, table: "session_model_usage")
        let hasModels = usageColumns.contains("session_id") && usageColumns.contains("input_tokens")
        func field(_ alias: String, _ name: String, _ available: Set<String>, fallback: String = "NULL") -> String {
            available.contains(name) ? "\(alias).\(name)" : fallback
        }
        let activity = field("s", "last_activity_at", sessionColumns)
        let started = field("s", "started_at", sessionColumns)
        let cwd = field("s", "cwd", sessionColumns, fallback: "''")
        let counters = ["api_call_count", "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens", "reasoning_tokens"]
        func selection(alias: String, available: Set<String>, model: String, time: String) -> String {
            let status = field(alias, "cost_status", available)
            let mode = field(alias, "billing_mode", available)
            let actual = field(alias, "actual_cost_usd", available)
            let estimate = field(alias, "estimated_cost_usd", available)
            let cost = "CASE WHEN \(status) IN ('included', 'unknown') OR \(mode) = 'subscription_included' THEN NULL "
                + "WHEN \(status) = 'actual' THEN \(actual) WHEN \(status) = 'estimated' THEN \(estimate) ELSE NULL END"
            return (["s.id", model, cwd, time] + counters.map { field(alias, $0, available, fallback: "0") } + [cost])
                .joined(separator: ", ")
        }
        var queries: [String] = []
        if hasModels {
            let time = "coalesce(\(field("u", "last_seen", usageColumns)), \(activity), \(started))"
            let select = selection(alias: "u", available: usageColumns,
                                   model: field("u", "model", usageColumns, fallback: "''"), time: time)
            queries.append("SELECT \(select) FROM session_model_usage u JOIN sessions s ON s.id = u.session_id WHERE \(time) >= ? ORDER BY u.rowid")
        }
        if sessionColumns.contains("input_tokens") {
            let time = "coalesce(\(activity), \(started))"
            let select = selection(alias: "s", available: sessionColumns,
                                   model: field("s", "model", sessionColumns, fallback: "''"), time: time)
            // Upgraded databases can retain sessions with no per-model rows.
            let missing = hasModels ? " AND NOT EXISTS (SELECT 1 FROM session_model_usage u WHERE u.session_id = s.id)" : ""
            queries.append("SELECT \(select) FROM sessions s WHERE \(time) >= ?\(missing) ORDER BY s.id")
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
                if let session = text(statement, 0), time.isFinite, time > 0 {
                    var row: [String: Any] = ["session_id": session, "model": text(statement, 1) ?? "",
                        "directory": text(statement, 2) ?? "", "time_created": time]
                    let names = ["requests", "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens", "reasoning_tokens"]
                    for (index, name) in names.enumerated() {
                        row[name] = max(0, sqlite3_column_int64(statement, Int32(index + 4)))
                    }
                    if sqlite3_column_type(statement, 10) != SQLITE_NULL {
                        let cost = sqlite3_column_double(statement, 10)
                        if cost.isFinite, cost >= 0 { row["cost"] = cost }
                    }
                    records.append(row)
                }
                result = sqlite3_step(statement)
            }
            // Never replace authoritative totals with a partial/cancelled read.
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

    /// Hands over the row `stmt` stands on, under the names the parser reads.
    private static func handOver(_ stmt: OpaquePointer?, line: (Data) -> Void) {
        guard let session = text(stmt, 1), let role = text(stmt, 2),
              sqlite3_column_type(stmt, 3) != SQLITE_NULL else { return }
        var json: [String: Any] = [
            "id": String(sqlite3_column_int64(stmt, 0)),
            "session_id": session,
            "role": role,
            "time_created": sqlite3_column_double(stmt, 3),
        ]
        if let finish = text(stmt, 4) { json["finish"] = finish }
        // A gateway session has the chat's name; a local one the folder it ran in.
        if let title = text(stmt, 5), !title.isEmpty {
            json["title"] = title
        } else if let name = text(stmt, 6), !name.isEmpty {
            json["title"] = name
        }
        if let cwd = text(stmt, 7), !cwd.isEmpty { json["directory"] = cwd }
        if let parent = text(stmt, 8), !parent.isEmpty { json["parent_session_id"] = parent }
        if let model = text(stmt, 9), !model.isEmpty { json["model"] = model }
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            line(data)
        }
    }

    /// Starts over from the window, telling the parser to forget what the
    /// earlier reading left open.
    private static func restart(_ cursor: AgentLogCursor, announce: Bool, line: (Data) -> Void) {
        cursor.offset = 0
        cursor.state = AgentLogState()
        if announce {
            line(Data(#"{"type":"reset"}"#.utf8))
        }
    }

    /// The message id just before the window starts.
    private static func firstRow(_ db: OpaquePointer?, since floor: Double) -> Int64 {
        guard floor > 0 else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT max(id) FROM messages WHERE timestamp < ?", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_bind_double(stmt, 1, floor) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
            // Every exit finalizes; a leaked statement keeps the connection
            // open and the poll cycle leaks one handle per database per read.
            sqlite3_finalize(stmt)
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_column_int64(stmt, 0)
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    private static func exists(_ db: OpaquePointer?, _ query: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
