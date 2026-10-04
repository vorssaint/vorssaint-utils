// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreServices
import Darwin
import Foundation

/// Everything read so far, one record per response. Not thread-safe: the
/// usage service confines it to its own queue.
final class AgentUsageStore {
    private(set) var records: [AgentUsageRecord] = []
    private var billables: [AgentBillable] = []
    /// The logs each response was read from: most in one, a resumed or
    /// archived session's again in another.
    private var sources: [[String]] = []
    private var index: [String: Int] = [:]
    private let summary = AgentUsageSummaryCache()
    private(set) var limits: [AgentProvider: AgentLimits] = [:]
    private(set) var codexPlan: String?
    private var codexPlanObserved = Date.distantPast
    /// Open turns by log file.
    private(set) var turns: [String: AgentLiveSession] = [:]
    /// Turns gone quiet, by log file: not shown as working, but work that
    /// resumes after an approval or a long command goes on with them.
    private(set) var waiting: [String: AgentLiveSession] = [:]
    /// Claude turns whose process was seen running, by log file.
    private var registered: Set<String> = []
    /// Turns whose last step ended expecting more, by log file, with when.
    private var settled: [String: Date] = [:]
    /// Off while the logs are first read, so history never replays as news.
    var reportsTransitions = false
    /// A turn that ended longer ago than this is history found late, like a
    /// session an agent moved to its archive, not news.
    static let lateEnd: TimeInterval = 5 * 60
    /// How long a quiet turn waits for its work to resume before it is over.
    /// A new Codex task always opens a turn of its own, but a Claude session
    /// resumed after its process was killed reads like work going on, so a
    /// Claude turn waits only an hour.
    static func resumeWindow(for provider: AgentProvider) -> TimeInterval {
        provider == .claude ? 3600 : 6 * 3600
    }

    var live: [AgentLiveSession] { Array(turns.values) }

    func snapshot(plans: [AgentProvider: AgentPlan], providers: Set<AgentProvider>, now: Date,
                  calendar: Calendar = .current) -> AgentUsageSnapshot {
        summary.snapshot(records: records, limits: limits, live: live, plans: plans,
                         providers: providers, now: now, calendar: calendar)
    }

    /// Applies one file's entries and returns the turns they finished.
    /// `parent` is the log whose turn a subagent's responses count toward.
    @discardableResult
    func apply(_ entries: [AgentLogEntry], file: String, provider: AgentProvider,
               tracksTurns: Bool, parent: String? = nil, modified: Date, now: Date = Date()) -> [AgentUsageEvent] {
        var events: [AgentUsageEvent] = []
        for entry in entries {
            switch entry {
            case .usage(let key, let record, let billable):
                add(record, billable: billable, key: key, source: file, turn: tracksTurns ? file : parent,
                    subagent: !tracksTurns)
            case .limits(let reading):
                updateLimits(reading)
            case .plan(let plan, let date):
                // An archived session read again from its start holds an
                // older plan than the one in use.
                guard codexPlanObserved <= date else { continue }
                codexPlan = plan
                codexPlanObserved = date
            case .turnBegan(let date):
                guard tracksTurns else { continue }
                settled[file] = nil
                // A log rewritten in place is read again from its start; the
                // turn it already holds keeps what its responses added, which
                // the second reading skips as repeats.
                if let turn = turns[file] ?? waiting[file], abs(turn.started.timeIntervalSince(date)) < 1 { continue }
                waiting[file] = nil
                turns[file] = AgentLiveSession(id: file, provider: provider, started: date,
                                               lastActivity: max(date, turns[file]?.lastActivity ?? date),
                                               model: "", project: "", tokens: AgentTokens(), cost: 0)
            case .turnActive(let date):
                guard tracksTurns else { continue }
                settled[file] = nil
                let moment = date ?? modified
                if var turn = turns[file] ?? waiting.removeValue(forKey: file) {
                    turn.lastActivity = max(turn.lastActivity, moment)
                    turns[file] = turn
                } else {
                    turns[file] = AgentLiveSession(id: file, provider: provider, started: moment, lastActivity: moment,
                                                   model: "", project: "", tokens: AgentTokens(), cost: 0)
                }
            case .turnSettled(let date):
                guard tracksTurns, var turn = turns[file] ?? waiting.removeValue(forKey: file) else { continue }
                turn.lastActivity = max(turn.lastActivity, date)
                turns[file] = turn
                settled[file] = date
            case .turnEnded(let date, let completed, let duration):
                guard tracksTurns else { continue }
                settled[file] = nil
                // A turn that went quiet on the way ends as the whole turn.
                let quiet = waiting.removeValue(forKey: file)
                guard let turn = turns.removeValue(forKey: file) ?? quiet, completed, reportsTransitions else { continue }
                let end = date ?? modified
                guard now.timeIntervalSince(end) <= Self.lateEnd else { continue }
                events.append(.finished(provider: provider,
                                        duration: max(0, duration ?? end.timeIntervalSince(turn.started)),
                                        cost: turn.cost, tokens: turn.tokens.total, project: turn.project))
            case .reset:
                let baseFile = file.components(separatedBy: "#").first ?? file
                forget(file: baseFile)
            }
        }
        return events
    }

