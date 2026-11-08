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
}
