// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// An agent that stops on something only the person can answer: what the
/// logs and session records say, what the store keeps, and when it is told.
enum AgentAttentionTests {
    static func run(_ suite: TestSuite) {
        claudeParsing(suite)
        codexParsing(suite)
        store(suite)
        records(suite)
        schedule(suite)
    }

    private static func line(_ json: String) -> Data { Data(json.utf8) }
    private static func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private static func claudeParsing(_ suite: TestSuite) {
        let now = at(0)
        var state = AgentLogState()
        func parse(_ json: String) -> [AgentLogEntry] { AgentLogParser.parseClaude(line(json), state: &state, now: now) }
        func call(_ name: String, _ id: String, time: String = "2026-09-21T23:43:00.000Z", sidechain: Bool = false) -> String {
            #"{"type":"assistant","timestamp":"\#(time)","isSidechain":\#(sidechain),"message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":{}}]}}"#
        }
        let asked = AgentTimestamp.parse("2026-09-21T23:43:00.000Z")!
        _ = parse(#"{"type":"user","timestamp":"2026-09-21T23:42:00.000Z","cwd":"/tmp/app","message":{"content":"go"}}"#)
        suite.expect(parse(call("AskUserQuestion", "toolu_q")) == [.turnActive(asked), .turnAwaiting(.question, asked, inferred: false)]
                        && state.awaitedTools == ["toolu_q": .question],
                     "a question the agent asks waits on the person, after the work it continues")
        suite.expect(parse(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_q","content":"yes"}]}}"#)
                        == [.turnActive(nil)] && state.awaitedTools.isEmpty,
                     "the answer to the question is work going on")
        suite.expect(parse(call("ExitPlanMode", "toolu_p")).last == .turnAwaiting(.plan, asked, inferred: false),
                     "a plan to approve waits on the person")
        _ = parse(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_p","content":"ok"}]}}"#)
        suite.expect(parse(call("Bash", "toolu_b")) == [.turnActive(asked)] && state.runningCommands == ["toolu_b"],
                     "a shell command never waits on the person by itself")
        suite.expect(parse(call("Read", "toolu_r")) == [.turnActive(asked)] && state.pendingTools == ["toolu_r"],
                     "another tool call is pending, which only a long quiet turns into a guess")
        _ = parse(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_r","content":"text with \"tool_use_id\":\"toolu_b\""}]}}"#)
        suite.expect(state.pendingTools.isEmpty && state.runningCommands == ["toolu_b"],
                     "a result answers its own call only, never one it quotes")
        suite.expect(parse(call("AskUserQuestion", "toolu_side", sidechain: true)).isEmpty && state.awaitedTools.isEmpty,
                     "a subagent's question is not the session's")
        suite.expect(parse(#"{"type":"user","timestamp":"2026-09-21T23:44:00.000Z","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#)
                        == [.turnEnded(nil, completed: false, duration: nil),
                            .turnAwaiting(.interrupted, AgentTimestamp.parse("2026-09-21T23:44:00.000Z")!, inferred: false)],
                     "an interruption ends the turn and leaves its work waiting")
        suite.expect(parse(#"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#).isEmpty,
                     "an interruption with no turn open leaves nothing waiting")
        _ = parse(#"{"type":"user","timestamp":"2026-09-21T23:45:00.000Z","message":{"content":"/model"}}"#)
        suite.expect(parse(#"{"type":"user","message":{"content":"<local-command-stdout>done</local-command-stdout>"}}"#)
                        == [.turnEnded(nil, completed: false, duration: nil)],
                     "a local command's output ends its turn without leaving work waiting")
    }

    private static func codexParsing(_ suite: TestSuite) {
        let now = at(0)
        var state = AgentLogState()
        func parse(_ json: String) -> [AgentLogEntry] { AgentLogParser.parseCodex(line(json), state: &state, now: now) }
        _ = parse(#"{"type":"turn_context","timestamp":1790088000,"payload":{"model":"gpt-5","approval_policy":"never"}}"#)
        _ = parse(#"{"type":"event_msg","timestamp":1790088000,"payload":{"type":"task_started"}}"#)
        suite.expect(state.codexApprovalPolicy == "never", "Codex says when it never asks before running a command")
        suite.expect(parse(#"{"type":"response_item","timestamp":1790088001,"payload":{"type":"custom_tool_call","status":"completed","call_id":"c1","name":"exec","input":"ls"}}"#).isEmpty
                        && state.codexPendingCalls == ["c1"],
                     "a Codex tool call is pending until its output")
        suite.expect(parse(#"{"type":"response_item","timestamp":1790088002,"payload":{"type":"custom_tool_call_output","call_id":"c1","output":[{"type":"input_text","text":"\"call_id\":\"c9\""}]}}"#).isEmpty
                        && state.codexPendingCalls.isEmpty,
                     "its output answers it, read without the output itself")
        _ = parse(#"{"type":"response_item","timestamp":1790088003,"payload":{"type":"function_call","name":"wait","arguments":"{}","call_id":"w1"}}"#)
        suite.expect(state.codexPendingCalls.isEmpty, "waiting on its own background work is not pending on the person")
        suite.expect(parse(#"{"type":"response_item","timestamp":1790088004,"payload":{"type":"function_call","name":"request_user_input","arguments":"{}","call_id":"q1"}}"#)
                        == [.turnAwaiting(.question, at(1_790_088_004), inferred: false)],
                     "a question that holds the turn waits on the person")
        suite.expect(parse(#"{"type":"response_item","timestamp":1790088010,"payload":{"type":"function_call_output","call_id":"q1","output":"answer"}}"#)
                        == [.turnActive(at(1_790_088_010))],
                     "its answer is work going on")
        _ = parse(#"{"type":"response_item","timestamp":1790088011,"payload":{"type":"function_call","name":"request_user_input_async","arguments":"{}","call_id":"q2"}}"#)
        suite.expect(parse(#"{"type":"event_msg","timestamp":1790088020,"payload":{"type":"task_complete","completed_at":1790088020}}"#)
                        == [.turnEnded(at(1_790_088_020), completed: false, duration: nil),
                            .turnAwaiting(.question, at(1_790_088_020), inferred: false)],
                     "a turn that ends on a question it posted waits for the answer instead of finishing")
        _ = parse(#"{"type":"event_msg","timestamp":1790088030,"payload":{"type":"task_started"}}"#)
        suite.expect(parse(#"{"type":"event_msg","timestamp":1790088040,"payload":{"type":"turn_aborted","reason":"interrupted","completed_at":1790088040}}"#)
                        == [.turnEnded(at(1_790_088_040), completed: false, duration: nil),
                            .turnAwaiting(.interrupted, at(1_790_088_040), inferred: false)],
                     "an interrupted Codex turn leaves its work waiting")
        _ = parse(#"{"type":"event_msg","timestamp":1790088050,"payload":{"type":"task_started"}}"#)
        suite.expect(parse(#"{"type":"event_msg","timestamp":1790088060,"payload":{"type":"task_complete","completed_at":1790088060}}"#)
                        == [.turnEnded(at(1_790_088_060), completed: true, duration: nil)],
                     "a question posted in an earlier turn does not hold the next one")
        var copilot = AgentLogState()
        _ = AgentLogParser.parseCopilot(line(#"{"type":"user.message","timestamp":"2026-09-21T23:42:00.000Z","data":{"content":"go"}}"#),
                                        state: &copilot, now: now)
        suite.expect(AgentLogParser.parseCopilot(line(#"{"type":"abort","timestamp":"2026-09-21T23:43:00.000Z","data":{}}"#),
                                                 state: &copilot, now: now).last
                        == .turnAwaiting(.interrupted, AgentTimestamp.parse("2026-09-21T23:43:00.000Z")!, inferred: false),
                     "a Copilot turn the person aborted leaves its work waiting")
    }

    private static func store(_ suite: TestSuite) {
        let now = at(2_000_000)
        let store = AgentUsageStore()
        var interrupted: [AgentProvider] = []
        store.turnInterrupted = { interrupted.append($0) }
        func apply(_ entries: [AgentLogEntry], _ file: String = "a", provider: AgentProvider = .claude,
                   at moment: Date = now) -> [AgentUsageEvent] {
            store.apply(entries, file: file, provider: provider, tracksTurns: true, modified: moment, now: moment)
        }
        _ = apply([.turnBegan(now.addingTimeInterval(-60)), .turnAwaiting(.question, now.addingTimeInterval(-30), inferred: false)])
        suite.expect(store.attention["a"]?.history == true && interrupted.isEmpty,
                     "a wait read while the logs are first read is history")
        var schedule = AgentAttentionSchedule()
        suite.expect(schedule.due(store.attention, now: now.addingTimeInterval(3600), delay: 60, repeats: true,
                                  interruptions: true, inferred: true, focused: []).isEmpty,
                     "history is never told")

        store.reportsTransitions = true
        _ = apply([.turnContext(model: "m", project: "app"), .turnAwaiting(.question, now, inferred: false)])
        suite.expect(store.attention["a"].map { !$0.history && $0.project == "app" && $0.cause == .question } == true,
                     "a wait read as it happens is news, and names its project")
        _ = apply([.usage(key: "k", record: AgentUsageRecord(provider: .claude, date: now.addingTimeInterval(5), model: "m",
                                                               project: "app", session: "s", tokens: AgentTokens(output: 1),
                                                               cost: nil, savings: 0),
                          billable: AgentBillable())])
        suite.expect(store.attention["a"] != nil, "usage alone does not answer a wait")
        _ = apply([.turnActive(now.addingTimeInterval(0.5))])
        suite.expect(store.attention["a"] != nil, "the rest of the line that asked does not answer it")
        _ = apply([.turnActive(now.addingTimeInterval(5))])
        suite.expect(store.attention["a"] == nil, "work after the wait answers it")

        _ = apply([.turnAwaiting(.permission, now, inferred: false)])
        store.closeIdleTurns(now: now.addingTimeInterval(NotchAgentSupport.idleTurn + 10), after: NotchAgentSupport.idleTurn)
        suite.expect(store.waiting["a"] != nil && store.attention["a"] != nil,
                     "a wait outlasts its turn going quiet")
        var processes = AgentSessionRegistry()
        processes.ended = ["a"]
        store.closeEndedTurns(processes)
        suite.expect(store.attention["a"] == nil, "a session that quit while it waited waits no longer")

        _ = apply([.turnBegan(now), .turnAwaiting(.question, now, inferred: false)], "gone")
        store.forget(file: "gone")
        suite.expect(store.attention["gone"] == nil, "a deleted session waits no longer")

        _ = apply([.turnBegan(now), .turnContext(model: "m", project: "app"),
                   .turnEnded(nil, completed: false, duration: nil), .turnAwaiting(.interrupted, now, inferred: false)], "i")
        suite.expect(store.attention["i"]?.project == "app" && interrupted == [.claude],
                     "an interruption keeps the project of the turn it ended, and is heard")
        _ = apply([.turnEnded(now, completed: false, duration: nil)], "i")
        suite.expect(store.attention["i"] != nil, "an unfinished end leaves interrupted work waiting")
        _ = apply([.turnBegan(now.addingTimeInterval(10))], "i")
        suite.expect(store.attention["i"] == nil, "a new prompt picks the work up")

        let events = apply([.turnBegan(now), .turnAwaiting(.question, now, inferred: false),
                            .turnEnded(now.addingTimeInterval(1), completed: true, duration: nil)], "f")
        suite.expect(events.count == 1 && events.allSatisfy { if case .finished = $0 { return true } else { return false } }
                        && store.attention["f"] == nil,
                     "apply still returns only finished turns, and a finished turn waits on nothing")

        _ = apply([.turnBegan(now.addingTimeInterval(-200))], "q", provider: .codex)
        store.inferQuietWaits(now: now, pending: ["q"], recorded: [])
        suite.expect(store.attention["q"].map { $0.inferred && $0.cause == .permission } == true,
                     "a call pending through a long quiet may wait on an approval")
        store.inferQuietWaits(now: now, pending: [], recorded: [])
        suite.expect(store.attention["q"] == nil, "a guess goes once its call comes back")
        _ = apply([.turnActive(now.addingTimeInterval(-30))], "q", provider: .codex)
        store.inferQuietWaits(now: now, pending: ["q"], recorded: [])
        suite.expect(store.attention["q"] == nil, "a call pending only briefly is not a guess")
    }

    private static func records(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-attention-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func record(_ pid: Int, _ session: String, _ status: String, waitingFor: String? = nil, at ms: Double = 1_790_088_000_000) {
            var json: [String: Any] = ["pid": pid, "sessionId": session, "status": status, "statusUpdatedAt": ms]
            if let waitingFor { json["waitingFor"] = waitingFor }
            try? JSONSerialization.data(withJSONObject: json).write(to: folder.appending(path: "\(pid).json"))
        }
        record(101, "s1", "waiting", waitingFor: "permission prompt")
        record(102, "s2", "busy")
        let registry = AgentSessionRegistry.read([folder], isRunning: { _ in true })
        suite.expect(registry.statuses["s1"] == AgentSessionRegistry.Status(status: "waiting", waitingFor: "permission prompt",
                                                                            updatedAt: at(1_790_088_000), pid: 101)
                        && registry.statuses["s2"]?.status == "busy" && registry.running == ["s1", "s2"],
                     "a session record says what the session is doing and since when")

        let store = AgentUsageStore()
        let files = ["s1": "/logs/s1.jsonl", "s2": "/logs/s2.jsonl"]
        store.apply([.turnBegan(at(1_790_087_900)), .turnContext(model: "m", project: "app")], file: "/logs/s1.jsonl",
                    provider: .claude, tracksTurns: true, modified: at(1_790_087_900), now: at(1_790_087_900))
        store.applyClaudeStatuses(registry, files: files, now: at(1_790_088_100))
        let wait = store.attention["/logs/s1.jsonl"]
        suite.expect(wait.map { $0.recorded && !$0.history && $0.cause == .permission && $0.since == at(1_790_088_000)
                        && $0.project == "app" } == true,
                     "a record waiting at launch is current, from when the record says")
        var schedule = AgentAttentionSchedule()
        suite.expect(schedule.due(store.attention, now: at(1_790_088_061), delay: 60, repeats: true, interruptions: false,
                                  inferred: false, focused: []).map(\.file) == ["/logs/s1.jsonl"],
                     "a record's wait is told after the delay")

        store.apply([.turnBegan(at(1_790_087_000))], file: "/logs/s2.jsonl", provider: .claude, tracksTurns: true,
                    modified: at(1_790_087_000), now: at(1_790_087_000))
        store.inferQuietWaits(now: at(1_790_088_100), pending: ["/logs/s2.jsonl"], recorded: [])
        suite.expect(store.attention["/logs/s2.jsonl"]?.inferred == true, "a quiet pending call is a guess")
        store.applyClaudeStatuses(registry, files: files, now: at(1_790_088_100))
        suite.expect(store.attention["/logs/s2.jsonl"] == nil, "a busy record takes the guess back")

        record(101, "s1", "waiting", waitingFor: "input needed", at: 1_790_088_200_000)
        store.applyClaudeStatuses(AgentSessionRegistry.read([folder], isRunning: { _ in true }), files: files,
                                  now: at(1_790_088_200))
        suite.expect(store.attention["/logs/s1.jsonl"]?.cause == .question, "the record says when a question waits")
        record(101, "s1", "idle", at: 1_790_088_300_000)
        store.applyClaudeStatuses(AgentSessionRegistry.read([folder], isRunning: { _ in true }), files: files,
                                  now: at(1_790_088_300))
        suite.expect(store.attention["/logs/s1.jsonl"] == nil, "an idle record ends the wait it gave")
    }

    private static func schedule(_ suite: TestSuite) {
        let since = at(1_000_000)
        func wait(_ file: String, _ cause: AgentAwait = .permission, inferred: Bool = false,
                  since start: Date = since) -> AgentAttention {
            AgentAttention(file: file, provider: .claude, project: file, place: .terminal, cause: cause, since: start,
                           inferred: inferred, history: false)
        }
        func due(_ schedule: inout AgentAttentionSchedule, _ waits: [AgentAttention], after seconds: TimeInterval,
                 repeats: Bool = true, interruptions: Bool = false, inferred: Bool = false,
                 focused: Set<String> = []) -> [String] {
            schedule.due(Dictionary(uniqueKeysWithValues: waits.map { ($0.file, $0) }),
                         now: since.addingTimeInterval(seconds), delay: 60, repeats: repeats,
                         interruptions: interruptions, inferred: inferred, focused: focused).map(\.file)
        }
        var schedule = AgentAttentionSchedule()
        let one = [wait("a")]
        suite.expect(due(&schedule, one, after: 59).isEmpty && due(&schedule, one, after: 60) == ["a"],
                     "the first notice comes after the delay")
        suite.expect(due(&schedule, one, after: 61).isEmpty && due(&schedule, one, after: 60 + 239).isEmpty
                        && due(&schedule, one, after: 60 + 240) == ["a"] && schedule.isReminder(one[0]),
                     "the first reminder comes four minutes later")
        suite.expect(due(&schedule, one, after: 60 + 839).isEmpty && due(&schedule, one, after: 60 + 840) == ["a"],
                     "the second comes ten minutes after that, fourteen after the first")
        suite.expect(due(&schedule, one, after: 60 + 7200).isEmpty, "then it stops")

        var once = AgentAttentionSchedule()
        suite.expect(due(&once, one, after: 60, repeats: false) == ["a"]
                        && due(&once, one, after: 3600, repeats: false).isEmpty,
                     "without reminders, a wait is told once")

        var interrupt = AgentAttentionSchedule()
        let paused = [wait("p", .interrupted)]
        suite.expect(due(&interrupt, paused, after: 600).isEmpty, "interruptions are told only when asked")
        suite.expect(due(&interrupt, paused, after: 299, interruptions: true).isEmpty
                        && due(&interrupt, paused, after: 300, interruptions: true) == ["p"]
                        && due(&interrupt, paused, after: 3600, interruptions: true).isEmpty,
                     "an interruption is told once, after five minutes")

        var guess = AgentAttentionSchedule()
        let guessed = [wait("g", inferred: true)]
        suite.expect(due(&guess, guessed, after: 600).isEmpty
                        && due(&guess, guessed, after: 120, inferred: true) == ["g"]
                        && due(&guess, guessed, after: 3600, inferred: true).isEmpty,
                     "a guess is told once, later, and only when asked")

        var dialog = AgentAttentionSchedule()
        suite.expect(due(&dialog, [wait("d", .dialog)], after: 119).isEmpty && due(&dialog, [wait("d", .dialog)], after: 120) == ["d"],
                     "an open dialog waits twice as long")

        var together = AgentAttentionSchedule()
        let two = [wait("a"), wait("b", since: since.addingTimeInterval(20))]
        suite.expect(due(&together, two, after: 60) == ["a"], "the first wait is told on time")
        suite.expect(due(&together, two, after: 80).isEmpty, "one due within the gap waits for it")
        let next = together.due(Dictionary(uniqueKeysWithValues: two.map { ($0.file, $0) }),
                                now: since.addingTimeInterval(60 + AgentAttentionPolicy.globalGap), delay: 60,
                                repeats: true, interruptions: false, inferred: false, focused: [])
        suite.expect(next.map(\.file) == ["b"], "then it is told on its own")
        var coalesced = AgentAttentionSchedule()
        suite.expect(due(&coalesced, two, after: 90) == ["a", "b"], "waits due together are one notice, the longest first")

        var focus = AgentAttentionSchedule()
        suite.expect(due(&focus, one, after: 60, focused: ["a"]).isEmpty, "a wait whose app is in front is held")
        suite.expect(due(&focus, one, after: 65).isEmpty && due(&focus, one, after: 120) == ["a"],
                     "out of the front, it waits a full delay again")
        var seen = AgentAttentionSchedule()
        _ = due(&seen, one, after: 30, focused: ["a"])
        _ = due(&seen, one, after: 41, focused: ["a"])
        suite.expect(due(&seen, one, after: 3600).isEmpty, "ten seconds in front marks it seen")
        var tapped = AgentAttentionSchedule()
        _ = due(&tapped, one, after: 60)
        tapped.markSeen(file: "a", in: ["a": one[0]])
        suite.expect(due(&tapped, one, after: 3600).isEmpty, "a tap on its notice marks it seen")
        suite.expect(due(&tapped, [wait("a", .question, since: since.addingTimeInterval(3600))], after: 3660) == ["a"],
                     "a new wait in the same session starts over")

        var resumed = AgentAttentionSchedule()
        resumed.hold(until: since.addingTimeInterval(4000 + AgentAttentionPolicy.resumeSettle))
        suite.expect(due(&resumed, two, after: 4000).isEmpty, "nothing is told while the island settles after a pause")
        suite.expect(due(&resumed, two, after: 4000 + AgentAttentionPolicy.resumeSettle) == ["a", "b"]
                        && due(&resumed, two, after: 4100).isEmpty,
                     "what came due meanwhile is told once")
    }
}