    /// A log removed while its turn ran, like a deleted chat, ends that turn
    /// without a notice: nothing finished. True when one was showing.
    @discardableResult
    func forget(file: String) -> Bool {
        waiting[file] = nil
        settled = settled.filter { $0.key != file && !$0.key.hasPrefix(file + "#") }
        var removed = turns.removeValue(forKey: file) != nil
        for key in turns.keys where key.hasPrefix(file + "#") {
            turns.removeValue(forKey: key)
            removed = true
        }
        for key in waiting.keys where key.hasPrefix(file + "#") {
            waiting.removeValue(forKey: key)
        }
        return removed
    }

    /// `source` is the log the response was read from; `file` names the log
    /// whose turn it counts toward. A subagent's responses leave that turn's
    /// model and project alone.
    private func add(_ record: AgentUsageRecord, billable: AgentBillable, key: String, source: String,
                     turn file: String?, subagent: Bool) {
        var delta = record.tokens
        var extra = record.cost ?? 0
        if let position = index[key] {
            if !sources[position].contains(source) { sources[position].append(source) }
            let old = records[position]
            let merged = old.tokens.merged(with: record.tokens)
            if merged == old.tokens {
                if record.provider == .opencode {
                    let newCost: Double?
                    let isReported: Bool
                    if record.reportedCost {
                        newCost = record.cost
                        isReported = true
                    } else if old.reportedCost {
                        newCost = old.cost
                        isReported = true
                    } else {
                        newCost = record.cost ?? old.cost
                        isReported = false
                    }
                    if newCost != old.cost || isReported != old.reportedCost {
                        summary.recordChanged(at: position, previous: old)
                        let extra = (newCost ?? 0) - (old.cost ?? 0)
                        records[position].cost = newCost
                        records[position].reportedCost = isReported
                        if let file, var turn = turns[file] ?? waiting[file],
                           record.date >= turn.started.addingTimeInterval(-1) {
                            waiting[file] = nil
                            turn.cost += extra
                            turns[file] = turn
                        }
                    }
                }
                return
            }
            summary.recordChanged(at: position, previous: old)
            var combined = billables[position]
            combined.tokens = merged
            combined.longCacheWrite = max(combined.longCacheWrite, billable.longCacheWrite)
            combined.webSearches = max(combined.webSearches, billable.webSearches)
            combined.fast = combined.fast || billable.fast
            combined.domestic = combined.domestic || billable.domestic
            let priced = AgentPricing.cost(combined, model: old.model)
            let newCost: Double?
            let isReported: Bool
            if record.provider == .opencode {
                if record.reportedCost {
                    newCost = record.cost
                    isReported = true
                } else if old.reportedCost {
                    newCost = old.cost
                    isReported = true
                } else {
                    newCost = priced.cost ?? record.cost ?? old.cost
                    isReported = false
                }
            } else {
                newCost = priced.cost
                isReported = false
            }
            delta = AgentTokens(input: merged.input - old.tokens.input,
                                cacheWrite: merged.cacheWrite - old.tokens.cacheWrite,
                                cacheRead: merged.cacheRead - old.tokens.cacheRead,
                                output: merged.output - old.tokens.output,
                                reasoning: merged.reasoning - old.tokens.reasoning)
            extra = (newCost ?? 0) - (old.cost ?? 0)
            billables[position] = combined
            records[position].tokens = merged
            records[position].cost = newCost
            records[position].savings = priced.savings
            records[position].reportedCost = isReported
        } else {
            summary.recordChanged(at: records.count, previous: nil)
            index[key] = records.count
            records.append(record)
            billables.append(billable)
            sources.append([source])
        }
        guard let file, var turn = turns[file] ?? waiting[file],
              record.date >= turn.started.addingTimeInterval(-1) else { return }
        waiting[file] = nil
        turn.tokens += delta
        turn.cost += extra
        turn.lastActivity = max(turn.lastActivity, record.date)
        if !subagent {
            if !record.model.isEmpty { turn.model = record.model }
            if !record.project.isEmpty { turn.project = record.project }
        }
        turns[file] = turn
    }

