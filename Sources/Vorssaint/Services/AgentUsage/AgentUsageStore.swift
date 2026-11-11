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
    /// Open turns by log file.
    private(set) var turns: [String: AgentLiveSession] = [:]
    /// Turns gone quiet, by log file: not shown as working, but work that
    /// resumes after an approval or a long command goes on with them.
    private(set) var waiting: [String: AgentLiveSession] = [:]
    /// Claude turns whose process was seen running, by log file.
    private var registered: Set<String> = []
    /// When a model last replied, by the log of the turn it counts toward.
    private var replies: [String: Date] = [:]
    /// Sessions waiting on the person, by the log of their turn. Kept apart
    /// from the turns, so a wait outlasts its turn going quiet.
    private(set) var attention: [String: AgentAttention] = [:]
    /// Off while the logs are first read, so history never replays as news.
    var reportsTransitions = false
    /// Hears each turn that opens while transitions are reported, on the
    /// thread that applies the logs.
    var turnStarted: ((AgentProvider) -> Void)?
    /// Hears each turn the person interrupted, or an error stopped, as it
    /// happens.
    var turnInterrupted: ((AgentProvider) -> Void)?
    /// A turn that ended longer ago than this is history found late, like a
    /// session an agent moved to its archive, not news.
    static let lateEnd: TimeInterval = 5 * 60
    /// How long the Mac stays offline, awake, before Claude's turns end:
    /// after a short drop, as when it changes networks, Claude goes on.
    static let offlineGrace: TimeInterval = 20
    /// How long a quiet turn waits for its work to resume before it is over:
    /// a Claude session resumed after its process was killed reads like work
    /// going on, so a turn waits only an hour.
    static let resumeWindow: TimeInterval = 3600

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
        // The turn an interruption ended, which the wait it leaves describes.
        var ended: AgentLiveSession?
        for entry in entries {
            switch entry {
            case .usage(let key, let record, let billable):
                add(record, billable: billable, key: key, source: file, turn: tracksTurns ? file : parent,
                    subagent: !tracksTurns)
            case .turnBegan(let date):
                guard tracksTurns else { continue }
                // A log rewritten in place is read again from its start; the
                // turn it already holds keeps what its responses added, which
                // the second reading skips as repeats.
                if let turn = turns[file] ?? waiting[file], abs(turn.started.timeIntervalSince(date)) < 1 { continue }
                attention[file] = nil
                waiting[file] = nil
                turns[file] = AgentLiveSession(id: file, provider: provider, started: date,
                                               lastActivity: max(date, turns[file]?.lastActivity ?? date),
                                               model: "", project: "", tokens: AgentTokens(), cost: 0)
                if reportsTransitions, now.timeIntervalSince(date) <= Self.lateEnd {
                    turnStarted?(provider)
                }
            case .turnActive(let date):
                guard tracksTurns else { continue }
                let moment = date ?? modified
                // Work after the wait began answers it; the line that asked
                // comes within the same second.
                if let wait = attention[file], wait.cause != .interrupted,
                   date == nil || moment > wait.since.addingTimeInterval(1) {
                    attention[file] = nil
                }
                if var turn = turns[file] ?? waiting.removeValue(forKey: file) {
                    turn.lastActivity = max(turn.lastActivity, moment)
                    turns[file] = turn
                } else {
                    turns[file] = AgentLiveSession(id: file, provider: provider, started: moment, lastActivity: moment,
                                                   model: "", project: "", tokens: AgentTokens(), cost: 0)
                    // Work seen before its turn's opening, as when the
                    // opening fell outside what was read, starts it all the same.
                    if reportsTransitions, now.timeIntervalSince(moment) <= Self.lateEnd {
                        turnStarted?(provider)
                    }
                }
            case .turnEnded(let date, let completed, let duration):
                guard tracksTurns else { continue }
                // A turn that went quiet on the way ends as the whole turn.
                let quiet = waiting.removeValue(forKey: file)
                let closing = turns.removeValue(forKey: file) ?? quiet
                if closing != nil { ended = closing }
                if completed { attention[file] = nil }
                guard let turn = closing, completed, reportsTransitions else { continue }
                let end = date ?? modified
                guard now.timeIntervalSince(end) <= Self.lateEnd else { continue }
                events.append(.finished(provider: provider,
                                        duration: max(0, duration ?? end.timeIntervalSince(turn.started)),
                                        cost: turn.cost, tokens: turn.tokens.total, project: turn.project))
            case .turnAwaiting(let cause, let date, let inferred):
                guard tracksTurns else { continue }
                let turn = turns[file] ?? waiting[file] ?? ended
                let history = !reportsTransitions || now.timeIntervalSince(date) > Self.lateEnd
                // The record says more than the log, and is current.
                if let wait = attention[file], wait.recorded, cause != .interrupted { continue }
                attention[file] = AgentAttention(file: file, provider: provider, project: turn?.project ?? "",
                                                 place: turn?.place ?? .terminal, cause: cause, since: date,
                                                 inferred: inferred, history: history)
                if cause == .interrupted, !history { turnInterrupted?(provider) }
            }
        }
        return events
    }

    /// A log removed while its turn ran, like a deleted chat, ends that turn
    /// without a notice: nothing finished. True when one was showing.
    @discardableResult
    func forget(file: String) -> Bool {
        waiting[file] = nil
        attention[file] = nil
        return turns.removeValue(forKey: file) != nil
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
            if merged == old.tokens { return }
            summary.recordChanged(at: position, previous: old)
            var combined = billables[position]
            combined.tokens = merged
            combined.longCacheWrite = max(combined.longCacheWrite, billable.longCacheWrite)
            combined.webSearches = max(combined.webSearches, billable.webSearches)
            combined.fast = combined.fast || billable.fast
            combined.domestic = combined.domestic || billable.domestic
            combined.isAggregate = combined.isAggregate || billable.isAggregate
            let priced = AgentPricing.cost(combined, model: old.model)
            delta = AgentTokens(input: merged.input - old.tokens.input,
                                cacheWrite: merged.cacheWrite - old.tokens.cacheWrite,
                                cacheRead: merged.cacheRead - old.tokens.cacheRead,
                                output: merged.output - old.tokens.output,
                                reasoning: merged.reasoning - old.tokens.reasoning)
            extra = (priced.cost ?? 0) - (old.cost ?? 0)
            billables[position] = combined
            records[position].tokens = merged
            records[position].cost = priced.cost
            records[position].savings = priced.savings
        } else {
            summary.recordChanged(at: records.count, previous: nil)
            index[key] = records.count
            records.append(record)
            billables.append(billable)
            sources.append([source])
        }
        guard let file else { return }
        // Noted before the turn check, which skips a reply dated before its
        // turn started: the model answered all the same.
        replies[file] = max(replies[file] ?? record.date, record.date)
        guard var turn = turns[file] ?? waiting[file],
              record.date >= turn.started.addingTimeInterval(-1) else { return }
        waiting[file] = nil
        turn.tokens += delta
        turn.cost += extra
        turn.lastActivity = max(turn.lastActivity, record.date)
        if !subagent {
            if !record.model.isEmpty { turn.model = record.model }
            if !record.project.isEmpty { turn.project = record.project }
            // Each Claude response names the client it came from.
            turn.place = record.claudeApp ? .app : .terminal
        }
        turns[file] = turn
    }

    /// Prices every response again, after a newer list arrives.
    func reprice() {
        summary.invalidate()
        for position in records.indices {
            let priced = AgentPricing.cost(billables[position], model: records[position].model)
            records[position].cost = priced.cost
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
        waiting = waiting.filter { now.timeIntervalSince($0.value.lastActivity) < Self.resumeWindow }
        attention = attention.filter { now.timeIntervalSince($0.value.since) < Self.resumeWindow }
        replies = replies.filter { turns[$0.key] != nil || waiting[$0.key] != nil }
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
        for file in turns.keys {
            let session = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            if processes.running.contains(session) {
                registered.insert(file)
            } else if processes.ended.contains(session)
                        || (processes.complete && (registered.contains(file) || (atLaunch && processes.listed))) {
                registered.remove(file)
                closed = forget(file: file) || closed
            }
        }
        // A session that waited long enough to go quiet, then quit.
        for file in attention.keys where turns[file] == nil && processes.ended.contains(Self.session(of: file)) {
            attention[file] = nil
        }
        return closed
    }

    /// The session id a Claude log is named after.
    static func session(of file: String) -> String {
        ((file as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Claude Code's own record of whether each session waits on the person,
    /// which outranks what its log suggests. `files` maps session ids to
    /// their logs.
    func applyClaudeStatuses(_ processes: AgentSessionRegistry, files: [String: String], now: Date) {
        for (session, status) in processes.statuses {
            guard let file = files[session] else { continue }
            let existing = attention[file]
            guard status.status == "waiting" else {
                // Busy or idle: no approval is pending. A question the log
                // shows stays until the log answers it, which it always does.
                if let existing, existing.inferred || existing.recorded { attention[file] = nil }
                continue
            }
            var cause: AgentAwait
            switch status.waitingFor {
            case "input needed": cause = .question
            case "dialog open": cause = .dialog
            default: cause = .permission
            }
            // A plan to approve asks as a permission does.
            if cause == .permission, existing?.cause == .plan { cause = .plan }
            if let existing, existing.recorded, existing.cause == cause { continue }
            let turn = turns[file] ?? waiting[file]
            let since = existing.map { $0.cause == cause && !$0.inferred ? $0.since : nil } ?? nil
            attention[file] = AgentAttention(file: file, provider: .claude, project: turn?.project ?? existing?.project ?? "",
                                             place: turn?.place ?? existing?.place ?? .terminal, cause: cause,
                                             since: since ?? status.updatedAt ?? now, inferred: false, history: false,
                                             recorded: true)
        }
        // A record that went away takes its wait with it.
        for (file, wait) in attention where wait.recorded && processes.statuses[Self.session(of: file)] == nil {
            attention[file] = nil
        }
    }

    /// Waits only the quiet suggests: a tool call in `pending` with nothing
    /// written for `AgentAttentionPolicy.inferQuiet`. A guess whose call came
    /// back, or whose session has a record to ask, goes.
    func inferQuietWaits(now: Date, pending: Set<String>, recorded: Set<String>) {
        for (file, wait) in attention where wait.inferred && (!pending.contains(file) || recorded.contains(file)) {
            attention[file] = nil
        }
        for file in pending where attention[file] == nil && !recorded.contains(file) {
            guard let turn = turns[file] ?? waiting[file],
                  now.timeIntervalSince(turn.lastActivity) >= AgentAttentionPolicy.inferQuiet else { continue }
            attention[file] = AgentAttention(file: file, provider: turn.provider, project: turn.project, place: turn.place,
                                             cause: .permission, since: turn.lastActivity, inferred: true, history: false)
        }
    }

    /// Claude Code retries for minutes without a word while the Mac is
    /// offline, then gives up; until it does, its turn would count on. Once
    /// the Mac, offline since `offline`, has been awake that way for
    /// `offlineGrace`, Claude's turns end without a notice, quiet ones too,
    /// so a retry that gets through opens a turn of its own. A turn whose
    /// model replied since then runs on a model on the Mac, and a turn in
    /// `running` waits on a command that runs here. True when a turn was
    /// showing.
    @discardableResult
    func closeOfflineTurns(since offline: Date, lasting elapsed: TimeInterval,
                           keeping running: @autoclosure () -> Set<String> = []) -> Bool {
        guard elapsed >= Self.offlineGrace else { return false }
        let commands = running()
        func ends(_ entry: (key: String, value: AgentLiveSession)) -> Bool {
            !commands.contains(entry.key) && (replies[entry.key] ?? .distantPast) < offline
        }
        let closed = turns.contains(where: ends)
        turns = turns.filter { !ends($0) }
        waiting = waiting.filter { !ends($0) }
        attention = attention.filter { $0.value.recorded || turns[$0.key] != nil || waiting[$0.key] != nil
            || $0.value.cause == .interrupted }
        return closed
    }

    var showsClaudeTurn: Bool { !turns.isEmpty }
    /// A Claude session waits on the person, which its record can end.
    var awaitsClaude: Bool { !attention.isEmpty }

    /// What is kept between launches: every counter the logs gave, and none
    /// of their text.
    struct Saved: Equatable {
        struct Record: Equatable {
            let key: String
            let record: AgentUsageRecord
            let billable: AgentBillable
            let sources: [String]
        }

        var records: [Record] = []
        var limits: [AgentLimits] = []
        var turns: [AgentLiveSession] = []
        var waiting: [AgentLiveSession] = []
    }

    var saved: Saved {
        var keys = [String](repeating: "", count: records.count)
        for (key, position) in index { keys[position] = key }
        let kept = records.indices.map {
            Saved.Record(key: keys[$0], record: records[$0], billable: billables[$0], sources: sources[$0])
        }
        return Saved(records: kept,
                     limits: limits.values.sorted { $0.provider.rawValue < $1.provider.rawValue },
                     turns: turns.values.sorted { $0.id < $1.id },
                     waiting: waiting.values.sorted { $0.id < $1.id })
    }

    convenience init(saved: Saved) {
        self.init()
        records = saved.records.map(\.record)
        billables = saved.records.map(\.billable)
        sources = saved.records.map(\.sources)
        for (position, entry) in saved.records.enumerated() { index[entry.key] = position }
        limits = Dictionary(saved.limits.map { ($0.provider, $0) }, uniquingKeysWith: { $1 })
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

/// Where Claude Code keeps its session logs.
struct AgentLogRoot: Equatable {
    let provider: AgentProvider
    let url: URL
    /// A folder another computer's logs are synced to: what they hold counts
    /// as usage, but never as a session running on this Mac.
    var synced = false

    /// Folders a synced tree keeps for itself, like Syncthing's old versions
    /// of each file, which hold no log of their own.
    static let ignoredFolders: Set<String> = [".stversions", ".stfolder", ".stfolder.removed-by-syncthing"]

    /// Canonical, because file events report real paths: a folder kept as a
    /// link elsewhere, as dotfile setups do, would otherwise never match.
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentLogRoot] {
        [".claude/projects", ".config/claude/projects"].map { path in
            AgentLogRoot(provider: .claude, url: canonical(home.appending(path: path, directoryHint: .isDirectory)))
        }
    }

    /// The roots of folders holding Claude Code logs synced from other
    /// computers. Each folder is searched all the way down, so one folder can
    /// hold several Claude profiles' `projects` trees side by side; a response
    /// two of them hold counts once, by its message and request ids.
    static func synced(_ folders: [String]) -> [AgentLogRoot] {
        var seen = Set<String>()
        return folders.compactMap { folder -> AgentLogRoot? in
            // Only a full path names a folder; a blank one is not this one.
            let path = (folder.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            guard path.hasPrefix("/") else { return nil }
            let url = canonical(URL(fileURLWithPath: path, isDirectory: true))
            guard url.path != "/", seen.insert(url.path).inserted else { return nil }
            return AgentLogRoot(provider: .claude, url: url, synced: true)
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

    /// Discovery and live file events admit the same logs.
    func accepts(_ path: String) -> Bool {
        let prefix = url.path + "/"
        guard path.hasPrefix(prefix), path.hasSuffix(".jsonl") else { return false }
        return !path.dropFirst(prefix.count).split(separator: "/").contains { Self.ignoredFolders.contains(String($0)) }
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
    /// What each running session's record says it is doing, when it says.
    var statuses: [String: Status] = [:]

    struct Status: Equatable {
        /// "busy", "idle" or "waiting".
        let status: String
        /// What a waiting session waits for, as "permission prompt".
        let waitingFor: String?
        let updatedAt: Date?
        let pid: Int32
    }

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
                guard isRunning(Int32(clamping: pid)) else {
                    registry.ended.insert(session)
                    continue
                }
                registry.running.insert(session)
                if let status = json["status"] as? String {
                    registry.statuses[session] = Status(status: status, waitingFor: json["waitingFor"] as? String,
                                                        updatedAt: AgentLogParser.seconds(json["statusUpdatedAt"]),
                                                        pid: Int32(clamping: pid))
                }
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
    /// A log only counted, never followed as work going on: one synced from
    /// another computer. The service decides, since only it knows the folders.
    var history = false
    /// Subagents report to a turn another file tracks.
    var tracksTurns: Bool { !history && parent == nil }
    /// The session log a Claude subagent works for.
    let parent: String?
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
        parent = AgentLogCursor.parent(of: path)
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

    static func isLog(_ path: String) -> Bool { path.hasSuffix(".jsonl") }

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
    /// on the most recent state. Claude subagents come after every session,
    /// so the turn each one works for already stands when its responses are
    /// read.
    static func discover(_ roots: [AgentLogRoot], since horizon: Date) -> [(path: String, provider: AgentProvider)] {
        var found: [(path: String, provider: AgentProvider, modified: Date, subagent: Bool)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        func include(_ url: URL, from root: AgentLogRoot) {
            guard root.accepts(url.path),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= horizon else { return }
            found.append((url.path, root.provider, modified, AgentLogCursor.parent(of: url.path) != nil))
        }
        for root in roots where root.exists {
            guard let enumerator = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: keys,
                                                                  options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if AgentLogRoot.ignoredFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                } else if url.path.hasSuffix(".jsonl") {
                    include(url, from: root)
                }
            }
        }
        return found.sorted { $0.subagent != $1.subagent ? $1.subagent : $0.modified < $1.modified }
            .map { ($0.path, $0.provider) }
    }

    /// Reads what was appended since the last call and hands over each
    /// complete line. A replaced or truncated file starts over.
    static func readAppended(_ cursor: AgentLogCursor, shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
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
            if !range.isEmpty, range.count <= maximumLine {
                line(buffer.subdata(in: range))
            }
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

/// Change notifications for one file that its writer replaces on save,
/// delivered on the usage queue. The folder is watched for the replacement
/// and the file for writes in place, and a burst of either arrives as one
/// call a moment later.
final class AgentFileWatcher {
    static let delay: TimeInterval = 0.25
    private let url: URL
    private let queue: DispatchQueue
    private let handler: () -> Void
    private var folder: DispatchSourceFileSystemObject?
    private var file: DispatchSourceFileSystemObject?
    private var scheduled = false

    init(_ url: URL, queue: DispatchQueue, handler: @escaping () -> Void) {
        self.url = url
        self.queue = queue
        self.handler = handler
    }

    deinit { stop() }

    /// Runs on `queue`.
    func start() {
        stop()
        folder = source(url.deletingLastPathComponent().path, events: .write)
        watchFile()
    }

    /// Runs on `queue`.
    func stop() {
        folder?.cancel()
        file?.cancel()
        folder = nil
        file = nil
        scheduled = false
    }

    /// A replaced file is a new one, so each change watches it afresh.
    private func watchFile() {
        file?.cancel()
        file = source(url.path, events: [.write, .extend, .delete, .rename])
    }

    private func source(_ path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        guard folder != nil, !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + Self.delay) { [weak self] in
            guard let self, self.scheduled else { return }
            self.scheduled = false
            self.watchFile()
            self.handler()
        }
    }
}
