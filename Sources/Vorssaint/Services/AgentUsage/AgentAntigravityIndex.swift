// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// agy keeps a small index of its conversations, `conversation_summaries.db`
/// beside `brain/`. It names the workspace folder each conversation was opened
/// in, which agy 1.5 no longer writes into the transcript. Only that folder's
/// name is read, the way the other agents' project labels are.
enum AgentAntigravityIndex {
    /// Size and modification time of the database and of its write-ahead log.
    private struct Stamp: Equatable {
        let database: [Int64]
        let log: [Int64]
    }

    private static let lock = NSLock()
    private static var cache: [String: (stamp: Stamp, projects: [String: String])] = [:]
    private static let databaseName = "conversation_summaries.db"
    private static let maximumRows = 50_000

    /// The workspace folder's name for the conversation a `transcript.jsonl`
    /// belongs to, or nil when agy has no index beside its `brain` folder or
    /// the conversation is not in it yet.
    static func project(forTranscript path: String) -> String? {
        guard let session = AgentLogCursor.antigravitySession(of: path) else { return nil }
        // <root>/brain/<session>/.system_generated/logs/transcript.jsonl
        let brain = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard brain.lastPathComponent == "brain" else { return nil }
        let database = brain.deletingLastPathComponent().appending(path: databaseName, directoryHint: .notDirectory)
        return projects(in: database)[session]
    }

    /// Every conversation's workspace folder name, by conversation id. Read
    /// again only when the database or its write-ahead log changed.
    static func projects(in database: URL) -> [String: String] {
        let path = database.path
        guard let stamp = stamp(of: path) else { return [:] }
        if let cached = lock.withLock({ cache[path] }), cached.stamp == stamp { return cached.projects }
        // A failed read is not kept: the stamp may never change again while
        // agy is not running, and the next pass should try the database anew.
        guard let projects = read(path) else { return [:] }
        lock.withLock { cache[path] = (stamp, projects) }
        return projects
    }

    /// The folder name of the first workspace in agy's `["file:///…"]` list.
    static func project(fromWorkspaceURIs text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return nil }
        for uri in list {
            guard let url = URL(string: uri), url.isFileURL else { continue }
            let name = AgentLogParser.projectName(url.path)
            if !name.isEmpty, name != "/" { return name }
        }
        return nil
    }

    private static func stamp(of path: String) -> Stamp? {
        func fingerprint(_ file: String) -> [Int64]? {
            var info = stat()
            guard stat(file, &info) == 0 else { return nil }
            return [Int64(info.st_size), Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec)]
        }
        guard let database = fingerprint(path) else { return nil }
        return Stamp(database: database, log: fingerprint(path + "-wal") ?? [])
    }

    /// Nil when the database could not be opened or read to its end.
    private static func read(_ path: String) -> [String: String]? {
        var db: OpaquePointer?
        // SQLite hands back a connection to close even when opening fails.
        defer { sqlite3_close(db) }
        // While agy runs, its newest rows are in the write-ahead log, which a
        // read-only connection reads through the `-shm` file beside it. agy
        // removes both when it exits and leaves the database in WAL mode,
        // which a read-only connection does not open without its log, so the
        // plain file, which then holds everything, is opened as immutable.
        let running = FileManager.default.fileExists(atPath: path + "-wal")
        let location = running ? path : URL(fileURLWithPath: path).absoluteString + "?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | (running ? 0 : SQLITE_OPEN_URI)
        guard sqlite3_open_v2(location, &db, flags, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 2000)
        var statement: OpaquePointer?
        let query = "SELECT conversation_id, workspace_uris FROM conversation_summaries "
            + "WHERE workspace_uris != '' ORDER BY rowid DESC LIMIT \(maximumRows)"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        var projects: [String: String] = [:]
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            defer { result = sqlite3_step(statement) }
            guard let id = sqlite3_column_text(statement, 0), let uris = sqlite3_column_text(statement, 1),
                  let project = project(fromWorkspaceURIs: String(cString: uris)) else { continue }
            projects[AgentLogParser.native(String(cString: id))] = project
        }
        return result == SQLITE_DONE ? projects : nil
    }
}