    /// Prices every response again, after a newer list arrives. List-derived
    /// rows recalculate against the new prices, while reported provider charges stay intact.
    func reprice() {
        summary.invalidate()
        for position in records.indices {
            guard !records[position].reportedCost else { continue }
            let priced = AgentPricing.cost(billables[position], model: records[position].model)
            // A zero OpenCode recorded for a model the list still does not
            // know stays that reply's cost.
            let recordedZero = records[position].provider == .opencode && records[position].cost == 0
            records[position].cost = priced.cost ?? (recordedZero ? 0 : nil)
            records[position].savings = priced.savings
        }
    }

    func setLimits(_ reading: AgentLimits) {
        limits[reading.provider] = reading
    }

    /// Keeps the newer of two readings of an account, whichever way each
    /// one arrived.
    func updateLimits(_ reading: AgentLimits) {
        if (limits[reading.provider]?.observedAt ?? .distantPast) <= reading.observedAt {
            limits[reading.provider] = reading
        }
    }

    func clearLimits(_ provider: AgentProvider) {
        limits[provider] = nil
    }

    /// A turn that has written nothing for this long is not being worked on:
    /// its process ended without a word, or it waits on something outside.
    /// It waits aside for a while, since work can resume after an approval
    /// or a long command.
    func closeIdleTurns(now: Date, after idle: TimeInterval) {
        for (file, turn) in turns where now.timeIntervalSince(turn.lastActivity) >= idle {
            turns[file] = nil
            waiting[file] = turn
        }
        waiting = waiting.filter { now.timeIntervalSince($0.value.lastActivity) < Self.resumeWindow(for: $0.value.provider) }
    }

    /// A turn whose last step ended expecting more, with nothing after it
    /// for a while, stopped there, as when OpenCode's loop stops on a
    /// rejected tool call: it ends without a notice, since nothing finished.
    /// True when one was showing.
    @discardableResult
    func closeSettledTurns(now: Date) -> Bool {
        var removed = false
        for (file, date) in settled where now.timeIntervalSince(date) >= AgentLogParser.openCodeSettle {
            settled[file] = nil
            waiting[file] = nil
            if turns.removeValue(forKey: file) != nil { removed = true }
        }
        return removed
    }

    /// A Claude session quit or killed in the middle of a turn, as when its
    /// terminal closes, writes nothing that ends the turn. Its process
    /// record says so sooner than the quiet wait: the record names a process
    /// that no longer runs, or a record seen running is gone. A session that
    /// keeps no record waits as before. At launch, a turn the logs left open
    /// without a record is over too, once the records could be read. True
    /// when a turn was showing.
    @discardableResult
    func closeEndedTurns(_ processes: AgentSessionRegistry, atLaunch: Bool = false) -> Bool {
        registered.formIntersection(turns.keys)
        var closed = false
        for (file, turn) in turns where turn.provider == .claude {
            let session = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            if processes.running.contains(session) {
                registered.insert(file)
            } else if processes.ended.contains(session)
                        || (processes.complete && (registered.contains(file) || (atLaunch && processes.listed))) {
                registered.remove(file)
                closed = forget(file: file) || closed
            }
        }
        return closed
    }

