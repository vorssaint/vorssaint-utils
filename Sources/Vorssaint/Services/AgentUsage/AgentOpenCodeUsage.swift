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

/// How far into the OpenCode database reading has got. Rows are found by
/// rowid: new rows keep arriving past the highest one seen, while replies
/// still in progress are looked up by id until they end. `applied`
/// remembers which rows already contributed their usage and lifecycle so a
/// reread merges without refiring. `ended` remembers which replies already
/// ended their turn, since a later charge can update the same row again.
/// `replied` and `active` remember per session the newest reply and the
/// newest activity applied, so a rewritten prompt never reopens a turn and
/// a prompt after long silence quietly closes the stale one first.
/// `identity` is the database file itself, so a replaced file starts over
/// instead of staying below an old watermark. `parents` caches session
/// ancestry, which never changes once written. `fileState` describes the
/// database and its journal the last time they were fully read, so an
/// unchanged poll skips the database entirely.
struct AgentOpenCodeCursor {
    var maxRowid: Int64 = 0
    var open: Set<String> = []
    var applied: [String: Int64] = [:]
    var ended: [String: Int64] = [:]
    var replied: [String: Int64] = [:]
    var active: [String: Int64] = [:]
    var parents: [String: String] = [:]
    var identity: UInt64 = 0
    var fileState: String = ""
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

    /// A message row becomes the entries the store applies. User rows only
    /// ever mark activity: the reader decides whether the turn keeps going
    /// or the stale one closes quietly first, so a rewritten prompt can
    /// never reopen a turn or replay a notice. Assistant rows carry usage
    /// when they have anything to count. Whether the turn stays working
    /// follows the row's own terminal status: a step that calls more tools,
    /// a step with an unknown finish, a compaction reply, or a reply with no
    /// status yet keeps it active, while a final response ends it as
    /// finished, a completed reply with no finish ends it as finished, and
    /// an error ends it quietly. A stop on a step that still calls tools
    /// stays terminal: it is the documented final status, and the part
    /// table that would tell them apart is never read.
    static func entries(messageID: String, sessionID: String, data: [String: Any],
                        directory: String?, now: Date) -> [AgentLogEntry] {
        guard let role = data["role"] as? String else { return [] }
        let path = data["path"] as? [String: Any]
        let project = project(cwd: path?["cwd"] as? String, root: path?["root"] as? String, directory: directory)
        let time = data["time"] as? [String: Any] ?? [:]
        let created = date(ms: time["created"]) ?? now
        let completed = date(ms: time["completed"])

        if role == "user" {
            return [.turnActive(created)]
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
        if data["error"] as? [String: Any] != nil || (data["finish"] as? String) == "content-filter" {
            // A failed reply ends the turn without a finish notice. OpenCode
            // itself turns a content filter finish into an error that breaks
            // the loop, so a refusal ends quietly too.
            entries.append(.turnEnded(moment, completed: false, duration: nil))
        } else if isCompaction(data) || finishKeepsWorking(data["finish"], completed: completed) {
            // A compaction reply summarizes context while the task goes on,
            // and these finishes all mean more work is coming: another tool
            // step, an undecided one, or a reply with no status yet.
            entries.append(.turnActive(moment))
        } else {
            // A final response, or a completed reply the loop stopped after,
            // ends the turn as finished.
            entries.append(.turnEnded(moment, completed: true, duration: nil))
        }
        return entries
    }

    /// A context compaction reply, marked as a summary of the task so far.
    /// It carries real token spend but the task goes on after it.
    static func isCompaction(_ data: [String: Any]) -> Bool {
        (data["mode"] as? String) == "compaction" || (data["agent"] as? String) == "compaction"
            || (data["summary"] as? Bool) == true
    }

    /// Finishes that keep the turn working: another tool step, an undecided
    /// one, or a missing one on a reply that has not completed. A completed
    /// reply without a finish means the loop stopped after it.
    static func finishKeepsWorking(_ finish: Any?, completed: Date?) -> Bool {
        guard let finish = finish as? String else { return completed == nil }
        return finish == "tool-calls" || finish == "unknown"
    }
}

/// Incremental reads of the OpenCode database. The file is opened read-only so
/// a running OpenCode never waits on the island, and only counters, model
/// names, times and folder names leave a row.
enum AgentOpenCodeReader {
    /// History the island can show: thirteen weeks for the activity map.
    private static let horizonDays = 91
    /// A prompt after this much silence closes the stale turn quietly
    /// instead of joining it, matching how long a quiet turn shows working.
    private static let quietAfter = Int64(NotchAgentSupport.idleTurn * 1_000)

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

