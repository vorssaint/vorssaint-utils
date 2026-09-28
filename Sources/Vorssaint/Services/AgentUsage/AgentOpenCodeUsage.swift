// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Where OpenCode keeps its sessions. The desktop app, the terminal UI and
/// the IDE extension all write to the same SQLite database; the file-based
/// JSON storage under `project/` is from older releases and is not read.
enum AgentOpenCodeDatabase {
    static func databaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".local/share/opencode/opencode.db", directoryHint: .notDirectory)
    }

    static func exists(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        FileManager.default.fileExists(atPath: databaseURL(home: home).path)
    }
}

/// How far into the OpenCode database reading has got. Message rows are
/// immutable except for an assistant reply that gains its tokens and completion
/// time, so the high-water mark is the newest `time_updated` seen; a small
/// overlap on every read catches rows that share a millisecond.
struct AgentOpenCodeCursor {
    var lastUpdated: Int64 = 0
}

/// One assistant reply from the OpenCode database, reduced to what the island
/// keeps. Only usage counters, model names, times and folder names leave a
/// row; prompts, replies and tool output are never decoded into anything that
/// is stored.
enum AgentOpenCodeParser {
    /// OpenCode writes milliseconds; anything else is refused.
    static func date(ms value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let ms = number.doubleValue
        guard ms.isFinite, ms > 0, ms < 1e16 else { return nil }
        return Date(timeIntervalSince1970: ms / 1_000)
    }

