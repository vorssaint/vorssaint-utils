// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CursorTranscriptReadTests {
    private static let start = AgentTimestamp.parse("2026-11-18T12:00:00Z")!
    private static let finished = #"{"type":"turn_ended","status":"success"}"#
    private static let assistant = #"{"role":"assistant","message":{"content":[]}}"#

    private static func prompt(_ text: String, dated: Bool = false) -> String {
        let prefix = dated ? "<timestamp>Wednesday, Nov 18, 2026, 12:00 PM (UTC)</timestamp>" : ""
        return #"{"role":"user","message":{"content":[{"type":"text","text":"\#(prefix)<user_query>\#(text)</user_query>"}]}}"#
    }

    private final class Log {
        let root: URL
        let file: URL
        var cursor: AgentLogCursor
        var store = AgentUsageStore()
        var events: [AgentUsageEvent] = []

        init(_ directory: URL, _ name: String) {
            root = AgentLogRoot.canonical(directory.deletingLastPathComponent().deletingLastPathComponent())
            file = AgentLogRoot.canonical(directory).appending(path: name + ".jsonl")
            cursor = AgentLogCursor(path: file.path, provider: .cursor, cursorRoot: root)
            store.reportsTransitions = true
        }

        func write(_ lines: [String], at seconds: TimeInterval, append: Bool = false) throws {
            let data = Data((lines.joined(separator: "\n") + "\n").utf8)
            if append {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: file, options: .atomic)
            }
            try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(seconds)],
                                                  ofItemAtPath: file.path)
        }

        func read(at seconds: TimeInterval) {
            _ = AgentLogReader.readCursor(cursor, into: store, now: start.addingTimeInterval(seconds)) {
                self.events.append($0)
            }
        }
    }

    static func run(_ suite: TestSuite) {
        let temp = FileManager.default.temporaryDirectory.appending(path: "vorss-cursor-reads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        let directory = temp.appending(path: ".cursor/projects/workspace/agent-transcripts")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try history(suite, directory)
            try rewrites(suite, directory)
            try cache(suite, directory)
            try archiveRoot(suite, temp)
        } catch {
            suite.expect(false, "could not exercise the Cursor transcript reader: \(error)")
        }
    }

    private static func history(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "history")
        try log.write([prompt("old"), assistant], at: -86_400)
        log.read(at: 0)
        log.store.closeIdleTurns(now: start, after: NotchAgentSupport.idleTurn)
        suite.expect(log.store.live.isEmpty && log.events.isEmpty &&
                     log.cursor.state.cursorLastActivity == start.addingTimeInterval(-86_400),
                     "an old unfinished Cursor file is quiet and keeps its actual last activity")

        let closed = Log(directory, "closed")
        try closed.write([prompt("old", dated: true), assistant, finished], at: 120)
        closed.read(at: 121)
        try closed.write([prompt("old", dated: true), assistant, finished], at: 135)
        closed.read(at: 136)
        suite.expect(closed.events.isEmpty && closed.store.live.isEmpty && closed.store.records.isEmpty &&
                     !closed.cursor.state.turnOpen, "attaching and replaying a closed transcript never reports a new finish")

        let loading = Log(directory, "loading")
        loading.store.reportsTransitions = false
        try loading.write([prompt("in progress", dated: true)], at: 55)
        loading.read(at: 57)
        loading.store.reportsTransitions = true
        try loading.write([finished], at: 61, append: true)
        loading.read(at: 62)
        suite.expect(loading.events == [.finished(provider: .cursor, duration: 6, cost: 0, tokens: 0, project: "workspace")],
                     "attaching just before the minute changes does not announce a short turn as a long task")
    }

    private static func archiveRoot(_ suite: TestSuite, _ temp: URL) throws {
        let manager = FileManager.default
        let directory = temp.appending(path: ".cursor/projects/cache-root/agent-transcripts")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = Log(directory, "empty")
        try log.write(["{}"], at: 0)
        log.read(at: 1)
        let offset = log.cursor.offset
        let saved = AgentUsageArchive.Contents(providers: [.cursor], store: log.store.saved, cursors: [log.cursor.saved])
        func restore() -> AgentLogCursor? {
            AgentUsageArchive.resume(saved, logs: [log.file.path], since: .distantPast, cursorRoot: log.root)
                .cursors[log.file.path]
        }
        suite.expect(offset > 0 && restore()?.offset == offset, "a regular transcript restores from the admitted root")

        // A saved name can have a different parent by the time reading resumes.
        let moved = temp.appending(path: "former-transcripts")
        try manager.moveItem(at: directory, to: moved)
        try manager.createSymbolicLink(at: directory, withDestinationURL: moved)
        suite.expect(restore() == nil, "a cache hit still requires a transcript inside its authorized root")
        let handle = try FileHandle(forWritingTo: moved.appending(path: log.file.lastPathComponent))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        log.read(at: 2)
        suite.expect(log.cursor.offset <= offset && log.store.live.isEmpty && log.events.isEmpty,
                     "an existing cursor consumes no bytes after its transcript directory becomes a link")
    }

    private static func rewrites(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "two-in-one-minute")
        let first = prompt("first", dated: true)
        let second = prompt("second", dated: true)
        try log.write(["{}"], at: 0)
        log.read(at: 1)
        try log.write([first], at: 3, append: true)
        log.read(at: 4)
        try log.write([finished], at: 10, append: true)
        log.read(at: 11)
        try log.write([second], at: 15, append: true)
        log.read(at: 16)
        suite.expect(log.cursor.state.cursorPromptCount == 2 && log.store.live.first?.started == start.addingTimeInterval(15),
                     "two prompts with the same minute tag keep distinct observed starts")
        try log.write([first, finished, second, assistant, finished], at: 48)
        log.read(at: 50)
        log.read(at: 51)
        suite.expect(log.events == [.finished(provider: .cursor, duration: 7, cost: 0, tokens: 0, project: "workspace"),
                                    .finished(provider: .cursor, duration: 33, cost: 0, tokens: 0, project: "workspace")],
                     "rewriting both turns reports only the new finish and keeps its observed duration")

        let undated = Log(directory, "undated")
        try undated.write([prompt("keep")], at: 9)
        undated.read(at: 11)
        try undated.write([prompt("keep"), assistant], at: 19)
        undated.read(at: 21)
        try undated.write([prompt("keep"), assistant, finished], at: 55)
        undated.read(at: 65)
        suite.expect(undated.events == [.finished(provider: .cursor, duration: 46, cost: 0, tokens: 0, project: "workspace")],
                     "an undated but observed prompt keeps its original start across intermediate and final rewrites")

        let replaced = Log(directory, "replaced")
        try replaced.write([first], at: 4)
        replaced.read(at: 5)
        try replaced.write([second, finished], at: 40)
        replaced.read(at: 45)
        suite.expect(replaced.events.isEmpty && replaced.store.live.isEmpty,
                     "a different prompt at the same ordinal and minute cannot finish the previously observed turn")
    }

    private static func cache(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "cached")
        try log.write(["{}"], at: 1)
        log.read(at: 2)
        try log.write([prompt("saved", dated: true)], at: 9, append: true)
        log.read(at: 10)

        // Keep a real second cursor so resume retains this provider's usage.
        let file = directory.deletingLastPathComponent().appending(path: "codex.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let codex = AgentLogCursor(path: file.path, provider: .codex)
        AgentLogReader.readAppended(codex) { _ in }
        let billable = AgentBillable(tokens: AgentTokens(input: 80, output: 20))
        let model = "gpt-6-astra"
        let priced = AgentPricing.cost(billable, model: model)
        let record = AgentUsageRecord(provider: .codex, date: start, model: model, project: "other", session: "other",
                                      tokens: billable.tokens, cost: priced.cost, savings: priced.savings)
        log.store.apply([.usage(key: "codex:test", record: record, billable: billable)],
                        file: file.path, provider: .codex, tracksTurns: false, modified: start)
        let now = start.addingTimeInterval(10)
        let providers: Set<AgentProvider> = [.codex, .cursor]
        let before = log.store.snapshot(plans: [:], providers: providers, now: now, cursorProjectsFound: true,
                                        cursorLastActivity: log.cursor.state.cursorLastActivity)
        let archive = AgentUsageArchive.Contents(providers: providers, store: log.store.saved,
                                                 cursors: [log.cursor.saved, codex.saved])
        let data = AgentUsageArchive.encode(archive, build: "cursor-test")
        guard let decoded = AgentUsageArchive.decode(data, build: "cursor-test") else {
            suite.expect(false, "the Cursor and Codex cache can be decoded")
            return
        }
        let resumed = AgentUsageArchive.resume(decoded, logs: [log.file.path, file.path], since: .distantPast,
                                              cursorRoot: log.root)
        guard let cursor = resumed.cursors[log.file.path] else {
            suite.expect(false, "the unchanged Cursor file resumes at its saved offset")
            return
        }
        log.cursor = cursor
        log.store = resumed.store
        log.store.reportsTransitions = true
        log.read(at: 12)
        let after = log.store.snapshot(plans: [:], providers: providers, now: now, cursorProjectsFound: true,
                                       cursorLastActivity: cursor.state.cursorLastActivity)
        let usage = after.usage(.today)
        suite.expect(usage == before.usage(.today) && usage.fullyPriced && usage.total.cost > 0 &&
                     usage.total.requests == 1 && usage.byProvider[.cursor] == nil &&
                     log.store.records.map(\.provider) == [.codex],
                     "Cursor activity leaves other providers' priced totals unchanged after archive repricing")
        suite.expect(after.seen.contains(.cursor) && after.lastActivity[.cursor] == start.addingTimeInterval(9) &&
                     after.cursorProjectsFound && cursor.state.cursorPromptCount == 1 && cursor.state.turnOpen,
                     "restoring the cache preserves Cursor activity and the open turn without a billing record")

        // A second restore from the same bytes exercises the valid finish
        // independently from a replacement that only looks like that turn.
        let verified = AgentUsageArchive.resume(decoded, logs: [log.file.path, file.path], since: .distantPast,
                                               cursorRoot: log.root)
        try log.write([prompt("other", dated: true), finished], at: 54)
        log.read(at: 56)
        suite.expect(log.events.isEmpty && log.store.live.isEmpty,
                     "a different prompt with identical timestamp and ordinal after cache restore does not notify")
        guard let verifiedCursor = verified.cursors[log.file.path] else {
            suite.expect(false, "the second cache restore also matched the original bytes")
            return
        }
        log.cursor = verifiedCursor
        log.store = verified.store
        log.store.reportsTransitions = true
        try log.write(["{}", prompt("saved", dated: true), assistant, finished], at: 54)
        log.read(at: 56)
        suite.expect(log.events == [.finished(provider: .cursor, duration: 45, cost: 0, tokens: 0, project: "workspace")],
                     "a rewrite preserving the verified cache prefix can finish the previously observed turn")
    }
}
