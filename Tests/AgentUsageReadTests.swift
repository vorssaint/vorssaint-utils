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
        static func readAppended(_ cursor: AgentLogCursor, shouldContinue: () -> Bool, line: (Data) -> Void) {
            AgentUsageProductionLogReader.readAppended(cursor, shouldContinue: shouldContinue) {
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
        var syncedRoots: [AgentLogRoot] = []
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
        func syncPolling() {}
        func watchNetwork() {}
        func publish() {
            snapshot = store.snapshot(plans: [:], providers: enabled, now: Date())
            publications.append(snapshot)
        }
        func report(_ event: AgentUsageEvent, allDone: Bool = false) {
            events.append(event)
            if allDone { allDoneEvents.append(event) }
        }
        var allDoneEvents: [AgentUsageEvent] = []
        var peakTurns = 0
        var attentionSchedule = AgentAttentionSchedule()
        var starts: [AgentProvider] = []
        func reportStart(_ provider: AgentProvider) { starts.append(provider) }
        var interrupts: [AgentProvider] = []
        func reportInterrupt(_ provider: AgentProvider) { interrupts.append(provider) }
        func observeFrontmost() {}
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
            ])
        ]
        for (provider, lines) in cases {
            let file = folder.appending(path: "\(provider.rawValue).jsonl")
            do { try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file) }
            catch { suite.expect(false, "the streaming fixture writes its log: \(error)"); continue }

            let cursor = AgentLogCursor(path: file.path, provider: provider)
            var entries: [AgentLogEntry] = []
            AgentUsageProductionLogReader.readAppended(cursor) { line in
                entries += provider.reader.parse(line, state: &cursor.state, now: now)
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
                            && host.events == expectedEvents,
                         "streaming \(provider.rawValue) preserves duplicate merging, usage, turns, limits and event order")
            suite.expect(!expectedEvents.isEmpty && host.cursors[file.path]?.state == cursor.state,
                         "\(provider.rawValue) retains the same parser context without replaying historical finishes")
            suite.expect(!host.read(file.path, provider: provider) && host.events == expectedEvents,
                         "an unchanged \(provider.rawValue) file neither changes the store nor replays events")
            host.readerCancellation?.isCancelled = true
            suite.expect(!host.read(file.path, provider: provider), "a cancelled reading consumes no more entries")
        }
        startup(suite, folder: folder.appending(path: "home"), cases: cases)
        allDone(suite, folder: folder)

        // Exercise the production watcher callback, not only discovery.
        let root = folder.appending(path: "projects")
        let project = root.appending(path: "-Users-me-app")
        let versions = root.appending(path: ".stversions/-Users-me-app")
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        let real = project.appending(path: "session.jsonl")
        let copy = versions.appending(path: "session~20261101-120000.jsonl")
        let other = project.appending(path: "notes.txt")
        let bytes = Data((cases[0].1.joined(separator: "\n") + "\n").utf8)
        for file in [real, copy, other] { try? bytes.write(to: file) }
        let watcher = Host()
        watcher.watchedRoots = [AgentLogRoot(provider: .claude, url: root)]
        watcher.filesChanged([copy.path, other.path, real.path], rescan: false)
        suite.expect(Set(watcher.cursors.keys) == [real.path] && watcher.store.records.count == 2,
                     "file watching admits Claude's logs and never a sync tool's old versions or other files")
        watcher.filesChanged([], rescan: true)
        suite.expect(Set(watcher.cursors.keys) == [real.path] && watcher.store.records.count == 2,
                     "rescans use the same path boundary and do not duplicate live activity")
    }

    /// The last of several turns that ran together is heard as all done;
    /// a turn that ran alone, or one that left others working, is not.
    private static func allDone(_ suite: TestSuite, folder: URL) {
        let now = Date().timeIntervalSince1970
        let host = Host()
        host.store.reportsTransitions = true
        func write(_ name: String, _ lines: [String]) {
            let file = folder.appending(path: "all-done-\(name).jsonl")
            let old = (try? Data(contentsOf: file)) ?? Data()
            try? (old + Data((lines.joined(separator: "\n") + "\n").utf8)).write(to: file)
            _ = host.read(file.path, provider: .claude)
        }
        let start = #"{"type":"user","timestamp":\#(now - 60),"sessionId":"s","message":{"content":"work"}}"#
        func done(_ name: String) -> String {
            #"{"type":"assistant","timestamp":\#(now),"sessionId":"s","requestId":"r-\#(name)","message":{"id":"m-\#(name)","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}}"#
        }
        write("solo", [start])
        write("solo", [done("solo")])
        suite.expect(host.events.count == 1 && host.allDoneEvents.isEmpty, "a turn that ran alone is only finished")
        write("a", [start])
        write("b", [start])
        write("a", [done("a")])
        suite.expect(host.events.count == 2 && host.allDoneEvents.isEmpty, "a turn that leaves another working is only finished")
        write("b", [done("b")])
        suite.expect(host.events.count == 3 && host.allDoneEvents.count == 1, "the last of two turns that ran together is all done")
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
            host.start(session: index + 1, providers: [provider], synced: [], cancellation: Cancellation())
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
        cancelled.start(session: 1, providers: [.claude], synced: [], cancellation: cancellation)
        suite.expect(cancelledDuringRead && !cancelled.snapshot.loaded && cancelled.publications.isEmpty,
                     "cancelling during the initial pass never publishes partial history as loaded")
        AgentLogReader.beforeLine = nil
        let stopped = Host()
        stopped.home = folder
        stopped.start(session: 2, providers: [.claude], synced: [], cancellation: cancellation)
        suite.expect(!stopped.snapshot.loaded && stopped.publications.isEmpty && stopped.store.records.isEmpty,
                     "an already cancelled startup cannot publish an empty loaded snapshot")

        let empty = Host()
        empty.home = folder.appending(path: "empty-home")
        empty.start(session: 1, providers: Set(AgentProvider.allCases), synced: [], cancellation: Cancellation())
        suite.expect(empty.publications.count == 1 && empty.snapshot.loaded && empty.snapshot.seen.isEmpty,
                     "a completed pass with genuinely no history leaves the loading state")
    }
}
