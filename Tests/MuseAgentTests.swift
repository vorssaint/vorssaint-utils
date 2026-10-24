// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Muse session logs: one event record per line, stamped in microseconds,
/// with each model call's tokens in a run's `model_completed` event.
enum MuseAgentTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        turns(suite)
        privacy(suite)
        discovery(suite)
    }

    private static let session = "01a142ac-8848-7bd0-9f3f-32057d77d605"
    private static let run = "01a142ad-a246-7031-875d-ee7566c88c42"

    private static func line(_ json: String) -> Data { Data(json.utf8) }

    private static func record(_ id: String, at micros: Int, _ payload: String,
                               type: String = "runtime.session") -> Data {
        line(#"{"schema_version":1,"id":"\#(id)","stream":{"kind":"session","id":"\#(session)"},"sequence":1,"recorded_at":\#(micros),"record_type":"event","durability":"durable","causation_id":null,"payload_type":"\#(type)","payload_schema_version":1,"payload":\#(payload)}"#)
    }

    private static func metadata(at micros: Int) -> Data {
        record("meta", at: micros, #"{"kind":"metadata","record":{"workspace_root":"/Users/me/code/app","provider_id":"meta","model_id":"muse-wonder-full-1.0"}}"#,
               type: "runtime.session.metadata")
    }

    private static func started(_ id: String, at micros: Int, prompt: String = "work") -> Data {
        record(id, at: micros, #"{"kind":"run","run_id":"\#(run)","event":{"kind":"started","prompt":"\#(prompt)"}}"#)
    }

    private static func completed(_ id: String, at micros: Int, input: Int, cached: Int, output: Int,
                                  reasoning: Int = 0, model: String = "muse-wonder-full-1.0") -> Data {
        record(id, at: micros, #"{"kind":"run","run_id":"\#(run)","event":{"kind":"model_completed","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cached_tokens":\#(cached),"cache_write_tokens":0,"cache_read_tokens":\#(cached),"reasoning_tokens":\#(reasoning)},"duration_ms":11513,"finish_reason":"tool_calls","model":"\#(model)"}}"#)
    }

    private static func terminal(_ id: String, at micros: Int, _ outcome: String, duration: Int) -> Data {
        record(id, at: micros, #"{"kind":"run","run_id":"\#(run)","event":{"kind":"terminal","terminal":"\#(outcome)","reason":null,"turn_duration_ms":\#(duration)}}"#)
    }

    private static func parsing(_ suite: TestSuite) {
        let reader = AgentProvider.muse.reader
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        _ = reader.parse(metadata(at: 1_792_119_965_848_659), state: &state, now: now)
        suite.expect(state.session == session && state.project == "app" && state.model == "muse-wonder-full-1.0",
                     "Muse metadata names the session, its folder and the model")

        let entries = reader.parse(completed("call-1", at: 1_792_120_049_000_000, input: 35_435, cached: 34_292,
                                             output: 161, reasoning: 9, model: "muse-spark-1.3"),
                                   state: &state, now: now)
        guard case .usage(let key, let usage, let billable)? = entries.first else {
            suite.expect(false, "a completed Muse model call reports usage")
            return
        }
        suite.expect(key == "muse:call-1", "Muse usage is keyed by its record so a repeated line counts once")
        suite.expect(usage.tokens == AgentTokens(input: 1_143, cacheWrite: 0, cacheRead: 34_292, output: 161, reasoning: 9)
                        && billable.tokens == usage.tokens,
                     "Muse input counts include the cache, which is split out of them")
        suite.expect(usage.date == Date(timeIntervalSince1970: 1_792_120_049),
                     "Muse records are stamped in microseconds")
        suite.expect(usage.provider == .muse && usage.model == "muse-spark-1.3" && usage.project == "app"
                        && usage.session == session,
                     "a Muse call keeps the model it ran on, the folder and the session")
        suite.expect(usage.cost == nil, "Muse models have no published price, so no API value is invented")

        let review = record("review", at: 1_792_120_050_000_000, #"{"kind":"approval","run_id":"\#(run)","event":{"kind":"automated_review_completed","status":"approved","assessment":{"rationale":"private"},"model":{"provider_id":"meta","model_id":"muse-wonder-full-1.0"},"usage":{"input_tokens":35435,"cached_input_tokens":34292,"non_cached_input_tokens":1143,"output_tokens":306,"reasoning_tokens":154,"total_tokens":35741}}}"#)
        let reviewed = reader.parse(review, state: &state, now: now)
        if case .usage(let key, let usage, _)? = reviewed.first {
            suite.expect(key == "muse:review" && usage.model == "muse-wonder-full-1.0" && usage.project == "app"
                            && usage.tokens == AgentTokens(input: 1_143, cacheWrite: 0, cacheRead: 34_292, output: 306, reasoning: 154)
                            && !String(describing: reviewed).contains("private"),
                         "an automated approval review counts its reviewer's tokens, not its reasoning")
        } else {
            suite.expect(false, "an automated approval review reports usage")
        }
        suite.expect(state.model == "muse-spark-1.3", "a reviewer's model does not replace the session's")

        let overstated = MuseReader.tokens(["input_tokens": 10, "cached_tokens": 50, "output_tokens": 1])
        suite.expect(overstated == AgentTokens(input: 0, cacheWrite: 0, cacheRead: 10, output: 1, reasoning: 0),
                     "a cache count above the input never makes a negative input")
        suite.expect(AgentProvider.muse.reportsLimits,
                     "Muse gets a card of its own")
    }

    private static func turns(_ suite: TestSuite) {
        let reader = AgentProvider.muse.reader
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        _ = reader.parse(metadata(at: 1_000_000), state: &state, now: now)
        let begin = Date(timeIntervalSince1970: 2)
        suite.expect(reader.parse(started("start", at: 2_000_000), state: &state, now: now)
                        == [.turnBegan(begin), .turnContext(model: "muse-wonder-full-1.0", project: "app")]
                        && state.turnOpen,
                     "a Muse run opens a turn with its model and folder")
        let call = reader.parse(completed("call", at: 5_000_000, input: 10, cached: 0, output: 2), state: &state, now: now)
        suite.expect(call.count == 2 && call.last == .turnActive(Date(timeIntervalSince1970: 5)),
                     "a model call during a run keeps the turn active")
        let switched = record("model", at: 6_000_000, #"{"kind":"run_model","record":{"provider_id":"meta","model_id":"muse-spark-1.3"}}"#,
                              type: "run.model.configured")
        suite.expect(reader.parse(switched, state: &state, now: now)
                        == [.turnContext(model: "muse-spark-1.3", project: "app")],
                     "a model chosen mid-run updates the open turn")
        suite.expect(reader.parse(terminal("end", at: 9_000_000, "completed", duration: 7_000), state: &state, now: now)
                        == [.turnEnded(Date(timeIntervalSince1970: 9), completed: true, duration: 7)]
                        && !state.turnOpen,
                     "a completed Muse run ends its turn with the duration Muse measured")
        suite.expect(reader.parse(terminal("again", at: 10_000_000, "completed", duration: 1), state: &state, now: now).isEmpty,
                     "a second terminal record without an open run reports nothing")
        _ = reader.parse(started("retry", at: 11_000_000), state: &state, now: now)
        suite.expect(reader.parse(terminal("failed", at: 12_000_000, "failed", duration: 1_000), state: &state, now: now)
                        == [.turnEnded(Date(timeIntervalSince1970: 12), completed: false, duration: 1)],
                     "a failed Muse run ends its turn without counting as finished")
    }

    private static func privacy(_ suite: TestSuite) {
        let reader = AgentProvider.muse.reader
        var state = AgentLogState()
        let secret = "private prompt text"
        let entries = reader.parse(started("start", at: 2_000_000, prompt: secret), state: &state, now: Date())
        suite.expect(!String(describing: entries).contains(secret) && !String(describing: state).contains(secret),
                     "a Muse prompt never reaches what the island keeps")
        let task = record("task", at: 3_000_000, #"{"kind":"task","task_id":"t","record":{"kind":"output","text":"secret output","event":{"kind":"model_completed","usage":{"input_tokens":5}}}}"#)
        suite.expect(reader.parse(task, state: &state, now: Date()).isEmpty,
                     "tool records are not read for usage, even when their output looks like a model event")
    }

    private static func discovery(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        guard let root = AgentLogRoot.all(home: home).first(where: { $0.provider == .muse }) else {
            suite.expect(false, "Muse has a log root")
            return
        }
        let base = root.url.path
        suite.expect(base.hasSuffix("/.local/share/muse/sessions"), "Muse logs are read from its sessions folder")
        let main = "\(base)/2026/10/15/\(session)/session.jsonl"
        let child = "\(base)/2026/10/15/\(session)/subagent/b712025c/session.jsonl"
        suite.expect(root.accepts(main) && root.accepts(child), "Muse session and subagent logs are read")
        suite.expect(!root.accepts("\(base)/2026/10/15/\(session)/approval-review/r.jsonl")
                        && !root.accepts("\(base)/.msp-view-v1/\(session)/session.jsonl")
                        && !root.accepts("\(base)/2026/10/15/\(session)/cli-1.log"),
                     "approval reviews, hidden caches and other files beside a Muse session are skipped")
        suite.expect(AgentLogCursor.parent(of: child, provider: .muse) == main
                        && AgentLogCursor.parent(of: main, provider: .muse) == nil,
                     "a Muse subagent works for the session whose folder holds it")
        let cursor = AgentLogCursor(path: child, provider: .muse)
        suite.expect(!cursor.tracksTurns && cursor.parent == main && AgentLogCursor(path: main, provider: .muse).tracksTurns,
                     "a Muse subagent's calls count toward its session's turn instead of opening their own")
        suite.expect(AgentLogCursor.parent(of: "/x/subagent/y/session.jsonl", provider: .codex) == nil,
                     "other agents keep their own subagent layout")
    }
}
