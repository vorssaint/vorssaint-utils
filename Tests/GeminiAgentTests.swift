// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Gemini CLI's session logs, as its chat recording writes them: a metadata
/// line, then each message whole, again whenever its tool calls finish.
enum GeminiAgentTests {
    private static let now = AgentTimestamp.parse("2026-10-27T15:10:00Z")!

    private static func line(_ json: String) -> Data { Data(json.utf8) }

    /// Times are written as Gemini CLI writes them, in ISO 8601.
    private static func message(_ id: String, _ type: String, at seconds: TimeInterval, _ fields: String = "") -> Data {
        let time = ISO8601DateFormatter.string(from: now.addingTimeInterval(seconds), timeZone: .gmt,
                                               formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        return line(#"{"id":"\#(id)","timestamp":"\#(time)","type":"\#(type)"\#(fields.isEmpty ? "" : ",")\#(fields)}"#)
    }

    private static func prompt(_ id: String, at seconds: TimeInterval) -> Data {
        message(id, "user", at: seconds, #""content":[{"text":"private"}]"#)
    }

    private static let usage = #""tokens":{"input":100,"output":10,"cached":0,"thoughts":0,"tool":0,"total":110},"model":"gemini-2.5-flash""#

    static func run(_ suite: TestSuite) {
        parsing(suite)
        lifecycle(suite)
        turns(suite)
        pricing(suite)
        discovery(suite)
    }

    private static func parsing(_ suite: TestSuite) {
        let reader = AgentProvider.gemini.reader
        var state = AgentLogState()
        let meta = line(#"{"sessionId":"s1","projectHash":"h","startTime":"2026-10-27T15:00:00.000Z","kind":"main"}"#)
        suite.expect(reader.parse(meta, state: &state, now: now).isEmpty && state.session == "s1",
                     "Gemini CLI's first line names the session")
        state.project = "app"
        let context = message("env", "user", at: -70, #""content":[{"text":"<session_context>\nThis is the Gemini CLI."}]"#)
        suite.expect(reader.parse(context, state: &state, now: now).isEmpty && !state.turnOpen,
                     "the context a Gemini CLI session opens with is no prompt")
        suite.expect(reader.parse(prompt("u1", at: -60), state: &state, now: now)
                        == [.turnBegan(now.addingTimeInterval(-60)), .turnContext(model: "", project: "app")],
                     "a Gemini CLI prompt opens its turn")

        let tokens = #""tokens":{"input":1000,"output":40,"cached":600,"thoughts":10,"tool":5,"total":1055},"model":"gemini-2.5-pro""#
        let asked = reader.parse(message("g1", "gemini", at: -50, #""content":"",\#(tokens)"#), state: &state, now: now)
        guard case .usage(let key, let record, let billable)? = asked.first else {
            suite.expect(false, "a Gemini CLI reply with tokens is usage")
            return
        }
        suite.expect(key == "gemini:s1:g1" && record.provider == .gemini && record.model == "gemini-2.5-pro"
                        && record.session == "s1" && record.project == "app" && record.date == now.addingTimeInterval(-50),
                     "a Gemini CLI reply is keyed by its message and carries its session, project and model")
        suite.expect(record.tokens == AgentTokens(input: 405, cacheWrite: 0, cacheRead: 600, output: 50, reasoning: 10)
                        && billable.tokens == record.tokens,
                     "cached tokens leave the prompt count, tool-use prompts join it and thinking bills as output")
        suite.expect(Array(asked.dropFirst()) == [.turnContext(model: "gemini-2.5-pro", project: "app"),
                                                  .turnActive(now.addingTimeInterval(-50))],
                     "a reply without text asked for tools, so the turn goes on")

        let finished = reader.parse(message("g1", "gemini", at: -50,
                                            #""content":"",\#(tokens),"toolCalls":[{"id":"t","status":"success"}]"#),
                                    state: &state, now: now)
        guard case .usage(let again, _, _)? = finished.first else {
            suite.expect(false, "a reply written again with its tool calls is still usage")
            return
        }
        suite.expect(again == key && finished.last == .turnActive(nil),
                     "finished tool calls repeat the reply's key and count as work now, not at the reply's time")
        let result = message("r1", "user", at: -40, #""content":[{"functionResponse":{"id":"t","name":"read_file","response":{"output":"private"}}}]"#)
        suite.expect(reader.parse(result, state: &state, now: now) == [.turnActive(now.addingTimeInterval(-40))],
                     "a tool result goes back as a user message without opening a turn")
        let answer = reader.parse(message("g2", "gemini", at: -30, #""content":"private","tokens":null,"model":"gemini-2.5-pro""#),
                                  state: &state, now: now)
        suite.expect(answer == [.turnContext(model: "gemini-2.5-pro", project: "app"), .turnSettled(now.addingTimeInterval(-30))]
                        && !state.turnOpen,
                     "a reply with text may be the turn's last, and one without tokens counts nothing")
        suite.expect(reader.parse(message("n0", "info", at: -25, #""content":"Session resumed.""#), state: &state, now: now).isEmpty,
                     "a notice after the turn's last reply has no turn to end")
        let quoted = message("u2", "user", at: -20, #""content":[{"text":"\"functionResponse\":{} <session_context>"}]"#)
        suite.expect(reader.parse(quoted, state: &state, now: now).first == .turnBegan(now.addingTimeInterval(-20)),
                     "a prompt that quotes a tool result's key or the session context still opens a turn")
        for notice in ["info", "warning", "error"] {
            state.turnOpen = true
            suite.expect(reader.parse(message("n", notice, at: -15, #""content":"Request cancelled.""#), state: &state, now: now)
                            == [.turnSettled(now.addingTimeInterval(-15))] && !state.turnOpen,
                         "a Gemini CLI \(notice) notice may end its turn")
        }
        for edit in [#"{"$set":{"lastUpdated":"2026-10-27T15:09:00.000Z","sessionId":"other"}}"#,
                     #"{"$patch":{"id":"g1","toolCalls":[{"id":"t"}]}}"#, #"{"$rewindTo":"g1"}"#,
                     #"{"id":"","timestamp":0,"type":"gemini","tokens":{"input":5,"total":5}}"#, "not json"] {
            suite.expect(reader.parse(line(edit), state: &state, now: now).isEmpty && state.session == "s1",
                         "Gemini CLI's edits to written messages add nothing: \(edit)")
        }
    }

    /// When a turn goes on and when it may be over, from the records Gemini
    /// CLI writes around tools, compression and empty replies.
    private static func lifecycle(_ suite: TestSuite) {
        let reader = AgentProvider.gemini.reader
        var state = AgentLogState()
        _ = reader.parse(prompt("u", at: -60), state: &state, now: now)
        _ = reader.parse(message("g", "gemini", at: -50, #""content":"Running the tests",\#(usage)"#), state: &state, now: now)
        suite.expect(!state.turnOpen, "a reply with text may have been the turn's last")
        _ = reader.parse(message("g", "gemini", at: -50, #""content":"Running the tests",\#(usage),"toolCalls":[{"id":"t"}]"#),
                         state: &state, now: now)
        suite.expect(state.turnOpen, "its finished tool calls show the turn went on")
        // Compressing the history writes a summary, an acknowledgement and
        // the turns it kept again, under new ids and without token counts or
        // a model: set as a new history, with tokens null, or synced, without.
        let resync = [message("s", "user", at: -40, #""content":[{"text":"<state_snapshot>private</state_snapshot>"}]"#),
                      message("a", "gemini", at: -40,
                              #""content":[{"text":"Got it. Thanks for the additional context!"}],"thoughts":[],"tokens":null"#),
                      message("k1", "user", at: -40, #""content":[{"text":"private"}]"#),
                      message("k2", "gemini", at: -40, #""content":[{"text":"private"}]"#)]
        let rewritten = resync.flatMap { reader.parse($0, state: &state, now: now) }
        suite.expect(!rewritten.contains { if case .turnBegan = $0 { return true } else { return false } }
                        && !rewritten.contains { if case .turnSettled = $0 { return true } else { return false } }
                        && !rewritten.contains { if case .usage = $0 { return true } else { return false } }
                        && state.turnOpen,
                     "a history compressed while its turn goes on neither restarts nor ends the turn, nor counts again")
        _ = reader.parse(message("r", "user", at: -30, #""content":[{"functionResponse":{"id":"t"}}]"#), state: &state, now: now)
        // A tool's binary output follows its result as an acknowledgement and
        // an info message holding the data, which goes to the model next.
        let ack = message("b1", "gemini", at: -30,
                          #""content":[{"text":"Binary content received. Proceeding with analysis.","thought":true}],"thoughts":[],"tokens":null"#)
        let binary = message("b2", "info", at: -30, #""content":[{"inlineData":{"mimeType":"image/png","data":"AAAA"}}]"#)
        suite.expect(reader.parse(ack, state: &state, now: now).isEmpty
                        && reader.parse(binary, state: &state, now: now) == [.turnActive(now.addingTimeInterval(-30))]
                        && state.turnOpen,
                     "a tool's binary output sent on to the model keeps the turn working")
        // An empty reply to tool results keeps its parts instead of text.
        let empty = reader.parse(message("e", "gemini", at: -20, #""content":[],"tokens":{"input":5,"total":5}"#),
                                 state: &state, now: now)
        suite.expect(empty.last == .turnSettled(now.addingTimeInterval(-20)) && !state.turnOpen,
                     "an empty reply to tool results may have been the turn's last")
        let hook = message("h", "user", at: -10, #""content":[{"text":"<hook_context>private</hook_context>"}]"#)
        suite.expect(reader.parse(hook, state: &state, now: now).isEmpty && !state.turnOpen,
                     "context a hook adds is no prompt")
    }

    private static func turns(_ suite: TestSuite) {
        let reader = AgentProvider.gemini.reader
        let store = AgentUsageStore()
        store.reportsTransitions = true
        var state = AgentLogState()
        var events: [AgentUsageEvent] = []
        let file = "tmp/app/chats/session.jsonl"
        func feed(_ data: Data) {
            events += store.apply(reader.parse(data, state: &state, now: now), file: file,
                                  provider: .gemini, tracksTurns: true, modified: now.addingTimeInterval(-5), now: now)
        }
        feed(line(#"{"sessionId":"s2","projectHash":"h"}"#))
        feed(prompt("u", at: -120))
        feed(message("g1", "gemini", at: -110, #""content":"Reading it",\#(usage)"#))
        suite.expect(store.live.count == 1 && store.live.first?.tokens.total == 110 && store.live.first?.model == "gemini-2.5-flash",
                     "a Gemini CLI turn shows its tokens and model while it works")
        store.closeSettledTurns(now: now.addingTimeInterval(-110 + AgentLogParser.settle - 1))
        suite.expect(store.live.count == 1, "a reply's turn goes on while its tools may still be running")
        store.closeSettledTurns(now: now.addingTimeInterval(-110 + AgentLogParser.settle))
        suite.expect(store.live.isEmpty && store.waiting[file]?.tokens.total == 110,
                     "a reply with nothing after it goes quiet, its turn waiting aside")
        feed(message("g1", "gemini", at: -110, #""content":"Reading it",\#(usage),"toolCalls":[{"id":"t","status":"success"}]"#))
        suite.expect(store.live.first?.started == now.addingTimeInterval(-120) && store.live.first?.tokens.total == 110
                        && store.live.first?.lastActivity == now.addingTimeInterval(-5),
                     "tools that ran past the wait bring back the same turn, at the time their result was written")
        feed(message("r", "user", at: -6, #""content":[{"functionResponse":{"id":"t"}}]"#))
        feed(message("g2", "gemini", at: -4, #""content":"Done",\#(usage)"#))
        suite.expect(store.records.count == 2 && store.live.first?.tokens.total == 220
                        && store.live.first?.lastActivity == now.addingTimeInterval(-4),
                     "a reply written again counts once, and the turn follows the work that came after it")

        // Quitting in the wait after a reply brings the turn back quiet.
        let restored = AgentUsageStore(saved: store.saved)
        suite.expect(restored.live.isEmpty && restored.waiting[file]?.tokens.total == 220,
                     "a Gemini CLI turn saved while it may be over comes back quiet, not working")

        store.closeSettledTurns(now: now.addingTimeInterval(-4 + AgentLogParser.settle))
        suite.expect(store.live.isEmpty && events.isEmpty,
                     "a Gemini CLI turn ends quietly once nothing follows its last reply")
        feed(prompt("u2", at: -2))
        suite.expect(store.live.first?.started == now.addingTimeInterval(-2) && store.live.first?.tokens.total == 0,
                     "the next prompt opens a turn of its own")
        feed(message("n", "info", at: -1, #""content":"Request cancelled.""#))
        store.closeSettledTurns(now: now.addingTimeInterval(-1 + AgentLogParser.settle))
        suite.expect(store.live.isEmpty && events.isEmpty && store.records.count == 2,
                     "a cancelled Gemini CLI request ends its turn without a notice")
        feed(message("n2", "info", at: 0, #""content":"Session saved.""#))
        suite.expect(store.live.isEmpty, "a later notice does not bring a quiet turn back")
    }

    private static func pricing(_ suite: TestSuite) {
        let price = { (model: String) in AgentPricing.price(for: model) }
        suite.expect(price("gemini-2.5-pro")?.input == 1.25 && price("google/gemini-2.5-pro")?.output == 10
                        && price("gemini-3.1-pro-preview")?.input == 2 && price("gemini-3.1-pro-preview-customtools")?.input == 2
                        && price("gemini-3-flash-preview")?.input == 0.5 && price("gemini-2.5-flash-lite")?.input == 0.1,
                     "Gemini models take their own published prices, whoever runs them")
        suite.expect(price("gemini-3.5-flash") == nil && price("gemini-2.5-flash-preview-tts") == nil
                        && price("gemini-3.1-flash-lite-image") == nil && price("gemma-4-31b-it") == nil,
                     "a Gemini model without a published price, or a specialized sibling, stays unpriced")
        let long = AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 250_000, output: 1_000)), model: "gemini-2.5-pro")
        suite.expect(abs((long.cost ?? 0) - (250_000 * 2.5 + 1_000 * 15) / 1_000_000) < 1e-9,
                     "a Gemini Pro prompt past 200K tokens bills at the long-context rate")
        let cached = AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 100, cacheRead: 900, output: 10)),
                                       model: "gemini-2.5-flash")
        suite.expect(abs((cached.cost ?? 0) - (100 * 0.3 + 900 * 0.03 + 10 * 2.5) / 1_000_000) < 1e-12
                        && abs(cached.savings - 900 * (0.3 - 0.03) / 1_000_000) < 1e-12,
                     "Gemini cache reads bill at their own rate and count as savings")

        let base = #""schema":1,"updated":"2099-01-01","claude":{"webSearch":0.01,"usOnlyMultiplier":1.1,"models":[{"id":"claude-x","input":1,"output":1,"cacheRead":1}],"plans":[]},"codex":{"models":[{"id":"gpt-x","input":1,"output":1,"cacheRead":1}],"plans":[]}"#
        let without = AgentPriceList.decode(Data("{\(base)}".utf8))
        let with = AgentPriceList.decode(Data(#"{\#(base),"gemini":{"models":[{"id":"gemini-x","input":1,"output":2,"cacheRead":0.1}]}}"#.utf8))
        suite.expect(without?.gemini.isEmpty == true && with?.gemini.map(\.id) == ["gemini-x"],
                     "a price list may leave Gemini out")
        suite.expect(AgentPriceList.decode(Data(#"{\#(base),"gemini":{"models":[{"id":"gpt-x","input":1,"output":1,"cacheRead":1}]}}"#.utf8)) == nil
                        && AgentPriceList.decode(Data(#"{\#(base),"gemini":[]}"#.utf8)) == nil,
                     "a Gemini section with another maker's models, or of the wrong shape, refuses the list")
        let shipped = AgentPricing.list
        if let without {
            let chosen = AgentPriceList.newer(shipped, without)
            suite.expect(chosen?.updated == without.updated && chosen?.gemini == shipped.gemini && !shipped.gemini.isEmpty,
                         "a newer published list without Gemini prices keeps the ones the app ships")
        }
        if let with {
            suite.expect(AgentPriceList.newer(shipped, with)?.gemini == with.gemini,
                         "a newer list's Gemini prices replace the shipped ones")
        }
    }

    private static func discovery(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory.appending(path: "vorss-gemini-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = AgentLogRoot.all(home: home).filter { $0.provider == .gemini }
        suite.expect(roots.map(\.url.path) == [home.appending(path: ".gemini/tmp").path,
                                               home.appending(path: ".cache/.gemini/tmp").path],
                     "Gemini CLI's sessions are read from its folder and from the cache folder its sandbox uses")
        guard let tmp = roots.first else { return }
        let project = tmp.url.appending(path: "my-app")
        let chats = project.appending(path: "chats")
        let main = chats.appending(path: "session-2026-10-27T15-00-abcdef12.jsonl")
        let subagent = chats.appending(path: "abcdef12-3456/sub-1.jsonl")
        let others = [project.appending(path: "logs.json"), project.appending(path: "checkpoints/checkpoint.jsonl"),
                      chats.appending(path: ".hidden.jsonl"), chats.appending(path: "session.json"),
                      chats.appending(path: "a/b/deep.jsonl"), tmp.url.appending(path: "loose.jsonl")]
        for file in [main, subagent] + others {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: Data("{}\n".utf8))
        }
        // A subagent finishes before the session that started it writes last.
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: subagent.path)
        FileManager.default.createFile(atPath: project.appending(path: ".project_root").path,
                                       contents: Data("/Users/me/code/My App\n".utf8))
        let canonical = AgentLogRoot(provider: .gemini, url: AgentLogRoot.canonical(tmp.url))
        let found = AgentLogReader.discover([canonical], since: .distantPast).map(\.path)
        let expected = [main, subagent].map { AgentLogRoot.canonical($0).path }
        suite.expect(found == expected,
                     "only each project's chats and their subagent folders are read, subagents after the sessions")
        suite.expect(expected.allSatisfy(canonical.accepts) && !others.map { AgentLogRoot.canonical($0).path }.contains(where: canonical.accepts),
                     "file events admit the same Gemini CLI logs discovery finds")

        let mainCursor = AgentLogCursor(path: expected[0], provider: .gemini)
        let subagentCursor = AgentLogCursor(path: expected[1], provider: .gemini)
        suite.expect(mainCursor.state.project == "My App" && subagentCursor.state.project == "My App",
                     "a Gemini CLI log's project is the folder its project record names")
        suite.expect(mainCursor.tracksTurns && !subagentCursor.tracksTurns,
                     "a Gemini CLI subagent's responses count without a turn of their own")
        mainCursor.state.session = "abcdef12-3456"
        suite.expect(subagentCursor.geminiParent(among: [expected[0]: mainCursor, expected[1]: subagentCursor]) == expected[0]
                        && mainCursor.geminiParent(among: [expected[0]: mainCursor]) == nil,
                     "a Gemini CLI subagent's responses count toward the turn of the session its folder names")
        suite.expect(!GeminiReader.isSubagent("/h/.gemini/tmp/chats/chats/session-2026-10-27T15-00-abcdef12.jsonl")
                        && GeminiReader.isSubagent("/h/.gemini/tmp/chats/chats/abcdef12/sub.jsonl"),
                     "a project named chats keeps its sessions' turns")
        mainCursor.offset = 3
        mainCursor.startOver(identity: 1)
        suite.expect(mainCursor.state.project == "My App" && mainCursor.state.session.isEmpty,
                     "a log read again from its start keeps its project and nothing else")
        let unmarked = tmp.url.appending(path: "legacy-hash/chats/session.jsonl").path
        suite.expect(AgentLogCursor(path: unmarked, provider: .gemini).state.project.isEmpty,
                     "a project folder without a record leaves the project unknown rather than guessed")

        // Opening a FIFO for reading waits for a writer, and the usage queue
        // must never wait on one named like the project record.
        let piped = tmp.url.appending(path: "piped")
        try? FileManager.default.createDirectory(at: piped.appending(path: "chats"), withIntermediateDirectories: true)
        let fifo = piped.appending(path: ".project_root")
        guard mkfifo(fifo.path, 0o600) == 0 else {
            suite.expect(false, "the Gemini CLI fixture creates a fifo")
            return
        }
        let done = DispatchSemaphore(value: 0)
        var read: String? = "unset"
        DispatchQueue.global().async {
            read = AgentLogCursor(path: piped.appending(path: "chats/session.jsonl").path, provider: .gemini).state.project
            done.signal()
        }
        let returned = done.wait(timeout: .now() + 2) == .success
        if !returned {
            let writer = open(fifo.path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { close(writer) }
            _ = done.wait(timeout: .now() + 2)
        }
        suite.expect(returned && read?.isEmpty == true, "a fifo in place of the project record is skipped instead of waited on")
    }
}