    static func millis(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1_000) }

    /// Tokens in the message shape, mapped onto the flat counts both logs
    /// reduce to. `input` already excludes cache traffic.
    static func tokens(_ value: Any?) -> AgentTokens? {
        guard let usage = value as? [String: Any] else { return nil }
        let cache = usage["cache"] as? [String: Any] ?? [:]
        func int(_ key: String, in dict: [String: Any]) -> Int {
            guard let number = dict[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
            let double = number.doubleValue
            guard double.isFinite, double > 0 else { return 0 }
            return Int(min(double, 1e12))
        }
        return AgentTokens(
            input: int("input", in: usage),
            cacheWrite: int("write", in: cache),
            cacheRead: int("read", in: cache),
            output: int("output", in: usage),
            reasoning: int("reasoning", in: usage))
    }

    static func cost(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double < 1e12 else { return nil }
        return double
    }

    /// The folder an agent ran in names the project.
    static func project(cwd: String?, root: String?, directory: String?) -> String {
        for candidate in [cwd, root, directory] {
            guard let path = candidate, !path.isEmpty else { continue }
            let name = AgentLogParser.projectName(path)
            if !name.isEmpty { return name }
        }
        return ""
    }

    /// A message row becomes the entries the store applies. User rows open the
    /// next turn (closing a previous one so it reports as finished); assistant
    /// rows carry usage when they have anything to count and always move the
    /// turn's activity forward so the island shows work in progress.
    static func entries(messageID: String, sessionID: String, data: [String: Any],
                        directory: String?, now: Date) -> [AgentLogEntry] {
        guard let role = data["role"] as? String else { return [] }
        let path = data["path"] as? [String: Any]
        let project = project(cwd: path?["cwd"] as? String, root: path?["root"] as? String, directory: directory)
        let time = data["time"] as? [String: Any] ?? [:]
        let created = date(ms: time["created"]) ?? now
        let completed = date(ms: time["completed"])

        if role == "user" {
            // A prompt that follows work ends the previous turn as the whole
            // turn; without a turn open the end is ignored and the start stands.
            return [.turnEnded(created, completed: true, duration: nil), .turnBegan(created)]
        }
        guard role == "assistant" else { return [] }
        var entries: [AgentLogEntry] = []
        let model = AgentLogParser.native((data["modelID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        let messageTokens = tokens(data["tokens"])
        let hasTokens = (messageTokens?.total ?? 0) > 0
        let dbCost = cost(data["cost"])
        if hasTokens, let messageTokens {
            let billable = AgentBillable(tokens: messageTokens)
            // Known families keep the list price the other agents show, so the
            // spend card compares like with like; anything else shows what
            // OpenCode itself recorded.
            let priced: (cost: Double?, savings: Double) = model.isEmpty
                ? (cost: nil, savings: 0) : AgentPricing.cost(billable, model: model)
            let recordCost = priced.cost ?? dbCost
            let key = "opencode:\(messageID)"
            let recordDate = completed ?? created
            entries.append(.usage(key: key, record: AgentUsageRecord(
                provider: .opencode, date: recordDate, model: model, project: project, session: sessionID,
                tokens: messageTokens, cost: recordCost, savings: priced.savings), billable: billable))
        } else if dbCost.map({ $0 > 0 }) == true, let dbCost {
            // A billed reply whose token breakdown is missing still counts.
            let empty = AgentTokens()
            let key = "opencode:\(messageID)"
            entries.append(.usage(key: key, record: AgentUsageRecord(
                provider: .opencode, date: completed ?? created, model: model, project: project,
                session: sessionID, tokens: empty, cost: dbCost, savings: 0),
                                        billable: AgentBillable(tokens: empty)))
        }
        // A placeholder without a completion time is work going on; a completed
        // reply moves the turn forward to its own time.
        entries.append(.turnActive(completed ?? created))
        return entries
    }
}

/// Incremental reads of the OpenCode database. The file is opened read-only so
/// a running OpenCode never waits on the island, and only counters, model
/// names, times and folder names leave a row.
enum AgentOpenCodeReader {
    /// Overlap between polls so rows sharing a millisecond are never missed;
    /// repeats are merged by key when they are applied.
    static let overlap: Int64 = 1_000
    /// History the island can show: thirteen weeks for the activity map.
    private static let horizonDays = 91

    static func horizon(now: Date = Date()) -> Int64 {
        Int64((now.timeIntervalSince1970 - Double(horizonDays) * 86_400) * 1_000)
    }

    /// Messages changed since the cursor, grouped by session in log order so
    /// each session's turns settle on the most recent state. The cursor
    /// advances to what was seen even when nothing applied.
    static func readNew(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        cursor: inout AgentOpenCodeCursor, now: Date = Date()) -> [(sessionID: String, entries: [AgentLogEntry])] {
        let url = AgentOpenCodeDatabase.databaseURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let since: Int64
        if cursor.lastUpdated <= 0 {
            since = horizon(now: now)
        } else {
            since = max(horizon(now: now), cursor.lastUpdated - overlap)
        }
        let rows = fetch(url: url, since: since)
        guard !rows.isEmpty else { return [] }
        var high = cursor.lastUpdated
        for row in rows { high = max(high, row.updated) }
        cursor.lastUpdated = high
        // Global time order keeps interleaved sessions' turns in the sequence
        // the store applies them.
        let ordered = rows.sorted {
            $0.created != $1.created ? $0.created < $1.created : $0.messageID < $1.messageID
        }
        var grouped: [(sessionID: String, entries: [AgentLogEntry])] = []
        grouped.reserveCapacity(ordered.count)
        for row in ordered {
            guard let data = (try? JSONSerialization.jsonObject(with: row.data)) as? [String: Any] else { continue }
            let entries = AgentOpenCodeParser.entries(messageID: row.messageID, sessionID: row.sessionID,
                                                      data: data, directory: row.directory, now: now)
            guard !entries.isEmpty else { continue }
            grouped.append((row.sessionID, entries))
        }
        return grouped
    }

    struct Row {
        let messageID: String
        let sessionID: String
        let created: Int64
        let updated: Int64
        let data: Data
        let directory: String?
    }

    private static func fetch(url: URL, since: Int64) -> [Row] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }
        // A busy writer never blocks a reader long; the next poll retries.
        sqlite3_busy_timeout(db, 500)
        let sql = """
        SELECT m.id, m.session_id, m.time_created, m.time_updated, m.data, s.directory
        FROM message m LEFT JOIN session s ON s.id = m.session_id
        WHERE m.time_updated >= ? ORDER BY m.time_created ASC, m.id ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, since)
        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = sqlite3_column_text(statement, 0).flatMap({ String(cString: $0) }),
                  let sessionID = sqlite3_column_text(statement, 1).flatMap({ String(cString: $0) }),
                  let bytes = sqlite3_column_blob(statement, 4) else { continue }
            let size = Int(sqlite3_column_bytes(statement, 4))
            guard size > 0, size <= AgentLogReader.maximumLine else { continue }
            let data = Data(bytes: bytes, count: size)
            let directory = sqlite3_column_text(statement, 5).flatMap { String(cString: $0) }
            rows.append(Row(messageID: messageID, sessionID: sessionID,
                            created: sqlite3_column_int64(statement, 2),
                            updated: sqlite3_column_int64(statement, 3),
                            data: data, directory: directory))
        }
        return rows
    }
}
