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
