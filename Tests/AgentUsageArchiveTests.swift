// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Progress saved by one launch and picked up by the next must leave the
/// store exactly as reading every log from its start would.
enum AgentUsageArchiveTests {
    private static let build = "1.0-1"

    private static func codex(_ time: String, _ json: String) -> String {
        #"{"timestamp":"\#(time)","type":\#(json)}"#
    }

    private static let firstHalf = [
        codex("2026-09-22T14:44:23.000Z", #""session_meta","payload":{"id":"s9","cwd":"/Users/me/code/web"}"#),
        codex("2026-09-22T14:44:24.000Z", #""turn_context","payload":{"model":"gpt-6-astra","cwd":"/Users/me/code/web","service_tier":"fast"}"#),
        codex("2026-09-22T14:44:25.000Z", #""event_msg","payload":{"type":"task_started"}"#),
        codex("2026-09-22T14:44:53.000Z", #""token_usage_record","payload":{"response_id":"r1","usage":{"input_tokens":300,"cached_input_tokens":200,"output_tokens":15,"reasoning_output_tokens":4}}"#),
        codex("2026-09-22T14:44:54.000Z", #""event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1790100000},"secondary":null,"plan_type":"pro"}}"#)
    ]

    private static let secondHalf = [
        codex("2026-09-22T14:50:00.000Z", #""token_usage_record","payload":{"response_id":"r2","usage":{"input_tokens":400,"cached_input_tokens":300,"output_tokens":20}}"#),
        // A duplicate of an earlier response only raises what it counted.
        codex("2026-09-22T14:50:01.000Z", #""token_usage_record","payload":{"response_id":"r1","usage":{"input_tokens":300,"cached_input_tokens":200,"output_tokens":18,"reasoning_output_tokens":4}}"#),
        codex("2026-09-22T14:52:00.000Z", #""event_msg","payload":{"type":"task_complete","duration_ms":20000}"#)
    ]

    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-archive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the archive fixture creates its folder: \(error)"); return }
        let log = folder.appending(path: "rollout.jsonl")
        let now = AgentTimestamp.parse("2026-09-22T15:00:00.000Z")!

        func read(_ cursor: AgentLogCursor, into store: AgentUsageStore) {
            AgentLogReader.readAppended(cursor) { line in
                let entries = AgentLogParser.parseCodex(line, state: &cursor.state, now: now)
                store.apply(entries, file: cursor.path, provider: .codex, tracksTurns: cursor.tracksTurns,
                            parent: cursor.parent, modified: cursor.modified, now: now)
            }
        }
        func write(_ lines: [String], ending: String = "\n") {
            try? Data((lines.joined(separator: "\n") + ending).utf8).write(to: log)
        }

        // One launch reads the first half, with the next line half written.
        let partial = #"{"timestamp":"2026-09-22T14:49:59.000Z","type":"event_msg","payload":{"type":"task_star"#
        write(firstHalf + [partial], ending: "")
        let first = AgentUsageStore()
        let cursor = AgentLogCursor(path: log.path, provider: .codex)
        read(cursor, into: first)
        suite.expect(!cursor.pending.isEmpty && cursor.saved.offset == cursor.offset - UInt64(cursor.pending.count),
                     "progress is saved at the start of a line still being written")
        let contents = AgentUsageArchive.Contents(providers: [.codex], store: first.saved, cursors: [cursor.saved])
        let data = AgentUsageArchive.encode(contents, build: build)
        let decoded = AgentUsageArchive.decode(data, build: build)
        suite.expect(decoded == contents, "saved progress reads back as it was written")
        var sourced = contents
        sourced.store.limits = [AgentLimits.Source.sessionLog, .claudeApp, .account].map {
            AgentLimits(provider: .codex, windows: [], observedAt: now, source: $0)
        }
        suite.expect(AgentUsageArchive.decode(AgentUsageArchive.encode(sourced, build: build), build: build) == sourced,
                     "limits keep where they came from: a log, the Claude app or the account")
        suite.expect(!first.saved.records.isEmpty && !first.saved.limits.isEmpty && first.saved.codexPlan != nil
                        && !first.saved.turns.isEmpty && cursor.state.fast && !cursor.state.model.isEmpty,
                     "the fixture saves records, limits, a plan, an open turn and parser context")

        // The next launch picks up there while the agent keeps writing.
        write(firstHalf + secondHalf)
        let resumed = AgentUsageStore(saved: decoded?.store ?? .init())
        let restored = decoded?.cursors.first.flatMap(AgentLogCursor.init(saved:))
        var resumedLines = 0
        if let restored {
            AgentLogReader.readAppended(restored) { line in
                resumedLines += 1
                let entries = AgentLogParser.parseCodex(line, state: &restored.state, now: now)
                resumed.apply(entries, file: restored.path, provider: .codex, tracksTurns: restored.tracksTurns,
                              parent: restored.parent, modified: restored.modified, now: now)
            }
        }
        let fresh = AgentUsageStore()
        let freshCursor = AgentLogCursor(path: log.path, provider: .codex)
        read(freshCursor, into: fresh)
        suite.expect(resumedLines == secondHalf.count, "a resumed launch reads only what was written since")
        suite.expect(resumed.saved == fresh.saved && restored?.state == freshCursor.state
                        && restored?.offset == freshCursor.offset,
                     "resuming leaves the same records, limits, turns and context as reading from the start")

        // A log replaced meanwhile is read again whole; nothing counts twice.
        let identity = restored?.identity
        try? Data(((firstHalf + secondHalf).joined(separator: "\n") + "\n").utf8).write(to: log, options: .atomic)
        var replacedLines = 0
        if let restored {
            AgentLogReader.readAppended(restored) { line in
                replacedLines += 1
                let entries = AgentLogParser.parseCodex(line, state: &restored.state, now: now)
                resumed.apply(entries, file: restored.path, provider: .codex, tracksTurns: restored.tracksTurns,
                              parent: restored.parent, modified: restored.modified, now: now)
            }
        }
        suite.expect(restored?.identity != identity && replacedLines == firstHalf.count + secondHalf.count
                        && resumed.saved.records == fresh.saved.records,
                     "a replaced log read again from its start merges into what was already counted")

        suite.expect(AgentUsageArchive.decode(data, build: "1.0-2") == nil,
                     "progress another build saved is not used")
        let damaged = [Data(), data.prefix(4), data.prefix(data.count / 2), data.dropLast(), data + Data([0])]
        suite.expect(damaged.allSatisfy { AgentUsageArchive.decode($0, build: build) == nil },
                     "a short, cut or padded file reads as nothing")
        // One changed bit can turn a count of 1 into -2 and still decode.
        var flipped = data
        var accepted: [Int] = []
        for position in 4..<flipped.count {
            for bit in 0..<8 {
                flipped[position] ^= 1 << bit
                if AgentUsageArchive.decode(flipped, build: build) != nil { accepted.append(position) }
                flipped[position] ^= 1 << bit
            }
        }
        suite.expect(accepted.isEmpty && AgentUsageArchive.decode(flipped, build: build) == contents,
                     "every changed bit is rejected rather than restored as other counts")
        var negative = contents
        if let first = negative.store.records.first {
            var record = first.record
            record.tokens.output = -2
            negative.store.records[0] = .init(key: first.key, record: record, billable: first.billable,
                                            sources: first.sources)
        }
        suite.expect(AgentUsageArchive.decode(AgentUsageArchive.encode(negative, build: build), build: build) == nil,
                     "a negative count is rejected even under a valid checksum, as the parser rejects it")

        // A log cut short and written again in place keeps its inode but
        // not its contents, and here grows past where reading stopped. The
        // next launch counts only what it holds now, as a fresh read would.
        func inode() -> UInt64 {
            var info = stat()
            return stat(log.path, &info) == 0 ? UInt64(info.st_ino) : 0
        }
        func readFresh(_ paths: [URL]) -> (store: AgentUsageStore, cursors: [AgentLogCursor]) {
            let store = AgentUsageStore()
            let cursors = paths.map { AgentLogCursor(path: $0.path, provider: .codex) }
            cursors.forEach { read($0, into: store) }
            return (store, cursors)
        }
        func saving(_ read: (store: AgentUsageStore, cursors: [AgentLogCursor])) -> AgentUsageArchive.Contents {
            AgentUsageArchive.Contents(providers: [.codex], store: read.store.saved, cursors: read.cursors.map(\.saved))
        }
        write(firstHalf + secondHalf)
        let original = saving(readFresh([log]))
        let inodeBefore = inode()
        let unchanged = AgentUsageArchive.resume(original, logs: [log.path], since: .distantPast)
        suite.expect(unchanged.cursors[log.path] != nil && unchanged.unchanged,
                     "an unchanged log resumes, with nothing left to save")
        let rewritten = (firstHalf + secondHalf + secondHalf)
            .map { $0.replacingOccurrences(of: #""response_id":"r"#, with: #""response_id":"x"#) }
        if let handle = try? FileHandle(forWritingTo: log) {
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: Data((rewritten.joined(separator: "\n") + "\n").utf8))
            try? handle.close()
        }
        let afterRewrite = AgentUsageArchive.resume(original, logs: [log.path], since: .distantPast)
        let again = afterRewrite.cursors[log.path] ?? AgentLogCursor(path: log.path, provider: .codex)
        read(again, into: afterRewrite.store)
        let rewrittenFresh = readFresh([log])
        suite.expect(inode() == inodeBefore && afterRewrite.cursors.isEmpty
                        && afterRewrite.store.saved == rewrittenFresh.store.saved
                        && again.state == rewrittenFresh.cursors.first?.state,
                     "a log rewritten in place on the same inode counts only what it holds now, with fresh context")

        // A session resumed into a new log repeats a response the old one
        // holds, here with a smaller count, as when copied mid-stream. With
        // the old log deleted while the app was closed, what the new one holds
        // stays at its own count and what only the old one gave goes.
        write(firstHalf + secondHalf)
        let other = folder.appending(path: "rollout-resumed.jsonl")
        let copied = secondHalf[0].replacingOccurrences(of: #""output_tokens":20"#, with: #""output_tokens":5"#)
        try? Data(((Array(firstHalf.prefix(3)) + [copied, secondHalf[2]]).joined(separator: "\n") + "\n").utf8)
            .write(to: other)
        let both = saving(readFresh([log, other]))
        try? FileManager.default.removeItem(at: log)
        let afterDelete = AgentUsageArchive.resume(both, logs: [other.path], since: .distantPast)
        let reread = afterDelete.cursors[other.path] ?? AgentLogCursor(path: other.path, provider: .codex)
        read(reread, into: afterDelete.store)
        let onlyOther = readFresh([other])
        let resumedAfterDelete = afterDelete.store.saved
        suite.expect(both.store.records.count == 2 && !afterDelete.unchanged && afterDelete.cursors.isEmpty
                        && resumedAfterDelete.records == onlyOther.store.saved.records
                        && resumedAfterDelete.turns == onlyOther.store.saved.turns
                        && resumedAfterDelete.waiting == onlyOther.store.saved.waiting,
                     "a deleted log takes back what only it held, and a log sharing a response is read again for its own count")
        // Limits and the plan describe the account when they were read, not
        // the log; the latest reading stays rather than an older one.
        suite.expect(resumedAfterDelete.limits == both.store.limits && resumedAfterDelete.codexPlan == both.store.codexPlan
                        && resumedAfterDelete.codexPlan != nil,
                     "the account's latest limits and plan stay when the log they came in is deleted")
        let gone = AgentUsageArchive.resume(contents, logs: [], since: .distantPast)
        suite.expect(!contents.store.turns.isEmpty && !gone.unchanged && gone.store.saved.records.isEmpty
                        && gone.store.saved.turns.isEmpty && gone.store.saved.waiting.isEmpty,
                     "a log gone takes its open turn with it, since nothing polls it any more")

        // Cut short and written again while the app runs, here past where
        // reading stopped: neither its inode nor its size shows it. It is read
        // again from its start at once. What its old contents gave stays
        // counted until the next launch, so its progress is not saved, and
        // that launch counts only what the log holds then.
        write(firstHalf + secondHalf)
        let live = readFresh([log])
        let liveInode = inode()
        if let handle = try? FileHandle(forWritingTo: log) {
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: Data((rewritten.joined(separator: "\n") + "\n").utf8))
            try? handle.close()
        }
        var liveLines = 0
        if let liveCursor = live.cursors.first {
            AgentLogReader.readAppended(liveCursor) { line in
                liveLines += 1
                let entries = AgentLogParser.parseCodex(line, state: &liveCursor.state, now: now)
                live.store.apply(entries, file: liveCursor.path, provider: .codex, tracksTurns: liveCursor.tracksTurns,
                                 parent: liveCursor.parent, modified: liveCursor.modified, now: now)
            }
        }
        let savedWhileLive = AgentUsageArchive.Contents(providers: [.codex], store: live.store.saved,
                                                        cursors: live.cursors.filter { !$0.restarted }.map(\.saved))
        let relaunch = AgentUsageArchive.resume(savedWhileLive, logs: [log.path], since: .distantPast)
        let relaunchCursor = relaunch.cursors[log.path] ?? AgentLogCursor(path: log.path, provider: .codex)
        read(relaunchCursor, into: relaunch.store)
        let rewrittenNow = readFresh([log])
        suite.expect(inode() == liveInode && live.cursors.first?.restarted == true && liveLines == rewritten.count
                        && relaunch.cursors.isEmpty && relaunch.store.saved == rewrittenNow.store.saved,
                     "a log written again in place while the app runs is read again at once, and the next launch counts only what it holds")

        // Developer builds keep the version of their release, and each one
        // may parse differently.
        let release: [String: Any] = ["CFBundleShortVersionString": "3.5", "CFBundleVersion": "120"]
        var developer = release
        developer["VorssaintBuildCommit"] = "abc1234 · 2026-10-01 09:00"
        var rebuilt = release
        rebuilt["VorssaintBuildCommit"] = "abc1234-dirty · 2026-10-01 09:05"
        suite.expect(AgentUsageArchive.build(info: release) == "3.5-120"
                        && AgentUsageArchive.build(info: developer) != AgentUsageArchive.build(info: release)
                        && AgentUsageArchive.build(info: developer) != AgentUsageArchive.build(info: rebuilt),
                     "a developer build keeps its progress apart from its release's and from another developer build's")

        // Opening a FIFO for reading waits for a writer, and a stop waits for
        // the usage queue: a FIFO named like a log must never be opened that way.
        let fifo = folder.appending(path: "pipe.jsonl")
        if mkfifo(fifo.path, 0o600) == 0 {
            let done = DispatchSemaphore(value: 0)
            var fingerprint: UInt64? = 1
            DispatchQueue.global().async {
                fingerprint = AgentLogReader.fingerprint(fifo.path, upTo: 0)
                done.signal()
            }
            let returned = done.wait(timeout: .now() + 2) == .success
            if !returned {
                // Lets a blocked open return so the run can go on.
                let writer = open(fifo.path, O_WRONLY | O_NONBLOCK)
                if writer >= 0 { close(writer) }
                _ = done.wait(timeout: .now() + 2)
            }
            suite.expect(returned && fingerprint == nil, "a fifo named like a log is skipped instead of waited on")
        } else {
            suite.expect(false, "the archive fixture creates a fifo")
        }

        // The layout lists every stored property by hand. One added later
        // must find its place there, or the archive would drop it without a
        // word while the restored cursors skip the lines that set it. A
        // property that is not kept between launches is listed here too.
        func labels(_ value: Any) -> [String] { Mirror(reflecting: value).children.compactMap(\.label) }
        let sample = first.saved
        guard let sampleRecord = sample.records.first, let sampleLimits = sample.limits.first,
              let sampleWindow = sampleLimits.windows.first, let sampleTurn = sample.turns.first else {
            suite.expect(false, "the archive fixture holds a record, limits with a window and an open turn")
            return
        }
        let layouts: [(name: String, stored: [String], written: [String])] = [
            ("AgentUsageArchive.Contents", labels(contents), ["providers", "store", "cursors"]),
            ("AgentUsageStore", labels(first),
             ["records", "billables", "sources", "index", "summary", "limits", "codexPlan", "codexPlanObserved",
              "turns", "waiting", "registered", "reportsTransitions"]),
            ("AgentUsageStore.Saved", labels(sample),
             ["records", "limits", "codexPlan", "codexPlanObserved", "turns", "waiting"]),
            ("AgentUsageStore.Saved.Record", labels(sampleRecord), ["key", "record", "billable", "sources"]),
            ("AgentUsageRecord", labels(sampleRecord.record),
             ["provider", "date", "model", "project", "session", "tokens", "cost", "savings"]),
            ("AgentBillable", labels(sampleRecord.billable),
             ["tokens", "longCacheWrite", "fast", "domestic", "webSearches"]),
            ("AgentTokens", labels(sampleRecord.record.tokens), ["input", "cacheWrite", "cacheRead", "output", "reasoning"]),
            ("AgentLimits", labels(sampleLimits), ["provider", "windows", "observedAt", "source"]),
            ("AgentLimitWindow", labels(sampleWindow), ["id", "kind", "minutes", "scope", "usedPercent", "resetsAt"]),
            ("AgentLiveSession", labels(sampleTurn),
             ["id", "provider", "started", "lastActivity", "model", "project", "tokens", "cost"]),
            ("AgentLogCursor", labels(cursor),
             ["path", "provider", "tracksTurns", "parent", "offset", "identity", "pending", "discarding", "state",
              "modified", "restarted", "fingerprinted"]),
            ("AgentLogCursor.Saved", labels(cursor.saved),
             ["path", "provider", "offset", "identity", "discarding", "modified", "state", "fingerprint"]),
            ("AgentLogState", labels(cursor.state),
             ["session", "project", "model", "turnOpen", "sawUsageRecords", "lastTotal", "fast"])
        ]
        for layout in layouts {
            suite.expect(layout.stored == layout.written,
                         "every stored property of \(layout.name) has its place in the archive's layout or is listed as not kept")
        }
    }
}

/// The production settle method against a recording archive: turning the
/// section off and quitting at once must still remove saved progress.
enum AgentUsageArchiveSettleTests {
    enum AgentUsageArchive {
        static var removed = 0
        static func remove() { removed += 1 }
    }

    class Fixture {
        let queue = DispatchQueue(label: "com.vorssaint.agent-usage.settle-test")
        var saved = 0
        func saveProgress() { saved += 1 }
    }

    static func run(_ suite: TestSuite) {
        defer { AgentUsageArchive.removed = 0 }
        let host = Host()
        // A first read still going when the section is turned off.
        let reading = DispatchSemaphore(value: 0)
        host.queue.async {
            reading.signal()
            Thread.sleep(forTimeInterval: 0.2)
        }
        reading.wait()
        host.settleArchive(keeping: false)
        suite.expect(AgentUsageArchive.removed == 1 && host.saved == 0,
                     "turning the section off removes saved progress before stopping returns, behind a read in progress")
        host.settleArchive(keeping: true)
        suite.expect(AgentUsageArchive.removed == 1 && host.saved == 1,
                     "quitting with the section on saves progress before stopping returns")
    }
}

typealias AgentUsageProductionArchive = AgentUsageArchive

/// The production save method against a recording archive.
enum AgentUsageArchiveSaveTests {
    enum AgentUsageArchive {
        typealias Contents = AgentUsageProductionArchive.Contents
        static var saved: [Contents] = []
        static func save(_ contents: Contents) -> Bool {
            saved.append(contents)
            return true
        }
    }

    class Fixture {
        var readerSession = 1
        var progressMark = 0
        var lastSave = Date.distantPast
        var savedMark: Int?
        var enabled: Set<AgentProvider> = [.claude]
        var store = AgentUsageStore()
        var cursors: [String: AgentLogCursor] = [:]
    }

    static func run(_ suite: TestSuite) {
        defer { AgentUsageArchive.saved = [] }
        // A provider turned off with the section still on: the reading that
        // follows has nothing yet, and still replaces the old file.
        let host = Host()
        host.saveProgress()
        suite.expect(AgentUsageArchive.saved.count == 1 && AgentUsageArchive.saved.first?.providers == [.claude]
                        && AgentUsageArchive.saved.first?.store.records.isEmpty == true,
                     "the first save of a reading replaces the file even with nothing read, dropping agents now off")
        host.saveProgress()
        suite.expect(AgentUsageArchive.saved.count == 1, "a save with nothing new since writes nothing")
        host.progressMark = 1
        host.saveProgress()
        suite.expect(AgentUsageArchive.saved.count == 2, "a save after reading moved on writes again")

        // A log replaced while the app ran still counts what its old contents
        // gave, so it is left out and the next launch reads it as rewritten.
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-archive-save-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let keptLog = folder.appending(path: "kept.jsonl")
        let replacedLog = folder.appending(path: "replaced.jsonl")
        try? Data("{}\n".utf8).write(to: keptLog)
        try? Data("{}\n".utf8).write(to: replacedLog)
        let kept = AgentLogCursor(path: keptLog.path, provider: .codex)
        let replaced = AgentLogCursor(path: replacedLog.path, provider: .codex)
        AgentLogReader.readAppended(kept) { _ in }
        AgentLogReader.readAppended(replaced) { _ in }
        try? Data("{}\n{}\n".utf8).write(to: replacedLog, options: .atomic)
        AgentLogReader.readAppended(replaced) { _ in }
        host.cursors = [keptLog.path: kept, replacedLog.path: replaced]
        host.progressMark = 2
        host.saveProgress()
        suite.expect(replaced.restarted && !kept.restarted
                        && AgentUsageArchive.saved.last?.cursors.map(\.path) == [keptLog.path],
                     "a log replaced or written again while the app ran is left out of saved progress")
    }
}
