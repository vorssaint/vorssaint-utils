// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CursorAgentTests {
    /// What Cursor writes under `~/.cursor/projects/<project>/agent-transcripts/`:
    /// Anthropic-shaped JSONL, a prompt in one line shape, a reply in another,
    /// and the transcript's own turn control lines between them. The synthetic
    /// samples follow those shapes; nothing in them is copied from a chat.
    static func run(_ suite: TestSuite) {
        turns(suite)
        usage(suite)
        records(suite)
        paths(suite)
    }

    private final class Log {
        let now = AgentTimestamp.parse("2026-10-27T12:10:00Z")!
        let file = "/Users/me/.cursor/projects/User-me-work-app/agent-transcripts/chat-1.jsonl"
        var state = AgentLogState()
        let store = AgentUsageStore()
        var events: [AgentUsageEvent] = []

        init() {
            store.reportsTransitions = true
            // The transcript names its session and project as the cursor is
            // made; the lines say nothing about either.
            state.project = "app"
        }

        @discardableResult
        func feed(_ json: String) -> [AgentLogEntry] {
            let entries = AgentLogParser.parseCursor(Data(json.utf8), state: &state, now: now)
            events += store.apply(entries, file: file, provider: .cursor,
                                  tracksTurns: true, modified: now, now: now)
            return entries
        }

        func apply(_ entries: [AgentLogEntry], tracksTurns: Bool = true) {
            events += store.apply(entries, file: file, provider: .cursor,
                                  tracksTurns: tracksTurns, modified: now, now: now)
        }

        var live: [AgentLiveSession] { store.live }
    }

    private static func turns(_ suite: TestSuite) {
        let log = Log()
        // A prompt opens the turn at the moment the transcript stamped it,
        // though the line itself carries no machine-readable time.
        let entries = log.feed(#"{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Monday, Oct 27, 2026, 3:10 PM (UTC+3)</timestamp>work"}]}}"#)
        let began = AgentTimestamp.parse("2026-10-27T12:10:00Z")!
        suite.expect(entries.first == .turnBegan(began) && entries.dropFirst() == [.turnContext(model: "", project: "app")],
                     "a Cursor prompt opens its turn at the stamped moment with the project from its path")
        suite.expect(log.live.first?.project == "app", "the encoded project folder names the project")
        // A follow-up prompt is activity of the turn that stands.
        let second = log.feed(#"{"role":"user","message":{"content":[{"type":"text","text":"keep going"}]}}"#)
        suite.expect(second.first == .turnActive(began), "a follow-up prompt keeps the turn it comes to")
        let reply = log.feed(#"{"role":"assistant","message":{"content":[{"type":"text","text":"the answer"}]}}"#)
        suite.expect(reply.first == .turnActive(began), "a reply keeps the turn active")
        let end = log.feed(#"{"type":"turn_ended","status":"success"}"#)
        suite.expect(end == [.turnEnded(log.now, completed: true, duration: nil)] && log.live.isEmpty,
                     "the transcript's own turn end closes its turn")
        suite.expect(log.events == [.finished(provider: .cursor, duration: 0, cost: 0, tokens: 0, project: "app")],
                     "a finished Cursor turn reports itself like every agent")
        // A turn the transcript ended as it failed finishes nothing.
        let aborted = Log()
        aborted.feed(#"{"role":"user","message":{"content":[{"type":"text","text":"work"}]}}"#)
        let ended = AgentLogParser.parseCursor(
            Data(#"{"type":"turn_ended","status":"failed"}"#.utf8), state: &aborted.state, now: aborted.now)
        suite.expect(ended == [.turnEnded(aborted.now, completed: false, duration: nil)],
                     "a failed Cursor turn ends unfinished")
        // A prompt stamped without its day of the week or its zone still reads.
        let bare = Log()
        let bareEntries = AgentLogParser.parseCursor(
            Data(#"{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Oct 27, 2026, 2:10 PM</timestamp>work"}]}}"#.utf8),
            state: &bare.state, now: bare.now)
        suite.expect(bareEntries.first == .turnBegan(AgentTimestamp.parse("2026-10-27T14:10:00Z")!),
                     "a prompt's stamp keeps the day of the week and the zone out of its reading")
    }

    private static func usage(_ suite: TestSuite) {
        let log = Log()
        log.feed(#"{"role":"user","message":{"content":[{"type":"text","text":"work"}]}}"#)
        let reply = #"{"role":"assistant","message":{"model":"gpt-5.2","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":400,"cache_read_input_tokens":100,"cache_creation_input_tokens":20,"output_tokens":80}}}"#
        let entries = log.feed(reply)
        suite.expect(entries.first == .turnActive(log.now), "a priced reply still keeps the turn working")
        let record = log.store.records.first
        suite.expect(record?.model == "gpt-5.2"
                        && record?.tokens == AgentTokens(input: 400, cacheWrite: 20, cacheRead: 100, output: 80),
                     "a reply's usage is recorded under the model that wrote it")
        // A reply line read again, as when the transcript is read again, is not counted twice.
        log.feed(reply)
        suite.expect(log.store.records.count == 1, "the same reply read twice is one response")
        // A reply without usage, as the transcripts older writes carry, is activity only.
        let quiet = Log()
        quiet.feed(#"{"role":"user","message":{"content":[{"type":"text","text":"work"}]}}"#)
        let activity = AgentLogParser.parseCursor(
            Data(#"{"role":"assistant","message":{"content":[{"type":"text","text":"text"}]}}"#.utf8),
            state: &quiet.state, now: quiet.now)
        suite.expect(activity.first == .turnActive(quiet.now) && quiet.store.records.isEmpty,
                     "a reply without usage counts activity only")
        // Broken lines must not break the reading.
        let broken = Log()
        suite.expect(AgentLogParser.parseCursor(Data("not json".utf8), state: &broken.state, now: broken.now).isEmpty
                        && AgentLogParser.parseCursor(Data(#"{"role":"assistant"}"#.utf8), state: &broken.state, now: broken.now).isEmpty
                        && AgentLogParser.parseCursor(Data(#"{"type":"unknown_kind"}"#.utf8), state: &broken.state, now: broken.now).isEmpty,
                     "a malformed or unknown Cursor line reads as nothing")
    }

    private static func records(_ suite: TestSuite) {
        let log = Log()
        let opened = AgentTimestamp.parse("2026-10-27T12:00:00Z")!
        let closed = AgentTimestamp.parse("2026-10-27T13:00:00Z")!
        log.apply([.turnBegan(opened), .turnContext(model: "", project: "app")])
        // A reply found in a transcript read again meets the turn it works on,
        // as the reader combines the entries with the state kept for the file.
        log.state.turnOpen = true
        log.apply(AgentLogParser.parseCursor(
            Data(#"{"role":"assistant","timestamp":"2026-10-27T12:00:10.000Z","message":{"model":"vorss-unknown-8","content":[],"usage":{"input_tokens":100,"output_tokens":50}}}"#.utf8),
            state: &log.state, now: log.now))
        log.apply([.turnEnded(closed, completed: true, duration: 3_600)])
        let snapshot = log.store.snapshot(plans: [:], providers: [AgentProvider.cursor], now: closed)
        suite.expect(snapshot.usage(.today).byProvider[AgentProvider.cursor]?.tokens == AgentTokens(input: 100, output: 50),
                     "a Cursor turn keeps its period's tokens like every agent")
        suite.expect(log.events == [.finished(provider: .cursor, duration: 3_600, cost: 0,
                                              tokens: 150, project: "app")],
                     "a Cursor turn of an unpriced model finishes with its tokens")
    }

    private static func paths(_ suite: TestSuite) {
        // The project folder encodes the workspace's absolute path; one that
        // exists on this Mac reads back through every dash it kept.
        let base = FileManager.default.temporaryDirectory.appending(path: "vorss-cursor-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let encoded = String(base.path.dropFirst()).replacingOccurrences(of: "/", with: "-")
        let path = "/.cursor/projects/\(encoded)/agent-transcripts/chat.jsonl"
        suite.expect(AgentLogParser.cursorProject(from: path) == AgentLogParser.projectName(base.path),
                     "a project folder that exists on disk reads back its project")
        // A project gone from disk still names itself the way a person sees it.
        suite.expect(AgentLogParser.cursorProject(from: "/.cursor/projects/app-agent-run/agent-transcripts/a.jsonl") == "agent-run",
                     "a project folder no longer on disk keeps its last readable names")
        suite.expect(AgentLogParser.cursorProject(from: "/Users/me/.cursor/projects") == "",
                     "a projects root with no transcript below it names no project")
    }
}
