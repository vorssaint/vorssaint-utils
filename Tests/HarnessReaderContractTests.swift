// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every provider resolves to the reader for its own harness, and each reader
/// parses its harness's lines into the entries the island keeps.
enum HarnessReaderContractTests {
    static func run(_ suite: TestSuite) {
        readersCoverProviders(suite)
        claudeGolden(suite)
        codexGolden(suite)
        openCodeGolden(suite)
        copilotGolden(suite)
        dshGolden(suite)
    }

    private static func line(_ json: String) -> Data { Data(json.utf8) }

    private static func readersCoverProviders(_ suite: TestSuite) {
        for provider in AgentProvider.allCases {
            let reader = provider.reader
            suite.expect(reader.provider == provider,
                         "\(provider.rawValue) resolves to its own harness reader")
            suite.expect(reader.readsFullHistoryFirst == (provider == .copilot),
                         "only the Copilot reader rereads history on its first pass")
        }
    }

    private static func claudeGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.claude.reader
        let began = Date(timeIntervalSince1970: 1_790_088_000)
        let prompt = line(#"{"type":"user","timestamp":1790088000,"sessionId":"s","cwd":"/Users/me/code/app","message":{"content":"work"}}"#)
        suite.expect(reader.parse(prompt, state: &state, now: now) == [.turnBegan(began)],
                     "a Claude prompt opens its turn")
        let interrupted = line(#"{"type":"user","timestamp":1790088010,"sessionId":"s","message":{"content":"[Request interrupted by user for now"}}"#)
        suite.expect(reader.parse(interrupted, state: &state, now: now)
                        == [.turnEnded(nil, completed: false, duration: nil)],
                     "an interrupted Claude prompt ends its turn unfinished")
        let sidechain = line(#"{"type":"user","timestamp":1790088020,"sessionId":"s","isSidechain":true,"message":{"content":"work"}}"#)
        suite.expect(reader.parse(sidechain, state: &state, now: now).isEmpty,
                     "a Claude subagent prompt never opens a turn")
    }

    private static func codexGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.codex.reader
        let meta = line(#"{"type":"session_meta","timestamp":1790088000,"payload":{"id":"s","cwd":"/tmp/example"}}"#)
        suite.expect(reader.parse(meta, state: &state, now: now).isEmpty
                        && state.session == "s" && state.project == "example",
                     "Codex session metadata names the session and project")
        let started = line(#"{"type":"event_msg","timestamp":1790088000,"payload":{"type":"task_started"}}"#)
        suite.expect(reader.parse(started, state: &state, now: now)
                        == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_000))],
                     "a Codex task start opens its turn")
        let bogus = line(#"{"type":"bogus","timestamp":1790088000,"payload":{}}"#)
        suite.expect(reader.parse(bogus, state: &state, now: now).isEmpty,
                     "an unknown Codex line parses to nothing")
    }

    private static func openCodeGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.opencode.reader
        let user = line(#"{"session_id":"s_oc_1","time_created":1790088000,"directory":"/Users/me/code/backend","role":"user","parts":[{"type":"text","text":"go"}]}"#)
        suite.expect(reader.parse(user, state: &state, now: now)
                        == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_000))],
                     "an OpenCode prompt opens its session turn")
        let stop = line(#"{"id":"msg_2","session_id":"s_oc_1","time_created":1790088020,"directory":"/Users/me/code/backend","role":"assistant","model_id":"stealth/ox-alpha","provider_id":"relay","cost":0.0015,"tokens":{"total":500,"input":400,"output":100,"reasoning":0,"cache":{"read":0,"write":0}},"finish":"stop"}"#)
        let stopped = reader.parse(stop, state: &state, now: now)
        suite.expect(stopped.last == .turnEnded(Date(timeIntervalSince1970: 1_790_088_020),
                                                completed: true, duration: 20),
                     "a finished OpenCode reply ends its turn with its duration")
        let reset = line(#"{"type":"reset"}"#)
        suite.expect(reader.parse(reset, state: &state, now: now) == [.reset(now)],
                     "an OpenCode reset restarts every session")
    }

    private static func copilotGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.copilot.reader
        let start = line(#"{"id":"start","timestamp":1790088000,"type":"session.start","data":{"sessionId":"s","selectedModel":"gpt-6-sol","context":{"cwd":"/tmp/example"}}}"#)
        suite.expect(reader.parse(start, state: &state, now: now).isEmpty
                        && state.session == "s" && state.model == "gpt-6-sol" && state.project == "example",
                     "a Copilot session start names the session, model and project")
        let prompt = line(#"{"id":"turn","timestamp":1790088000,"type":"user.message","data":{"turnId":"0","content":"private"}}"#)
        suite.expect(reader.parse(prompt, state: &state, now: now)
                        == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_000)),
                            .turnContext(model: "gpt-6-sol", project: "example")],
                     "a Copilot prompt opens its turn with its context")
        let reply = line(#"{"id":"message","timestamp":1790088000,"type":"assistant.message","data":{"model":"gpt-6-sol","content":"private"}}"#)
        suite.expect(reader.parse(reply, state: &state, now: now).count == 3,
                     "a Copilot reply counts its request and keeps the turn active")
        let end = line(#"{"id":"end","timestamp":1790088020,"type":"assistant.turn_end","data":{"turnId":"0"}}"#)
        suite.expect(reader.parse(end, state: &state, now: now)
                        == [.turnEnded(Date(timeIntervalSince1970: 1_790_088_020),
                                       completed: true, duration: nil)],
                     "a Copilot turn end finishes its turn")
        let checkpoint = line(#"{"id":"c","timestamp":1790088020,"type":"session.usage_checkpoint","data":{}}"#)
        suite.expect(reader.parse(checkpoint, state: &state, now: now).isEmpty,
                     "a Copilot usage checkpoint parses to nothing")
    }

    private static func dshGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.dsh.reader
        let header = line(#"{"v":1,"type":"session","session":"session-7fe88e4c-4773-4582-ab38-d5b56f942811","ts":1790088000000,"cwd":"/Users/me/code/app","parent":null,"preset":"standard"}"#)
        suite.expect(reader.parse(header, state: &state, now: now).isEmpty
                        && state.session == "session-7fe88e4c-4773-4582-ab38-d5b56f942811"
                        && state.project == "app" && !state.dshSubagent,
                     "a DeepSeek session header names the session and project")
        let start = line(#"{"v":1,"type":"turn","ts":1790088000000,"turn":1,"phase":"start"}"#)
        suite.expect(reader.parse(start, state: &state, now: now)
                        == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_000))],
                     "a DeepSeek turn start opens its turn")
        let usage = line(#"{"v":1,"type":"usage","ts":1790088010000,"turn":1,"step":2,"seq":20,"request":"eb7abe7f","model":"deepseek/deepseek-v4.1-flash","provider":"commandcode","tokens":{"input":100,"cacheWrite":20,"cacheRead":300,"output":40,"reasoning":10},"cost":0.001}"#)
        let counted = reader.parse(usage, state: &state, now: now)
        if case .usage(let key, let record, let billable)? = counted.first, counted.count == 1 {
            suite.expect(key == "dsh:eb7abe7f"
                            && record.provider == .dsh && record.model == "deepseek/deepseek-v4.1-flash"
                            && record.project == "app" && record.session == state.session
                            && record.tokens == AgentTokens(input: 100, cacheWrite: 20, cacheRead: 300, output: 40, reasoning: 10)
                            && record.cost == 0.001 && record.reportedCost && record.savings == 0
                            && billable.tokens == record.tokens,
                         "a DeepSeek usage line keeps its dedupe key, counters, model, project and reported price")
        } else {
            suite.expect(false, "a DeepSeek usage line counts exactly one response")
        }
        let missingRequest = line(#"{"v":1,"type":"usage","ts":1790088015000,"turn":3,"step":4,"model":"deepseek/deepseek-v4.1-flash","tokens":{"input":10,"output":5}}"#)
        if case .usage(let key, let record, _)? = reader.parse(missingRequest, state: &state, now: now).first {
            suite.expect(key == "dsh:session-7fe88e4c-4773-4582-ab38-d5b56f942811:3:4:1790088015.0"
                            && record.cost == nil && !record.reportedCost,
                         "a DeepSeek usage line without a response id is keyed by its place in the session")
        } else {
            suite.expect(false, "a DeepSeek usage line without a response id is counted")
        }
        let end = line(#"{"v":1,"type":"turn","ts":1790088020000,"turn":1,"phase":"end","completed":true}"#)
        suite.expect(reader.parse(end, state: &state, now: now)
                        == [.turnEnded(Date(timeIntervalSince1970: 1_790_088_020), completed: true, duration: nil)],
                     "a completed DeepSeek turn ends its turn")
        let aborted = line(#"{"v":1,"type":"turn","ts":1790088030000,"turn":2,"phase":"end","completed":false}"#)
        suite.expect(reader.parse(aborted, state: &state, now: now)
                        == [.turnEnded(Date(timeIntervalSince1970: 1_790_088_030), completed: false, duration: nil)],
                     "an aborted DeepSeek turn ends unfinished")
        let unknown = line(#"{"v":1,"type":"checkpoint","ts":1790088030000}"#)
        suite.expect(reader.parse(unknown, state: &state, now: now).isEmpty,
                     "an unknown DeepSeek line parses to nothing")
        let emptyModel = line(#"{"v":1,"type":"usage","ts":1790088040000,"turn":2,"step":1,"request":"m3","model":"","tokens":{"input":5,"output":1}}"#)
        suite.expect(reader.parse(emptyModel, state: &state, now: now).isEmpty,
                     "a DeepSeek usage line without a model is ignored")

        // A file that starts mid-session holds no metadata: only usage counts.
        var midway = AgentLogState()
        if case .usage(_, let record, _)? = reader.parse(usage, state: &midway, now: now).first {
            suite.expect(record.session.isEmpty && record.project.isEmpty,
                         "a DeepSeek file read from the middle counts its usage without a session or project")
        } else {
            suite.expect(false, "a DeepSeek file read from the middle still counts its usage")
        }

        var subagent = AgentLogState()
        let subheader = line(#"{"v":1,"type":"session","session":"s-sub","ts":1790088000000,"cwd":"/Users/me/code/app","parent":"session-7fe88e4c-4773-4582-ab38-d5b56f942811"}"#)
        suite.expect(reader.parse(subheader, state: &subagent, now: now).isEmpty && subagent.dshSubagent
                        && subagent.session == "s-sub" && subagent.project == "app",
                     "a DeepSeek session header marks a subagent session")
        suite.expect(reader.parse(start, state: &subagent, now: now).isEmpty
                        && reader.parse(end, state: &subagent, now: now).isEmpty,
                     "a DeepSeek subagent's turns never show as work")
        let subusage = line(#"{"v":1,"type":"usage","ts":1790088010000,"turn":1,"step":1,"request":"m2","model":"deepseek/deepseek-v4.1-flash","tokens":{"input":10,"output":5}}"#)
        if case .usage(_, let record, _)? = reader.parse(subusage, state: &subagent, now: now).first {
            suite.expect(record.provider == .dsh && record.session == "s-sub" && record.project == "app"
                            && record.tokens == AgentTokens(input: 10, output: 5) && record.cost == nil,
                         "a DeepSeek subagent's usage is counted without a turn")
        } else {
            suite.expect(false, "a DeepSeek subagent's usage line is counted")
        }

        let root = AgentLogRoot(provider: .dsh, url: URL(fileURLWithPath: "/Users/me/.vorssaint/agents/dsh", isDirectory: true))
        suite.expect(root.accepts(root.url.appending(path: "session-7fe88e4c.jsonl").path)
                        && !root.accepts(root.url.appending(path: "notes.txt").path),
                     "the DeepSeek feed admits the JSONL files in its folder and nothing else")
        suite.expect(AgentLogRoot.all(home: URL(fileURLWithPath: "/Users/me", isDirectory: true))
                        .first { $0.provider == .dsh }?.url.path == "/Users/me/.vorssaint/agents/dsh",
                     "the DeepSeek feed folder is read without configuration")
    }
}