    var showsClaudeTurn: Bool { turns.values.contains { $0.provider == .claude } }

    /// What is kept between launches: every counter the logs gave, and none
    /// of their text. OpenCode's database is read again at each launch, so
    /// nothing it gave is kept.
    struct Saved: Equatable {
        struct Record: Equatable {
            let key: String
            let record: AgentUsageRecord
            let billable: AgentBillable
            let sources: [String]
        }

        var records: [Record] = []
        var limits: [AgentLimits] = []
        var codexPlan: String?
        var codexPlanObserved = Date.distantPast
        var turns: [AgentLiveSession] = []
        var waiting: [AgentLiveSession] = []
    }

    var saved: Saved {
        var keys = [String](repeating: "", count: records.count)
        for (key, position) in index { keys[position] = key }
        let kept = records.indices.filter { records[$0].provider != .opencode }.map {
            Saved.Record(key: keys[$0], record: records[$0], billable: billables[$0], sources: sources[$0])
        }
        return Saved(records: kept,
                     limits: limits.values.sorted { $0.provider.rawValue < $1.provider.rawValue },
                     codexPlan: codexPlan, codexPlanObserved: codexPlanObserved,
                     turns: turns.values.filter { $0.provider != .opencode }.sorted { $0.id < $1.id },
                     waiting: waiting.values.filter { $0.provider != .opencode }.sorted { $0.id < $1.id })
    }

