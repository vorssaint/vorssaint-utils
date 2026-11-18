// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Oh My Pi (`omp`) session logs: turns, usage and subagents.
enum OmpAgentTests {
    private static let now = AgentTimestamp.parse("2026-11-11T13:30:00Z")!

    private final class Log {
        var state = AgentLogState()
        let store = AgentUsageStore()
        let file: String
        let parent: String?

        init(file: String = "/s/-proj/2026_a.jsonl", parent: String? = nil) {
            self.file = file
            self.parent = parent
            store.reportsTransitions = true
        }

        @discardableResult
        func feed(_ json: String) -> [AgentUsageEvent] {
            let entries = AgentProvider.omp.reader.parse(Data(json.utf8), state: &state, now: OmpAgentTests.now)
            return store.apply(entries, file: file, provider: .omp, tracksTurns: parent == nil, parent: parent,
                               modified: OmpAgentTests.now, now: OmpAgentTests.now)
        }
    }

    static func run(_ suite: TestSuite) {
        modelNames(suite)
        turns(suite)
        interruptions(suite)
        usage(suite)
        subagents(suite)
        roots(suite)
    }

    private static let header = #"{"type":"session","version":3,"id":"01a1","timestamp":"2026-11-11T13:24:39.249Z","cwd":"/Users/me/orca/workspaces/tagai/img-bot"}"#

    private static func prompt(_ at: String) -> String {
        #"{"type":"message","id":"u1","parentId":"x","timestamp":"\#(at)","message":{"role":"user","content":[{"type":"text","text":"work"}],"attribution":"user"}}"#
    }

    private static func reply(_ at: String, stop: String, id: String, output: Int = 277, cost: Double = 0.1294746,
                              model: String = "claude-opus-5-5") -> String {
        #"{"type":"message","id":"\#(id)","timestamp":"\#(at)","message":{"role":"assistant","content":[],"provider":"anthropic","model":"\#(model)","usage":{"input":4,"output":\#(output),"cacheRead":29513,"cacheWrite":14752,"totalTokens":44546,"cost":{"total":\#(cost)},"cttl":{"ephemeral1h":14752}},"stopReason":"\#(stop)","responseId":"msg_\#(id)"}}"#
    }

    private static func toolResult(_ at: String) -> String {
        #"{"type":"message","id":"t1","timestamp":"\#(at)","message":{"role":"toolResult","toolCallId":"toolu_1","toolName":"bash","content":[{"type":"text","text":"\"role\":\"user\" quoted"}],"isError":false}}"#
    }

    private static func modelNames(_ suite: TestSuite) {
        suite.expect(OmpReader.modelName("anthropic/claude-opus-5-5") == "claude-opus-5-5",
                     "an omp model keeps its bare id without the provider")
        suite.expect(OmpReader.modelName("anthropic/claude-fable-5-2:high") == "claude-fable-5-2",
                     "an omp model drops its thinking level")
        suite.expect(OmpReader.modelName("gpt-5.6-terra") == "gpt-5.6-terra", "a bare omp model stays as it is")
    }

    private static func turns(_ suite: TestSuite) {
        let log = Log()
        log.feed(header)
        suite.expect(log.state.session == "01a1" && log.state.project == "img-bot",
                     "the omp session header names the session and its folder")
        log.feed(prompt("2026-11-11T13:24:40.852Z"))
        suite.expect(log.store.live.count == 1 && log.store.live.first?.provider == .omp,
                     "a person's omp prompt opens a turn")
        log.feed(reply("2026-11-11T13:24:45.864Z", stop: "toolUse", id: "a1"))
        log.feed(toolResult("2026-11-11T13:24:47.831Z"))
        suite.expect(log.store.live.count == 1 && log.state.turnOpen,
                     "a tool call and its result keep the omp turn going, even quoting a prompt")
        let events = log.feed(reply("2026-11-11T13:29:00.000Z", stop: "stop", id: "a2"))
        suite.expect(log.store.live.isEmpty && !log.state.turnOpen, "the final omp reply ends the turn")
        suite.expect(events.contains { if case .finished(.omp, _, _, _, "img-bot") = $0 { true } else { false } },
                     "a finished omp turn is reported with its project")
        log.feed(toolResult("2026-11-11T13:29:01.000Z"))
        suite.expect(log.store.live.isEmpty, "a late tool result never opens an omp turn")
    }

    private static func interruptions(_ suite: TestSuite) {
        for stop in ["aborted", "error"] {
            let log = Log()
            log.feed(header)
            log.feed(prompt("2026-11-11T13:24:40.852Z"))
            let events = log.feed(reply("2026-11-11T13:25:00.000Z", stop: stop, id: "a1"))
            suite.expect(log.store.live.isEmpty && !events.contains { if case .finished = $0 { true } else { false } },
                         "an omp turn that ends \(stop) stops without a finished notice")
            log.feed(reply("2026-11-11T13:25:10.000Z", stop: "toolUse", id: "a2"))
            suite.expect(log.store.live.count == 1, "a retry after an omp \(stop) opens the turn again")
        }
        let steering = Log()
        steering.feed(header)
        steering.feed(prompt("2026-11-11T13:24:40.852Z"))
        steering.feed(reply("2026-11-11T13:24:45.000Z", stop: "toolUse", id: "a1"))
        steering.feed(prompt("2026-11-11T13:24:50.000Z"))
        suite.expect(steering.store.live.count == 1
                        && steering.store.live.first?.started == AgentTimestamp.parse("2026-11-11T13:24:40.852Z"),
                     "a message sent while omp works steers the turn it is in")
    }

