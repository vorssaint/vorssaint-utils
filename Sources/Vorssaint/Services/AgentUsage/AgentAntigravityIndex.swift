// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import SQLite3

/// Read-only metadata lookup against Antigravity's `conversation_summaries.db`
/// beside each `brain/` folder. Only `conversation_id`, `workspace_uris`
/// (reduced immediately to the folder's own name) and `parent_conversation_id`
/// are queried; titles, previews, search indexes and conversation bodies are
/// never read.
final class AgentAntigravityIndex {
    struct Entry: Equatable {
        let project: String
        let parentSession: String
    }

    private struct Stamp: Equatable {
        let dbModified: Date
        let walModified: Date
    }

    private struct Cache {
        let stamp: Stamp
        let entries: [String: Entry]
    }

    struct DeferredUsage {
        let file: String
        let date: Date
        let entry: AgentLogEntry
        let modified: Date
    }

    enum DeferredRollback {
        case remove
        case restore(AgentLogCursor.Saved)
    }

    private var caches: [String: Cache] = [:]
    /// Maps canonical `brain/` directory paths to their original Antigravity
    /// data directories so symlinked `brain/` folders still locate
    /// `conversation_summaries.db` in the data directory that owns them.
    private var dataDirectories: [String: URL] = [:]
    /// Child usage held until the parent transcript advances across turn
    /// boundaries, keyed by parent transcript path.
    private var deferredUsage: [String: [DeferredUsage]] = [:]
    /// Last committed cursor progress for each child transcript that currently
    /// has uncommitted deferred entries, used to roll back safely on cancel.
    private var deferredRollbacks: [String: DeferredRollback] = [:]

    func deferUsage(forParent parentPath: String, file: String, date: Date,
                    entry: AgentLogEntry, modified: Date,
                    rollback: DeferredRollback) {
        if deferredRollbacks[file] == nil {
            deferredRollbacks[file] = rollback
        }
        deferredUsage[parentPath, default: []].append(
            DeferredUsage(file: file, date: date, entry: entry, modified: modified))
    }

    func drainDeferredUsage(forParent parentPath: String, through cutoff: Date? = nil,
                            inclusive: Bool = true) -> [DeferredUsage] {
        guard let pending = deferredUsage[parentPath], !pending.isEmpty else { return [] }
        let matched: [DeferredUsage]
        let remaining: [DeferredUsage]
        if let cutoff {
            matched = pending.filter { inclusive ? $0.date <= cutoff : $0.date < cutoff }
            remaining = pending.filter { inclusive ? $0.date > cutoff : $0.date >= cutoff }
        } else {
            matched = pending
            remaining = []
        }
        deferredUsage[parentPath] = remaining.isEmpty ? nil : remaining
        if !matched.isEmpty {
            let stillPending = deferredSourceFiles
            for item in matched where !stillPending.contains(item.file) {
                deferredRollbacks.removeValue(forKey: item.file)
            }
        }
        return matched.sorted { $0.date < $1.date }
    }

    @discardableResult
    func forwardDeferredUsage(from childPath: String, to parentPath: String) -> Bool {
        guard childPath != parentPath,
              let pending = deferredUsage.removeValue(forKey: childPath),
              !pending.isEmpty else { return false }
        deferredUsage[parentPath, default: []].append(contentsOf: pending)
        return true
    }

    func clearDeferredUsage() {
        deferredUsage.removeAll()
        deferredRollbacks.removeAll()
    }

    /// Source transcript paths with uncommitted deferred usage waiting on a parent.
    var deferredSourceFiles: Set<String> {
        Set(deferredUsage.values.flatMap { $0.map(\.file) })
    }

    func deferredRollback(for file: String) -> DeferredRollback? {
        deferredRollbacks[file]
    }

    /// Discards all pending deferred child usage and returns the rollback
    /// action for every affected child transcript cursor.
    @discardableResult
    func discardDeferredUsage() -> [String: DeferredRollback] {
        var rollbacks = deferredRollbacks
        for file in deferredSourceFiles where rollbacks[file] == nil {
            rollbacks[file] = .remove
        }
        deferredUsage.removeAll()
        deferredRollbacks.removeAll()
        return rollbacks
    }

