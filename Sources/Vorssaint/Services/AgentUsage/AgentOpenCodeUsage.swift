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
/// immutable except for an assistant reply that gains tokens, a completion
/// time or a final charge, so the high-water mark is the newest
/// `time_updated` seen; a small overlap on every read catches rows that share
/// a millisecond. `applied` remembers which rows already contributed their
/// lifecycle transitions so a reread merges usage without reopening turns.
/// `identity` is the database file itself, so a replaced file starts over
/// instead of staying below an old watermark.
struct AgentOpenCodeCursor {
    var lastUpdated: Int64 = 0
    var applied: [String: Int64] = [:]
    var identity: UInt64 = 0
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
    /// reduce to. `input` already excludes cache traffic, and `output`
    /// already contains the reasoning tokens, the way both logs keep them:
    /// the database bills them separately, so they are added back together.
    static func tokens(_ value: Any?) -> AgentTokens? {
        guard let usage = value as? [String: Any] else { return nil }
        let cache = usage["cache"] as? [String: Any] ?? [:]
        func int(_ key: String, in dict: [String: Any]) -> Int {
            guard let number = dict[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
            let double = number.doubleValue
            guard double.isFinite, double > 0 else { return 0 }
            return Int(min(double, 1e12))
        }
        let output = int("output", in: usage)
        let reasoning = int("reasoning", in: usage)
        return AgentTokens(
            input: int("input", in: usage),
            cacheWrite: int("write", in: cache),
            cacheRead: int("read", in: cache),
            output: min(output + reasoning, 2_000_000_000_000),
            reasoning: reasoning)
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
    /// rows carry usage when they have anything to count. Whether the turn
    /// stays working follows the row's own terminal status: a step that calls
    /// more tools, or a reply with no status yet, keeps it active, while a
    /// final response ends it as finished and an error ends it quietly.
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
            let billable = AgentBillable(tokens: messageTokens, reportedCost: dbCost)
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
                                        billable: AgentBillable(tokens: empty, reportedCost: dbCost)))
        }
        let moment = completed ?? created
        if data["error"] as? [String: Any] != nil {
            // A failed reply ends the turn without a finish notice.
            entries.append(.turnEnded(moment, completed: false, duration: nil))
        } else if let finish = data["finish"] as? String, finish != "tool-calls" {
            // Anything but another tool step is the response the turn worked
            // toward: stopping, hitting a limit, or ending for another reason.
            entries.append(.turnEnded(moment, completed: true, duration: nil))
        } else {
            // A tool step, or a placeholder without a status yet, is work
            // going on; a completed step moves the turn forward to its time.
            entries.append(.turnActive(moment))
        }
        return entries
    }
}

/// Incremental reads of the OpenCode database. The file is opened read-only so
/// a running OpenCode never waits on the island, and only counters, model
/// names, times and folder names leave a row.
enum AgentOpenCodeReader {
    /// Overlap between polls so rows sharing a millisecond are never missed;
    /// repeats merge by key, and rows already applied keep only their usage
    /// so a reread never reopens a turn.
    static let overlap: Int64 = 1_000
    /// History the island can show: thirteen weeks for the activity map.
    private static let horizonDays = 91
    /// Rows read, parsed and applied per page, so stopping the section ends
    /// even a first scan promptly and memory stays bounded.
    static let pageLimit = 1_000

    /// One session's entries with the session whose turn they belong to.
    /// Child sessions of a subagent count toward their root ancestor and
    /// never own a turn of their own.
    struct Batch {
        var sessionID: String
        var rootSessionID: String
        var entries: [AgentLogEntry]
    }

    static func horizon(now: Date = Date()) -> Int64 {
        Int64((now.timeIntervalSince1970 - Double(horizonDays) * 86_400) * 1_000)
    }

    /// The session at the root of `session`'s ancestry, following parent
    /// links; a session whose parent is unknown stays its own root.
    static func root(of session: String, parents: [String: String]) -> String {
        var seen: Set<String> = [session]
        var current = session
        while let parent = parents[current], !parent.isEmpty, !seen.contains(parent) {
            seen.insert(parent)
            current = parent
        }
        return current
    }

