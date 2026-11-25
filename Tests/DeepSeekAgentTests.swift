import Foundation

enum DeepSeekAgentTests {
    static func run(_ suite: TestSuite) {
        headerAndTurns(suite)
        usage(suite)
        lifecycle(suite)
        seededHistory(suite)
        subagents(suite)
    }

    private static let now = Date(timeIntervalSince1970: 1_790_088_100)
    private static let began = Date(timeIntervalSince1970: 1_790_088_000)
    private static let ended = Date(timeIntervalSince1970: 1_790_088_020)
    private static let header = #"{"type":"session","version":4,"id":"session-one","cwd":"/Users/example/code/project"}"#
    private static let start = #"{"type":"turn/start","time":1790088000000,"seq":1,"data":{}}"#
    private static let response = #"{"type":"assistant/message","time":1790088010000,"seq":5,"data":{"message":{"source":{"model":"deepseek-v4-pro"}},"usage":{"inputTokens":120,"cacheReadTokens":80,"cacheWriteTokens":20,"outputTokens":40,"reasoningTokens":15}}}"#

    private static func parse(_ json: String, state: inout AgentLogState) -> [AgentLogEntry] {
        DeepSeekReader().parse(Data(json.utf8), state: &state, now: now)
    }

    private static func headerAndTurns(_ suite: TestSuite) {
        var state = AgentLogState()
        suite.expect(parse(header, state: &state).isEmpty
                        && state.session == "session-one" && state.project == "project",
                     "a DeepSeek v4 header names its session and working project")
        suite.expect(parse(start, state: &state) == [.turnBegan(began), .turnContext(model: "", project: "project")],
                     "DeepSeek timestamps in milliseconds open the turn at the correct instant")
        for reason in ["completed", "max-tokens", "aborted", "error"] {
            _ = parse(start, state: &state)
            let end = #"{"type":"turn/end","time":1790088020000,"data":{"reason":{"kind":"\#(reason)"}}}"#
            suite.expect(parse(end, state: &state)
                            == [.turnEnded(ended, completed: reason == "completed" || reason == "max-tokens", duration: nil)],
                         "DeepSeek \(reason) ends its turn with the actual completion status")
            suite.expect(!state.turnOpen && parse(end, state: &state).isEmpty,
                         "a repeated DeepSeek turn end never reports a second completion")
        }
    }

    private static func usage(_ suite: TestSuite) {
        var state = AgentLogState()
        _ = parse(header, state: &state)
        _ = parse(start, state: &state)
        let entries = parse(response, state: &state)
        guard let first = entries.first, case .usage(let key, let record, let billable) = first else {
            suite.expect(false, "a DeepSeek assistant response exposes its usage counters")
            return
        }
        suite.expect(key == "deepseek:session-one:5" && record.provider == .deepseek
                        && record.session == "session-one" && record.project == "project"
                        && record.model == "deepseek-v4-pro" && state.model == record.model,
                     "DeepSeek usage retains provider, session, sequence, model and project identity")
        suite.expect(record.tokens == AgentTokens(input: 120, cacheWrite: 20, cacheRead: 80, output: 40, reasoning: 15)
                        && record.tokens.prompt == 220 && record.tokens.total == 260
                        && billable.tokens == record.tokens,
                     "DeepSeek uncached input and cache traffic remain separate without double-counting reasoning")
        suite.expect(entries.last == .turnActive(Date(timeIntervalSince1970: 1_790_088_010)),
                     "a DeepSeek response keeps an open turn active rather than completing it")
        let duplicate = parse(response, state: &state)
        suite.expect(duplicate == entries, "replaying a DeepSeek sequence preserves the same deduplication identity")
        let store = AgentUsageStore()
        store.apply(entries, file: "original", provider: .deepseek, tracksTurns: true, modified: now, now: now)
        store.apply(duplicate, file: "copied", provider: .deepseek, tracksTurns: true, modified: now, now: now)
        suite.expect(store.records.count == 1 && store.records.first?.tokens.total == 260,
                     "the shared store counts a replayed DeepSeek sequence only once across files")
        let noSequence = response.replacingOccurrences(of: #","seq":5"#, with: "")
        suite.expect(!parse(noSequence, state: &state).contains { if case .usage = $0 { return true }; return false },
                     "DeepSeek responses without a stable sequence never create billable records")
    }

    private static func lifecycle(_ suite: TestSuite) {
        var state = AgentLogState()
        suite.expect(parse(start, state: &state).isEmpty, "DeepSeek event lines need a supported session header")
        for version in [3, 5] {
            _ = parse(#"{"type":"session","version":\#(version),"id":"unsupported"}"#, state: &state)
            suite.expect(parse(start, state: &state).isEmpty && parse(response, state: &state).isEmpty,
                         "unsupported DeepSeek session version \(version) is ignored")
        }
        _ = parse(header, state: &state)
        _ = parse(start, state: &state)
        for type in ["step/start", "step/end", "tool/call", "tool/result"] {
            let entries = parse(#"{"type":"\#(type)","time":1790088010000,"data":{}}"#, state: &state)
            suite.expect(entries == [.turnActive(Date(timeIntervalSince1970: 1_790_088_010))] && state.turnOpen,
                         "DeepSeek \(type) signals activity and never prematurely completes a turn")
        }
    }

    private static func seededHistory(_ suite: TestSuite) {
        var state = AgentLogState()
        _ = parse(#"{"type":"session","version":4,"id":"seeded","cwd":"/tmp/project","isSeeded":true}"#, state: &state)
        suite.expect(parse(start, state: &state).isEmpty && parse(response, state: &state).isEmpty,
                     "inherited DeepSeek history creates neither live turns nor duplicated usage")
        _ = parse(#"{"type":"session/end-seed","data":{"inherited":false}}"#, state: &state)
        suite.expect(parse(start, state: &state).isEmpty,
                     "a non-inherited end-seed marker does not release inherited history")
        _ = parse(#"{"type":"session/end-seed","data":{"inherited":true}}"#, state: &state)
        suite.expect(parse(start, state: &state).first == .turnBegan(began) && !parse(response, state: &state).isEmpty,
                     "only the inherited end-seed boundary admits new DeepSeek work")
    }

    private static func subagents(_ suite: TestSuite) {
        var state = AgentLogState()
        _ = parse(#"{"type":"session","version":4,"id":"child","cwd":"/tmp/project","delegationDepth":1}"#, state: &state)
        suite.expect(parse(start, state: &state).isEmpty && !state.turnOpen,
                     "a delegated DeepSeek subagent never opens a separate live root turn")
        let entries = parse(response, state: &state)
        suite.expect(entries.count == 1 && entries.contains { if case .usage = $0 { return true }; return false },
                     "a DeepSeek subagent contributes usage without manufacturing a live turn")
        suite.expect(parse(#"{"type":"turn/end","time":1790088020000,"data":{"reason":{"kind":"completed"}}}"#, state: &state).isEmpty,
                     "a DeepSeek subagent end never emits a root completion")
    }
}