    /// Records the data directory for each canonical Antigravity `brain/` root.
    func register(roots: [AgentLogRoot]) {
        dataDirectories.removeAll(keepingCapacity: true)
        for root in roots where root.provider == .antigravity {
            if let dataDirectory = root.dataDirectory {
                dataDirectories[root.url.path] = dataDirectory
            }
        }
    }

    /// Resolves metadata for `session` under the Antigravity data folder that
    /// holds `transcriptPath` (`<dataDir>/brain/<session>/.system_generated/logs/transcript.jsonl`).
    func entry(forSession session: String, transcriptPath: String, dataDirectory: URL? = nil) -> Entry? {
        guard !session.isEmpty,
              let dbPath = databasePath(forTranscript: transcriptPath, dataDirectory: dataDirectory) else { return nil }
        return entries(at: dbPath)[session]
    }

    /// Returns all descendant conversation IDs whose `parentSession` chain
    /// leads back to `parentSession` in the Antigravity index for `transcriptPath`.
    func childSessions(forParent parentSession: String, transcriptPath: String,
                       dataDirectory: URL? = nil) -> [String] {
        guard !parentSession.isEmpty,
              let dbPath = databasePath(forTranscript: transcriptPath, dataDirectory: dataDirectory) else { return [] }
        let all = entries(at: dbPath)
        guard !all.isEmpty else { return [] }
        var byParent: [String: [String]] = [:]
        for (session, entry) in all where !entry.parentSession.isEmpty {
            byParent[entry.parentSession, default: []].append(session)
        }
        var result: [String] = []
        var seen: Set<String> = [parentSession]
        var queue: [String] = [parentSession]
        var cursor = 0
        while cursor < queue.count, result.count < 256 {
            let current = queue[cursor]
            cursor += 1
            for child in byParent[current] ?? [] where seen.insert(child).inserted {
                result.append(child)
                queue.append(child)
            }
        }
        return result
    }

    /// Resolves `conversation_summaries.db` for `transcriptPath`, preferring
    /// an explicit or registered data directory when `brain/` is symlinked.
    func databasePath(forTranscript transcriptPath: String, dataDirectory: URL? = nil) -> String? {
        if let explicit = dataDirectory ?? Self.brainPath(forTranscript: transcriptPath).flatMap({ dataDirectories[$0] }) {
            let preserved = explicit.appending(path: "conversation_summaries.db", directoryHint: .notDirectory).path
            if FileManager.default.fileExists(atPath: preserved) {
                return preserved
            }
        }
        return Self.databasePath(forTranscript: transcriptPath)
    }

    /// Returns `<brain>` from `<brain>/<session>/.system_generated/logs/transcript.jsonl`.
    static func brainPath(forTranscript transcriptPath: String) -> String? {
        let url = URL(fileURLWithPath: transcriptPath, isDirectory: false)
        // transcript.jsonl -> logs -> .system_generated -> <session> -> brain
        let logs = url.deletingLastPathComponent()
        let sys = logs.deletingLastPathComponent()
        let session = sys.deletingLastPathComponent()
        let brain = session.deletingLastPathComponent()
        guard logs.lastPathComponent == "logs", sys.lastPathComponent == ".system_generated",
              brain.path != session.path else { return nil }
        return brain.path
    }

    /// Derives `<dataDir>/conversation_summaries.db` from a transcript path.
    static func databasePath(forTranscript transcriptPath: String) -> String? {
        guard let brain = brainPath(forTranscript: transcriptPath) else { return nil }
        let brainURL = URL(fileURLWithPath: brain, isDirectory: true)
        let dataDir = brainURL.deletingLastPathComponent()
        guard dataDir.path != brainURL.path else { return nil }
        return dataDir.appending(path: "conversation_summaries.db", directoryHint: .notDirectory).path
    }

