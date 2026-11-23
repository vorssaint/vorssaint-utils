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
    var cost = 0.0
    var tokens = 0
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
            SELECT count(CASE WHEN parent_id IS NULL THEN 1 END), total(cost),
                   total(tokens_input + tokens_output + tokens_reasoning + tokens_cache_read + tokens_cache_write),
                   max(time_updated)
            FROM session WHERE time_updated >= ?
            """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, totals, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, from)
            if sqlite3_step(stmt) == SQLITE_ROW {
                summary.sessions = Int(sqlite3_column_int64(stmt, 0))
                let cost = sqlite3_column_double(stmt, 1)
                summary.cost = cost.isFinite && cost > 0 ? cost : 0
                summary.tokens = max(0, Int(sqlite3_column_double(stmt, 2)))
                if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                    summary.lastUsed = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)) / 1000)
                }
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
        return summary
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
