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
        var readerClaudeProfile = ClaudeAccountProfile()
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
        func syncPolling() {}
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
        codexThreads(suite, folder: folder)

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

    private static func codexThreads(_ suite: TestSuite, folder: URL) {
        let now = Date().timeIntervalSince1970
        let host = Host()
        host.store.reportsTransitions = true
        func write(_ name: String, _ lines: [String], append: Bool = false, into target: Host? = nil) -> URL {
            let file = folder.appending(path: name)
            let data = Data((lines.joined(separator: "\n") + "\n").utf8)
            if append, let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else { try? data.write(to: file) }
            _ = (target ?? host).read(file.path, provider: .codex)
            return file
        }
        // Editing an earlier message reverts the thread: its turn stops, and
        // the thread goes on in a log named after it and a new rollout.
        let thread = "01a14017-9c92-7862-8f2a-2019293313fe"
        let original = write("rollout-2026-10-16T10-00-00-\(thread).jsonl", [
            #"{"type":"session_meta","timestamp":\#(now - 30),"payload":{"id":"\#(thread)","source":"vscode"}}"#,
            #"{"type":"event_msg","timestamp":\#(now - 29),"payload":{"type":"task_started"}}"#
        ])
        suite.expect(host.store.live.count == 1, "a new Codex main thread is live")
        _ = write(original.lastPathComponent, [
            #"{"type":"event_msg","timestamp":\#(now - 20),"payload":{"type":"turn_aborted"}}"#
        ], append: true)
        let reverted = write("rollout-2026-10-16T10-20-00-\(thread)_01a14099-0000-7000-8000-000000000001.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now - 10),"payload":{"id":"\#(thread)","source":"vscode"}}"#,
            #"{"type":"event_msg","timestamp":\#(now - 9),"payload":{"type":"task_started"}}"#,
            #"{"type":"token_usage_record","timestamp":\#(now - 8),"payload":{"response_id":"revert-response","usage":{"input_tokens":10,"output_tokens":4}}}"#,
            #"{"type":"event_msg","timestamp":\#(now - 8),"payload":{"type":"token_count","rate_limits":{"plan_type":"plus","primary":{"used_percent":35,"window_minutes":300}}}}"#
        ])
        suite.expect(host.store.live.count == 1 && host.store.live.first?.id == reverted.path
                        && host.store.live.first?.tokens.total == 14 && host.store.records.count == 1
                        && host.store.limits[.codex] != nil && host.events.isEmpty,
                     "a reverted Codex thread goes on in its underscored log with its live turn, usage and limits")
        // Subagents, Guardian reviews and memory tasks have ordinary log
        // names, and a child can copy its parent's history, metadata included.
        let children = [("spawned", #"{"subagent":{"thread_spawn":{"parent_thread_id":"\#(thread)","depth":1}}}"#),
                        ("guardian", #"{"subagent":{"other":"guardian"}}"#),
                        ("compact", #"{"subagent":"compact"}"#),
                        ("memory", #"{"internal":"memory_consolidation"}"#)]
        for (index, (kind, source)) in children.enumerated() {
            let file = write("child\(index).jsonl", [
                #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"child-\#(index)","source":\#(source)}}"#,
                #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"\#(thread)","source":"vscode"}}"#,
                #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"task_started"}}"#
            ])
            suite.expect(host.cursors[file.path]?.tracksTurns == false
                            && host.cursors[file.path]?.state.session == "child-\(index)" && host.store.live.count == 1,
                         "a Codex \(kind) log keeps its own metadata and owns no turn when its parent's is copied after it")
        }
        // A subagent's responses count toward its thread's turn and keep it
        // working while the thread only waits on it.
        host.store.closeIdleTurns(now: Date(timeIntervalSince1970: now + 600), after: 120)
        suite.expect(host.store.live.isEmpty, "a quiet Codex thread stops showing as working")
        _ = write("worker.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now + 580),"payload":{"id":"worker","session_id":"\#(thread)","parent_thread_id":"\#(thread)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\#(thread)","depth":1}}}}}"#,
            #"{"type":"event_msg","timestamp":\#(now + 580),"payload":{"type":"task_started"}}"#,
            #"{"type":"token_usage_record","timestamp":\#(now + 590),"payload":{"response_id":"worker-response","usage":{"input_tokens":6,"output_tokens":1}}}"#
        ])
        suite.expect(host.store.live.count == 1 && host.store.live.first?.id == reverted.path
                        && host.store.live.first?.tokens.total == 21,
                     "a Codex subagent's responses count toward its thread's turn and keep it working while the thread waits")
        let saved = AgentUsageReadProductionArchive.Contents(providers: [.codex], store: host.store.saved,
                                                             cursors: host.cursors.values.map(\.saved))
        let encoded = AgentUsageReadProductionArchive.encode(saved, build: "codex-thread-test")
        let decoded = AgentUsageReadProductionArchive.decode(encoded, build: "codex-thread-test")
        suite.expect(decoded == saved, "Codex thread identity survives an archive round trip")
        if let decoded {
            let restored = AgentUsageReadProductionArchive.resume(decoded, logs: Set(host.cursors.keys), since: .distantPast)
            suite.expect(restored.cursors[reverted.path]?.tracksTurns == true
                            && restored.cursors[folder.appending(path: "child0.jsonl").path]?.tracksTurns == false,
                         "restored Codex cursors preserve main and subagent identity without rereading metadata")
            let restoredHost = Host()
            restoredHost.cursors = restored.cursors
            restoredHost.store = restored.store
            _ = write("worker.jsonl", [
                #"{"type":"token_usage_record","timestamp":\#(now + 595),"payload":{"response_id":"worker-response-2","usage":{"input_tokens":2,"output_tokens":1}}}"#
            ], append: true, into: restoredHost)
            suite.expect(restoredHost.store.live.first?.id == reverted.path && restoredHost.store.live.first?.tokens.total == 24,
                         "a restored Codex subagent finds its thread's log again")
            _ = write("child0.jsonl", [
                #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"\#(thread)","source":"vscode"}}"#,
                #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"task_started"}}"#,
                #"{"type":"token_usage_record","timestamp":\#(now),"payload":{"response_id":"child-response","usage":{"input_tokens":3,"output_tokens":2}}}"#
            ], append: true, into: restoredHost)
            _ = write(reverted.lastPathComponent, [
                #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"task_complete"}}"#
            ], append: true, into: restoredHost)
            suite.expect(restoredHost.store.live.isEmpty && restoredHost.store.records.count == 4,
                         "after cache restore a child adds usage without a turn and the reverted thread's task finishes")
        }
        _ = write(reverted.lastPathComponent, [
            #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"task_complete","duration_ms":9000}}"#
        ], append: true)
        suite.expect(host.store.live.isEmpty && host.events.count == 1,
                     "the reverted thread's task ends exactly once and clears the running indicator")
        // A subagent can be read before its thread's log, and that log can move.
        let early = Host()
        let other = "01a14099-2222-7000-8000-000000000003"
        _ = write("early-child.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"early-child","session_id":"\#(other)","source":{"subagent":{"other":"guardian"}}}}"#,
            #"{"type":"token_usage_record","timestamp":\#(now),"payload":{"response_id":"early-1","usage":{"input_tokens":1,"output_tokens":1}}}"#
        ], into: early)
        let otherLog = write("rollout-2026-10-16T11-00-00-\(other).jsonl", [
            #"{"type":"session_meta","timestamp":\#(now - 5),"payload":{"id":"\#(other)","source":"vscode"}}"#,
            #"{"type":"event_msg","timestamp":\#(now - 5),"payload":{"type":"task_started"}}"#
        ], into: early)
        _ = write("early-child.jsonl", [
            #"{"type":"token_usage_record","timestamp":\#(now + 1),"payload":{"response_id":"early-2","usage":{"input_tokens":2,"output_tokens":2}}}"#
        ], append: true, into: early)
        suite.expect(early.store.live.first?.id == otherLog.path && early.store.live.first?.tokens.total == 4,
                     "a Codex subagent read before its thread's log counts toward it once that log is read")
        let moved = folder.appending(path: "moved-\(otherLog.lastPathComponent)")
        try? FileManager.default.moveItem(at: otherLog, to: moved)
        _ = early.read(otherLog.path, provider: .codex)
        _ = early.read(moved.path, provider: .codex)
        _ = write("early-child.jsonl", [
            #"{"type":"token_usage_record","timestamp":\#(now + 2),"payload":{"response_id":"early-3","usage":{"input_tokens":3,"output_tokens":3}}}"#
        ], append: true, into: early)
        suite.expect(early.store.live.first?.id == moved.path && early.store.live.first?.tokens.total == 6,
                     "a Codex subagent follows its thread's log when the log moves")
        // Logs from before per-response records report running totals, which
        // a child's copy of its parent's history repeats.
        let totals = Host()
        let parentTotals = #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#
        _ = write("totals-parent.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"totals-parent","source":"cli"}}"#,
            parentTotals
        ], into: totals)
        _ = write("totals-child.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"totals-child","source":{"subagent":"review"}}}"#,
            #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"totals-parent","source":"cli"}}"#,
            parentTotals,
            #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":130,"output_tokens":15},"last_token_usage":{"input_tokens":30,"output_tokens":5}}}}"#
        ], into: totals)
        suite.expect(totals.store.records.count == 2 && totals.store.records.map(\.tokens.total).reduce(0, +) == 145
                        && totals.cursors[folder.appending(path: "totals-child.jsonl").path]?.state.session == "totals-child",
                     "a Codex child's copy of its parent's running totals is not counted again")
        let legacy = AgentLogCursor(path: folder.appending(path: "legacy_main.jsonl").path, provider: .codex)
        _ = AgentLogParser.parseCodex(Data(#"{"type":"session_meta","payload":{"id":"legacy"}}"#.utf8),
                                      state: &legacy.state, now: Date())
        let custom = AgentLogCursor(path: folder.appending(path: "custom_client.jsonl").path, provider: .codex)
        _ = AgentLogParser.parseCodex(Data(#"{"type":"session_meta","payload":{"id":"custom","source":{"custom":"editor"}}}"#.utf8),
                                      state: &custom.state, now: Date())
        suite.expect(legacy.tracksTurns && custom.tracksTurns,
                     "Codex threads with no source or a custom client own their turns whatever the file name")
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
}
