// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// What the AI page's Kilo Code card shows for the chosen period.
struct AgentKiloSummary: Equatable {
    /// The Kilo CLI or its data folder is on this Mac.
    var installed = false
    /// Signed in to a Kilo account. Read from whether an active account is
    /// recorded, never from the account's tokens.
    var signedIn = false
    /// Top-level sessions that were active in the period; subagents' own
    /// sessions add their cost and tokens but are not counted again.
    var sessions = 0
    var tokens = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    /// Messages sent, and the agent's replies and tool steps, in the period.
    var prompts = 0
    var steps = 0
    var linesAdded = 0
    var linesRemoved = 0

    /// The share of input served from cache, 0 to 1; nil before anything was read.
    var cacheShare: Double? {
        let read = input + cacheRead
        return read > 0 ? Double(cacheRead) / Double(read) : nil
    }
    /// The model of the session used most recently in the period.
    var model: String?
    var lastUsed: Date?
}

/// Reads Kilo Code's CLI database (~/.local/share/kilo/kilo.db), read-only.
/// Kilo keeps each session's running totals on its row, so only the
/// session table's totals and the account state are read: no prompt, reply,
/// title, path or credential ever leaves the database.
enum AgentKiloReader {
    static func dataFolder(home: URL) -> URL { home.appending(path: ".local/share/kilo", directoryHint: .isDirectory) }
    static func database(home: URL) -> URL { dataFolder(home: home).appending(path: "kilo.db") }
    static func cli(home: URL) -> URL { home.appending(path: ".kilo/bin/kilo") }

