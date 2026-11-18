// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// How far reading Oh My Pi's statistics has got with its prompts, beside
/// the last reply read that `AgentLogCursor.offset` holds. Replies use the
/// cursor's own offset because both are handed over in one reading.
struct AgentOhMyPiProgress {
    /// The last prompt read, by its row in the statistics.
    var userOffset: Int64 = 0
}

/// Reads Oh My Pi usage from the statistics database it keeps beside its
/// sessions (~/.omp/stats.db). Oh My Pi reduces every reply to counters
/// there itself, so the query takes only those columns: no prompt, reply
/// or tool output is in the database to begin with, and none is read here.
///
/// Its rows are never rewritten, and its counters only grow, so new rows
/// are the ones past the row read last. Its statistics are rebuilt when a
/// session file changes, which can replace the database; a new file starts
/// again from the horizon, as OpenCode's database does.
enum AgentOhMyPiReader {
    /// The one statistics database Oh My Pi keeps in its folder.
    static let database = "stats.db"

    /// When the database or its write-ahead log last changed; nil when
    /// there is none.
    static func modified(_ path: String) -> Date? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        var wal = stat()
        let walModified = stat(path + "-wal", &wal) == 0 ? date(wal.st_mtimespec) : .distantPast
        return max(date(info.st_mtimespec), walModified)
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    /// Reads the prompts and replies saved since the last read, or since
    /// `horizon` on a first read. Calls `line` with a small JSON payload of
    /// the values read for each, in the order they were written.
    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let identity = UInt64(info.st_ino)

        // A database replaced or recreated starts again from the horizon.
        if identity != cursor.identity {
            let replaced = cursor.identity != 0
            cursor.identity = identity
            restart(cursor, announce: replaced, line: line)
        }
        cursor.modified = modified(cursor.path) ?? date(info.st_mtimespec)

        var db: OpaquePointer?
        // SQLite hands back a connection to close even when opening fails.
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(cursor.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              exists(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'messages'") else { return }
        sqlite3_busy_timeout(db, 2000)
        let hasPrompts = exists(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'user_messages'")

        let floor = Int64(max(0, horizon.timeIntervalSince1970) * 1000)
        if cursor.offset == 0 {
            cursor.offset = UInt64(firstRow(db, table: "messages", since: floor))
        }
        if hasPrompts, cursor.ohMyPi.userOffset == 0 {
            cursor.ohMyPi.userOffset = firstRow(db, table: "user_messages", since: floor)
        }

        // Prompts and replies are read together and handed over in the
        // order they were written, so a turn opens before its replies.
        var rows: [(time: Int64, prompt: Bool, data: Data)] = []

        if hasPrompts {
            var stmt: OpaquePointer?
            let query = """
                SELECT id, session_file, entry_id, folder, timestamp, model
                FROM user_messages WHERE id > ? ORDER BY id
                """
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, cursor.ohMyPi.userOffset)
                while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
                    cursor.ohMyPi.userOffset = sqlite3_column_int64(stmt, 0)
                    guard let session = text(stmt, 1) else { continue }
                    var json: [String: Any] = ["type": "user",
                                               "id": text(stmt, 2) ?? "",
                                               "session": sessionID(session),
                                               "folder": text(stmt, 3) ?? "",
                                               "timestamp": sqlite3_column_int64(stmt, 4)]
                    if let model = text(stmt, 5) { json["model"] = model }
                    if let data = try? JSONSerialization.data(withJSONObject: json) {
                        rows.append((sqlite3_column_int64(stmt, 4), true, data))
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        guard shouldContinue() else { return }

        var stmt: OpaquePointer?
        let query = """
            SELECT id, session_file, entry_id, folder, model, timestamp, stop_reason,
                error_message IS NOT NULL, input_tokens, output_tokens,
                cache_read_tokens, cache_write_tokens, cost_total, cost_unpriced, agent_type
            FROM messages WHERE id > ? ORDER BY id
            """
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(stmt, 1, Int64(cursor.offset))
        while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
            cursor.offset = UInt64(max(0, sqlite3_column_int64(stmt, 0)))
            guard let session = text(stmt, 1) else { continue }
            let json: [String: Any] = ["type": "assistant",
                                       "id": text(stmt, 2) ?? "",
                                       "session": sessionID(session),
                                       "folder": text(stmt, 3) ?? "",
                                       "model": text(stmt, 4) ?? "",
                                       "timestamp": sqlite3_column_int64(stmt, 5),
                                       "stop": text(stmt, 6) ?? "",
                                       "error": sqlite3_column_int64(stmt, 7) != 0,
                                       "tokens": ["input": sqlite3_column_int64(stmt, 8),
                                                  "output": sqlite3_column_int64(stmt, 9),
                                                  "cacheRead": sqlite3_column_int64(stmt, 10),
                                                  "cacheWrite": sqlite3_column_int64(stmt, 11)],
                                       "cost": sqlite3_column_double(stmt, 12),
                                       "unpriced": sqlite3_column_int64(stmt, 13) != 0,
                                       "agent": text(stmt, 14) ?? "main"]
            if let data = try? JSONSerialization.data(withJSONObject: json) {
                rows.append((sqlite3_column_int64(stmt, 5), false, data))
            }
        }
        sqlite3_finalize(stmt)

        for row in rows.sorted(by: { $0.time != $1.time ? $0.time < $1.time : $0.prompt && !$1.prompt })
        where shouldContinue() {
            line(row.data)
        }
    }

    /// The name a session is kept under, from the file Oh My Pi kept it in.
    private static func sessionID(_ sessionFile: String) -> String {
        var name = (sessionFile as NSString).lastPathComponent
        if name.hasSuffix(".jsonl") { name = String(name.dropLast(6)) }
        return name
    }

    /// Starts over from the horizon, telling the parser to forget what the
    /// earlier reading left open.
    private static func restart(_ cursor: AgentLogCursor, announce: Bool, line: (Data) -> Void) {
        cursor.offset = 0
        cursor.ohMyPi = AgentOhMyPiProgress()
        cursor.state = AgentLogState()
        if announce {
            line(Data(#"{"type":"reset"}"#.utf8))
        }
    }

    /// The row just before the first one written at `floor` or later, so a
    /// first read skips what the island cannot show anyway. Rows are never
    /// rewritten, so that place stays where it was found.
    private static func firstRow(_ db: OpaquePointer?, table: String, since floor: Int64) -> Int64 {
        guard floor > 0 else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT min(id) FROM \(table) WHERE timestamp >= ?",
                                 -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, floor)
        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
            // Nothing that recent: everything there is skipped.
            var newest: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT max(id) FROM \(table)", -1, &newest, nil) == SQLITE_OK
            else { return 0 }
            defer { sqlite3_finalize(newest) }
            return sqlite3_step(newest) == SQLITE_ROW ? sqlite3_column_int64(newest, 0) : 0
        }
        return max(0, sqlite3_column_int64(stmt, 0) - 1)
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
