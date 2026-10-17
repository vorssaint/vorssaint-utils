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
        kiroGolden(suite)
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

    private static func kiroGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.kiro.reader
        let began = Date(timeIntervalSince1970: 1_790_088_000)
        let header = line(#"{"type":"kiro.session","session":"sess_k","workspace":"/Users/me/code/app","model":"claude-sonnet-5"}"#)
        suite.expect(reader.parse(header, state: &state, now: now).isEmpty
                        && state.session == "sess_k" && state.project == "app" && state.model == "claude-sonnet-5",
                     "a Kiro session header names the session, project and model")
        let prompt = line(#"{"id":"u","timestamp":"2026-09-22T14:40:00.000Z","payload":{"type":"user","content":[{"kind":"text","data":"private"}]}}"#)
        suite.expect(reader.parse(prompt, state: &state, now: now).isEmpty,
                     "a Kiro prompt alone opens no turn; its turn start does")
        let start = line(#"{"id":"s","timestamp":"2026-09-22T14:40:00.000Z","payload":{"type":"turn_start","executionId":"e1"}}"#)
        suite.expect(reader.parse(start, state: &state, now: now)
                        == [.turnBegan(began), .turnContext(model: "claude-sonnet-5", project: "app")],
                     "a Kiro turn start opens its turn with its context")
        let reasoning = line(#"{"id":"r","timestamp":"2026-09-22T14:40:05.000Z","payload":{"type":"assistant","operationType":"Reasoning","content":"private","reasoningModelId":"qdev::claude-opus-5.5"}}"#)
        suite.expect(reader.parse(reasoning, state: &state, now: now)
                        == [.turnContext(model: "claude-opus-5.5", project: "app"),
                            .turnActive(began.addingTimeInterval(5))],
                     "a Kiro reply names the model without its backend prefix")
        let summary = line(#"{"id":"m","timestamp":"2026-09-22T14:40:20.000Z","payload":{"type":"usage_summary","promptTurnSummaries":[{"unit":"credit","unitPlural":"credits","usage":1.5,"usedTools":["read"]}],"elapsedTime":20000,"status":"success","executionId":"e1","requestIds":["a","b"]}}"#)
        let record = AgentUsageRecord(provider: .kiro, date: began.addingTimeInterval(20), model: "claude-opus-5.5",
                                      project: "app", session: "sess_k", requests: 2, tokens: AgentTokens(),
                                      cost: 0, savings: 0, reportedCost: true, credits: 1.5)
        suite.expect(reader.parse(summary, state: &state, now: now)
                        == [.usage(key: "kiro:sess_k:e1", record: record, billable: AgentBillable(isAggregate: true))],
                     "a Kiro usage summary records its requests at no cost: the plan covers its credits")
        let empty = line(#"{"id":"z","timestamp":"2026-09-22T14:40:20.000Z","payload":{"type":"usage_summary","promptTurnSummaries":[],"status":"aborted","executionId":"e0"}}"#)
        suite.expect(reader.parse(empty, state: &state, now: now).isEmpty,
                     "a Kiro summary without credits or requests records nothing")
        let end = line(#"{"id":"t","timestamp":"2026-09-22T14:40:21.000Z","payload":{"type":"turn_end","stopReason":"end_turn","executionId":"e1"}}"#)
        suite.expect(reader.parse(end, state: &state, now: now)
                        == [.turnEnded(began.addingTimeInterval(21), completed: true, duration: nil)] && !state.turnOpen,
                     "a Kiro turn end finishes its turn")
        _ = reader.parse(start, state: &state, now: now)
        let cancelled = line(#"{"id":"c","timestamp":"2026-09-22T14:40:30.000Z","payload":{"type":"turn_end","stopReason":"cancelled"}}"#)
        suite.expect(reader.parse(cancelled, state: &state, now: now)
                        == [.turnEnded(began.addingTimeInterval(30), completed: false, duration: nil)],
                     "a cancelled Kiro turn ends unfinished")
        var legacy = AgentLogState()
        let turn = line(#"{"type":"kiro.legacy_turn","session":"old","cwd":"/Users/me/code/cli","end":"2026-09-22T12:01:00.000Z","model":"claude-sonnet-5","credits":0.5,"requests":3}"#)
        guard case .usage(let key, let old, _)? = reader.parse(turn, state: &legacy, now: now).first else {
            suite.expect(false, "an older Kiro session's turn records its usage")
            return
        }
        suite.expect(key == "kiro:old:2026-09-22T12:01:00.000Z" && old.project == "cli" && old.requests == 3
                        && old.cost == 0 && old.credits == 0.5 && old.reportedCost && old.tokens == AgentTokens(),
                     "an older Kiro session's turn is recorded under its end time")
    }
}