    convenience init(saved: Saved) {
        self.init()
        records = saved.records.map(\.record)
        billables = saved.records.map(\.billable)
        sources = saved.records.map(\.sources)
        for (position, entry) in saved.records.enumerated() { index[entry.key] = position }
        limits = Dictionary(saved.limits.map { ($0.provider, $0) }, uniquingKeysWith: { $1 })
        codexPlan = saved.codexPlan
        codexPlanObserved = saved.codexPlanObserved
        turns = Dictionary(saved.turns.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        waiting = Dictionary(saved.waiting.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    /// Keeps memory bounded to the history the island can show.
    func dropRecords(before date: Date) {
        guard records.contains(where: { $0.date < date }) else { return }
        keepRecords { records[$0].date >= date }
    }

    /// Takes back what logs gone or rewritten since they were read gave, as
    /// reading every log from its start would: a response only they held
    /// goes, one another log also holds stays. Their turns end without a
    /// notice.
    func forget(files: Set<String>) {
        for file in files { forget(file: file) }
        var emptied = false
        for position in sources.indices where sources[position].contains(where: files.contains) {
            sources[position].removeAll(where: files.contains)
            emptied = emptied || sources[position].isEmpty
        }
        if emptied { keepRecords { !sources[$0].isEmpty } }
    }

    /// The logs holding a response that one of `files` also holds.
    func files(sharingWith files: Set<String>) -> Set<String> {
        var sharing = Set<String>()
        for list in sources where list.contains(where: files.contains) { sharing.formUnion(list) }
        return sharing
    }

    /// Every log that gave a response or holds a turn.
    var files: Set<String> {
        Set(sources.joined()).union(turns.keys).union(waiting.keys)
    }

    private func keepRecords(where keep: (Int) -> Bool) {
        summary.invalidate()
        var kept: [AgentUsageRecord] = []
        var keptBillables: [AgentBillable] = []
        var keptSources: [[String]] = []
        var positions: [Int: Int] = [:]
        for offset in records.indices where keep(offset) {
            positions[offset] = kept.count
            kept.append(records[offset])
            keptBillables.append(billables[offset])
            keptSources.append(sources[offset])
        }
        index = index.compactMapValues { positions[$0] }
        records = kept
        billables = keptBillables
        sources = keptSources
    }
}

/// Where each agent keeps its session logs.
struct AgentLogRoot: Equatable {
    let provider: AgentProvider
    let url: URL

    /// Canonical, because file events report real paths: a folder kept as a
    /// link elsewhere, as dotfile setups do, would otherwise never match.
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentLogRoot] {
        [(AgentProvider.claude, ".claude/projects"), (.claude, ".config/claude/projects"),
         (.codex, ".codex/sessions"), (.codex, ".codex/archived_sessions"),
         (.opencode, ".local/share/opencode")].map { provider, path in
            AgentLogRoot(provider: provider, url: canonical(home.appending(path: path, directoryHint: .isDirectory)))
        }
    }

    /// The path the file system reports for `url`; the path as given while
    /// nothing exists there yet.
    static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    var exists: Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
}

/// The Claude sessions with a process, from the `sessions/<pid>.json` record
/// Claude Code keeps beside its logs while it runs. A process that exits
/// removes its record; one that is killed leaves it behind.
struct AgentSessionRegistry: Equatable {
    /// Session ids, which name their log files, with a running process.
    var running: Set<String> = []
    /// Session ids whose recorded process no longer runs.
    var ended: Set<String> = []
    /// False when a record could not be read, as while it is being written,
    /// so a missing session proves nothing.
    var complete = true
    /// A sessions folder could be listed, so this Claude Code keeps records.
    var listed = false

    /// `folders` are the `sessions` folders beside each Claude log root.
    static func read(_ folders: [URL], isRunning: (Int32) -> Bool = AgentSessionRegistry.isRunning) -> AgentSessionRegistry {
        var registry = AgentSessionRegistry()
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            registry.listed = true
            for name in names where name.hasSuffix(".json") && Int32(name.dropLast(5)) != nil {
                guard let data = try? Data(contentsOf: folder.appending(path: name)), data.count < 1 << 16,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let pid = json["pid"] as? Int, let session = json["sessionId"] as? String, !session.isEmpty else {
                    registry.complete = false
                    continue
                }
                // A session run in a container or virtual machine that shares
                // this folder names a process this Mac cannot see.
                if let domain = json["pidDomain"] as? String, domain != "darwin" { continue }
                if isRunning(Int32(clamping: pid)) { registry.running.insert(session) } else { registry.ended.insert(session) }
            }
        }
        // A session resumed by a new process after an old one was killed.
        registry.ended.subtract(registry.running)
        return registry
    }

    static func isRunning(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }
}

/// How far into one log file reading has got.
final class AgentLogCursor {
    let path: String
    let provider: AgentProvider
    /// Subagents and side threads report to a turn another file tracks.
    let tracksTurns: Bool
    /// The session log a Claude subagent works for.
    let parent: String?
    /// Replies still being written and the rows read last, for a database.
    var openCode = AgentOpenCodeProgress()
    var offset: UInt64 = 0
    var identity: UInt64 = 0
    var pending = Data()
    var discarding = false
    var state = AgentLogState()
    var modified = Date.distantPast
    /// Set when the log turned out replaced, cut short or written again after
    /// part of it was read. What its old contents gave is still counted, so
    /// its progress is not saved: the next launch reads it as rewritten.
    private(set) var restarted = false

    init(path: String, provider: AgentProvider) {
        self.path = path
        self.provider = provider
        let name = (path as NSString).lastPathComponent
        let parent = provider == .claude ? AgentLogCursor.parent(of: path) : nil
        self.parent = parent
        tracksTurns = provider == .claude ? parent == nil : (provider == .codex ? !name.contains("_") : true)
    }

    /// Where reading stopped, at a line boundary: a line still being written
    /// is read again whole from the file.
    struct Saved: Equatable {
        let path: String
        let provider: AgentProvider
        let offset: UInt64
        let identity: UInt64
        let discarding: Bool
        let modified: Date
        let state: AgentLogState
        /// Tells the log that was read from one rewritten in place, which
        /// keeps its inode.
        let fingerprint: UInt64
    }

    /// The fingerprint taken right after reading, so saved progress
    /// describes the bytes as they were read, not as they are when saving.
    private var fingerprinted: (offset: UInt64, identity: UInt64, value: UInt64)?

    /// Where a resumed read picks up: the start of a line still being
    /// written, or past a line too long to keep.
    private var boundary: UInt64 { discarding ? offset : offset - UInt64(pending.count) }

    /// Reads the log again from its start.
    func startOver(identity: UInt64) {
        if offset > 0 { restarted = true }
        self.identity = identity
        offset = 0
        pending = Data()
        discarding = false
        state = AgentLogState()
        fingerprinted = nil
    }

