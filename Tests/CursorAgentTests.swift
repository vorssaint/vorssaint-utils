// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CursorAgentTests {
    private final class Log {
        let now = AgentTimestamp.parse("2026-11-18T10:00:00Z")!
        var state = AgentLogState()
        let store = AgentUsageStore()
        let path: String

        init(path: String = "/Users/demo/.cursor/projects/Users-demo-Desktop-demo/agent-transcripts/session/session.jsonl") {
            self.path = path
            store.reportsTransitions = true
            CursorReader.adopt(path: path, into: &state)
        }

        @discardableResult
        func feed(_ object: [String: Any]) -> [AgentUsageEvent] {
            let bytes = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return store.apply(AgentLogParser.parseCursor(bytes, state: &state, now: now),
                               file: path, provider: .cursor, tracksTurns: true, modified: now, now: now)
        }

        @discardableResult
        func user(_ text: String) -> [AgentUsageEvent] {
            feed(["role": "user", "message": ["content": [["type": "text", "text": text]]]])
        }

        @discardableResult
        func assistant(tools: Bool) -> [AgentUsageEvent] {
            var content: [[String: Any]] = [["type": "text", "text": "working"]]
            if tools {
                content.append(["type": "tool_use", "name": "Shell", "input": ["command": "true"]])
            }
            return feed(["role": "assistant", "message": ["content": content]])
        }
    }

    static func run(_ suite: TestSuite) {
        turns(suite)
        discovery(suite)
        projectName(suite)
        timestamps(suite)
    }

    private static func turns(_ suite: TestSuite) {
        let log = Log()
        suite.expect(log.state.session == "session" && !log.state.project.isEmpty,
                     "Cursor session and project come from the transcript path")
        let project = log.state.project
        log.user("<timestamp>Wednesday, Nov 18, 2026, 6:00 PM (UTC+0)</timestamp>\n<user_query>hi</user_query>")
        suite.expect(log.state.turnOpen && log.store.live.count == 1 && log.store.live.first?.project == project,
                     "a Cursor user prompt opens a live turn with its project")
        log.assistant(tools: true)
        suite.expect(log.state.turnOpen && log.store.live.count == 1,
                     "Cursor tool steps keep the turn live")
        log.assistant(tools: false)
        suite.expect(log.state.turnOpen, "a Cursor text reply alone does not finish the turn")
        let finished = log.feed(["type": "turn_ended", "status": "success"])
        let finishedOK: Bool = {
            guard finished.count == 1, case .finished(let provider, _, let cost, let tokens, let name) = finished[0]
            else { return false }
            return provider == .cursor && cost == 0 && tokens == 0 && name == project
        }()
        suite.expect(finishedOK && !log.state.turnOpen && log.store.live.isEmpty,
                     "Cursor turn_ended finishes the task once")
        suite.expect(log.feed(["type": "turn_ended", "status": "success"]).isEmpty,
                     "repeated Cursor turn_ended events do not repeat completion alerts")

        log.user("next")
        log.assistant(tools: true)
        suite.expect(log.feed(["type": "turn_ended", "status": "aborted"]).isEmpty && !log.state.turnOpen
                        && log.store.live.isEmpty,
                     "an aborted Cursor turn closes without a completion notice")
    }

    private static func discovery(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "vorss-cursor-logs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appending(path: "Users-demo-Desktop-demo/agent-transcripts/abc")
        let tools = root.appending(path: "Users-demo-Desktop-demo/agent-tools")
        try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let transcript = session.appending(path: "abc.jsonl")
        FileManager.default.createFile(atPath: transcript.path, contents: Data("{}\n".utf8))
        FileManager.default.createFile(atPath: tools.appending(path: "noise.jsonl").path, contents: Data("{}\n".utf8))
        let other = session.deletingLastPathComponent().appending(path: "other/other-extra.jsonl")
        try? FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: other.path, contents: Data("{}\n".utf8))

        let found = AgentLogReader.discover(
            [AgentLogRoot(provider: .cursor, url: AgentLogRoot.canonical(root))], since: .distantPast)
        suite.expect(found.map(\.path) == [AgentLogRoot.canonical(transcript).path],
                     "Cursor discovery reads only matching agent transcripts")
        let home = FileManager.default.temporaryDirectory.appending(path: "vorss-cursor-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try? FileManager.default.createDirectory(at: home.appending(path: ".cursor/projects"),
                                                 withIntermediateDirectories: true)
        let expected = AgentLogRoot.canonical(home.appending(path: ".cursor/projects")).path
        suite.expect(AgentLogRoot.all(home: home).contains {
            $0.provider == .cursor && $0.url.path == expected
        }, "Cursor agent transcripts are a discovered local root")
    }

    private static func projectName(_ suite: TestSuite) {
        suite.expect(AgentLogParser.cursorProject(from: "/tmp/.cursor/projects/empty-window/agent-transcripts/id/id.jsonl")
                        == "empty-window",
                     "short Cursor project slugs keep their name")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let encoded = home.split(separator: "/").joined(separator: "-")
        let path = "\(home)/.cursor/projects/\(encoded)-Desktop-demo-app/agent-transcripts/id/id.jsonl"
        let name = AgentLogParser.cursorProject(from: path)
        suite.expect(name == "demo-app" || name.hasSuffix("demo-app") || name == "Desktop-demo-app",
                     "Cursor project names recover the workspace folder when possible")
    }

    private static func timestamps(_ suite: TestSuite) {
        let date = AgentTimestamp.parseCursor("Wednesday, Nov 18, 2026, 6:09 PM (UTC+8)")
        suite.expect(date == AgentTimestamp.parse("2026-11-18T10:09:00Z"),
                     "Cursor transcript timestamps convert to UTC")
        suite.expect(AgentTimestamp.parseCursor("2026-11-18T10:09:00Z")
                        == AgentTimestamp.parse("2026-11-18T10:09:00Z"),
                     "ISO Cursor timestamps still parse")
    }
}
