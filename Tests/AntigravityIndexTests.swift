// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// The workspace of an agy 1.5 conversation is only in the index agy keeps
/// beside `brain/`, not in the transcript.
enum AntigravityIndexTests {
    static func run(_ suite: TestSuite) {
        workspaceNames(suite)
        indexBesideBrain(suite)
    }

    // MARK: Workspace names

    private static func workspaceNames(_ suite: TestSuite) {
        suite.expect(AgentAntigravityIndex.project(fromWorkspaceURIs: #"["file:///Users/me/work/app"]"#) == "app",
                     "a workspace URI gives its folder's name")
        suite.expect(AgentAntigravityIndex.project(fromWorkspaceURIs: #"["file:///Users/me/work/app","file:///tmp"]"#)
                        == "app",
                     "the first workspace names the conversation")
        suite.expect(AgentAntigravityIndex.project(fromWorkspaceURIs: #"["file:///Users/me/My%20App/"]"#) == "My App",
                     "an escaped, slash-ended workspace URI gives the folder's name")
        suite.expect(AgentAntigravityIndex.project(fromWorkspaceURIs: #"["https://example.com/x","file:///Users/me/app"]"#)
                        == "app",
                     "a workspace that is not a local folder is passed over")
        for text in ["", "[]", "not json", #"{"a":1}"#, #"["file:///"]"#, #"["https://example.com"]"#] {
            suite.expect(AgentAntigravityIndex.project(fromWorkspaceURIs: text) == nil,
                         "workspace list \(text.isEmpty ? "(empty)" : text) names no project")
        }
    }

    // MARK: Index beside brain

    private static func indexBesideBrain(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "vorssaint-agy-index-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = home.appending(path: ".gemini/antigravity-cli", directoryHint: .isDirectory)
        let first = "11111111-1111-4111-8111-111111111111"
        let second = "22222222-2222-4222-8222-222222222222"
        func transcript(_ id: String) -> String {
            cli.appending(path: "brain/\(id)/.system_generated/logs/transcript.jsonl").path
        }
        do {
            try FileManager.default.createDirectory(at: cli.appending(path: "brain"), withIntermediateDirectories: true)
        } catch {
            suite.expect(false, "Antigravity index fixture: \(error)")
            return
        }
        let path = cli.appending(path: "conversation_summaries.db").path

        suite.expect(AgentAntigravityIndex.project(forTranscript: transcript(first)) == nil,
                     "no index beside brain names no project")

        var writer: OpaquePointer?
        defer { sqlite3_close(writer) }
        guard sqlite3_open(path, &writer) == SQLITE_OK,
              exec(writer, "PRAGMA journal_mode=WAL"),
              exec(writer, "CREATE TABLE conversation_summaries (conversation_id text PRIMARY KEY, "
                    + "workspace_uris text NOT NULL, status text NOT NULL DEFAULT '')"),
              exec(writer, "INSERT INTO conversation_summaries (conversation_id, workspace_uris) VALUES "
                    + "('\(first)', '[\"file:///Users/me/work/app\"]')") else {
            suite.expect(false, "Antigravity index fixture: database could not be written")
            return
        }
        // agy removes the write-ahead log and its shared memory when it exits
        // (the system's SQLite leaves them), and the database stays in WAL mode.
        sqlite3_close(writer)
        writer = nil
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")
        suite.expect(!FileManager.default.fileExists(atPath: path + "-wal"),
                     "the index fixture is a WAL-mode database with no log, as agy leaves it")
        suite.expect(AgentAntigravityIndex.project(forTranscript: transcript(first)) == "app",
                     "the index names a conversation's workspace while agy is not running")

        guard sqlite3_open(path, &writer) == SQLITE_OK,
              exec(writer, "INSERT INTO conversation_summaries (conversation_id, workspace_uris) VALUES "
                    + "('\(second)', '[\"file:///Users/me/work/other\"]')") else {
            suite.expect(false, "Antigravity index fixture: second row could not be written")
            return
        }
        suite.expect(FileManager.default.fileExists(atPath: path + "-wal"),
                     "a running agy keeps its newest rows in the write-ahead log")
        suite.expect(AgentAntigravityIndex.project(forTranscript: transcript(second)) == "other"
                        && AgentAntigravityIndex.project(forTranscript: transcript(first)) == "app",
                     "the index shows rows still in the write-ahead log of a running agy")

        // The service reads a new transcript from its start, which empties the
        // state the project is kept in.
        let log = URL(fileURLWithPath: transcript(first))
        let reply: [String: Any] = ["step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
                                    "created_at": ISO8601DateFormatter().string(from: Date()),
                                    "input_tokens": 1_000, "output_tokens": 200]
        do {
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (JSONSerialization.data(withJSONObject: reply) + Data("\n".utf8)).write(to: log)
        } catch {
            suite.expect(false, "Antigravity index fixture: transcript could not be written: \(error)")
            return
        }
        let host = AgentUsageReadTests.Host()
        host.read(log.path, provider: .antigravity)
        suite.expect(host.store.records.map(\.project) == ["app"],
                     "a transcript's first read gives its responses the project the index names")

        // A database that cannot be read is tried again though it did not change.
        let broken = home.appending(path: "broken/conversation_summaries.db")
        try? FileManager.default.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
        var other: OpaquePointer?
        defer { sqlite3_close(other) }
        guard sqlite3_open(broken.path, &other) == SQLITE_OK,
              exec(other, "CREATE TABLE unrelated (id text)") else {
            suite.expect(false, "Antigravity index fixture: unreadable database could not be written")
            return
        }
        suite.expect(AgentAntigravityIndex.projects(in: broken).isEmpty,
                     "a database without agy's table names no project")
        // The table appears with the file's size and time unchanged, so only a
        // read that was not kept can see it.
        var before = stat()
        var after = stat()
        guard stat(broken.path, &before) == 0,
              exec(other, "DROP TABLE unrelated"),
              exec(other, "CREATE TABLE conversation_summaries (conversation_id text, workspace_uris text)"),
              exec(other, "INSERT INTO conversation_summaries VALUES ('\(first)', '[\"file:///Users/me/work/app\"]')") else {
            suite.expect(false, "Antigravity index fixture: table could not be replaced")
            return
        }
        let times = [before.st_atimespec, before.st_mtimespec]
        suite.expect(utimensat(AT_FDCWD, broken.path, times, 0) == 0 && stat(broken.path, &after) == 0
                        && after.st_size == before.st_size
                        && after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec
                        && after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
                     "the index fixture changed without its size or time changing")
        suite.expect(AgentAntigravityIndex.projects(in: broken)[first] == "app",
                     "a failed read of the index is not remembered as an empty index")

        suite.expect(AgentAntigravityIndex.project(forTranscript: transcript("33333333-3333-4333-8333-333333333333")) == nil,
                     "a conversation the index does not hold names no project")
        let elsewhere = home.appending(path: "somewhere/\(first)/.system_generated/logs/transcript.jsonl").path
        suite.expect(AgentAntigravityIndex.project(forTranscript: elsewhere) == nil,
                     "a transcript outside a brain folder is not looked up")
    }

    // MARK: Helpers

    private static func exec(_ db: OpaquePointer?, _ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }
}
