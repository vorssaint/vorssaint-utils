// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// How far reading one OpenCode database has got, beside the last rowid
/// read that `AgentLogCursor.offset` holds.
struct AgentOpenCodeProgress {
    /// Replies still being written, by id, with what they held when read.
    var open: [String: (updated: Int64, length: Int64, changed: Date)] = [:]
    /// The rows read last, oldest first.
    var tail: [(rowid: Int64, id: String)] = []
}

/// Reads OpenCode sessions and messages from its SQLite database (~/.local/share/opencode/opencode.db).
enum AgentOpenCodeReader {
    /// The one database OpenCode keeps in its data folder.
    static let database = "opencode.db"

    /// Rows read last, newest last, to notice when the newest were deleted.
    static let tailLength = 64
    /// A reply that has not changed for this long is not being written any more.
    static let abandoned: TimeInterval = 86_400

    /// The values the parser reads from a message, under the names it reads
    /// them by. The query takes out only these, so prompts, replies, the
    /// summaries OpenCode saves on prompts and error text never leave the
    /// database. Of an error, only whether there is one is read, and of the
    /// paths a reply records, only the folder it worked in.
    private static let values: [(name: String, path: String)] = [
        ("role", "$.role"), ("parentID", "$.parentID"), ("modelID", "$.modelID"), ("model_id", "$.model_id"),
        ("model", "$.model"), ("tokens", "$.tokens"), ("cost", "$.cost"), ("finish", "$.finish"),
        ("time", "$.time"), ("cwd", "$.path.cwd"),
    ]

    /// When the database or its write-ahead log last changed; nil when there
    /// is no database.
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

    /// Reads the messages saved since the last read, or since `horizon` on a
    /// first read, and the replies still being written that changed since.
    /// Calls `line` with a small JSON payload of the values read for each.
    ///
    /// OpenCode indexes messages by session only, so a filter on their times
    /// would walk the whole table. SQLite stores rows in the order they were
    /// saved and keeps that place when a row is updated: new rows are the
    /// ones past `cursor.offset`, the last rowid read, and the only rows that
    /// change afterwards are replies still being written, looked up by id.
    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let identity = UInt64(info.st_ino)

        // Check if database was replaced or recreated
        if identity != cursor.identity {
            let replaced = cursor.identity != 0
            cursor.identity = identity
            restart(cursor, announce: replaced, line: line)
        }
        cursor.modified = modified(cursor.path) ?? date(info.st_mtimespec)

        var db: OpaquePointer?
        // SQLite hands back a connection to close even when opening fails.
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(cursor.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return
        }
        sqlite3_busy_timeout(db, 2000)

        // Reverting a session deletes its newest messages, and SQLite gives
        // their rowids to the next ones saved.
        if !resumes(db, cursor) { restart(cursor, announce: true, line: line) }
        if cursor.offset == 0 {
            cursor.offset = UInt64(firstRow(db, since: Int64(max(0, horizon.timeIntervalSince1970) * 1000)))
        }

