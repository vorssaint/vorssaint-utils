// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Fixtures follow Oh My Pi's v3 SessionEntry and Usage types.
enum OhMyPiAgentTests {
    static func run(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var state = AgentLogState()
        func entries(_ json: String) -> [AgentLogEntry] {
            AgentLogParser.parsePi(Data(json.utf8), state: &state, now: now, provider: .omp)
        }
        func usage(_ list: [AgentLogEntry]) -> (String, AgentUsageRecord, AgentBillable)? {
            for case .usage(let key, let record, let billable) in list { return (key, record, billable) }
            return nil
        }
        _ = entries(#"{"type":"session","version":3,"id":"omp-s1","cwd":"/Users/me/code/backend/"}"#)
        suite.expect(state.session == "omp-s1" && state.project == "backend", "Oh My Pi keeps its session and project")
        _ = entries(#"{"type":"model_change","model":"relay/mystery-omp-model"}"#)
        suite.expect(state.model == "mystery-omp-model", "Oh My Pi model changes remove only the provider prefix")
        _ = entries(#"{"type":"model_change","model":"relay/other-model","role":"smol"}"#)
        suite.expect(state.model == "mystery-omp-model", "an auxiliary model change does not replace Oh My Pi's main model")
        _ = entries(#"{"type":"model_change","model":"relay/vendor/model","role":"default"}"#)
        suite.expect(state.model == "vendor/model", "Oh My Pi preserves slashes inside a model identifier")
        _ = entries(#"{"type":"model_change","model":"relay/mystery-omp-model","role":"default"}"#)
        suite.expect(entries(#"{"type":"message","id":"u1","message":{"role":"user","content":"private"}}"#)
                        == [.turnBegan(now)], "an Oh My Pi user message begins work")
        let reply = entries(#"{"type":"message","id":"a1","message":{"role":"assistant","stopReason":"toolUse","usage":{"input":1000,"output":200,"cacheRead":50,"cacheWrite":30,"reasoningTokens":50,"cttl":{"ephemeral5m":10,"ephemeral1h":20},"server":{"webSearch":2},"cost":{"total":0.0042}}}}"#)
        let first = usage(reply)
        suite.expect(first?.0 == "omp:omp-s1:a1" && first?.1.provider == .omp
                        && first?.1.tokens == AgentTokens(input: 1000, cacheWrite: 30, cacheRead: 50, output: 200, reasoning: 50)
                        && first?.2.longCacheWrite == 20 && first?.2.webSearches == 2, "Oh My Pi keeps reasoning and the nested cache TTL breakdown without double counting")
        suite.expect(first?.1.cost == 0.0042 && first?.1.reportedCost == true
                        && reply.last == .turnActive(now), "Oh My Pi falls back to recorded costs and continues tool calls")
        suite.expect(entries(#"{"type":"message","id":"t1","message":{"role":"toolResult","content":"private"}}"#)
                        == [.turnActive(nil)], "an Oh My Pi tool result keeps work active without retaining its content")
        let background = entries(#"{"type":"model_usage","id":"m1","purpose":"session-title","role":"smol","model":"auxiliary-model","stopReason":"stop","usage":{"input":10,"output":5,"cacheRead":2,"cacheWrite":0,"cost":{"total":0.001}}}"#)
        suite.expect(background.count == 1 && usage(background)?.0 == "omp:omp-s1:m1"
                        && usage(background)?.1.model == "auxiliary-model" && state.model == "mystery-omp-model" && state.turnOpen,
                     "Oh My Pi auxiliary usage is billed without changing the main model or ending its turn")
        let orchestrated = usage(entries(#"{"type":"model_usage","id":"m2","purpose":"compaction","model":"auxiliary-model","usage":{"input":10,"output":5,"cacheRead":2,"cacheWrite":0,"orchestration":{"input":3,"output":4,"cacheRead":6},"cost":{"total":0.001}}}"#))
        suite.expect(orchestrated?.1.tokens == AgentTokens(input: 13, cacheWrite: 0, cacheRead: 8, output: 9, reasoning: 0),
                     "Oh My Pi includes separately billed orchestration tokens")
        let invalidCost = usage(entries(#"{"type":"model_usage","id":"m3","purpose":"session-title","model":"auxiliary-model","usage":{"input":1,"output":1,"cost":{"total":-1}}}"#))
        let free = usage(entries(#"{"type":"model_usage","id":"m4","purpose":"session-title","model":"auxiliary-model","usage":{"input":1,"output":1,"cost":{"total":0}}}"#))
        suite.expect(invalidCost?.1.cost == nil && free?.1.cost == 0,
                     "Oh My Pi rejects negative recorded costs but preserves a legitimate zero")
        let limited = entries(#"{"type":"message","id":"a2","message":{"role":"assistant","stopReason":"length"}}"#)
        suite.expect(limited == [.turnEnded(now, completed: true, duration: nil)] && !state.turnOpen,
                     "Oh My Pi's output limit stops showing work as active")
        for stop in ["aborted", "error"] {
            _ = entries(#"{"type":"message","id":"u2","message":{"role":"user"}}"#)
            let ended = entries(#"{"type":"message","id":"a3","message":{"role":"assistant","stopReason":"\#(stop)","usage":{"input":0,"output":0}}}"#)
            suite.expect(ended == [.turnEnded(now, completed: false, duration: nil)] && !state.turnOpen,
                         "Oh My Pi \(stop) ends work unfinished without fabricating usage")
        }
        suite.expect(entries(#"{"type":"custom","data":{"usage":{"input":9}}}"#).isEmpty
                        && entries(#"{"type":"usage","kind":"cache_warm","usage":{"input":9}}"#).isEmpty
                        && entries(#"{"type":"message","message":"damaged"}"#).isEmpty,
                     "Oh My Pi ignores unrelated and malformed records")
        var piState = AgentLogState()
        suite.expect(AgentLogParser.parsePi(Data(#"{"type":"model_usage","usage":{"input":9}}"#.utf8), state: &piState, now: now).isEmpty,
                     "Oh My Pi auxiliary usage is not accepted as Pi usage")
        let store = AgentUsageStore()
        store.apply(reply + background, file: "/omp/session.jsonl", provider: .omp, tracksTurns: true, modified: now)
        store.apply(reply + background, file: "/omp/session.jsonl", provider: .omp, tracksTurns: true, modified: now)
        suite.expect(store.records.count == 2, "rereading Oh My Pi entries does not count their usage twice")
        let home = URL(fileURLWithPath: "/tmp/omp-home-\(UUID().uuidString)", isDirectory: true)
        suite.expect(AgentLogRoot.all(home: home).contains { $0.provider == .omp && $0.url.path == home.appending(path: ".omp/agent/sessions").path },
                     "Oh My Pi discovers its default session directory separately from Pi")
        suite.expect(!AgentProvider.pi.reportsLimits && !AgentProvider.omp.reportsLimits
                        && AgentProvider.omp.reportsCost, "Pi and Oh My Pi report costs, not plan limits")
    }
}