    func fingerprintRead() {
        let end = boundary
        if let taken = fingerprinted, taken.offset == end, taken.identity == identity { return }
        fingerprinted = AgentLogReader.fingerprint(path, upTo: end).map { (end, identity, $0) }
    }

    /// False once the log no longer holds what was read: written again in
    /// place, perhaps past where reading stopped, which its size and inode
    /// alone do not show.
    var holdsWhatWasRead: Bool {
        guard let taken = fingerprinted, taken.identity == identity else { return true }
        return AgentLogReader.fingerprint(path, upTo: taken.offset) == taken.value
    }

    var saved: Saved {
        let end = boundary
        let fingerprint: UInt64
        if let taken = fingerprinted, taken.offset == end, taken.identity == identity {
            fingerprint = taken.value
        } else {
            fingerprint = AgentLogReader.fingerprint(path, upTo: end) ?? 0
            fingerprinted = (end, identity, fingerprint)
        }
        return Saved(path: path, provider: provider, offset: end, identity: identity, discarding: discarding,
                     modified: modified, state: state, fingerprint: fingerprint)
    }

    /// Nil when the path no longer holds the log that was read up to the
    /// saved offset: replaced by another file, or cut short and written
    /// again in place.
    convenience init?(saved: Saved) {
        var info = stat()
        guard stat(saved.path, &info) == 0, UInt64(info.st_ino) == saved.identity,
              AgentLogReader.fingerprint(saved.path, upTo: saved.offset) == saved.fingerprint else { return nil }
        self.init(path: saved.path, provider: saved.provider)
        offset = saved.offset
        identity = saved.identity
        discarding = saved.discarding
        modified = saved.modified
        state = saved.state
        fingerprinted = (saved.offset, saved.identity, saved.fingerprint)
    }

    /// Claude Code keeps a session's subagents in `<session>/subagents/`,
    /// beside the session's own `<session>.jsonl`.
    static func parent(of path: String) -> String? {
        guard let range = path.range(of: "/subagents/", options: .backwards) else { return nil }
        return String(path[..<range.lowerBound]) + ".jsonl"
    }
}

enum AgentLogReader {
    static let chunkSize = 4 << 20
    /// A line longer than this is a pasted file or a tool's output, never a
    /// usage record; it is skipped rather than held in memory.
    static let maximumLine = 32 << 20

    static func isLog(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name == AgentOpenCodeReader.database || name == AgentOpenCodeReader.database + "-wal" { return true }
        return path.hasSuffix(".jsonl")
    }

