// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CopilotAgentTests {
    private final class Log {
        let now = AgentTimestamp.parse("2026-09-27T15:10:00Z")!
        var state = AgentLogState()
        let store = AgentUsageStore()
        var sequence = 0

        init() { store.reportsTransitions = true }

        @discardableResult
        func feed(_ type: String, _ data: [String: Any] = [:], agent: String? = nil,
                  at seconds: TimeInterval = 0, id: String? = nil) -> [AgentUsageEvent] {
            sequence += 1
            var event: [String: Any] = ["type": type, "data": data, "id": id ?? "event-\(sequence)",
                                         "timestamp": now.addingTimeInterval(seconds).timeIntervalSince1970]
            if let agent { event["agentId"] = agent }
            // Data before envelope fields, whitespace and escaped slashes are
            // all valid JSON and must not change ownership or event type.
            let bytes = try! JSONSerialization.data(withJSONObject: event, options: [.sortedKeys, .prettyPrinted])
            return raw(bytes)
        }

        @discardableResult
        func raw(_ bytes: Data) -> [AgentUsageEvent] {
            store.apply(AgentLogParser.parseCopilot(bytes, state: &state, now: now), file: "events.jsonl",
                        provider: .copilot, tracksTurns: true, modified: now, now: now)
        }

        func start() {
            feed("session.start", ["sessionId": "demo", "selectedModel": "gpt-6-sol",
                                    "context": ["gitRoot": "/tmp/demo"]], at: -240)
            feed("user.message", ["content": "synthetic task"], at: -180)
            feed("assistant.turn_start", ["turnId": "0"], at: -179)
        }

        var requests: Int { store.records.reduce(0) { $0 + $1.requests } }
    }

    static func run(_ suite: TestSuite) {
        turns(suite)
        envelopes(suite)
        accounting(suite)
        requestIdentity(suite)
        unresolvedModels(suite)
        CopilotArchiveTests.run(suite)
    }

    private static func requestIdentity(_ suite: TestSuite) {
        let log = Log()
        log.start()
        log.feed("assistant.message", ["apiCallId": "call-1", "messageId": "chunk-1", "phase": "commentary"], at: -120)
        log.feed("assistant.message", ["apiCallId": "call-1", "messageId": "chunk-2", "phase": "response"], at: -60)
        log.feed("assistant.message", ["apiCallId": "call-1", "messageId": "chunk-2", "phase": "response"], at: -60)
        suite.expect(log.requests == 1 && log.store.records.first?.date == log.now.addingTimeInterval(-120),
                     "several Copilot message chunks and replays represent one API call at its original date")
        suite.expect(log.feed("assistant.turn_end", ["turnId": "0"]).count == 1 && !log.state.turnOpen,
                     "deduplicating Copilot request activity still processes the final chunk's lifecycle")
        log.feed("session.shutdown", ["modelMetrics": ["gpt-6-sol": ["requests": ["count": 1],
                                                                   "usage": ["inputTokens": 10]]]])
        suite.expect(log.requests == 1, "shutdown does not inflate a multi-chunk Copilot API call")
        log.feed("assistant.message", ["apiCallId": "call-2", "messageId": "chunk-3"])
        suite.expect(log.requests == 2, "different Copilot API call IDs count separately")
        log.feed("assistant.message", ["apiCallId": "call-2", "messageId": "chunk-4"], agent: "helper")
        suite.expect(log.requests == 3, "request identities are scoped to the emitting Copilot agent")
        log.feed("assistant.message", ["apiCallId": "", "messageId": "legacy-1"])
        log.feed("assistant.message", ["messageId": "legacy-1"])
        log.feed("assistant.message", ["messageId": "legacy-2"])
        log.feed("assistant.message", ["messageId": "call-1"])
        suite.expect(log.requests == 6,
                     "missing or empty Copilot API IDs retain message fallback without colliding with call IDs")
    }

    private static func unresolvedModels(_ suite: TestSuite) {
        let log = Log()
        log.start()
        log.feed("assistant.message", ["apiCallId": "root-call", "messageId": "root"])
        log.feed("assistant.message", ["apiCallId": "helper-call", "messageId": "helper-1"], agent: "helper", at: -86_400)
        log.feed("assistant.message", ["apiCallId": "helper-call", "messageId": "helper-2"], agent: "helper", at: -86_399)
        suite.expect(log.requests == 2 && log.store.records.filter { $0.model.isEmpty }.count == 1
                        && log.state.copilotRequests["gpt-6-sol"] == 1,
                     "model-less Copilot subagent chunks stay separate from the root model's request count")
        let metrics: [String: Any] = [
            "gpt-6-sol": ["requests": ["count": 1], "usage": ["inputTokens": 10]],
            "claude-sonnet-4.5": ["requests": ["count": 1], "usage": ["inputTokens": 20]]
        ]
        log.feed("session.shutdown", ["modelMetrics": metrics])
        suite.expect(log.requests == 2 && log.store.records.reduce(0) { $0 + $1.tokens.input } == 30,
                     "shutdown counts an unresolved Copilot subagent once while retaining actual model token totals")
        let recordCount = log.store.records.count
        log.feed("session.shutdown", ["modelMetrics": metrics])
        suite.expect(log.requests == 2 && log.store.records.count == recordCount,
                     "repeated Copilot shutdowns never spend the same unresolved-request credit twice")
        let before = log.store.snapshot(plans: [:], providers: [.copilot], now: log.now)
        log.feed("assistant.message", ["apiCallId": "helper-call", "messageId": "helper-3", "model": "claude-sonnet-4.5"],
                 agent: "helper")
        let after = log.store.snapshot(plans: [:], providers: [.copilot], now: log.now)
        let fresh = AgentUsageSummary.snapshot(records: log.store.records, limits: [:], live: [], plans: [:],
                                               providers: [.copilot], now: log.now)
        suite.expect(log.requests == 2 && log.store.records.filter { $0.model.isEmpty }.isEmpty
                        && log.store.records.first(where: { $0.model == "claude-sonnet-4.5" })?.date
                            == log.now.addingTimeInterval(-86_400),
                     "a later Copilot chunk can resolve its request's model without changing its count or original day")
        suite.expect(before.days.map { $0.total.requests } == after.days.map { $0.total.requests }
                        && after.periods == fresh.periods,
                     "late Copilot model attribution updates cached model shares without shifting historical activity")
        log.feed("session.shutdown", ["modelMetrics": metrics])
        suite.expect(log.requests == 2, "shutdown after late model attribution does not duplicate a request")
        log.feed("assistant.message", ["apiCallId": "new-helper-call", "messageId": "new-helper"], agent: "helper")
        var resumed = metrics
        resumed["claude-sonnet-4.5"] = ["requests": ["count": 2], "usage": ["inputTokens": 25]]
        log.feed("session.shutdown", ["modelMetrics": resumed])
        suite.expect(log.requests == 3 && log.store.records.reduce(0) { $0 + $1.tokens.input } == 35,
                     "resumed Copilot sessions reconcile new unresolved requests and cumulative token growth")

        let ambiguous = Log()
        ambiguous.feed("assistant.message", ["apiCallId": "unknown", "messageId": "unknown-1"], agent: "helper")
        let totals: [String: Any] = ["gpt-6-sol": ["requests": ["count": 2]],
                                     "claude-sonnet-4.5": ["requests": ["count": 2]]]
        ambiguous.feed("session.shutdown", ["modelMetrics": totals])
        suite.expect(ambiguous.requests == 4 && ambiguous.state.copilotRequests[""] == 2
                        && ambiguous.state.copilotRequests["gpt-6-sol"] == 1
                        && ambiguous.state.copilotRequests["claude-sonnet-4.5"] == 1,
                     "an unresolved request offsets the whole shutdown once, without guessing its model")
        ambiguous.feed("session.shutdown", ["modelMetrics": totals])
        suite.expect(ambiguous.requests == 4, "ambiguous multi-model shutdown reconciliation is idempotent")
        ambiguous.feed("assistant.message", ["apiCallId": "unknown", "messageId": "unknown-2", "model": "gpt-6-sol"],
                       agent: "helper")
        ambiguous.feed("session.shutdown", ["modelMetrics": totals])
        suite.expect(ambiguous.requests == 4, "resolving one ambiguous request cannot cause another shutdown top-up")
    }

    private static func turns(_ suite: TestSuite) {
        let log = Log()
        log.start()
        let tools: [[String: Any]] = [["toolCallId": "tool", "name": "read_file",
                                      "arguments": ["type": "assistant.turn_end", "agentId": "nested", "model": "wrong"]]]
        log.feed("assistant.message", ["messageId": "response-1", "content": "checking", "toolRequests": tools], at: -150)
        suite.expect(log.feed("assistant.turn_end", ["turnId": "0"], at: -120).isEmpty
                        && log.state.turnOpen && log.store.live.count == 1,
                     "Copilot tool iterations keep the user's task live without premature completion")
        let requests = log.requests
        log.feed("session.usage_checkpoint", ["totalPremiumRequests": 0], at: -119)
        log.feed("session.usage_checkpoint", ["totalPremiumRequests": 0.5], at: -118)
        suite.expect(log.requests == requests && requests == 1 && log.state.turnOpen,
                     "Copilot activity counts model responses independently of repeated premium checkpoints")
        log.feed("assistant.turn_start", ["turnId": "helper-turn"], agent: "helper", at: -115)
        log.feed("assistant.message", ["messageId": "helper-response", "model": "claude-opus-5.5", "content": "done"],
                 agent: "helper", at: -110)
        for type in ["abort", "assistant.turn_end", "session.model_change", "session.shutdown"] {
            suite.expect(log.feed(type, ["turnId": "helper-turn", "newModel": "wrong"], agent: "helper", at: -100).isEmpty
                            && log.state.turnOpen && log.state.model == "gpt-6-sol"
                            && log.store.live.first?.model == "gpt-6-sol",
                         "a Copilot subagent's \(type) never alters root work")
        }
        log.feed("assistant.turn_start", ["turnId": "1"], at: -90)
        log.feed("session.task_complete", ["success": true], at: -80)
        suite.expect(log.state.turnOpen && log.store.live.first?.started == log.now.addingTimeInterval(-180),
                     "the next Copilot iteration preserves the user's original task start")
        log.feed("assistant.message", ["messageId": "response-2", "content": "done", "toolRequests": []], at: -10)
        suite.expect(log.feed("assistant.turn_end", ["turnId": "0"], at: -5).isEmpty && log.state.turnOpen,
                     "an older Copilot turn end cannot close the current iteration")
        suite.expect(log.feed("assistant.turn_end", ["turnId": "1"])
                        == [.finished(provider: .copilot, duration: 180, cost: 0, tokens: 0, project: "demo")]
                        && log.store.live.isEmpty && !log.state.turnOpen && log.requests == 3,
                     "only the final root response finishes the whole Copilot task once")
        suite.expect(log.feed("assistant.turn_end", ["turnId": "1"]).isEmpty,
                     "repeated Copilot turn-end events do not repeat completion alerts")
        log.feed("assistant.turn_start", ["turnId": "2"])
        log.feed("assistant.message", ["messageId": "commentary", "phase": "commentary", "content": "continuing"])
        suite.expect(log.feed("assistant.turn_end", ["turnId": "2"]).isEmpty && log.state.turnOpen,
                     "a resumed root start restores activity and commentary alone does not complete it")
        log.feed("session.context_changed", ["cwd": "/tmp/other"])
        suite.expect(log.state.project == "other" && log.store.live.first?.project == "other",
                     "Copilot project changes reach the live task")
        suite.expect(log.feed("abort", ["reason": "cancelled"]).isEmpty && !log.state.turnOpen && log.store.live.isEmpty,
                     "root cancellation ends work without a successful completion alert")
    }

    private static func envelopes(_ suite: TestSuite) {
        let log = Log()
        log.start()
        let before = log.state
        let payload: [String: Any] = ["type": "assistant.turn_end", "agentId": "helper", "timestamp": 1,
                                      "data": ["turnId": "0"]]
        log.feed("tool.execution_complete", ["success": true, "result": ["structuredContent": payload]])
        suite.expect(log.state == before && log.requests == 0,
                     "nested structured tool output cannot impersonate a Copilot envelope")
        let content = String(repeating: #"\"type\":\"assistant.turn_end\"\\"#, count: 20_000)
        log.feed("assistant.message", ["messageId": "escaped", "content": content,
                                        "toolRequests": [["name": "tool", "arguments": payload]]])
        suite.expect(log.state.model == "gpt-6-sol" && log.state.turnOpen && !log.state.copilotFinalResponse,
                     "large escaped content and nested tool fields cannot override model or root identity")
        let malformed = log.state
        log.raw(Data(#"{"type":"assistant.message","data":{"content":"unfinished"#.utf8))
        log.raw(Data(#"{"type":"assistant.turn_end","type":"abort","data":{}}"#.utf8))
        suite.expect(log.state == malformed, "incomplete or ambiguous Copilot envelopes do not change state")
        log.raw(Data(#"{"t\u0079pe":"assistant.message","data":{"messageId":"unicode","model":"gpt\u002d6-sol","content":"done"}}"#.utf8))
        suite.expect(log.state.model == "gpt-6-sol" && log.state.copilotFinalResponse && log.requests == 2,
                     "escaped structural keys and string values remain valid Copilot metadata")
        let actual = Data(#" { "type" : "assistant.turn_start", "data" : { "turnId" : "next" } } "#.utf8)
        var framed = Data("prefix".utf8)
        framed.append(actual)
        framed.append(Data("suffix".utf8))
        suite.expect(AgentLogReader.copilotHistoryLine(framed, range: 6..<(6 + actual.count)),
                     "Copilot startup filtering respects line ranges and JSON whitespace")
        let nested = try! JSONSerialization.data(withJSONObject: ["type": "tool.execution_complete", "data": payload])
        suite.expect(!AgentLogReader.copilotHistoryLine(nested, range: 0..<nested.count),
                     "Copilot startup filtering rejects event names found only in nested payloads")
    }

    private static func accounting(_ suite: TestSuite) {
        let log = Log()
        log.start()
        log.feed("assistant.message", ["messageId": "same", "content": "done"], at: -120)
        log.feed("assistant.message", ["messageId": "same", "content": "done"], at: -120)
        suite.expect(log.requests == 1, "replayed Copilot responses do not count twice")
        let first: [String: Any] = ["gpt-6-sol": ["requests": ["count": 3],
            "usage": ["inputTokens": 11, "cacheReadTokens": 12, "cacheWriteTokens": 13, "outputTokens": 14, "reasoningTokens": 15]]]
        log.feed("session.shutdown", ["modelMetrics": first], id: "shutdown-1")
        let tokens = log.store.records.reduce(into: AgentTokens()) { $0 += $1.tokens }
        suite.expect(log.requests == 3 && tokens == AgentTokens(input: 11, cacheWrite: 13, cacheRead: 12, output: 14, reasoning: 15),
                     "Copilot shutdown fills missing requests and mandatory usage counters without double-counting responses")
        let count = log.store.records.count
        log.feed("session.shutdown", ["modelMetrics": first], id: "shutdown-repeat")
        suite.expect(log.requests == 3 && log.store.records.count == count,
                     "unchanged cumulative Copilot counters add no activity or tokens")
        let next: [String: Any] = ["gpt-6-sol": ["requests": ["count": 4],
            "usage": ["inputTokens": 20, "outputTokens": 20],
            "tokenDetails": ["input": ["tokenCount": 21], "cache_read": ["tokenCount": 12],
                             "cache_write": ["tokenCount": 13], "output": ["tokenCount": 24]]]]
        log.feed("session.shutdown", ["modelMetrics": next], id: "shutdown-2")
        suite.expect(log.requests == 4 && log.store.records.reduce(0) { $0 + $1.tokens.input } == 21
                        && log.store.records.reduce(0) { $0 + $1.tokens.output } == 24,
                     "Copilot prefers token details and adds only cumulative growth")

        let onlyShutdown = Log()
        onlyShutdown.feed("session.shutdown", ["modelMetrics": first])
        let snapshot = onlyShutdown.store.snapshot(plans: [:], providers: [.copilot], now: onlyShutdown.now)
        suite.expect(onlyShutdown.requests == 3 && snapshot.days.last?.total.requests == 3,
                     "a Copilot log without checkpoints still records its active day and requests")
        let noCount = Log()
        noCount.feed("session.shutdown", ["modelMetrics": ["gpt-6-sol": ["usage": ["inputTokens": 10]]]])
        suite.expect(noCount.requests == 1, "tokens prove Copilot activity even when the optional request count is absent")

        let price = Log()
        price.feed("session.shutdown", ["modelMetrics": ["claude-sonnet-4.5": ["requests": ["count": 3],
            "usage": ["inputTokens": 300_000, "outputTokens": 3_000, "cacheReadTokens": 0, "cacheWriteTokens": 0]]]])
        let expected = 3 * AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 100_000, output: 1_000)),
                                             model: "claude-sonnet-4.5").cost!
        suite.expectClose(price.store.records.compactMap(\.cost).reduce(0, +), expected,
                          "Copilot session totals do not trigger a per-request long-context premium")
        price.store.reprice()
        suite.expectClose(price.store.records.compactMap(\.cost).reduce(0, +), expected,
                          "refreshing the price list preserves Copilot's aggregate pricing semantics")
        let individual = AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 300_000, output: 3_000)),
                                           model: "claude-sonnet-4.5").cost!
        suite.expect(individual > expected, "individual long-context requests retain their existing premium")
        let activityOnly = Log()
        activityOnly.feed("assistant.message", ["messageId": "unpriced-model", "model": "unknown", "content": "done"])
        activityOnly.store.reprice()
        suite.expect(activityOnly.store.records.first?.cost == 0,
                     "repricing activity without token usage does not invent unknown model costs")

        let dates = Log()
        dates.start()
        dates.feed("assistant.message", ["messageId": "yesterday", "content": "done"], at: -86_400)
        dates.feed("assistant.message", ["messageId": "today", "content": "done"])
        dates.feed("session.usage_checkpoint", ["totalPremiumRequests": 0])
        let history = dates.store.snapshot(plans: [:], providers: [.copilot], now: dates.now)
        suite.expect(history.days.suffix(2).map { $0.total.requests } == [1, 1],
                     "Copilot activity remains on each response's date across a later accounting checkpoint")
    }
}