    /// Derives `<dataDir>/brain/<session>/.system_generated/logs/transcript.jsonl`
    /// beside `transcriptPath` within the same Antigravity brain directory.
    static func transcriptPath(forSession session: String, siblingOf transcriptPath: String) -> String? {
        guard !session.isEmpty, session != ".", session != "..",
              !session.contains("/"), !session.contains("\\"),
              let brain = brainPath(forTranscript: transcriptPath) else { return nil }
        return URL(fileURLWithPath: brain, isDirectory: true)
            .appending(path: session, directoryHint: .isDirectory)
            .appending(path: ".system_generated/logs/transcript.jsonl", directoryHint: .notDirectory)
            .path
    }

    func clear() {
        caches.removeAll()
        dataDirectories.removeAll()
        deferredUsage.removeAll()
        deferredRollbacks.removeAll()
    }

    private func entries(at dbPath: String) -> [String: Entry] {
        guard let stamp = Self.stamp(at: dbPath) else {
            caches[dbPath] = nil
            return [:]
        }
        if let cached = caches[dbPath], cached.stamp == stamp {
            return cached.entries
        }
        let loaded = Self.load(at: dbPath)
        caches[dbPath] = Cache(stamp: stamp, entries: loaded)
        return loaded
    }

    private static func stamp(at path: String) -> Stamp? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        var wal = stat()
        let walDate = stat(path + "-wal", &wal) == 0 ? AgentLogCursor.modificationDate(wal) : .distantPast
        return Stamp(dbModified: AgentLogCursor.modificationDate(info), walModified: walDate)
    }

    static func load(at dbPath: String) -> [String: Entry] {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db else { return [:] }
        sqlite3_busy_timeout(db, 1000)

        var parents: [String: String] = [:]
        if tableExists(db, name: "conversation_parents") {
            var parentStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT conversation_id, parent_id FROM conversation_parents", -1, &parentStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(parentStmt) }
                while sqlite3_step(parentStmt) == SQLITE_ROW {
                    if let cid = text(parentStmt, 0), let pid = text(parentStmt, 1), !cid.isEmpty, !pid.isEmpty {
                        parents[cid] = AgentLogParser.native(pid)
                    }
                }
            }
        }

        var result: [String: Entry] = [:]
        if tableExists(db, name: "conversation_summaries") {
            let hasParentColumn = columnExists(db, table: "conversation_summaries", column: "parent_conversation_id")
            let query = hasParentColumn
                ? "SELECT conversation_id, workspace_uris, parent_conversation_id FROM conversation_summaries"
                : "SELECT conversation_id, workspace_uris, '' FROM conversation_summaries"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let cid = text(stmt, 0), !cid.isEmpty else { continue }
                    let project = projectName(fromWorkspaceURIs: text(stmt, 1) ?? "")
                    let parentColumn = text(stmt, 2) ?? ""
                    let parent = !parentColumn.isEmpty ? AgentLogParser.native(parentColumn) : (parents[cid] ?? "")
                    guard !project.isEmpty || !parent.isEmpty else { continue }
                    result[AgentLogParser.native(cid)] = Entry(project: project, parentSession: parent)
                }
            }
        }
        for (cid, pid) in parents where result[cid] == nil {
            result[AgentLogParser.native(cid)] = Entry(project: "", parentSession: pid)
        }
        return result
    }

    static func projectName(fromWorkspaceURIs raw: String) -> String {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return "" }
        var fallback = ""
        for entry in array {
            let path: String
            if let url = URL(string: entry), url.isFileURL {
                path = url.path
            } else if entry.hasPrefix("/") {
                path = entry
            } else {
                continue
            }
            let name = AgentLogParser.projectName(path)
            guard !name.isEmpty, name != "/" else { continue }
            if fallback.isEmpty { fallback = name }
            // Prefer a non-temporary workspace when multiple URIs are listed.
            if !path.hasPrefix("/private/var/folders/") && !path.hasPrefix("/var/folders/") && !path.hasPrefix("/tmp/") {
                return name
            }
        }
        return fallback
    }

    private static func tableExists(_ db: OpaquePointer, name: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", -1, &stmt, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func columnExists(_ db: OpaquePointer, table: String, column: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM pragma_table_info('\(table)') WHERE name = ?", -1, &stmt, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, column, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }
}