    /// Reads what changed since the cursor, handing each new or updated
    /// row's entries to `receive` in log order. Polls skip the database
    /// entirely while its file and journal are unchanged. New rows are found
    /// past the highest rowid seen, and replies still in progress are looked
    /// up by id until they end, so each poll touches only what changed
    /// instead of scanning the whole history. Rows already applied are
    /// skipped before their payload is decoded. The single scan applies each
    /// row as it is stepped, so memory stays bounded and stopping the
    /// section ends the scan at the next row. Returns whether the file was
    /// replaced or removed, whether the scan ran to its end, and whether
    /// anything new was handed over. The watermark and the saved file state
    /// advance only on a clean run to the end. Stopping polling ends the
    /// scan early; the next start reads from the beginning again.
    @discardableResult
    static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     cursor: inout AgentOpenCodeCursor, now: Date = Date(),
                     shouldContinue: () -> Bool = { true },
                     receive: (Batch) -> Bool) -> (reset: Bool, complete: Bool, changed: Bool) {
        let url = AgentOpenCodeDatabase.databaseURL(home: home)
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            // Removed: forget live turns from the old file, keep history.
            let hadState = cursor.maxRowid > 0 || !cursor.applied.isEmpty || cursor.identity != 0
            cursor = AgentOpenCodeCursor()
            return (reset: hadState, complete: true, changed: false)
        }
        let identity = UInt64(info.st_ino)
        var reset = false
        if cursor.identity != 0, cursor.identity != identity {
            // Replaced: old watermarks would hide every row of the new
            // file, so start over and drop the old file's live turns.
            cursor = AgentOpenCodeCursor()
            reset = true
        }
        cursor.identity = identity
        // Unchanged files need no query at all: the journal carries every
        // write, so matching sizes and times mean nothing new arrived.
        // The state below is the one taken before the query, so a write
        // that lands mid scan is picked up by the next poll instead of
        // being baked into a state its rows missed.
        let preState = fileState(url: url, info: info)
        if !reset, cursor.fileState == preState {
            return (reset: false, complete: true, changed: false)
        }
        let horizon = horizon(now: now)
        cursor.applied = cursor.applied.filter { $0.value >= horizon }
        cursor.ended = cursor.ended.filter { cursor.applied[$0.key] != nil }
        cursor.replied = cursor.replied.filter { $0.value >= horizon }
        cursor.active = cursor.active.filter { $0.value >= horizon }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            return (reset: reset, complete: true, changed: false)
        }
        defer { sqlite3_close(db) }
        // A busy writer never blocks a reader long; the next poll retries.
        sqlite3_busy_timeout(db, 500)
        var changed = false
        var maxRowid = cursor.maxRowid
        var complete = false
        if cursor.maxRowid <= 0 {
            // First read: one scan of the history in log order, so
            // interleaved sessions' turns settle in the sequence the store
            // applies them. Rows older than the horizon still move the
            // watermark past them.
            let done = scan(db: db, sql: """
                SELECT m.rowid, m.id, m.session_id, m.time_created, m.time_updated, m.data,
                       s.directory, s.time_created, s.parent_id
                FROM message m LEFT JOIN session s ON s.id = m.session_id
                ORDER BY m.time_created ASC, m.id ASC
                """, bind: [], cursor: &cursor, now: now, horizon: horizon,
                shouldContinue: shouldContinue, receive: receive, maxRowid: &maxRowid)
            complete = done.complete
            changed = done.changed
        } else {
            // Later polls touch only what changed: rows past the watermark
            // in log order, then replies still in progress by id.
            let open = cursor.open.sorted()
            if !open.isEmpty, shouldContinue() {
                let marks = open.map { _ in "?" }.joined(separator: ",")
                let done = scan(db: db, sql: """
                    SELECT m.rowid, m.id, m.session_id, m.time_created, m.time_updated, m.data,
                           s.directory, s.time_created, s.parent_id
                    FROM message m LEFT JOIN session s ON s.id = m.session_id
                    WHERE m.id IN (\(marks)) ORDER BY m.time_created ASC, m.id ASC
                    """, bind: open, cursor: &cursor, now: now, horizon: horizon,
                    shouldContinue: shouldContinue, receive: receive, maxRowid: &maxRowid)
                complete = done.complete
                changed = done.changed
                if !complete { return finish(reset: reset, cursor: &cursor, url: url, changed: changed) }
            }
            if shouldContinue() {
                let done = scan(db: db, sql: """
                    SELECT m.rowid, m.id, m.session_id, m.time_created, m.time_updated, m.data,
                           s.directory, s.time_created, s.parent_id
                    FROM message m LEFT JOIN session s ON s.id = m.session_id
                    WHERE m.rowid > \(maxRowid) ORDER BY m.time_created ASC, m.id ASC
                    """, bind: [], cursor: &cursor, now: now, horizon: horizon,
                    shouldContinue: shouldContinue, receive: receive, maxRowid: &maxRowid)
                complete = done.complete
                changed = changed || done.changed
            }
        }
        return finish(reset: reset, cursor: &cursor, url: url, changed: changed, complete: complete,
                      maxRowid: maxRowid, preState: preState)
    }

    /// Stores the watermark and the pre query file state after a clean run
    /// to the end. Anything earlier keeps the old ones, so the next poll
    /// replays what the stopped scan missed.
    private static func finish(reset: Bool, cursor: inout AgentOpenCodeCursor, url: URL, changed: Bool,
                               complete: Bool = true, maxRowid: Int64? = nil,
                               preState: String? = nil) -> (reset: Bool, complete: Bool, changed: Bool) {
        if complete {
            if let maxRowid { cursor.maxRowid = max(maxRowid, cursor.maxRowid) }
            if let preState { cursor.fileState = preState }
        }
        return (reset: reset, complete: complete, changed: changed)
    }

    /// Steps one statement, handing each new or updated row to the same
    /// treatment: rows already applied never decode again, forked copies
    /// never apply at all, and everything else goes through the lifecycle
    /// gates before `receive` sees it. Returns whether the statement ran to
    /// its end. Watermark, maps and file state stay untouched here; the
    /// caller advances them only on a clean run.
    private static func scan(db: OpaquePointer, sql: String, bind: [String],
                             cursor: inout AgentOpenCodeCursor, now: Date, horizon: Int64,
                             shouldContinue: () -> Bool, receive: (Batch) -> Bool,
                             maxRowid: inout Int64) -> (complete: Bool, changed: Bool) {
        guard let query = prepare(db, sql: sql) else { return (true, false) }
        defer { sqlite3_finalize(query) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in bind.enumerated() {
            sqlite3_bind_text(query, Int32(offset + 1), (value as NSString).utf8String, -1, transient)
        }
        var checks = 0
        var changed = false
        while sqlite3_step(query) == SQLITE_ROW {
            checks += 1
            if checks % 32 == 0, !shouldContinue() { return (false, changed) }
            guard let rowid = columnInt64(query, 0), let messageID = text(query, 1),
                  let sessionID = text(query, 2) else { continue }
            let created = columnInt64(query, 3) ?? 0
            let updated = columnInt64(query, 4) ?? 0
            maxRowid = max(maxRowid, rowid)
            // Rows older than the horizon only move the watermark past them.
            // Already applied rows never decode again: the same update time
            // means the same bytes.
            guard created >= horizon else {
                cursor.applied[messageID] = updated
                continue
            }
            guard cursor.applied[messageID] != updated else { continue }
            guard let bytes = sqlite3_column_blob(query, 5) else { continue }
            let size = Int(sqlite3_column_bytes(query, 5))
            guard size > 0, size <= AgentLogReader.maximumLine else {
                cursor.applied[messageID] = updated
                continue
            }
            let data = Data(bytes: bytes, count: size)
            guard shouldContinue() else { return (false, changed) }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                cursor.applied[messageID] = updated
                continue
            }
            // A forked session copies every message of its source under new
            // ids while each copy keeps its old creation time, cost and
            // tokens. Rows born long before their own session are those
            // copies: counting them would add the same usage twice and
            // could replay a finished notice, so they never apply.
            if let born = columnInt64(query, 7), created + forkTolerance < born {
                cursor.applied[messageID] = updated
                continue
            }
            let directory = text(query, 6)
            let isUser = (json["role"] as? String) == "user"
            guard let gated = gatedEntries(messageID: messageID, sessionID: sessionID, created: created,
                                           data: json, directory: directory, cursor: &cursor, now: now),
                  !gated.entries.isEmpty else {
                cursor.applied[messageID] = updated
                continue
            }
            cursor.parents[sessionID] = text(query, 8) ?? ""
            let batch = Batch(sessionID: sessionID,
                              rootSessionID: root(of: sessionID, parents: &cursor.parents, db: db),
                              entries: gated.entries)
            guard receive(batch) else { return (false, changed) }
            noteApplied(messageID: messageID, sessionID: sessionID, created: created, updated: updated,
                        isUser: isUser, terminal: gated.terminal, entries: gated.entries, cursor: &cursor)
            changed = true
        }
        return (checks % 32 != 0 || shouldContinue(), changed)
    }

    /// A forked copy is born long before its own session. No genuine row
    /// predates its session by anything like this margin: measured across
    /// thousands of live rows, the earliest message follows its session by
    /// milliseconds.
    private static let forkTolerance: Int64 = 60_000

    private static func columnInt64(_ statement: OpaquePointer, _ column: Int32) -> Int64? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, column)
    }

    /// What the database and its journal looked like: matching sizes and
    /// times mean no write landed since the last read, since the journal
    /// carries every write. Missing files read as their absence.
    private static func fileState(url: URL, info: stat) -> String {
        var wal = stat()
        let journal: String
        if stat(url.path + "-wal", &wal) == 0 {
            journal = "\(wal.st_size):\(wal.st_mtimespec.tv_sec):\(wal.st_mtimespec.tv_nsec)"
        } else {
            journal = "absent"
        }
        return "\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)|\(journal)"
    }

    /// The session at the root of `session`'s ancestry, following parent
    /// links and asking the database about ancestors the cache has not
    /// seen; a session whose parent stays unknown is its own root.
    /// Ancestry never changes once written, so cached links never go stale.
    private static func root(of session: String, parents: inout [String: String], db: OpaquePointer) -> String {
        var seen: Set<String> = [session]
        var current = session
        var hops = 0
        while hops < 8 {
            // A cached empty parent is a known root, not a missing entry:
            // only a truly unknown session asks the database again.
            if let known = parents[current] {
                if known.isEmpty { break }
                if seen.contains(known) { break }
                seen.insert(known)
                current = known
            } else if let fresh = parentOf(db: db, session: current) {
                parents[current] = fresh
                if fresh.isEmpty { break }
                if seen.contains(fresh) { break }
                seen.insert(fresh)
                current = fresh
            } else {
                break
            }
            hops += 1
        }
        return current
    }

    /// One session's parent, asked of the database only when the cache has
    /// not seen it. Ancestry never changes once written.
    private static func parentOf(db: OpaquePointer, session: String) -> String? {
        guard let query = prepare(db, sql: "SELECT parent_id FROM session WHERE id = ? LIMIT 1") else { return nil }
        defer { sqlite3_finalize(query) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(query, 1, (session as NSString).utf8String, -1, transient)
        guard sqlite3_step(query) == SQLITE_ROW else { return nil }
        return text(query, 0) ?? ""
    }

    /// Entries for a new or updated row, with whether they end the turn.
    /// Prompts older than a reply the session already applied are rewrites
    /// and never apply; a prompt that follows recent activity keeps the turn
    /// going, while one after long silence quietly closes the stale turn
    /// first and opens a fresh one. Assistant lifecycle transitions fire
    /// once per row; usage always applies so growing tokens and late
    /// charges merge.
    private static func gatedEntries(messageID: String, sessionID: String, created: Int64,
                                     data: [String: Any], directory: String?, cursor: inout AgentOpenCodeCursor,
                                     now: Date) -> (entries: [AgentLogEntry], terminal: Bool)? {
        var entries = AgentOpenCodeParser.entries(messageID: messageID, sessionID: sessionID,
                                                  data: data, directory: directory, now: now)
        let isUser = (data["role"] as? String) == "user"
        if isUser {
            if let replied = cursor.replied[sessionID], replied > created {
                return nil
            }
            if let last = cursor.active[sessionID], created - last < quietAfter {
                return (entries, false)
            }
            let closed: [AgentLogEntry]
            if let last = cursor.active[sessionID], last > 0 {
                closed = [.turnEnded(Date(timeIntervalSince1970: Double(last) / 1_000), completed: false, duration: nil)]
            } else {
                closed = []
            }
            return (closed + entries, false)
        }
        let terminal = entries.contains {
            if case .turnEnded = $0 { true } else { false }
        }
        if cursor.ended[messageID] != nil {
            entries = entries.filter {
                if case .turnEnded = $0 { false } else { true }
            }
        }
        return (entries, terminal)
    }

    /// Remembers a received row: usage merges on its next update while its
    /// lifecycle never refires, replies still in progress stay watched
    /// until they end, and the session maps place later prompts.
    private static func noteApplied(messageID: String, sessionID: String, created: Int64, updated: Int64,
                                    isUser: Bool, terminal: Bool, entries: [AgentLogEntry],
                                    cursor: inout AgentOpenCodeCursor) {
        cursor.applied[messageID] = updated
        var moment = created
        for entry in entries {
            switch entry {
            case .usage(_, let record, _):
                moment = max(moment, AgentOpenCodeParser.millis(record.date))
            case .turnEnded(let date, _, _):
                if let date { moment = max(moment, AgentOpenCodeParser.millis(date)) }
                cursor.ended[messageID] = updated
            case .turnActive(let date):
                if let date { moment = max(moment, AgentOpenCodeParser.millis(date)) }
            default:
                break
            }
        }
        cursor.active[sessionID] = max(cursor.active[sessionID] ?? 0, moment)
        if !isUser {
            cursor.replied[sessionID] = max(cursor.replied[sessionID] ?? 0, created)
            if terminal {
                cursor.open.remove(messageID)
            } else {
                cursor.open.insert(messageID)
            }
        }
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
