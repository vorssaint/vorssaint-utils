// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

typealias AgentUsageProductionLogReader = AgentLogReader
typealias AgentUsageReadProductionArchive = AgentUsageArchive

/// Runs the service's production startup/read methods, parser, cursor and store. The
/// reader wrapper only observes when a complete line is handed to the service.
enum AgentUsageReadTests {
    enum AgentLogReader {
        static var beforeLine: (() -> Void)?
        static func isLog(_ path: String) -> Bool { AgentUsageProductionLogReader.isLog(path) }
        static func discover(_ roots: [AgentLogRoot], since horizon: Date) -> [(path: String, provider: AgentProvider)] {
            AgentUsageProductionLogReader.discover(roots, since: horizon)
        }
        static func copilotHistoryLine(_ buffer: Data, range: Range<Int>) -> Bool {
            AgentUsageProductionLogReader.copilotHistoryLine(buffer, range: range)
        }
        static func readCopilotHistory(_ cursor: AgentLogCursor, shouldContinue: () -> Bool,
                                       line: (Data) -> Void) {
            AgentUsageProductionLogReader.readCopilotHistory(cursor, shouldContinue: shouldContinue) {
                beforeLine?()
                line($0)
            }
        }
        static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast, shouldContinue: () -> Bool,
                                 including: ((Data, Range<Int>) -> Bool)? = nil,
                                 line: (Data) -> Void) {
            AgentUsageProductionLogReader.readAppended(cursor, since: horizon, shouldContinue: shouldContinue,
                                                        including: including) {
                beforeLine?()
                line($0)
            }
        }
    }

    enum AgentUsageArchive {
        static func load() -> AgentUsageReadProductionArchive.Contents? { nil }
        static func resume(_ contents: AgentUsageReadProductionArchive.Contents, logs: Set<String>, since horizon: Date)
            -> (store: AgentUsageStore, cursors: [String: AgentLogCursor], unchanged: Bool) {
            AgentUsageReadProductionArchive.resume(contents, logs: logs, since: horizon)
        }
    }

    final class Cancellation {
        var isCancelled = false
    }

    /// Run startup's serial work inline so every delivered line can inspect
    /// publication state, without timers, file watchers or main-queue races.
    struct Queue {
        func async(execute work: () -> Void) { work() }
    }

    enum NotchAgentSupport {
        static let idleTurn: TimeInterval = 120
        static func dailyBudget() -> Double? { nil }
    }

    class Fixture {
        static let horizon = TimeInterval(AgentUsageSnapshot.dayCount) * 86_400
        let queue = Queue()
        var home = FileManager.default.temporaryDirectory
        var readerSession = 1
        var watchedRoots: [AgentLogRoot] = []
        var readerCancellation: Cancellation? = Cancellation()
        var cursors: [String: AgentLogCursor] = [:]
        var store = AgentUsageStore()
        var enabled: Set<AgentProvider> = []
        var previousLimits: [AgentProvider: AgentLimits] = [:]
        var budgetDay: Date?
        var snapshot = AgentUsageSnapshot()
        var publications: [AgentUsageSnapshot] = []
        var events: [AgentUsageEvent] = []
        var savedMark: Int?
        var progressMark: Int { 0 }
        func saveProgress() {}
        func startTimer() {}
        func loadPrices() {}
        func closeEndedTurns(_ roots: [AgentLogRoot], atLaunch: Bool) {}
        func readClaudePlan() {}
        func readClaudeApp(now: Date) {}
        func watch(_ roots: [AgentLogRoot]) { watchedRoots = roots }
        func startPolling() {}
        func watchNetwork() {}
        func publish() {
            snapshot = store.snapshot(plans: [:], providers: enabled, now: Date())
            publications.append(snapshot)
        }
        func report(_ event: AgentUsageEvent) { events.append(event) }
        func checkLimits() {}
        func schedulePublish() {}
    }

    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-streaming-\(UUID().uuidString)")
        defer {
            AgentLogReader.beforeLine = nil
            try? FileManager.default.removeItem(at: folder)
        }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the streaming fixture creates its folder: \(error)"); return }
        let now = Date()
        let timestamp = now.timeIntervalSince1970
        deepSeekParsing(suite)
        let cases: [(AgentProvider, [String])] = [
            (.claude, [
                #"{"type":"user","timestamp":\#(timestamp),"sessionId":"s","message":{"content":"work"}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":2}}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r2","message":{"id":"m2","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":7}}}"#
            ]),
            (.codex, [
                #"{"type":"session_meta","timestamp":\#(timestamp),"payload":{"id":"s","cwd":"/tmp/example"}}"#,
                #"{"type":"turn_context","timestamp":\#(timestamp),"payload":{"model":"gpt-5.2-codex"}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"task_started"}}"#,
                #"{"type":"token_usage_record","timestamp":\#(timestamp),"payload":{"response_id":"r","usage":{"input_tokens":10,"output_tokens":2}}}"#,
                #"{"type":"token_usage_record","timestamp":\#(timestamp),"payload":{"response_id":"r","usage":{"input_tokens":10,"output_tokens":5}}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"token_count","rate_limits":{"plan_type":"pro","primary":{"used_percent":42,"window_minutes":300}}}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"task_complete","duration_ms":20000}}"#
            ]),
            (.copilot, [
                #"{"id":"start","timestamp":\#(timestamp),"type":"session.start","data":{"sessionId":"s","selectedModel":"gpt-6-sol","context":{"cwd":"/tmp/example"}}}"#,
                #"{"id":"turn","timestamp":\#(timestamp),"type":"user.message","data":{"turnId":"0","content":"private"}}"#,
                #"{"id":"message","timestamp":\#(timestamp),"type":"assistant.message","data":{"model":"gpt-6-sol","content":"private"}}"#,
                #"{"id":"checkpoint","timestamp":\#(timestamp),"type":"session.usage_checkpoint","data":{"totalPremiumRequests":1}}"#,
                #"{"id":"end","timestamp":\#(timestamp),"type":"assistant.turn_end","data":{"turnId":"0"}}"#,
                #"{"id":"usage","timestamp":\#(timestamp),"type":"session.shutdown","data":{"modelMetrics":{"gpt-6-sol":{"requests":{"count":1},"tokenDetails":{"input":{"tokenCount":10},"cache_read":{"tokenCount":20},"cache_write":{"tokenCount":0},"output":{"tokenCount":5}},"usage":{"reasoningTokens":2}}}}}"#,
                #"{"id":"final-checkpoint","timestamp":\#(timestamp),"type":"session.usage_checkpoint","data":{}}"#
            ])
        ]
        for (provider, lines) in cases {
            // A canonical filename, not a Codex side-thread filename.
            let file = folder.appending(path: "\(provider.rawValue).jsonl")
            do { try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file) }
            catch { suite.expect(false, "the streaming fixture writes its log: \(error)"); continue }

            let cursor = AgentLogCursor(path: file.path, provider: provider)
            var entries: [AgentLogEntry] = []
            let consume: (Data) -> Void = { line in
                switch provider {
                case .claude: entries += AgentLogParser.parseClaude(line, state: &cursor.state, now: now)
                case .codex: entries += AgentLogParser.parseCodex(line, state: &cursor.state, now: now)
                case .opencode: entries += AgentLogParser.parseOpenCode(line, state: &cursor.state, now: now)
                case .copilot: entries += AgentLogParser.parseCopilot(line, state: &cursor.state, now: now)
                case .deepseek: entries += AgentLogParser.parseDeepSeek(line, state: &cursor.state, now: now)
                }
            }
            if provider == .copilot {
                AgentUsageProductionLogReader.readCopilotHistory(cursor, line: consume)
            } else {
                AgentUsageProductionLogReader.readAppended(cursor, line: consume)
            }
            let reference = AgentUsageStore()
            reference.reportsTransitions = true
            let expectedEvents = reference.apply(entries, file: file.path, provider: provider,
                                                 tracksTurns: cursor.tracksTurns, parent: cursor.parent,
                                                 modified: cursor.modified, now: now)
            let host = Host()
            host.store.reportsTransitions = true
            var counts: [Int] = []
            AgentLogReader.beforeLine = { counts.append(host.store.records.count) }
            suite.expect(host.read(file.path, provider: provider), "a \(provider.rawValue) log reports parsed entries")
            AgentLogReader.beforeLine = nil
            suite.expect(counts.contains(where: { $0 > 0 }),
                         "\(provider.rawValue) records are applied before the rest of the log is read")
            suite.expect(host.store.records == reference.records && host.store.turns == reference.turns
                            && host.store.waiting == reference.waiting && host.store.limits == reference.limits
                            && host.store.codexPlan == reference.codexPlan && host.events == expectedEvents,
                         "streaming \(provider.rawValue) preserves duplicate merging, usage, turns, limits, plans and event order")
            suite.expect((provider == .copilot || !expectedEvents.isEmpty)
                            && host.cursors[file.path]?.state == cursor.state,
                         "\(provider.rawValue) retains the same parser context without replaying historical finishes")
            suite.expect(!host.read(file.path, provider: provider) && host.events == expectedEvents,
                         "an unchanged \(provider.rawValue) file neither changes the store nor replays events")
            host.readerCancellation?.isCancelled = true
            suite.expect(!host.read(file.path, provider: provider), "a cancelled reading consumes no more entries")
        }
        startup(suite, folder: folder.appending(path: "home"), cases: cases)

        let openFile = folder.appending(path: "copilot-open.jsonl")
        let openLines = [
            #"{"id":"start","timestamp":"2026-09-27T15:00:00.000Z","type":"session.start","data":{"sessionId":"open","selectedModel":"gpt-6-sol","context":{"cwd":"/tmp/open-project"}}}"#,
            #"{"id":"turn","timestamp":"2026-09-27T15:01:00.000Z","type":"user.message","data":{"content":"still working"}}"#,
            #"{"id":"iteration","timestamp":"2026-09-27T15:01:01.000Z","type":"assistant.turn_start","data":{"turnId":"0"}}"#,
            #"{"id":"reply","timestamp":"2026-09-27T15:01:30.000Z","type":"assistant.message","data":{"model":"gpt-6-sol","content":"in progress","toolRequests":[{"name":"read_file","toolCallId":"tool"}]}}"#,
            #"{"id":"checkpoint","timestamp":"2026-09-27T15:01:45.000Z","type":"session.usage_checkpoint","data":{"totalPremiumRequests":0}}"#,
            #"{"id":"intermediate-end","timestamp":"2026-09-27T15:01:46.000Z","type":"assistant.turn_end","data":{"turnId":"0"}}"#,
            #"{"id":"next-iteration","timestamp":"2026-09-27T15:01:47.000Z","type":"assistant.turn_start","data":{"turnId":"1"}}"#
        ]
        try? Data((openLines.joined(separator: "\n") + "\n").utf8).write(to: openFile)
        let openHost = Host()
        suite.expect(openHost.read(openFile.path, provider: .copilot)
                        && openHost.store.turns[openFile.path]?.project == "open-project"
                        && openHost.store.turns[openFile.path]?.model == "gpt-6-sol"
                        && openHost.cursors[openFile.path]?.state.turnOpen == true
                        && openHost.store.records.count == 1,
                     "startup restores ongoing Copilot work after a checkpoint and an intermediate tool turn-end")
        if let handle = try? FileHandle(forWritingTo: openFile) {
            _ = try? handle.seekToEnd()
            let end = [
                #"{"id":"final","timestamp":"2026-09-27T15:01:59.000Z","type":"assistant.message","data":{"content":"done"}}"#,
                #"{"id":"end","timestamp":"2026-09-27T15:02:00.000Z","type":"assistant.turn_end","data":{"turnId":"1"}}"#
            ]
            try? handle.write(contentsOf: Data((end.joined(separator: "\n") + "\n").utf8))
            try? handle.close()
        }
        openHost.store.reportsTransitions = true
        suite.expect(openHost.read(openFile.path, provider: .copilot)
                        && openHost.cursors[openFile.path]?.state.turnOpen == false
                        && openHost.store.turns[openFile.path] == nil,
                     "the restored Copilot turn finishes when its root assistant turn-end arrives")

        // Exercise the production watcher callback, not only discovery.
        let root = folder.appending(path: "session-state")
        let session = root.appending(path: "demo")
        let workspace = session.appending(path: "workspace/nested")
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let real = session.appending(path: "events.jsonl")
        let nested = workspace.appending(path: "events.jsonl")
        let arbitrary = session.appending(path: "data.jsonl")
        let bytes = Data((openLines.joined(separator: "\n") + "\n").utf8)
        for file in [real, nested, arbitrary] { try? bytes.write(to: file) }
        let watcher = Host()
        watcher.watchedRoots = [AgentLogRoot(provider: .copilot, url: root)]
        watcher.filesChanged([nested.path, arbitrary.path, real.path], rescan: false)
        suite.expect(Set(watcher.cursors.keys) == [real.path] && watcher.store.records.count == 1,
                     "Copilot file watching admits only each session's event log and never its workspace JSONL")
        watcher.filesChanged([], rescan: true)
        suite.expect(Set(watcher.cursors.keys) == [real.path] && watcher.store.records.count == 1,
                     "Copilot rescans use the same path boundary and do not duplicate live activity")
    }

    private static func startup(_ suite: TestSuite, folder: URL, cases: [(AgentProvider, [String])]) {
        defer { AgentLogReader.beforeLine = nil }
        for (provider, lines) in cases {
            guard let root = AgentLogRoot.all(home: folder).first(where: { $0.provider == provider }) else {
                suite.expect(false, "the startup fixture has a root for \(provider)")
                return
            }
            let file = root.url.appending(path: "session/events.jsonl")
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
            } catch { suite.expect(false, "the startup fixture writes its log: \(error)"); return }
        }
        let host = Host()
        host.home = folder
        // A changed provider selection resets the displayed snapshot before
        // starting a fresh pass, just as stop()/syncWithPreferences() do.
        for (index, item) in cases.enumerated() {
            let provider = item.0
            host.snapshot = AgentUsageSnapshot()
            host.publications.removeAll()
            var readings: [(loaded: Bool, publications: Int, records: Int)] = []
            AgentLogReader.beforeLine = {
                readings.append((host.snapshot.loaded, host.publications.count, host.store.records.count))
            }
            host.start(session: index + 1, providers: [provider], cancellation: Cancellation())
            suite.expect(!readings.isEmpty && readings.allSatisfy { !$0.loaded && $0.publications == 0 },
                         "\(provider) startup stays in Reading usage until the entire history pass finishes")
            suite.expect(readings.contains { $0.records > 0 },
                         "\(provider) startup still streams records into the store while the page is loading")
            suite.expect(host.publications.count == 1 && host.snapshot.loaded
                            && host.snapshot.seen == [provider] && !host.store.records.isEmpty,
                         "\(provider) startup publishes populated history once, without an empty summary-cache baseline")
        }

        let cancelled = Host()
        cancelled.home = folder
        let cancellation = Cancellation()
        var cancelledDuringRead = false
        AgentLogReader.beforeLine = {
            if !cancelled.store.records.isEmpty {
                cancellation.isCancelled = true
                cancelledDuringRead = true
            }
        }
        cancelled.start(session: 1, providers: [.copilot], cancellation: cancellation)
        suite.expect(cancelledDuringRead && !cancelled.snapshot.loaded && cancelled.publications.isEmpty,
                     "cancelling during the initial pass never publishes partial history as loaded")
        AgentLogReader.beforeLine = nil
        let stopped = Host()
        stopped.home = folder
        stopped.start(session: 2, providers: [.copilot], cancellation: cancellation)
        suite.expect(!stopped.snapshot.loaded && stopped.publications.isEmpty && stopped.store.records.isEmpty,
                     "an already cancelled startup cannot publish an empty loaded snapshot")

        let empty = Host()
        empty.home = folder.appending(path: "empty-home")
        empty.start(session: 1, providers: Set(AgentProvider.allCases), cancellation: Cancellation())
        suite.expect(empty.publications.count == 1 && empty.snapshot.loaded && empty.snapshot.seen.isEmpty,
                     "a completed pass with genuinely no history leaves the loading state")

    }

    /// The Harness's projection is the session's current state, rewritten whole
    /// as it runs, so the same session is read again on every poll. Its totals
    /// are cumulative: reading the same state twice must count it once, and the
    /// turn must open, stay open while work runs, and end exactly once.
    static func deepSeekParsing(_ suite: TestSuite) {
        // 2026-10-05 is a Monday, 02:00 UTC, the hour DeepSeek bills as off peak.
        let stamp = Date(timeIntervalSince1970: 1_791_165_600)
        /// `steps` and `output` are the counters the Harness advances as it
        /// works. They are the only evidence of work there is: the projection
        /// is rewritten for reasons unrelated to it, and a projection belonging
        /// to a conversation untouched for twenty-two hours was still being
        /// written, so neither the file's arrival nor its own time says anything.
        func projection(turn: Int, working: Bool, input: Int, cacheRead: Int, output: Int,
                        steps: Int, started: Date? = nil) -> String {
            """
            {"type":"state","session":"s","tokens":{"input":\(input),"cacheWrite":0,\
            "cacheRead":\(cacheRead),"output":\(output)},"turn":\(turn),"working":\(working),\
            "started":\((started ?? stamp).timeIntervalSince1970),"steps":\(steps),\
            "cwd":"/tmp/deepseek-project","model":"deepseek-flash"}
            """
        }
        func entries(_ line: String, _ state: inout AgentLogState) -> [AgentLogEntry] {
            AgentLogParser.parseDeepSeek(Data(line.utf8), state: &state, now: stamp)
        }
        /// A reading arriving one second later, as the poller delivers it.
        func later(_ state: inout AgentLogState, _ line: String, _ seconds: TimeInterval) -> [AgentLogEntry] {
            AgentLogParser.parseDeepSeek(Data(line.utf8), state: &state, now: stamp.addingTimeInterval(seconds))
        }

        let store = AgentUsageStore()
        store.reportsTransitions = true
        let path = "projection-s.json"
        var state = AgentLogState()

        // A session mid-turn, with its counters where they stand.
        let opening = entries(projection(turn: 1, working: true, input: 1_000, cacheRead: 0, output: 100, steps: 5), &state)
        let firstEvents = store.apply(opening, file: path, provider: .deepseek, tracksTurns: true,
                                      modified: stamp, now: stamp)
        suite.expect(store.records.count == 1 && store.records.first?.provider == .deepseek
                        && store.records.first?.project == "deepseek-project"
                        && store.records.first?.session == "s" && store.records.first?.model == "deepseek-flash",
                     "a Harness session is recorded with its project, session and model")
        suite.expect(store.live.count == 1 && firstEvents.isEmpty,
                     "the turn is shown working, and nothing has finished yet")
        // The app starts with a fresh state, so the first look at a session that
        // finished hours ago must not read as new work. Its counters are only a
        // baseline; nothing has been seen to move yet.
        let coldStart = AgentUsageStore()
        coldStart.reportsTransitions = true
        var coldState = AgentLogState()
        _ = coldStart.apply(entries(projection(turn: 4, working: false, input: 9_000, cacheRead: 0,
                                               output: 268_677, steps: 298), &coldState),
                            file: "finished.json", provider: .deepseek, tracksTurns: true,
                            modified: stamp, now: stamp)
        suite.expect(coldStart.live.isEmpty,
                     "a conversation finished hours ago is not started live by the first look")

        // The same counters again, as the next poll delivers them: one record,
        // one turn, and no claim that work happened.
        _ = store.apply(later(&state, projection(turn: 1, working: true, input: 1_000, cacheRead: 0, output: 100,
                                                 steps: 5), 30),
                        file: path, provider: .deepseek, tracksTurns: true, modified: stamp, now: stamp)
        suite.expect(store.records.count == 1 && store.live.count == 1,
                     "reading the session's running totals again does not count them twice")
        suite.expect(store.live.first?.lastActivity == stamp,
                     "a projection that arrived without its counters moving is not counted as work")

        // The Harness stops to ask something. The projection says so only by
        // its question list becoming non-empty; it keeps no tool names, so
        // this is the one readable sign.
        var askState = AgentLogState()
        let askStore = AgentUsageStore()
        askStore.reportsTransitions = true
        func asking(_ active: String, turn: Int = 1) -> String {
            """
            {"type":"state","session":"q","tokens":{"input":1,"cacheWrite":0,"cacheRead":0,"output":1},\
            "turn":\(turn),"working":true,"started":\(stamp.timeIntervalSince1970),"steps":1,\
            "waitingForAnswer":\(active),"cwd":"/tmp/asked","model":"deepseek-flash"}
            """
        }
        func ask(_ line: String, _ seconds: TimeInterval) -> [AgentUsageEvent] {
            let at = stamp.addingTimeInterval(seconds)
            let entries = AgentLogParser.parseDeepSeek(Data(line.utf8), state: &askState, now: at)
            return askStore.apply(entries, file: "asked.json", provider: .deepseek, tracksTurns: true,
                                  modified: at, now: at)
        }
        func asked(_ events: [AgentUsageEvent]) -> Bool {
            events.contains { if case .question = $0 { return true } else { return false } }
        }
        suite.expect(!asked(ask(asking("false"), 0)), "a working Harness raises no question notice")
        suite.expect(asked(ask(asking("true"), 30)), "a Harness waiting on an answer raises one")
        suite.expect(!asked(ask(asking("true"), 60)),
                     "the same question read again does not raise a second notice")
        suite.expect(!asked(ask(asking("false"), 90)), "the answer clears the waiting state")
        suite.expect(asked(ask(asking("true", turn: 2), 120)),
                     "a later question is news again")

        // The counters move: the work is going on, and the activity is now.
        let moving = stamp.addingTimeInterval(60)
        _ = store.apply(later(&state, projection(turn: 1, working: true, input: 2_000, cacheRead: 5_000, output: 400,
                                                 steps: 6), 60),
                        file: path, provider: .deepseek, tracksTurns: true, modified: moving, now: moving)
        let grew = store.records.first
        suite.expect(grew?.tokens.input == 2_000 && grew?.tokens.cacheRead == 5_000 && grew?.tokens.output == 400,
                     "a growing session replaces the reading rather than adding a second one")
        suite.expect(store.live.count == 1 && store.records.count == 1
                        && store.live.first?.lastActivity == moving,
                     "counters that moved mark the turn as alive at that reading")

        // The Harness stops. The counters stop with it, and the step closes.
        let closing = store.apply(later(&state, projection(turn: 1, working: false, input: 2_000, cacheRead: 5_000,
                                                          output: 400, steps: 6), 90),
                                  file: path, provider: .deepseek, tracksTurns: true,
                                  modified: stamp.addingTimeInterval(90), now: stamp.addingTimeInterval(90))
        let ended = closing.contains { (event: AgentUsageEvent) -> Bool in
            if case .finished(let provider, _, _, _, _) = event { return provider == .deepseek }
            return false
        }
        suite.expect(ended, "the turn is reported finished when the Harness stops")
        suite.expect(store.live.isEmpty, "a stopped session leaves nothing working")
        // Reading the stopped state again neither ends it twice nor reopens it.
        let again = store.apply(later(&state, projection(turn: 1, working: false, input: 2_000, cacheRead: 5_000,
                                                        output: 400, steps: 6), 120),
                                file: path, provider: .deepseek, tracksTurns: true,
                                modified: stamp.addingTimeInterval(120), now: stamp.addingTimeInterval(120))
        suite.expect(again.isEmpty && store.records.count == 1 && store.live.isEmpty,
                     "a settled session read again reports nothing with a banner from before")

        // A second prompt opens the next turn, and the counters keep rising.
        let second = store.apply(later(&state, projection(turn: 2, working: true, input: 3_000, cacheRead: 9_000,
                                                         output: 900, steps: 9), 150),
                                 file: path, provider: .deepseek, tracksTurns: true,
                                 modified: stamp.addingTimeInterval(150), now: stamp.addingTimeInterval(150))
        // Opening a turn is bookkeeping, not a banner, so `apply` reports
        // nothing for it; what shows is that exactly one turn is working.
        suite.expect(second.isEmpty && store.live.count == 1 && store.live.first?.tokens.input == 3_000,
                     "the next prompt opens the next turn, silently, with its own reading")
        suite.expect(store.records.count == 2, "each turn keeps its own countable reading")
        suite.expect(store.records.allSatisfy { ($0.cost ?? 0) > 0 },
                     "each turn is priced from the shipped list")

        // The wait is measured from the prompt, not from when this Mac first
        // read the projection: a session already running when the app starts
        // must show the hour it has run, not zero.
        let longRunning = AgentUsageStore()
        longRunning.reportsTransitions = true
        var runState = AgentLogState()
        let began = stamp.addingTimeInterval(-3_600)
        _ = longRunning.apply(entries(projection(turn: 1, working: true, input: 10, cacheRead: 0, output: 1,
                                                 steps: 1, started: began), &runState),
                              file: "running.json", provider: .deepseek, tracksTurns: true,
                              modified: stamp, now: stamp)
        suite.expect(longRunning.live.first?.started == began,
                     "a session already running is measured from its prompt, not from the reading")

        // A projection that keeps arriving without its counters moving never
        // counts as work, so the turn goes idle and is ended. This is the
        // reported symptom: a finished conversation still counting upward.
        let stalled = AgentUsageStore()
        stalled.reportsTransitions = true
        var stallState = AgentLogState()
        _ = stalled.apply(entries(projection(turn: 1, working: true, input: 10, cacheRead: 0, output: 1,
                                             steps: 1, started: stamp), &stallState),
                          file: "stalled.json", provider: .deepseek, tracksTurns: true,
                          modified: stamp, now: stamp)
        suite.expect(stalled.live.count == 1, "the session is working while its counters stand")
        // Ten more minutes of the same projection arriving, counters unmoved.
        for minute in stride(from: 30.0, through: 600.0, by: 30.0) {
            let at = stamp.addingTimeInterval(minute)
            _ = stalled.apply(later(&stallState, projection(turn: 1, working: true, input: 10, cacheRead: 0,
                                                            output: 1, steps: 1), minute),
                              file: "stalled.json", provider: .deepseek, tracksTurns: true,
                              modified: at, now: at)
            stalled.closeIdleTurns(now: at, after: AgentUsageStore.idleTurn(for:))
        }
        suite.expect(stalled.live.isEmpty,
                     "a projection whose counters never move does not hold a turn open")

        // The Harness is counted over sooner than an agent that logs per event,
        // since once its projection stops being rewritten the work has stopped.
        suite.expect(AgentUsageStore.idleTurn(for: .deepseek) < AgentUsageStore.idleTurn(for: .claude)
                        && AgentUsageStore.idleTurn(for: .deepseek) < AgentUsageStore.idleTurn(for: .codex)
                        && AgentUsageStore.idleTurn(for: .deepseek) <= 45,
                     "a quiet Harness is counted over sooner than an agent that logs per event")

        deepSeekReader(suite, stamp: stamp)
    }

    /// The reader walks the Harness's own projection layout, so it is driven
    /// over a file written the way the Harness writes one, fields around the
    /// ones it reads included, which it has to step over.
    private static func deepSeekReader(_ suite: TestSuite, stamp: Date) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-dsh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the projection fixture creates its folder: \(error)"); return }

        /// A projection written the way the Harness writes one: the fields the
        /// reader reads, plus the ones around them it has to step over. The
        /// identity carries no id, because the real one does not either — the
        /// file's own name is the session.
        func projection(version: Int, turn: Int = 1, openStep: Any = NSNull(),
                        pending: [String: Any] = [:]) -> Data {
            let body: [String: Any] = [
                "version": version,
                "record": [
                    "identity": ["formatVersion": 4, "createdAt": 1_791_165_500_000,
                                 "cwd": "/Users/someone/Documents/git projects/graft",
                                 "isSeeded": false, "inheritedEventCount": 0],
                    "rows": [
                        "title": ["ver": 1, "seq": 1149, "val": "a long prompt the reader must step over"],
                        "tokenUsage": ["ver": 2, "seq": 1149, "val": [
                            "totals": ["uncachedInputTokens": 103_149, "outputTokens": 388_597,
                                       "cacheReadTokens": 49_798_528, "cacheWriteTokens": 7],
                            "last": ["turn": 1, "step": 183, "buckets": [:]] as [String: Any],
                        ]],
                        "sessionStats": ["ver": 1, "seq": 1149, "val": [
                            "turns": 1, "steps": 183, "llmMs": 1_877_149, "lastTurn": turn,
                            "openStep": openStep, "pendingCalls": pending,
                        ]],
                        "modelSelection": ["ver": 1, "seq": 9, "val": [
                            "lastUsed": ["provider": "deepseek-account", "model": "deepseek-flash"],
                            "pending": NSNull(),
                        ]],
                        "sessionListMetadata": ["ver": 1, "seq": 1149, "val": [
                            "blank": false, "lastPromptAt": Int(stamp.timeIntervalSince1970 * 1000),
                        ]],
                    ],
                ],
            ]
            return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        }

        func read(_ body: Data, name: String) -> [[String: Any]] {
            let file = folder.appending(path: name)
            do { try body.write(to: file) }
            catch { suite.expect(false, "the projection fixture writes: \(error)"); return [] }
            var lines: [[String: Any]] = []
            AgentDeepSeekReader.read(file.path) { line in
                if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { lines.append(object) }
            }
            return lines
        }

        let working = read(projection(version: AgentDeepSeekReader.version,
                                      openStep: ["step": 299, "turn": 1, "startTime": 1_791_165_742_195]),
                           name: "working.json")
        guard let state = working.first else {
            suite.expect(false, "a working projection is read into one object"); return
        }
        suite.expect(working.count == 1 && state["type"] as? String == "state"
                        && state["session"] as? String == "working.json"
                        && state["cwd"] as? String == "/Users/someone/Documents/git projects/graft"
                        && state["model"] as? String == "deepseek-flash"
                        && state["working"] as? Bool == true,
                     "the projection's session, folder, model and turn are read, and it is seen working")
        let tokens = state["tokens"] as? [String: Int] ?? [:]
        suite.expect(tokens["input"] == 103_149 && tokens["cacheRead"] == 49_798_528
                        && tokens["output"] == 388_597 && tokens["cacheWrite"] == 7,
                     "the running totals come through in the shape the parser counts")
        suite.expect(AgentLogParser.seconds(state["started"]) == stamp,
                     "the turn is dated by the prompt, not by when the projection was read")
        suite.expect(state["modified"] == nil,
                     "no file time is carried: it proves nothing about whether work is going on")
        // The counters are what judge activity, so they come through too.
        suite.expect(state["steps"] as? Int == 183 && state["output"] as? Int == 388_597,
                     "the projection's work counters come through for the parser to watch")
        suite.expect(state["turn"] as? Int == 1,
                     "the turn's number survives the number-versus-boolean bridging JSON round trips through (saw \(String(describing: state["turn"])))")

        // Between steps, with a tool call outstanding, the loop is still working.
        let between = read(projection(version: AgentDeepSeekReader.version,
                                      pending: ["call_00_x": 1_791_165_500_000]), name: "between.json")
        suite.expect(between.first?["working"] as? Bool == true,
                     "a session waiting on a tool call still reads as working")
        let idle = read(projection(version: AgentDeepSeekReader.version), name: "idle.json")
        suite.expect(idle.first?["working"] as? Bool == false, "an idle session reads as not working")

        // A projection from a later Harness is left alone rather than guessed at.
        suite.expect(read(projection(version: AgentDeepSeekReader.version + 1), name: "newer.json").isEmpty,
                     "a projection written by a newer Harness is not read as if it were this one")
        suite.expect(read(Data(#"{"version":7}"#.utf8), name: "shallow.json").isEmpty
                        && read(Data("not json at all".utf8), name: "broken.json").isEmpty,
                     "a projection without the fields it reads is ignored")
    }
}