    /// Reads what changed since the cursor, handing each session's entries to
    /// `receive` in log order and returning whether the file was replaced or
    /// removed and whether the scan ran to its end. Reading, parsing and
    /// applying proceed in bounded pages keyed by update time, so no page
    /// boundary ever skips a row and stopping the section ends the scan at
    /// the next row or page boundary. Rows whose lifecycle already applied
    /// keep only usage for merging. Stopping polling ends the scan early;
    /// the next start reads from the beginning again.
    @discardableResult
    static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     cursor: inout AgentOpenCodeCursor, now: Date = Date(),
                     shouldContinue: () -> Bool = { true },
                     receive: (Batch) -> Bool) -> (reset: Bool, complete: Bool) {
        let url = AgentOpenCodeDatabase.databaseURL(home: home)
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            // Removed: forget live turns from the old file, keep history.
            let hadState = cursor.lastUpdated > 0 || !cursor.applied.isEmpty || cursor.identity != 0
            cursor = AgentOpenCodeCursor()
            return (reset: hadState, complete: true)
        }
        let identity = UInt64(info.st_ino)
        var reset = false
        if cursor.identity != 0, cursor.identity != identity {
            // Replaced: the old watermark would hide every row of the new
            // file, so start over and drop the old file's live turns.
            cursor = AgentOpenCodeCursor()
            reset = true
        }
        cursor.identity = identity
        let horizon = horizon(now: now)
        cursor.applied = cursor.applied.filter { $0.value >= horizon }
        let floor: Int64
        if cursor.lastUpdated <= 0 {
            floor = horizon
        } else {
            floor = max(horizon, cursor.lastUpdated - overlap)
        }
        var keyUpdated: Int64 = -1
        var keyID = ""
        var high = cursor.lastUpdated
        var complete = false
        while shouldContinue() {
            let fetch = fetchRows(url: url, updatedFloor: floor, afterUpdated: keyUpdated, afterID: keyID,
                                  shouldContinue: shouldContinue)
            if fetch.rows.isEmpty {
                complete = true
                break
            }
            // Time order keeps interleaved sessions' turns in the sequence
            // the store applies them.
            let ordered = fetch.rows.sorted {
                $0.created != $1.created ? $0.created < $1.created : $0.messageID < $1.messageID
            }
            var stopped = false
            for row in ordered {
                guard shouldContinue() else { stopped = true; break }
                guard let data = (try? JSONSerialization.jsonObject(with: row.data)) as? [String: Any] else { continue }
                var entries = AgentOpenCodeParser.entries(messageID: row.messageID, sessionID: row.sessionID,
                                                          data: data, directory: row.directory, now: now)
                if cursor.applied[row.messageID] == row.updated {
                    // Already applied: usage may still need merging when a
                    // charge arrives separately, but lifecycle transitions
                    // fire once.
                    entries = entries.filter { if case .usage = $0 { true } else { false } }
                }
                guard !entries.isEmpty else {
                    if cursor.applied[row.messageID] == nil { cursor.applied[row.messageID] = row.updated }
                    continue
                }
                let batch = Batch(sessionID: row.sessionID,
                                  rootSessionID: root(of: row.sessionID, parents: fetch.parents),
                                  entries: entries)
                guard receive(batch) else { stopped = true; break }
                cursor.applied[row.messageID] = row.updated
                high = max(high, row.updated)
            }
            cursor.lastUpdated = high
            guard !stopped else { break }
            if let last = fetch.rows.max(by: {
                $0.updated != $1.updated ? $0.updated < $1.updated : $0.messageID < $1.messageID
            }) {
                keyUpdated = last.updated
                keyID = last.messageID
            }
            if fetch.rows.count < pageLimit { complete = true; break }
        }
        return (reset: reset, complete: complete)
    }

    struct Row {
        let messageID: String
        let sessionID: String
        let created: Int64
        let updated: Int64
        let data: Data
        let directory: String?
    }

    private struct Fetch {
        var rows: [Row]
        var parents: [String: String]
    }

    private static func fetchRows(url: URL, updatedFloor: Int64, afterUpdated: Int64, afterID: String,
                                  shouldContinue: () -> Bool) -> Fetch {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else { return Fetch(rows: [], parents: [:]) }
        defer { sqlite3_close(db) }
        // A busy writer never blocks a reader long; the next poll retries.
        sqlite3_busy_timeout(db, 500)
        var parents: [String: String] = [:]
        if let sessions = prepare(db, sql: "SELECT id, parent_id FROM session") {
            defer { sqlite3_finalize(sessions) }
            var checks = 0
            while sqlite3_step(sessions) == SQLITE_ROW {
                checks += 1
                if checks % 64 == 0, !shouldContinue() { break }
                guard let id = text(sessions, 0) else { continue }
                parents[id] = text(sessions, 1) ?? ""
            }
        }
        guard shouldContinue() else { return Fetch(rows: [], parents: parents) }
        guard let query = prepare(db, sql: """
            SELECT m.id, m.session_id, m.time_created, m.time_updated, m.data, s.directory
            FROM message m LEFT JOIN session s ON s.id = m.session_id
            WHERE m.time_updated >= ? AND (m.time_updated > ? OR (m.time_updated = ? AND m.id > ?))
            ORDER BY m.time_updated ASC, m.id ASC LIMIT \(pageLimit)
            """) else { return Fetch(rows: [], parents: parents) }
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, updatedFloor)
        sqlite3_bind_int64(query, 2, afterUpdated)
        sqlite3_bind_int64(query, 3, afterUpdated)
        // A copy: the bridged string's bytes only live for the bind call.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(query, 4, (afterID as NSString).utf8String, -1, transient)
        var rows: [Row] = []
        rows.reserveCapacity(min(pageLimit, 256))
        var checks = 0
        while sqlite3_step(query) == SQLITE_ROW {
            checks += 1
            if checks % 32 == 0, !shouldContinue() { break }
            guard rows.count < pageLimit,
                  let messageID = text(query, 0), let sessionID = text(query, 1),
                  let bytes = sqlite3_column_blob(query, 4) else { continue }
            let size = Int(sqlite3_column_bytes(query, 4))
            guard size > 0, size <= AgentLogReader.maximumLine else { continue }
            rows.append(Row(messageID: messageID, sessionID: sessionID,
                            created: sqlite3_column_int64(query, 2),
                            updated: sqlite3_column_int64(query, 3),
                            data: Data(bytes: bytes, count: size),
                            directory: text(query, 5)))
        }
        return Fetch(rows: rows, parents: parents)
    }

    private static func prepare(_ db: OpaquePointer, sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        return statement
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).flatMap { String(cString: $0) }
    }
}
