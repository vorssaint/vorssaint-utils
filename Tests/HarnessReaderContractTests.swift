// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The reader protocol move preserves parsing: every harness reader returns
/// the same entries and end state as the `AgentLogParser` entry point it
/// replaces, and every provider resolves to the reader for its own harness.
enum HarnessReaderContractTests {
    static func run(_ suite: TestSuite) {
        readersCoverProviders(suite)
        claudeGolden(suite)
        codexGolden(suite)
        openCodeGolden(suite)
        copilotGolden(suite)
        readersMatchParser(suite)
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

    /// Every reader returns the entry points' output line for line, with the
    /// same state carried across lines, so the move is byte-equivalent.
    private static func readersMatchParser(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        let timestamp = now.timeIntervalSince1970
        let claude = [
            #"{"type":"user","timestamp":\#(timestamp),"sessionId":"s","cwd":"/Users/me/code/app","message":{"content":"work"}}"#,
            #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":2}}}"#,
            #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r2","message":{"id":"m2","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":7}}}"#,
            #"{"type":"user","timestamp":\#(timestamp),"sessionId":"s","isSidechain":true,"message":{"content":"work"}}"#,
        ]
        check(suite, provider: .claude, lines: claude, now: now)
        let codex = [
            #"{"type":"session_meta","timestamp":\#(timestamp),"payload":{"id":"s","cwd":"/tmp/example"}}"#,
            #"{"type":"turn_context","timestamp":\#(timestamp),"payload":{"model":"gpt-5.2-codex","service_tier":"fast"}}"#,
            #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"task_started"}}"#,
            #"{"type":"token_usage_record","timestamp":\#(timestamp),"payload":{"response_id":"r","usage":{"input_tokens":10,"output_tokens":2}}}"#,
            #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"token_count","rate_limits":{"plan_type":"pro","primary":{"used_percent":42,"window_minutes":300}}}}"#,
            #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"task_complete","duration_ms":20000}}"#,
        ]
        check(suite, provider: .codex, lines: codex, now: now)
        let opencode = [
            #"{"session_id":"s_oc_1","time_created":1790088000,"directory":"/Users/me/code/backend","role":"user","parts":[{"type":"text","text":"go"}]}"#,
            #"{"id":"msg_1","session_id":"s_oc_1","time_created":1790088005,"directory":"/Users/me/code/backend","role":"assistant","model_id":"stealth/ox-alpha","provider_id":"relay","cost":0.0042,"tokens":{"total":1250,"input":1000,"output":200,"reasoning":50,"cache":{"read":50,"write":0}},"finish":"tool-calls"}"#,
            #"{"id":"msg_2","session_id":"s_oc_1","time_created":1790088020,"directory":"/Users/me/code/backend","role":"assistant","model_id":"stealth/ox-alpha","provider_id":"relay","cost":0.0015,"tokens":{"total":500,"input":400,"output":100,"reasoning":0,"cache":{"read":0,"write":0}},"finish":"stop"}"#,
            #"{"id":"msg_3","session_id":"s_oc_1","time_created":1790088030,"directory":"/Users/me/code/backend","role":"compaction","model":{"id":"stealth/ox-alpha"},"cost":0.0001,"tokens":{"input":10,"output":5}}"#,
        ]
        check(suite, provider: .opencode, lines: opencode, now: now)
        let copilot = [
            #"{"id":"start","timestamp":\#(timestamp),"type":"session.start","data":{"sessionId":"s","selectedModel":"gpt-6-sol","context":{"cwd":"/tmp/example"}}}"#,
            #"{"id":"turn","timestamp":\#(timestamp),"type":"user.message","data":{"turnId":"0","content":"private"}}"#,
            #"{"id":"message","timestamp":\#(timestamp),"type":"assistant.message","data":{"model":"gpt-6-sol","content":"private"}}"#,
            #"{"id":"end","timestamp":\#(timestamp),"type":"assistant.turn_end","data":{"turnId":"0"}}"#,
            #"{"id":"usage","timestamp":\#(timestamp),"type":"session.shutdown","data":{"modelMetrics":{"gpt-6-sol":{"requests":{"count":1},"tokenDetails":{"input":{"tokenCount":10},"cache_read":{"tokenCount":20},"cache_write":{"tokenCount":0},"output":{"tokenCount":5}},"usage":{"reasoningTokens":2}}}}}"#,
        ]
        check(suite, provider: .copilot, lines: copilot, now: now)
    }

    private static func check(_ suite: TestSuite, provider: AgentProvider, lines: [String], now: Date) {
        var viaReader = AgentLogState()
        var viaParser = AgentLogState()
        let reader = provider.reader
        for (index, json) in lines.enumerated() {
            let data = line(json)
            let left = reader.parse(data, state: &viaReader, now: now)
            let right: [AgentLogEntry]
            switch provider {
            case .claude: right = AgentLogParser.parseClaude(data, state: &viaParser, now: now)
            case .codex: right = AgentLogParser.parseCodex(data, state: &viaParser, now: now)
            case .opencode: right = AgentLogParser.parseOpenCode(data, state: &viaParser, now: now)
            case .copilot: right = AgentLogParser.parseCopilot(data, state: &viaParser, now: now)
            // Muse arrived with the reader protocol and never had a parser entry point to match.
            case .muse: return
            }
            suite.expect(left == right, "\(provider.rawValue) reader matches line \(index)")
            suite.expect(viaReader == viaParser, "\(provider.rawValue) reader keeps line \(index) state")
        }
    }
}