        let hasParentID = exists(db, "SELECT 1 FROM pragma_table_info('session') WHERE name = 'parent_id'")
        let hasParts = exists(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'part'")

        // A reply that ends the loop by its finish can still hold tool calls
        // the loop goes on with, and the summary of a compaction OpenCode
        // started on its own is followed by its request to continue. Only
        // each part's type and state are looked at, never its content.
        let toolCalls = hasParts ? """
            CASE WHEN \(field("m.data", "$.role")) = 'assistant'
                AND \(field("m.data", "$.finish")) NOT IN ('tool-calls', 'unknown')
            THEN EXISTS (SELECT 1 FROM part p WHERE p.message_id = m.id
                AND \(field("p.data", "$.type")) = 'tool'
                AND coalesce(\(field("p.data", "$.metadata.providerExecuted")), 0) = 0
                AND NOT (coalesce(\(field("p.data", "$.state.status")), '') = 'error'
                    AND coalesce(\(field("p.data", "$.state.metadata.interrupted")), 0) = 1))
            ELSE 0 END
            """ : "0"
        let autoCompaction = hasParts ? """
            CASE WHEN \(field("m.data", "$.role")) = 'assistant' AND \(field("m.data", "$.summary")) = 1
            THEN EXISTS (SELECT 1 FROM part p WHERE p.message_id = \(field("m.data", "$.parentID"))
                AND \(field("p.data", "$.type")) = 'compaction' AND \(field("p.data", "$.auto")) = 1)
            ELSE 0 END
            """ : "0"
        // A reply is written until it records when it completed.
        let writing = """
            coalesce(\(field("m.data", "$.role")) = 'assistant'
                AND \(field("m.data", "$.time.completed")) IS NULL, 0)
            """
        let parentCol = hasParentID ? "s.parent_id" : "NULL"
        // One pass over each message's JSON hands over the values the parser
        // reads. SQLite keeps that parse for the checks above in the same row.
        let paths = values.map { "'\($0.path)'" }.joined(separator: ", ")
        let select = """
        SELECT m.rowid, m.id, m.session_id, m.time_created, m.time_updated, length(m.data), s.directory,
            \(parentCol), CASE WHEN json_valid(m.data) THEN json_extract(m.data, \(paths)) END,
            \(toolCalls), \(autoCompaction), \(writing),
            CASE WHEN json_valid(m.data) THEN json_type(m.data, '$.error') END
        FROM message m
        JOIN session s ON m.session_id = s.id
        """
        let now = Date()

        // Replies still being written, before anything saved after them.
        let open = Array(cursor.openCode.open.keys)
        if !open.isEmpty {
            let marks = Array(repeating: "?", count: open.count).joined(separator: ", ")
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, select + " WHERE m.id IN (\(marks)) ORDER BY m.rowid", -1, &stmt, nil) == SQLITE_OK
            else { return }
            defer { sqlite3_finalize(stmt) }
            for (index, id) in open.enumerated() {
                sqlite3_bind_text(stmt, Int32(index + 1), id, -1, transient)
            }
            var found = Set<String>()
            while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
                guard let id = text(stmt, 1), let known = cursor.openCode.open[id] else { continue }
                found.insert(id)
                let updated = sqlite3_column_int64(stmt, 4)
                let length = sqlite3_column_int64(stmt, 5)
                // Unchanged since the last read: nothing is copied or parsed.
                if updated == known.updated && length == known.length {
                    if now.timeIntervalSince(known.changed) > abandoned { cursor.openCode.open[id] = nil }
                    continue
                }
                handOver(stmt, cursor: cursor, now: now, line: line)
            }
            // A reply deleted with its session or by a revert is written no more.
            guard shouldContinue() else { return }
            for id in open where !found.contains(id) { cursor.openCode.open[id] = nil }
        }

        // Everything saved since the last read.
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, select + " WHERE m.rowid > ? ORDER BY m.rowid", -1, &stmt, nil) == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(cursor.offset))
        while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            cursor.offset = UInt64(max(0, rowid))
            if let id = text(stmt, 1) {
                cursor.openCode.tail.append((rowid, id))
                if cursor.openCode.tail.count > tailLength { cursor.openCode.tail.removeFirst() }
            }
            handOver(stmt, cursor: cursor, now: now, line: line)
        }
    }

    /// Hands over the row `stmt` stands on, and keeps a reply still being
    /// written to look at again.
    private static func handOver(_ stmt: OpaquePointer?, cursor: AgentLogCursor, now: Date, line: (Data) -> Void) {
        // A later version could leave any of these empty; such a row is
        // skipped rather than read as if it held a value.
        guard let id = text(stmt, 1), let sessionID = text(stmt, 2),
              sqlite3_column_type(stmt, 3) != SQLITE_NULL else { return }
        let created = sqlite3_column_int64(stmt, 3)
        let updated = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? created : sqlite3_column_int64(stmt, 4)
        if sqlite3_column_int64(stmt, 11) != 0 {
            cursor.openCode.open[id] = (sqlite3_column_int64(stmt, 4), sqlite3_column_int64(stmt, 5), now)
        } else {
            cursor.openCode.open[id] = nil
        }

        // A row whose data cannot be read is let go above, not looked at again.
        guard let extracted = text(stmt, 8),
              let found = (try? JSONSerialization.jsonObject(with: Data(extracted.utf8))) as? [Any],
              found.count == values.count else { return }
        var json: [String: Any] = [:]
        for (value, read) in zip(values, found) where !(read is NSNull) { json[value.name] = read }
        if let cwd = json.removeValue(forKey: "cwd") { json["path"] = ["cwd": cwd] }
        json["id"] = id
        json["session_id"] = sessionID
        json["parent_session_id"] = text(stmt, 7) ?? ""
        json["directory"] = text(stmt, 6) ?? ""
        json["time_created"] = created
        json["time_updated"] = updated
        if sqlite3_column_int64(stmt, 9) != 0 { json["tool_calls"] = true }
        if sqlite3_column_int64(stmt, 10) != 0 { json["auto_compaction"] = true }
        if let error = text(stmt, 12), error != "null" { json["error"] = true }

        if let mergedData = try? JSONSerialization.data(withJSONObject: json) {
            line(mergedData)
        }
    }

    /// Starts over from the horizon, telling the parser to forget what the
    /// earlier reading left open.
    private static func restart(_ cursor: AgentLogCursor, announce: Bool, line: (Data) -> Void) {
        cursor.offset = 0
        cursor.openCode = AgentOpenCodeProgress()
        cursor.state = AgentLogState()
        if announce {
            line(Data(#"{"type":"reset"}"#.utf8))
        }
    }

    /// False when every row read last is gone or holds another message, so
    /// the place reached means nothing. When only the newest were deleted,
    /// reading goes on after the newest one still there.
    private static func resumes(_ db: OpaquePointer?, _ cursor: AgentLogCursor) -> Bool {
        let tail = cursor.openCode.tail
        guard !tail.isEmpty else { return true }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id FROM message WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK else {
            return true
        }
        defer { sqlite3_finalize(stmt) }
        for position in tail.indices.reversed() {
            sqlite3_reset(stmt)
            sqlite3_bind_int64(stmt, 1, tail[position].rowid)
            guard sqlite3_step(stmt) == SQLITE_ROW, text(stmt, 0) == tail[position].id else { continue }
            cursor.offset = UInt64(tail[position].rowid)
            cursor.openCode.tail.removeLast(tail.count - 1 - position)
            return true
        }
        return false
    }

    /// The rowid just before the first message created at `floor` or later.
    /// Rows are stored in the order they were saved, so their times only
    /// grow along them, and a binary search finds the place in a few steps.
    private static func firstRow(_ db: OpaquePointer?, since floor: Int64) -> Int64 {
        guard floor > 0 else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT rowid, time_created FROM message WHERE rowid >= ? ORDER BY rowid LIMIT 1",
                                 -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        var last: OpaquePointer?
        var high: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT max(rowid) FROM message", -1, &last, nil) == SQLITE_OK,
           sqlite3_step(last) == SQLITE_ROW {
            high = sqlite3_column_int64(last, 0)
        }
        sqlite3_finalize(last)
        var low: Int64 = 0
        // Everything up to `low` is older than the floor; the answer is at most `high`.
        while low < high {
            let middle = low + (high - low + 1) / 2
            sqlite3_reset(stmt)
            sqlite3_bind_int64(stmt, 1, middle)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                high = middle - 1
                continue
            }
            let rowid = sqlite3_column_int64(stmt, 0)
            if sqlite3_column_type(stmt, 1) == SQLITE_NULL || sqlite3_column_int64(stmt, 1) < floor {
                low = rowid
            } else {
                high = middle - 1
            }
        }
        return low
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    /// A JSON value that reads as null, instead of failing the whole query,
    /// when a row holds something other than JSON.
    private static func field(_ column: String, _ path: String) -> String {
        "(CASE WHEN json_valid(\(column)) THEN json_extract(\(column), '\(path)') END)"
    }

    private static func exists(_ db: OpaquePointer?, _ query: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