    private static func usage(_ suite: TestSuite) {
        let log = Log()
        log.feed(header)
        log.feed(prompt("2026-11-11T13:24:40.852Z"))
        log.feed(reply("2026-11-11T13:24:45.864Z", stop: "toolUse", id: "a1"))
        log.feed(reply("2026-11-11T13:24:45.864Z", stop: "toolUse", id: "a1"))
        suite.expect(log.store.records.count == 1, "a replayed omp response counts once")
        guard let record = log.store.records.first else { return }
        suite.expect(record.provider == .omp && record.model == "claude-opus-5-5" && record.project == "img-bot"
                        && record.session == "01a1",
                     "an omp response records its model, project and session")
        suite.expect(record.tokens == AgentTokens(input: 4, cacheWrite: 14752, cacheRead: 29513, output: 277),
                     "an omp response's tokens keep input, cache reads, cache writes and output apart")
        suite.expect((record.cost ?? 0) > 0, "an omp response has an API value")

        let unknown = Log()
        unknown.feed(header)
        unknown.feed(reply("2026-11-11T13:24:45.864Z", stop: "stop", id: "b1", cost: 0.25, model: "some/unlisted-model"))
        suite.expect(unknown.store.records.first.map { $0.cost == 0.25 && $0.reportedCost } == true,
                     "a model the list does not know costs what omp recorded")

        let side = Log()
        side.feed(header)
        side.feed(#"{"type":"model_usage","id":"m1","timestamp":"2026-11-11T13:24:46.526Z","purpose":"title","provider":"anthropic","model":"claude-opus-5-5","usage":{"input":717,"output":31,"cacheRead":44265,"cacheWrite":0,"cost":{"total":0.012341}},"stopReason":"stop"}"#)
        suite.expect(side.store.records.count == 1 && side.store.live.isEmpty,
                     "omp's side requests, like naming the session, count without opening a turn")
    }

    private static func subagents(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "omp-\(UUID().uuidString)/-proj", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let session = folder.appending(path: "2026_a.jsonl").path
        let task = folder.appending(path: "2026_a/Worker.jsonl").path
        let nested = folder.appending(path: "2026_a/Worker/Helper.jsonl").path
        try? FileManager.default.createDirectory(at: folder.appending(path: "2026_a/Worker"), withIntermediateDirectories: true)
        for path in [session, task, nested] { FileManager.default.createFile(atPath: path, contents: Data()) }
        suite.expect(AgentLogCursor.ompParent(of: session) == nil, "an omp session's own log has no parent")
        suite.expect(AgentLogCursor.ompParent(of: task) == session, "an omp subagent reports to its session's log")
        suite.expect(AgentLogCursor.ompParent(of: nested) == session,
                     "a subagent's own subagent reports to the outermost session")
        suite.expect(AgentLogCursor(path: task, provider: .omp).tracksTurns == false
                        && AgentLogCursor(path: session, provider: .omp).tracksTurns,
                     "only an omp session's own log tracks turns")

        let main = Log(file: session)
        main.feed(header)
        main.feed(prompt("2026-11-11T13:24:40.852Z"))
        main.feed(reply("2026-11-11T13:24:45.000Z", stop: "toolUse", id: "a1"))
        let sub = Log(file: task, parent: session)
        sub.feed(#"{"type":"session","version":3,"id":"01a2","parentSession":"01a1","timestamp":"2026-11-11T13:25:00Z","cwd":"/Users/me/orca/workspaces/tagai/img-bot"}"#)
        sub.feed(prompt("2026-11-11T13:25:01.000Z"))
        sub.feed(reply("2026-11-11T13:25:05.000Z", stop: "stop", id: "s1"))
        suite.expect(sub.store.live.isEmpty && sub.store.records.count == 1,
                     "an omp subagent counts its usage without a turn of its own")
    }

    private static func roots(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let root = AgentLogRoot.all(home: home).first { $0.provider == .omp }
        suite.expect(root?.url.path == "/Users/me/.omp/agent/sessions", "omp logs are read from ~/.omp/agent/sessions")
        if let root {
            suite.expect(root.accepts("/Users/me/.omp/agent/sessions/-proj/2026_a.jsonl")
                            && !root.accepts("/Users/me/.omp/agent/sessions/-proj/2026_a/1.bash.log"),
                         "only omp's JSONL logs are read, never a tool's output")
        }
    }
}
