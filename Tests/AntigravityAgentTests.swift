// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AntigravityAgentTests {
    static func run(_ suite: TestSuite) {
        let temporary = AgentLogRoot.canonical(FileManager.default.temporaryDirectory)
        let home = temporary.appending(path: "vorss-antigravity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        do {
            try transcripts(suite, home: home)
        } catch {
            suite.expect(false, "Antigravity transcript fixtures: \(error)")
        }
    }

    private static func transcripts(_ suite: TestSuite, home: URL) throws {
        let files = FileManager.default
        let roots = AgentLogRoot.all(home: home, providers: [.antigravity])
        suite.expect(roots.map { $0.url.deletingLastPathComponent().lastPathComponent }
                        == ["antigravity", "antigravity-cli", "antigravity-ide"]
                        && AgentLogRoot.all(home: home, providers: [.codex]).allSatisfy { $0.provider == .codex },
                     "Antigravity discovers the three client roots only when its provider is enabled")
        let session = UUID().uuidString.lowercased()
        let transcripts = roots.map { $0.url.appending(path: session + "/" + AntigravityReader.transcript) }
        let path = transcripts[0]
        let duplicate = transcripts[1]
        let symlink = transcripts[2]
        for file in transcripts {
            try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let start = Date().addingTimeInterval(-20)
        let formatter = ISO8601DateFormatter()
        func timestamp(_ seconds: TimeInterval) -> String {
            formatter.string(from: start.addingTimeInterval(seconds))
        }
        let prompt = #"{"step_index":0,"type":"USER_INPUT","status":"DONE","source":"USER_EXPLICIT","created_at":"\#(timestamp(0))","content":"fixture prompt text"}"#
        let working = #"{"step_index":1,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"\#(timestamp(1))","model":"gemini-2.5-pro","input_tokens":120,"cache_read_tokens":50,"output_tokens":30,"thinking_tokens":8,"tool_calls":[{"args":{"output_tokens":9999}}]}"#
        let complete = #"{"step_index":2,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"\#(timestamp(4))","output_tokens":10,"tool_calls":[]}"#
        let stopped = #"{"step_index":2,"type":"ERROR_MESSAGE","status":"DONE","created_at":"\#(timestamp(4))"}"#
        let oldPrompt = #"{"step_index":0,"type":"USER_INPUT","status":"DONE","source":"SYSTEM","created_at":"\#(timestamp(-1))"}"#
        let noCounters = #"{"step_index":3,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"\#(timestamp(5))","content":"message without counters"}"#
        let horizon = start.addingTimeInterval(-3600)
        let now = start.addingTimeInterval(10)
        func write(_ lines: [String], to file: URL = path) throws {
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file, options: .atomic)
        }
        try write([oldPrompt, prompt, working])
        try write([prompt, working, complete, noCounters], to: duplicate)
        try write([prompt, working, complete], to: path.deletingLastPathComponent().appending(path: "transcript_full.jsonl"))
        try files.createSymbolicLink(at: symlink, withDestinationURL: path)
        let linkedSession = roots[2].url.appending(path: UUID().uuidString.lowercased())
        try files.createSymbolicLink(at: linkedSession, withDestinationURL: roots[0].url.appending(path: session))
        suite.expect(Set(AgentLogReader.discover(roots, since: horizon).map(\.path)) == [path.path, duplicate.path],
                     "discovery admits only primary transcripts under real conversation directories")
        suite.expect(!roots[0].accepts(path.deletingLastPathComponent().appending(path: "transcript_full.jsonl").path),
                     "the event watcher rejects the alternate full transcript")

        let store = AgentUsageStore()
        store.reportsTransitions = true
        let cursor = AgentLogCursor(path: path.path, provider: .antigravity)
        var events: [AgentUsageEvent] = []
        func read(_ cursor: AgentLogCursor, into store: AgentUsageStore) {
            _ = AgentLogReader.readAntigravity(cursor, into: store, now: now, since: horizon,
                                               shouldContinue: { true }) { events.append($0) }
        }

        read(cursor, into: store)
        suite.expect(store.live.first?.provider == .antigravity && events.isEmpty,
                     "a model response with tool calls leaves the observed human turn running")
        suite.expect(store.records.count == 1
                        && store.records.first?.tokens == AgentTokens(input: 120, cacheRead: 50, output: 30, reasoning: 8),
                     "uses the measured counters, retaining cache and reasoning without double-counting either")

        try write([oldPrompt, prompt, working, complete])
        read(cursor, into: store)
        suite.expect(store.live.isEmpty && events.count == 1 && store.records.count == 2,
                     "atomic replacement completes the observed turn and ingests its response once")
        read(AgentLogCursor(path: duplicate.path, provider: .antigravity), into: store)
        read(AgentLogCursor(path: symlink.path, provider: .antigravity), into: store)
        suite.expect(store.records.count == 2 && store.live.isEmpty && events.count == 1,
                     "a duplicate client transcript, linked file, or reply without counts adds no usage or completion")
        suite.expect(store.records.last?.cost == nil && store.records.last?.model.isEmpty == true,
                     "a response without a model retains observed tokens and an unknown API value")

        let saved = AgentUsageArchive.Contents(providers: [.antigravity], store: store.saved, cursors: [cursor.saved])
        let bytes = AgentUsageArchive.encode(saved, build: "antigravity-test")
        let decoded = AgentUsageArchive.decode(bytes, build: "antigravity-test")
        let restored = decoded?.cursors.first.flatMap { AgentLogCursor(saved: $0) }
        suite.expect(decoded?.providers == [.antigravity] && restored?.state.session == session
                        && restored?.offset == cursor.offset && bytes.range(of: Data("fixture prompt text".utf8)) == nil,
                     "the cache keeps just the metadata and resumes an unchanged secure transcript")

        let watch = AgentUsageReadTests.Host()
        watch.watchedRoots = roots
        watch.filesChanged([path.path, duplicate.path, symlink.path], rescan: false)
        suite.expect(watch.store.records.count == 2 && watch.store.live.isEmpty,
                     "the production watcher routes Antigravity transcripts into usage history")

        try write([prompt, working])
        read(cursor, into: store)
        try write([prompt, working, stopped])
        read(cursor, into: store)
        suite.expect(store.live.isEmpty && events.count == 1, "a failed turn does not send a completion notice")

        let idleStore = AgentUsageStore()
        read(AgentLogCursor(path: duplicate.path, provider: .antigravity), into: idleStore)
        suite.expect(idleStore.records.count == 2 && idleStore.live.isEmpty,
                     "a completed conversation still contributes to history on the first read")
    }
}
