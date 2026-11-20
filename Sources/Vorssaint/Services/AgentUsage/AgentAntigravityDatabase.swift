// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import SQLite3

/// Reads Antigravity workspace metadata strictly read-only so sessions show
/// their repository name without decoding conversation titles or prompts.
enum AgentAntigravityDatabase {
    static let database = "conversation_summaries.db"

    private struct Snapshot {
        let modified: Date
        let projects: [String: String]
    }

    private static let lock = NSLock()
    private static var cache: [String: Snapshot] = [:]

    /// Extracts `<conversation_id>` from
    /// `<app_data_dir>/brain/<conversation_id>/.system_generated/logs/transcript.jsonl`.
    static func conversationID(from transcriptPath: String) -> String? {
        let url = URL(fileURLWithPath: transcriptPath)
        let logs = url.deletingLastPathComponent()
        guard url.lastPathComponent == "transcript.jsonl", logs.lastPathComponent == "logs" else { return nil }
        let systemGenerated = logs.deletingLastPathComponent()
        guard systemGenerated.lastPathComponent == ".system_generated" else { return nil }
        let session = systemGenerated.deletingLastPathComponent().lastPathComponent
        return session.isEmpty ? nil : session
    }

    /// Derives `<app_data_dir>/conversation_summaries.db` beside `brain/`.
    static func databasePath(near transcriptPath: String) -> String? {
        let url = URL(fileURLWithPath: transcriptPath)
        let brain = url
            .deletingLastPathComponent() // logs
            .deletingLastPathComponent() // .system_generated
            .deletingLastPathComponent() // <conversation_id>
            .deletingLastPathComponent() // brain
        guard brain.lastPathComponent == "brain" else { return nil }
        return brain.deletingLastPathComponent().appending(path: database).path
    }

    static func projectName(for conversationID: String, near transcriptPath: String) -> String? {
        guard !conversationID.isEmpty, let dbPath = databasePath(near: transcriptPath) else { return nil }
        return projectName(for: conversationID, databasePath: dbPath)
    }

    static func projectName(for conversationID: String, databasePath dbPath: String) -> String? {
        guard !conversationID.isEmpty, let currentModified = modified(dbPath) else { return nil }
        if let cached = lock.withLock({ cache[dbPath] }), cached.modified == currentModified {
            return cached.projects[conversationID]
        }
        guard let loaded = loadProjects(at: dbPath) else { return nil }
        lock.withLock {
            cache[dbPath] = Snapshot(modified: currentModified, projects: loaded)
        }
        return loaded[conversationID]
    }

    /// Combines the main database file and `-wal` modification times, returning
    /// nil when the main database does not exist.
    static func modified(_ path: String) -> Date? {
        guard let main = fileModified(path) else { return nil }
        if let wal = fileModified(path + "-wal"), wal > main { return wal }
        return main
    }

    private static func fileModified(_ path: String) -> Date? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
            + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    private static func loadProjects(at dbPath: String) -> [String: String]? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)

        let sql = "SELECT conversation_id, workspace_uris FROM conversation_summaries WHERE workspace_uris IS NOT NULL"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var projects: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0),
                  let urisC = sqlite3_column_text(stmt, 1) else { continue }
            let conversationID = String(cString: idC)
            let urisRaw = String(cString: urisC)
            if let project = projectName(fromWorkspaceURIsJSON: urisRaw), !project.isEmpty {
                projects[conversationID] = project
            }
        }
        return projects
    }

    static func projectName(fromWorkspaceURIsJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [String],
              let first = array.first, !first.isEmpty else { return nil }
        let path: String
        if let url = URL(string: first), url.isFileURL {
            path = url.path
        } else {
            path = first
        }
        let name = AgentLogParser.projectName(path)
        return name.isEmpty ? nil : name
    }
}