    /// A hash of the log's first and last few kilobytes before `offset`, and
    /// of the offset itself. A log rewritten with a different start, or
    /// different lines just before where reading stopped, no longer matches.
    /// Nil when the file cannot be read that far.
    static func fingerprint(_ path: String, upTo offset: UInt64) -> UInt64? {
        // Without O_NONBLOCK a FIFO named like a log would block the open,
        // and a stop waiting for the usage queue with it.
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let span: UInt64 = 4096
        // FNV-1a: stable across launches, unlike `Hasher`.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ bytes: UnsafeRawBufferPointer) {
            for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3 }
        }
        withUnsafeBytes(of: offset.littleEndian, mix)
        var buffer = [UInt8](repeating: 0, count: Int(span))
        for start in [0, offset - min(span, offset)] {
            let length = Int(min(span, offset - start))
            let read = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, length, off_t(start)) }
            guard read == length else { return nil }
            buffer.withUnsafeBytes { mix(UnsafeRawBufferPointer(rebasing: $0[..<length])) }
        }
        return hash
    }

    /// Log files changed since `horizon`, newest last so live turns settle
    /// on the most recent state. Subagents come after every session, so the
    /// turn each one works for already stands when its responses are read.
    static func discover(_ roots: [AgentLogRoot], since horizon: Date) -> [(path: String, provider: AgentProvider)] {
        var found: [(path: String, provider: AgentProvider, modified: Date, subagent: Bool)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for root in roots where root.exists {
            // OpenCode keeps its database beside the snapshots, clones and
            // logs of its data folder, which are never walked.
            if root.provider == .opencode {
                let path = root.url.appending(path: AgentOpenCodeReader.database).path
                if let modified = AgentOpenCodeReader.modified(path), modified >= horizon {
                    found.append((path, root.provider, modified, false))
                }
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: keys,
                                                                  options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.path.hasSuffix(".jsonl") {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= horizon else { continue }
                let subagent = root.provider == .claude && AgentLogCursor.parent(of: url.path) != nil
                found.append((url.path, root.provider, modified, subagent))
            }
        }
        return found.sorted { $0.subagent != $1.subagent ? $1.subagent : $0.modified < $1.modified }
            .map { ($0.path, $0.provider) }
    }

    /// Reads what was appended since the last call and hands over each
    /// complete line. A replaced or truncated file starts over.
    /// A database has no files to leave out, so its first read starts at
    /// `horizon` instead.
    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        if cursor.provider == .opencode {
            AgentOpenCodeReader.readAppended(cursor, since: horizon, shouldContinue: shouldContinue, line: line)
            return
        }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let size = UInt64(max(0, info.st_size))
        let identity = UInt64(info.st_ino)
        cursor.modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        if identity != cursor.identity || size < cursor.offset
            || (size > cursor.offset && !cursor.holdsWhatWasRead) {
            cursor.startOver(identity: identity)
        }
        defer { cursor.fingerprintRead() }
        guard size > cursor.offset, let handle = FileHandle(forReadingAtPath: cursor.path) else { return }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: cursor.offset) } catch { return }
        while cursor.offset < size, shouldContinue() {
            let wanted = Int(min(UInt64(chunkSize), size - cursor.offset))
            // A first read can cover gigabytes; each chunk and what was parsed
            // from it are released before the next one.
            let read: Bool = autoreleasepool {
                guard let chunk = try? handle.read(upToCount: wanted), !chunk.isEmpty else { return false }
                cursor.offset += UInt64(chunk.count)
                split(chunk, cursor: cursor, line: line)
                return true
            }
            guard read else { break }
        }
    }

    private static func split(_ chunk: Data, cursor: AgentLogCursor, line: (Data) -> Void) {
        var buffer = cursor.pending
        buffer.append(chunk)
        var start = 0
        let count = buffer.count
        var lines: [Range<Int>] = []
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            // What was carried over holds no line break; a long line is
            // not searched again with every chunk it spans.
            var position = cursor.pending.count
            while position < count, let found = memchr(base + position, 0x0A, count - position) {
                let end = base.distance(to: UnsafeRawPointer(found))
                lines.append(start..<end)
                start = end + 1
                position = start
            }
        }
        for range in lines {
            if cursor.discarding {
                cursor.discarding = false
                continue
            }
            if !range.isEmpty, range.count <= maximumLine { line(buffer.subdata(in: range)) }
        }
        // Once a line is oversized, scan only for its terminator. Retaining
        // subsequent fragments would rebuild a buffer we can never deliver.
        if cursor.discarding || count - start > maximumLine {
            cursor.pending = Data()
            cursor.discarding = true
        } else {
            cursor.pending = start < count ? buffer.subdata(in: start..<count) : Data()
        }
    }
}

/// File-level change notifications for the log folders, delivered on the
/// usage queue. The system coalesces bursts, so a busy agent costs one
/// callback a second at most.
final class AgentLogWatcher {
    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue
    private let handler: ([String], Bool) -> Void

    init(queue: DispatchQueue, handler: @escaping (_ paths: [String], _ rescan: Bool) -> Void) {
        self.queue = queue
        self.handler = handler
    }

    deinit { stop() }

    @discardableResult
    func start(_ paths: [String]) -> Bool {
        stop()
        guard !paths.isEmpty else { return false }
        // The stream holds the watcher until it is released, so a callback
        // already queued can never outlive it.
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<AgentLogWatcher>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<AgentLogWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<AgentLogWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                                                | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)
            let rescan = (0..<count).contains { flags[$0] & lost != 0 }
            watcher.handler(changed, rescan)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagWatchRoot)
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, paths as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else {
            return false
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return false
        }
        stream = created
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
