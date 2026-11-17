// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Tests Command Code log parsing, record creation, turn handling, file admission,
/// idempotency, and store aggregation.
enum CommandCodeUsageTests {
    static func run(_ suite: TestSuite) {
        assistantUsage(suite)
        inputTokensClamp(suite)
        freeModelCost(suite)
        turnBoundaries(suite)
        rootAdmission(suite)
        malformedLines(suite)
        idempotentRead(suite)
        storeAggregation(suite)
        modelFallback(suite)
        realDataInvariants(suite)
    }

    private static func sessionLine(id: String = "test-session-1", cwd: String = "/path/to/my-project") -> Data {
        Data(#"{"type":"session","version":3,"id":"\#(id)","timestamp":"2026-11-16T07:00:00.000Z","cwd":"\#(cwd)"}"#.utf8)
    }

    private static func userMessage(text: String, id: String = "user-1", time: String = "2026-11-16T07:00:01.000Z") -> Data {
        Data(#"{"type":"message","id":"\#(id)","timestamp":"\#(time)","message":{"role":"user","content":[{"type":"text","text":"\#(text)"}]}}"#.utf8)
    }

    private static func toolResultMessage(id: String = "tool-1", time: String = "2026-11-16T07:00:02.000Z") -> Data {
        Data(#"{"type":"message","id":"\#(id)","timestamp":"\#(time)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"call-1","content":[{"type":"text","text":"result"}]}]}}"#.utf8)
    }

    private static func assistantMessage(id: String = "asst-1",
                                         time: String = "2026-11-16T07:00:03.000Z",
                                         model: String = "deepseek/deepseek-v4-flash",
                                         hasToolUse: Bool = false,
                                         inputTokens: Int = 1000,
                                         outputTokens: Int = 200,
                                         cacheReadTokens: Int = 800,
                                         cacheWriteTokens: Int = 50,
                                         costUsd: Double = 0.0015) -> Data {
        let content: String
        if hasToolUse {
            content = #"[{"type":"text","text":"thinking..."},{"type":"tool_use","id":"call-1","name":"exec"}]"#
        } else {
            content = #"[{"type":"text","text":"done"}]"#
        }
        return Data("""
        {"type":"message","id":"\(id)","timestamp":"\(time)","model":"\(model)","message":{"role":"assistant","content":\(content)},"usage":{"inputTokens":\(inputTokens),"outputTokens":\(outputTokens),"cacheReadTokens":\(cacheReadTokens),"cacheWriteTokens":\(cacheWriteTokens),"costUsd":\(costUsd)}}
        """.utf8)
    }

    // 1. assistant usage => record with model, project from cwd, tokens, cost reportedCost true
    private static func assistantUsage(_ suite: TestSuite) {
        suite.run("Command Code assistant usage") {
            let reader = CommandCodeReader()
            var state = AgentLogState()
            let now = Date()

            _ = reader.parse(sessionLine(id: "sess-abc", cwd: "/Users/dev/repos/awesome-app"), state: &state, now: now)
            suite.expect(state.session == "sess-abc", "session id recorded from line 0")
            suite.expect(state.project == "awesome-app", "project name derived from cwd")

            let line = assistantMessage(
                id: "msg-123",
                time: "2026-11-16T08:00:00.000Z",
                model: "deepseek/deepseek-v4-flash",
                hasToolUse: false,
                inputTokens: 1000,
                outputTokens: 250,
                cacheReadTokens: 800,
                cacheWriteTokens: 60,
                costUsd: 0.0025
            )

            let entries = reader.parse(line, state: &state, now: now)
            let usageEntry = entries.first(where: {
                if case .usage = $0 { return true }
                return false
            })

            suite.expect(usageEntry != nil, "emits usage entry")
            guard case .usage(let key, let record, let billable)? = usageEntry else { return }

            suite.expect(key == "commandcode:sess-abc:msg-123", "key matches commandcode:<session>:<msgId>")
            suite.expect(record.provider == .commandcode, "provider is commandcode")
            suite.expect(record.model == "deepseek/deepseek-v4-flash", "model matches")
            suite.expect(record.project == "awesome-app", "project matches state")
            suite.expect(record.session == "sess-abc", "session matches state")
            suite.expect(record.tokens.input == 200, "input tokens = inputTokens - cacheReadTokens (1000 - 800 = 200)")
            suite.expect(record.tokens.cacheRead == 800, "cache read tokens match")
            suite.expect(record.tokens.cacheWrite == 60, "cache write tokens match")
            suite.expect(record.tokens.output == 250, "output tokens match")
            suite.expect(record.cost == 0.0025, "cost matches costUsd")
            suite.expect(record.savings == 0, "savings are 0")
            suite.expect(record.reportedCost == true, "reportedCost is true")
            suite.expect(billable.tokens == record.tokens, "billable tokens match record tokens")
        }
    }

    // 2. inputTokens < cacheReadTokens => input 0, never negative
    private static func inputTokensClamp(_ suite: TestSuite) {
        suite.run("Command Code inputTokens clamped to 0") {
            let reader = CommandCodeReader()
            var state = AgentLogState()
            let now = Date()

            _ = reader.parse(sessionLine(), state: &state, now: now)
            let line = assistantMessage(inputTokens: 500, cacheReadTokens: 700)
            let entries = reader.parse(line, state: &state, now: now)

            guard case .usage(_, let record, _)? = entries.first(where: {
                if case .usage = $0 { return true }
                return false
            }) else {
                suite.expect(false, "expected usage entry")
                return
            }

            suite.expect(record.tokens.input == 0, "clamped to 0 when inputTokens < cacheReadTokens")
            suite.expect(record.tokens.cacheRead == 700, "cacheRead preserved")
        }
    }

    // 3. free model costUsd 0 => cost 0 (not nil)
    private static func freeModelCost(_ suite: TestSuite) {
        suite.run("Command Code free model cost 0 is not nil") {
            let reader = CommandCodeReader()
            var state = AgentLogState()
            let now = Date()

            _ = reader.parse(sessionLine(), state: &state, now: now)
            let line = assistantMessage(model: "poolside/laguna-s-2.1-free", costUsd: 0)
            let entries = reader.parse(line, state: &state, now: now)

            guard case .usage(_, let record, _)? = entries.first(where: {
                if case .usage = $0 { return true }
                return false
            }) else {
                suite.expect(false, "expected usage entry")
                return
            }

            suite.expect(record.cost == 0.0, "cost is exactly 0.0, not nil")
            suite.expect(record.reportedCost == true, "reportedCost is true for free model")
        }
    }

    // 4. tool_result-only user msg does not start a turn; user text starts one; final assistant (no tool_use) ends it
    private static func turnBoundaries(_ suite: TestSuite) {
        suite.run("Command Code turn boundaries") {
            let reader = CommandCodeReader()
            var state = AgentLogState()
            let now = Date()

            _ = reader.parse(sessionLine(), state: &state, now: now)

            // tool_result-only user message does not start a turn
            let toolOnly = toolResultMessage()
            let toolEntries = reader.parse(toolOnly, state: &state, now: now)
            suite.expect(toolEntries.isEmpty, "tool_result-only emits no entries")
            suite.expect(!state.turnOpen, "turn is not open")

            // user text message starts a turn
            let userPrompt = userMessage(text: "Hello assistant")
            let promptEntries = reader.parse(userPrompt, state: &state, now: now)
            suite.expect(state.turnOpen, "turn is now open")
            let hasTurnBegan = promptEntries.contains {
                if case .turnBegan = $0 { return true }
                return false
            }
            suite.expect(hasTurnBegan, "emits .turnBegan")

            // assistant with tool_use continues turn
            let asstTool = assistantMessage(id: "asst-tool", hasToolUse: true)
            let asstToolEntries = reader.parse(asstTool, state: &state, now: now)
            suite.expect(state.turnOpen, "turn remains open")
            let hasTurnActive = asstToolEntries.contains {
                if case .turnActive = $0 { return true }
                return false
            }
            suite.expect(hasTurnActive, "assistant with tool_use emits .turnActive")

            // tool_result inside open turn emits nothing
            let innerTool = toolResultMessage(id: "tool-2")
            let innerToolEntries = reader.parse(innerTool, state: &state, now: now)
            suite.expect(innerToolEntries.isEmpty, "inner tool_result emits nothing")
            suite.expect(state.turnOpen, "turn still open")

            // final assistant (no tool_use) ends the turn
            let asstFinal = assistantMessage(id: "asst-final", hasToolUse: false)
            let finalEntries = reader.parse(asstFinal, state: &state, now: now)
            suite.expect(!state.turnOpen, "turn is closed")
            let hasTurnEnded = finalEntries.contains {
                if case .turnEnded = $0 { return true }
                return false
            }
            suite.expect(hasTurnEnded, "final assistant emits .turnEnded")
        }
    }

    // 5. checkpoints and hooks-audit files not admitted by AgentLogRoot.accepts; normal file admitted; wrong depth rejected
    private static func rootAdmission(_ suite: TestSuite) {
        suite.run("Command Code AgentLogRoot admission rules") {
            let root = AgentLogRoot(provider: .commandcode, url: URL(fileURLWithPath: "/Users/test/.commandcode/projects"))

            // Valid: <root>/<project>/<uuid>.jsonl
            suite.expect(root.accepts("/Users/test/.commandcode/projects/my-proj/session-1.jsonl"),
                         "admits normal 2-component file")

            // Checkpoints rejected
            suite.expect(!root.accepts("/Users/test/.commandcode/projects/my-proj/session-1.checkpoints.jsonl"),
                         "rejects checkpoints file")

            // Hooks audit rejected
            suite.expect(!root.accepts("/Users/test/.commandcode/projects/my-proj/hooks-audit-123.jsonl"),
                         "rejects hooks-audit file")

            // Non-jsonl rejected
            suite.expect(!root.accepts("/Users/test/.commandcode/projects/my-proj/session-1.meta.json"),
                         "rejects non-jsonl file")
            suite.expect(!root.accepts("/Users/test/.commandcode/projects/my-proj/config.json"),
                         "rejects config.json")

            // Hidden directory rejected
            suite.expect(!root.accepts("/Users/test/.commandcode/projects/.hidden/session-1.jsonl"),
                         "rejects hidden project directory")

            // Hidden file rejected
            suite.expect(!root.accepts("/Users/test/.commandcode/projects/my-proj/.hidden.jsonl"),
                         "rejects hidden file")

            // Wrong depth rejected (1 component)
            suite.expect(!root.accepts("/Users/test/.commandcode/projects/session-1.jsonl"),
                         "rejects 1-component path directly under root")

            // Wrong depth rejected (3 components)
            suite.expect(!root.accepts("/Users/test/.commandcode/projects/my-proj/sub/session-1.jsonl"),
                         "rejects 3-component path in nested subfolder")
        }
    }

    // 6. malformed line, empty line, missing usage => no entries, no crash
    private static func malformedLines(_ suite: TestSuite) {
        suite.run("Command Code malformed and missing lines") {
            let reader = CommandCodeReader()
            var state = AgentLogState()
            let now = Date()

            // Empty line
            suite.expect(reader.parse(Data(), state: &state, now: now).isEmpty, "empty data returns empty")
            suite.expect(reader.parse(Data("   \n".utf8), state: &state, now: now).isEmpty, "whitespace returns empty")

            // Malformed JSON
            suite.expect(reader.parse(Data("not json".utf8), state: &state, now: now).isEmpty, "not json returns empty")
            suite.expect(reader.parse(Data("{\"type\":\"message\"".utf8), state: &state, now: now).isEmpty, "truncated json returns empty")

            // Assistant message missing usage
            let noUsage = Data(#"{"type":"message","id":"m1","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}"#.utf8)
            suite.expect(reader.parse(noUsage, state: &state, now: now).isEmpty, "assistant missing usage returns empty")

            // Irrelevant message types
            let otherType = Data(#"{"type":"notification","data":{"foo":"bar"}}"#.utf8)
            suite.expect(reader.parse(otherType, state: &state, now: now).isEmpty, "unrelated type returns empty")
        }
    }

    // 7. Re-reading the same file does not double count (store level)
    private static func idempotentRead(_ suite: TestSuite) {
        suite.run("Command Code store idempotent read") {
            let store = AgentUsageStore()
            let reader = CommandCodeReader()
            var state = AgentLogState()
            let now = Date()

            let sess = sessionLine(id: "idem-session", cwd: "/Users/dev/repos/idem-proj")
            let user = userMessage(text: "Hello", id: "u-1")
            let asst = assistantMessage(id: "a-1", costUsd: 0.005)

            let lines = [sess, user, asst]
            var entries: [AgentLogEntry] = []
            for line in lines {
                entries.append(contentsOf: reader.parse(line, state: &state, now: now))
            }

            let file = "/Users/dev/.commandcode/projects/idem-proj/idem-session.jsonl"
            store.apply(entries, file: file, provider: .commandcode, tracksTurns: true, modified: now, now: now)

            suite.expect(store.records.count == 1, "first read adds 1 record")
            suite.expect(store.records.first?.cost == 0.005, "cost recorded")

            // Re-read with same entries (simulating log re-read or cursor restart)
            store.apply(entries, file: file, provider: .commandcode, tracksTurns: true, modified: now, now: now)
            suite.expect(store.records.count == 1, "re-read does not double count records")
        }
    }

    // 8. Aggregation through the store/snapshot: models and projects appear in period usage
    private static func storeAggregation(_ suite: TestSuite) {
        suite.run("Command Code store aggregation") {
            let store = AgentUsageStore()
            let reader = CommandCodeReader()
            var state = AgentLogState()
            let now = Date()

            let sess = sessionLine(id: "agg-sess", cwd: "/Users/dev/repos/my-service")
            let user = userMessage(text: "Do task", id: "u-agg")
            let asst = assistantMessage(id: "a-agg", model: "deepseek/deepseek-v4-flash", costUsd: 0.010)

            var entries: [AgentLogEntry] = []
            for line in [sess, user, asst] {
                entries.append(contentsOf: reader.parse(line, state: &state, now: now))
            }

            let file = "/Users/dev/.commandcode/projects/my-service/agg-sess.jsonl"
            store.apply(entries, file: file, provider: .commandcode, tracksTurns: true, modified: now, now: now)

            let snapshot = store.snapshot(plans: [:], providers: [.commandcode], now: now)
            let periodUsage = snapshot.usage(.month)

            suite.expect(snapshot.seen.contains(.commandcode), "commandcode marked seen")
            suite.expect(snapshot.lastActivity[.commandcode] != nil, "lastActivity set for commandcode")
            suite.expect(periodUsage.total.cost > 0.009, "period cost aggregated")

            let modelShares = periodUsage.models
            let foundModel = modelShares.contains { $0.id.contains("deepseek-v4-flash") }
            suite.expect(foundModel, "model appears in period usage models")

            let projectShares = periodUsage.projects
            let foundProject = projectShares.contains { $0.id == "my-service" }
            suite.expect(foundProject, "project appears in period usage projects")
        }
    }

    // 9. Model fallback when assistant line lacks model
    private static func modelFallback(_ suite: TestSuite) {
        suite.run("Command Code model fallback to state.model") {
            let reader = CommandCodeReader()
            var state = AgentLogState()
            let now = Date()

            _ = reader.parse(sessionLine(), state: &state, now: now)

            let firstMsg = assistantMessage(id: "m-1", model: "deepseek/deepseek-v4-flash")
            _ = reader.parse(firstMsg, state: &state, now: now)
            suite.expect(state.model == "deepseek/deepseek-v4-flash", "state.model is populated from first message")

            // Second message lacks model key
            let noModelMsg = Data("""
            {"type":"message","id":"m-2","timestamp":"2026-11-16T08:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"usage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":0,"cacheWriteTokens":0,"costUsd":0.0001}}
            """.utf8)

            let entries = reader.parse(noModelMsg, state: &state, now: now)
            guard case .usage(_, let record, _)? = entries.first(where: {
                if case .usage = $0 { return true }
                return false
            }) else {
                suite.expect(false, "expected usage entry")
                return
            }

            suite.expect(record.model == "deepseek/deepseek-v4-flash", "record model falls back to state.model")
        }
    }

    // 10. Real data invariants (skips if dir absent; no machine-specific counts)
    private static func realDataInvariants(_ suite: TestSuite) {
        suite.run("Command Code real data invariants") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let projectsDir = home.appending(path: ".commandcode/projects")
            guard FileManager.default.fileExists(atPath: projectsDir.path) else { return }

            let root = AgentLogRoot(provider: .commandcode, url: projectsDir)
            guard let enumerator = FileManager.default.enumerator(at: projectsDir,
                                                                 includingPropertiesForKeys: [.isRegularFileKey],
                                                                 options: [.skipsHiddenFiles]) else { return }

            let reader = CommandCodeReader()
            let now = Date()
            var verifiedRecords = 0

            while let url = enumerator.nextObject() as? URL {
                guard root.accepts(url.path), let data = try? Data(contentsOf: url) else { continue }
                var state = AgentLogState()
                data.withUnsafeBytes { raw in
                    var start = 0
                    let bytes = raw.bindMemory(to: UInt8.self)
                    for i in 0..<bytes.count {
                        if bytes[i] == 10 {
                            let lineData = data.subdata(in: start..<i)
                            start = i + 1
                            let entries = reader.parse(lineData, state: &state, now: now)
                            for entry in entries {
                                if case .usage(_, let record, _) = entry {
                                    verifiedRecords += 1
                                    suite.expect(record.tokens.input >= 0, "input tokens non-negative")
                                    suite.expect(!record.model.isEmpty, "model non-empty")
                                    suite.expect(!record.project.isEmpty, "project non-empty")
                                }
                            }
                        }
                    }
                    if start < bytes.count {
                        let lineData = data.subdata(in: start..<bytes.count)
                        let entries = reader.parse(lineData, state: &state, now: now)
                        for entry in entries {
                            if case .usage(_, let record, _) = entry {
                                verifiedRecords += 1
                                suite.expect(record.tokens.input >= 0, "input tokens non-negative")
                                suite.expect(!record.model.isEmpty, "model non-empty")
                                suite.expect(!record.project.isEmpty, "project non-empty")
                            }
                        }
                    }
                }
            }
            if verifiedRecords > 0 {
                suite.expect(verifiedRecords > 0, "invariants verified on real usage entries")
            }
        }
    }
}