    static func isInstalled(home: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: cli(home: home).path)
            || FileManager.default.fileExists(atPath: database(home: home).path)
    }

    /// When the database or its write-ahead log last changed; nil without one.
    static func modified(home: URL) -> Date? {
        let path = database(home: home).path
        func date(_ path: String) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        }
        guard let base = date(path) else { return nil }
        return max(base, date(path + "-wal") ?? .distantPast)
    }

    /// The start of a period that ends today: today alone, or the last 7 or 30 days.
    static func start(of period: AgentPeriod, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1 - period.days, to: today) ?? today
    }

    static func read(home: URL, since: Date) -> AgentKiloSummary {
        var summary = AgentKiloSummary(installed: isInstalled(home: home))
        let path = database(home: home).path
        guard FileManager.default.fileExists(atPath: path) else { return summary }
        var db: OpaquePointer?
        // SQLite hands back a connection to close even when opening fails.
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return summary }
        sqlite3_busy_timeout(db, 2000)
        summary.installed = true

        if table("account_state", in: db) {
            summary.signedIn = exists("SELECT 1 FROM account_state WHERE active_account_id IS NOT NULL", in: db)
        }
        if !summary.signedIn, table("control_account", in: db) {
            summary.signedIn = exists("SELECT 1 FROM control_account WHERE active = 1", in: db)
        }
        guard table("session", in: db) else { return summary }

        // Kilo stores times in milliseconds.
        let from = Int64((since.timeIntervalSince1970 * 1000).rounded(.down))
        let totals = """
            SELECT count(CASE WHEN parent_id IS NULL THEN 1 END),
                   total(tokens_input + tokens_output + tokens_reasoning + tokens_cache_read + tokens_cache_write),
                   max(time_updated), total(tokens_input), total(tokens_output + tokens_reasoning), total(tokens_cache_read)
            FROM session WHERE time_updated >= ?
            """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, totals, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, from)
            if sqlite3_step(stmt) == SQLITE_ROW {
                summary.sessions = Int(sqlite3_column_int64(stmt, 0))
                summary.tokens = count(stmt, 1)
                if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                    summary.lastUsed = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)) / 1000)
                }
                summary.input = count(stmt, 3)
                summary.output = count(stmt, 4)
                summary.cacheRead = count(stmt, 5)
            }
        }
        sqlite3_finalize(stmt)

        stmt = nil
        let latest = "SELECT model FROM session WHERE time_updated >= ? AND model IS NOT NULL AND model <> '' ORDER BY time_updated DESC LIMIT 1"
        if sqlite3_prepare_v2(db, latest, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, from)
            if sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) {
                summary.model = modelName(String(cString: text))
            }
        }
        sqlite3_finalize(stmt)

        // Lines changed, where this Kilo records them on the session.
        stmt = nil
        let lines = "SELECT total(summary_additions), total(summary_deletions) FROM session WHERE time_updated >= ?"
        if sqlite3_prepare_v2(db, lines, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, from)
            if sqlite3_step(stmt) == SQLITE_ROW {
                summary.linesAdded = count(stmt, 0)
                summary.linesRemoved = count(stmt, 1)
            }
        }
        sqlite3_finalize(stmt)

        // Only each message's role is read, never its text.
        if table("message", in: db) {
            stmt = nil
            let roles = """
                SELECT count(CASE WHEN json_extract(data, '$.role') = 'user' THEN 1 END),
                       count(CASE WHEN json_extract(data, '$.role') = 'assistant' THEN 1 END)
                FROM message WHERE time_created >= ?
                """
            if sqlite3_prepare_v2(db, roles, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, from)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    summary.prompts = count(stmt, 0)
                    summary.steps = count(stmt, 1)
                }
            }
            sqlite3_finalize(stmt)
        }
        return summary
    }

    /// Kilo's use for each of the last `AgentUsageSnapshot.dayCount` days and for each
    /// hour of today, shaped like the other agents' history so the AI page can chart
    /// it the same way. Kilo does not report a price, so every bucket is partial and
    /// the page falls back to tokens. Buckets sit under `.opencode`, the agent Kilo
    /// is built on; the page recolours them.
    static func series(home: URL, now: Date, calendar: Calendar = .current) -> (days: [AgentBucket], hours: [AgentBucket]) {
        let today = calendar.startOfDay(for: now)
        let dayStarts = (0..<AgentUsageSnapshot.dayCount).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        let hourStarts = (0...max(0, calendar.component(.hour, from: now))).compactMap {
            calendar.date(byAdding: .hour, value: $0, to: today)
        }
        let empty = (days: dayStarts.map { AgentBucket(start: $0) }, hours: hourStarts.map { AgentBucket(start: $0) })
        let path = database(home: home).path
        guard FileManager.default.fileExists(atPath: path) else { return empty }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              table("session", in: db) else { return empty }
        sqlite3_busy_timeout(db, 2000)

        func totals(_ format: String, since: Date) -> [String: AgentTotals] {
            let sql = """
                SELECT strftime('\(format)', time_updated / 1000, 'unixepoch', 'localtime'),
                       count(CASE WHEN parent_id IS NULL THEN 1 END),
                       total(tokens_input), total(tokens_output + tokens_reasoning),
                       total(tokens_cache_read), total(tokens_cache_write)
                FROM session WHERE time_updated >= ? GROUP BY 1
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
            sqlite3_bind_int64(stmt, 1, Int64((since.timeIntervalSince1970 * 1000).rounded(.down)))
            var found: [String: AgentTotals] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let key = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) else { continue }
                var total = AgentTotals()
                total.requests = Int(sqlite3_column_int64(stmt, 1))
                total.tokens = AgentTokens(input: count(stmt, 2), cacheWrite: count(stmt, 5),
                                           cacheRead: count(stmt, 4), output: count(stmt, 3))
                total.unpriced = total.tokens.total > 0 ? 1 : 0
                found[key] = total
            }
            return found
        }

        func key(_ date: Date, _ format: String) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter.string(from: date)
        }

        let perDay = totals("%Y-%m-%d", since: dayStarts.first ?? today)
        let perHour = totals("%Y-%m-%d %H", since: today)
        return (dayStarts.map { start in
            var bucket = AgentBucket(start: start)
            if let found = perDay[key(start, "yyyy-MM-dd")] { bucket.byProvider[.opencode] = found }
            return bucket
        }, hourStarts.map { start in
            var bucket = AgentBucket(start: start)
            if let found = perHour[key(start, "yyyy-MM-dd HH")] { bucket.byProvider[.opencode] = found }
            return bucket
        })
    }

    private static func count(_ stmt: OpaquePointer?, _ column: Int32) -> Int {
        let value = sqlite3_column_double(stmt, column)
        return value.isFinite && value > 0 ? Int(value) : 0
    }

    /// Kilo records a model as JSON (`{"providerID":…,"modelID":…}`) or as
    /// `provider/model`; the card shows the model's own name.
    static func modelName(_ stored: String) -> String? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let id = (object["modelID"] ?? object["id"] ?? object["model"]) as? String
            return id.flatMap { $0.isEmpty ? nil : $0 }
        }
        let name = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return name.isEmpty ? nil : name
    }

    private static func table(_ name: String, in db: OpaquePointer?) -> Bool {
        exists("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(name)'", in: db)
    }

    private static func exists(_ sql: String, in db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        return sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK && sqlite3_step(stmt) == SQLITE_ROW
    }
}
