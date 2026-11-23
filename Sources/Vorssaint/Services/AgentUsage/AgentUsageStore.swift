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
    /// Only responses present in multiple Cursor transcripts need per-file readings.
    private var cursorCopies: [Int: [String: AgentUsageRecord]] = [:]
    private var cursorUsageRevisions: [String: (count: Int, revision: UInt64)] = [:]
    private var cursorUsageGeneration: UInt64 = 0
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
    /// When a model last replied, by the log of the turn it counts toward.
    private var replies: [String: Date] = [:]
    /// Off while the logs are first read, so history never replays as news.
    var reportsTransitions = false
    /// A turn that ended longer ago than this is history found late, like a
    /// session an agent moved to its archive, not news.
    static let lateEnd: TimeInterval = 5 * 60
    /// How long the Mac stays offline, awake, before Claude's turns end:
    /// after a short drop, as when it changes networks, Claude goes on.
    static let offlineGrace: TimeInterval = 20
    /// How long a quiet turn waits for its work to resume before it is over.
    /// A new Codex task always opens a turn of its own, but a Claude session
    /// resumed after its process was killed reads like work going on, so a
    /// Claude turn waits only an hour.
    static func resumeWindow(for provider: AgentProvider) -> TimeInterval {
        provider == .claude ? 3600 : 6 * 3600
    }

    var live: [AgentLiveSession] { Array(turns.values) }

    /// Any copy with counters resolves the missing usage for that response ID.
    func transcriptActivity(for state: AgentLogState) -> CursorTranscriptActivity {
        var activity = CursorTranscriptActivity(project: state.project, minutes: state.cursorUnmeteredMinutes,
                                               modelMinutes: state.cursorUnmeteredModelMinutes,
                                               undatedThrough: state.cursorUndatedResponseThrough)
        for (id, response) in state.cursorUnmeteredResponses {
            guard index[CursorReader.usageKey(session: state.session, id: id)] == nil else { continue }
            if let minute = response.minute {
                activity.minutes.insert(minute)
                if !response.model.isEmpty {
                    activity.modelMinutes[response.model] = max(activity.modelMinutes[response.model] ?? minute, minute)
                }
            } else if let through = response.undatedThrough {
                activity.undatedThrough = max(activity.undatedThrough ?? .distantPast, through)
            }
        }
        return activity
    }

    func cursorUsageRevision(for session: String) -> UInt64 { cursorUsageRevisions[session]?.revision ?? 0 }

    private func cursorKeyCountChanged(for session: String, by delta: Int) {
        let count = (cursorUsageRevisions[session]?.count ?? 0) + delta
        cursorUsageGeneration &+= 1
        cursorUsageRevisions[session] = count == 0 ? nil : (count, cursorUsageGeneration)
    }

    func snapshot(plans: [AgentProvider: AgentPlan], providers: Set<AgentProvider>, now: Date,
                  calendar: Calendar = .current, cursorProjectsFound: Bool = false,
                  cursorActivity: [CursorTranscriptActivity] = [], cursorLastActivity: Date? = nil) -> AgentUsageSnapshot {
        var result = summary.snapshot(records: records, limits: limits, live: live, plans: plans,
                                      providers: providers, now: now, calendar: calendar)
        if providers.contains(.cursor) {
            result.cursorProjectsFound = cursorProjectsFound
            result.includeCursorActivity(cursorActivity)
            if let cursorLastActivity {
                result.seen.insert(.cursor)
                result.lastActivity[.cursor] = max(result.lastActivity[.cursor] ?? .distantPast, cursorLastActivity)
            }
        }
        return result
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
                // Copilot's session totals and Cursor's occasional metered replies
                // do not describe a complete live turn.
                let historyOnly = provider == .copilot || (provider == .cursor && key.hasPrefix("cursor-transcript:"))
                let turn = historyOnly ? nil : tracksTurns ? file : parent
                add(record, billable: billable, key: key, source: file, turn: turn, subagent: !tracksTurns)
            case .usageModel(let key, let model):
                guard let position = index[key], records[position].model.isEmpty else { continue }
                let old = records[position]
                records[position] = AgentUsageRecord(provider: old.provider, date: old.date, model: model,
                    project: old.project, session: old.session, requests: old.requests,
                    tokens: old.tokens, cost: old.cost, savings: old.savings, reportedCost: old.reportedCost)
                // Incremental token updates keep the same model; attribution
                // changes instead rebuild model buckets from the records.
                summary.invalidate()
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
            case .turnContext(let model, let project):
                guard tracksTurns else { continue }
                if var turn = turns[file] {
                    if !model.isEmpty { turn.model = model }
                    if !project.isEmpty { turn.project = project }
                    turns[file] = turn
                } else if var turn = waiting[file] {
                    if !model.isEmpty { turn.model = model }
                    if !project.isEmpty { turn.project = project }
                    waiting[file] = turn
                }
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
            if key.hasPrefix("cursor-transcript:"), record.provider == .cursor {
                updateCursorResponse(record, at: position, from: source)
                return
            }
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
            combined.isAggregate = combined.isAggregate || billable.isAggregate
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
            if record.provider == .cursor { cursorKeyCountChanged(for: record.session, by: 1) }
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
        }
        turns[file] = turn
    }

    private func updateCursorResponse(_ incoming: AgentUsageRecord, at position: Int, from file: String) {
        let singleSource = sources[position].count == 1 && sources[position][0] == file
        let previous = singleSource ? records[position] : cursorCopies[position]?[file]
        let reading: AgentUsageRecord
        if let previous {
            let tokens = previous.tokens.merged(with: incoming.tokens)
            let model = previous.model.isEmpty ? incoming.model : previous.model
            guard tokens != previous.tokens || model != previous.model else { return }
            reading = AgentUsageRecord(provider: .cursor, date: previous.date, model: model, project: previous.project,
                                       session: previous.session, tokens: tokens, cost: nil, savings: 0)
        } else {
            reading = incoming
        }
        if singleSource {
            selectCursorReading(reading, at: position)
        } else {
            if cursorCopies[position] == nil {
                cursorCopies[position] = [sources[position][0]: records[position]]
            }
            cursorCopies[position]?[file] = reading
            if !sources[position].contains(file) { sources[position].append(file) }
            selectCursorCopy(at: position)
        }
    }

    /// Copies can contain different streamed prefixes. Choose one whole reading
    /// so a copied transcript cannot synthesize new totals or move between projects
    /// according to scan order.
    @discardableResult
    private func selectCursorCopy(at position: Int) -> Bool {
        guard let winner = cursorCopies[position]?.min(by: { lhs, rhs in
            if lhs.value.tokens.total != rhs.value.tokens.total { return lhs.value.tokens.total > rhs.value.tokens.total }
            return lhs.key < rhs.key
        }) else { return false }
        return selectCursorReading(winner.value, at: position)
    }

    @discardableResult
    private func selectCursorReading(_ reading: AgentUsageRecord, at position: Int) -> Bool {
        let old = records[position]
        let newBucket = old.date != reading.date || old.project != reading.project || old.model != reading.model
        guard newBucket || old.tokens != reading.tokens else { return false }
        if newBucket { summary.invalidate() } else { summary.recordChanged(at: position, previous: old) }
        let billable = AgentBillable(tokens: reading.tokens)
        let priced = AgentPricing.cost(billable, model: reading.model)
        var selected = reading
        selected.cost = priced.cost
        selected.savings = priced.savings
        records[position] = selected
        billables[position] = billable
        return true
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
        replies = replies.filter { turns[$0.key] != nil || waiting[$0.key] != nil }
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

    /// Claude Code retries for minutes without a word while the Mac is
    /// offline, then gives up; until it does, its turn would count on. Once
    /// the Mac, offline since `offline`, has been awake that way for
    /// `offlineGrace`, Claude's turns end without a notice, quiet ones too,
    /// so a retry that gets through opens a turn of its own. A turn whose
    /// model replied since then runs on a model on the Mac, and a turn in
    /// `running` waits on a command that runs here. A Codex turn opens only
    /// when its task starts, so it could not come back while the task goes
    /// on, and nothing shows that Copilot retries without a word: both are
    /// left alone. True when a turn was showing.
    @discardableResult
    func closeOfflineTurns(since offline: Date, lasting elapsed: TimeInterval,
                           keeping running: @autoclosure () -> Set<String> = []) -> Bool {
        guard elapsed >= Self.offlineGrace else { return false }
        let commands = running()
        func ends(_ entry: (key: String, value: AgentLiveSession)) -> Bool {
            entry.value.provider == .claude && !commands.contains(entry.key)
                && (replies[entry.key] ?? .distantPast) < offline
        }
        let closed = turns.contains(where: ends)
        turns = turns.filter { !ends($0) }
        waiting = waiting.filter { !ends($0) }
        settled = settled.filter { turns[$0.key] != nil || waiting[$0.key] != nil }
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
        for (position, entry) in saved.records.enumerated() {
            index[entry.key] = position
            if entry.record.provider == .cursor { cursorKeyCountChanged(for: entry.record.session, by: 1) }
        }
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
    @discardableResult
    func forget(files: Set<String>) -> Bool {
        var changed = false
        for file in files where forget(file: file) { changed = true }
        return forgetUsage(files: files) || changed
    }

    /// Rebuild a rewritten transcript's counters without losing its observed turn.
    @discardableResult
    func forgetUsage(files: Set<String>) -> Bool {
        guard !files.isEmpty else { return false }
        var emptied = false
        var replaced = false
        for position in sources.indices where sources[position].contains(where: files.contains) {
            sources[position].removeAll(where: files.contains)
            if cursorCopies[position] != nil {
                cursorCopies[position] = cursorCopies[position]?.filter { !files.contains($0.key) }
                if selectCursorCopy(at: position) { replaced = true }
                if sources[position].count < 2 { cursorCopies[position] = nil }
            }
            emptied = emptied || sources[position].isEmpty
        }
        if emptied { keepRecords { !sources[$0].isEmpty } }
        return emptied || replaced
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
        for offset in records.indices {
            guard keep(offset) else {
                if records[offset].provider == .cursor { cursorKeyCountChanged(for: records[offset].session, by: -1) }
                continue
            }
            positions[offset] = kept.count
            kept.append(records[offset])
            keptBillables.append(billables[offset])
            keptSources.append(sources[offset])
        }
        cursorCopies = Dictionary(uniqueKeysWithValues: cursorCopies.compactMap { old, copies in
            positions[old].map { ($0, copies) }
        })
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
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                    claudeProfile: ClaudeAccountProfile = ClaudeAccountProfile(),
                    providers: Set<AgentProvider> = Set(AgentProvider.allCases)) -> [AgentLogRoot] {
        let claude = providers.contains(.claude) ? claudeProfile.logURLs(home: home).map {
            AgentLogRoot(provider: .claude, url: canonical($0))
        } : []
        return claude + [(AgentProvider.codex, ".codex/sessions"), (.codex, ".codex/archived_sessions"),
         (.opencode, ".local/share/opencode"), (.copilot, ".copilot/session-state"),
         (.cursor, ".cursor/projects")].compactMap { provider, path in
            guard providers.contains(provider) else { return nil }
            return AgentLogRoot(provider: provider, url: canonical(home.appending(path: path, directoryHint: .isDirectory)))
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
        if provider == .cursor { return CursorTranscriptAccess(root: url).exists }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// Discovery and live file events admit the same provider-specific logs.
    func accepts(_ path: String) -> Bool {
        let prefix = url.path + "/"
        guard path.hasPrefix(prefix) else { return false }
        if provider == .opencode { return path == url.appending(path: AgentOpenCodeReader.database).path }
        guard path.hasSuffix(".jsonl") else { return false }
        let parts = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
        if provider == .copilot {
            return parts.count == 2 && !parts[0].isEmpty && !parts[0].hasPrefix(".") && parts[1] == "events.jsonl"
        }
        if provider == .cursor {
            guard (3...4).contains(parts.count), !parts[0].isEmpty, !parts[0].hasPrefix("."),
                  parts[1] == "agent-transcripts", !parts[2].isEmpty, !parts[2].hasPrefix(".") else { return false }
            return parts.count == 3 || parts[3] == parts[2] + ".jsonl"
        }
        return true
    }
}

/// The two on-disk layouts for one Cursor session. Newer versions may leave
/// the old flat copy in place after moving a conversation into its own folder.
struct CursorTranscriptFiles {
    let flat: URL
    let nested: URL

    init(directory: URL, session: String) {
        let filename = session + ".jsonl"
        flat = directory.appending(path: filename, directoryHint: .notDirectory)
        nested = directory.appending(path: session, directoryHint: .isDirectory)
            .appending(path: filename, directoryHint: .notDirectory)
    }

    /// `path` has already been admitted by the Cursor log root.
    init(path: String) {
        let file = URL(fileURLWithPath: path, isDirectory: false)
        let parent = file.deletingLastPathComponent()
        let session = file.deletingPathExtension().lastPathComponent
        let nested = parent.lastPathComponent == session && parent.deletingLastPathComponent().lastPathComponent == "agent-transcripts"
        self.init(directory: nested ? parent.deletingLastPathComponent() : parent, session: session)
    }

    func preferred(in access: CursorTranscriptAccess) -> (path: String, modified: Date)? {
        for file in [nested, flat] {
            if let info = access.info(at: file.path) {
                return (file.path, AgentLogCursor.modificationDate(info))
            }
        }
        return nil
    }

    /// On a move or deletion, remove the old cursor, turn and activity
    /// together before reading the selected copy. A change to either filename
    /// can be the first event macOS delivers.
    func select(root: URL, cursors: inout [String: AgentLogCursor], store: AgentUsageStore) -> (path: String?, changed: Bool) {
        let selected = preferred(in: CursorTranscriptAccess(root: root))?.path
        var removed = false
        for path in [flat.path, nested.path] where path != selected {
            if cursors.removeValue(forKey: path) != nil {
                store.forget(files: [path])
                removed = true
            }
        }
        return (selected, removed)
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
    let cursorAccess: CursorTranscriptAccess?
    /// Subagents report to a turn another file tracks.
    var tracksTurns: Bool {
        provider == .claude ? parent == nil : (provider == .codex ? !state.codexSubagent : true)
    }
    /// The session log a Claude subagent works for.
    let parent: String?
    /// Replies still being written and the rows read last, for a database.
    var openCode = AgentOpenCodeProgress()
    var offset: UInt64 = 0
    var identity: UInt64 = 0
    var pending = Data()
    var discarding = false
    var state = AgentLogState()
    /// Matches an open prompt across rewrites in this process. Never archived.
    var cursorPromptFingerprint: UInt64?
    var cursorPrefix = CursorTranscriptPrefix()
    private weak var coverageStore: AgentUsageStore?
    fileprivate var cachedCoverage: (revision: UInt64, activity: CursorTranscriptActivity)?
    /// Restored copies share one archived total. Replay to recover each file's own contribution.
    var needsUsageReplay = false
    var modified = Date.distantPast
    /// Set when the log turned out replaced, cut short or written again after
    /// part of it was read. What its old contents gave is still counted, so
    /// its progress is not saved: the next launch reads it as rewritten.
    private(set) var restarted = false
    /// The log of the thread a Codex subagent works for, and how many logs
    /// there were when it was looked for. Not saved: a relaunch looks again.
    private var codexParentLog: String?
    private var codexParentSearch = -1

    init(path: String, provider: AgentProvider, cursorRoot: URL? = nil) {
        self.path = path
        self.provider = provider
        cursorAccess = provider == .cursor ? cursorRoot.map { CursorTranscriptAccess(root: $0) } : nil
        let parent = provider == .claude ? AgentLogCursor.parent(of: path) : nil
        self.parent = parent
        if provider == .cursor { CursorReader.adopt(path: path, into: &state) }
    }

    /// The log whose turn a Codex subagent's responses count toward. It can
    /// be read after the subagent's or move, and a reverted thread goes on in
    /// a new log, so it is looked for again when a log turns up or the one
    /// found goes away; the one written last is the thread's current log.
    func codexParent(among cursors: [String: AgentLogCursor]) -> String? {
        guard provider == .codex, !state.codexRoot.isEmpty, !tracksTurns else { return nil }
        if codexParentSearch != cursors.count || codexParentLog.map({ cursors[$0] == nil }) == true {
            codexParentSearch = cursors.count
            codexParentLog = cursors.values
                .filter { $0.provider == .codex && $0.tracksTurns && $0.state.session == state.codexRoot }
                .max { $0.modified < $1.modified }?.path
        }
        return codexParentLog
    }

    /// Resolving missing response IDs against other copies is necessary only after a change.
    func transcriptActivity(in store: AgentUsageStore) -> CursorTranscriptActivity {
        guard !state.cursorUnmeteredResponses.isEmpty else { return store.transcriptActivity(for: state) }
        let revision = store.cursorUsageRevision(for: state.session)
        if coverageStore === store, let cachedCoverage, cachedCoverage.revision == revision { return cachedCoverage.activity }
        let activity = store.transcriptActivity(for: state)
        coverageStore = store
        cachedCoverage = (revision, activity)
        return activity
    }

    @discardableResult
    func dropCursorCoverage(before horizon: Date) -> Bool {
        guard state.dropCursorCoverage(before: horizon) else { return false }
        cachedCoverage = nil
        return true
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
        /// Cursor's fingerprint covers every committed byte. Its edge sample
        /// is a shortcut for an unchanged file with no outstanding checks.
        let cursorSample: UInt64?
    }

    /// The fingerprint taken right after reading, so saved progress
    /// describes the bytes as they were read, not as they are when saving.
    private var fingerprinted: (offset: UInt64, identity: UInt64, value: UInt64)?

    /// Where a resumed read picks up: the start of a line still being
    /// written, or past a line too long to keep.
    fileprivate var boundary: UInt64 { discarding ? offset : offset - UInt64(pending.count) }

    /// Reads the log again from its start.
    func startOver(identity: UInt64) {
        if offset > 0 { restarted = true }
        self.identity = identity
        offset = 0
        pending = Data()
        discarding = false
        state = AgentLogState()
        cursorPromptFingerprint = nil
        cursorPrefix = CursorTranscriptPrefix()
        cachedCoverage = nil
        if provider == .cursor { CursorReader.adopt(path: path, into: &state) }
        fingerprinted = nil
        codexParentSearch = -1
    }

    private func fingerprint(upTo end: UInt64, descriptor: Int32? = nil) -> UInt64? {
        if let descriptor { return AgentLogReader.fingerprint(descriptor, upTo: end) }
        if provider == .cursor {
            guard let file = cursorAccess?.openFile(at: path) else { return nil }
            return file.fingerprint(upTo: end)
        }
        return AgentLogReader.fingerprint(path, upTo: end)
    }

    func fingerprintRead(descriptor: Int32? = nil) {
        let end = boundary
        if let taken = fingerprinted, taken.offset == end, taken.identity == identity { return }
        fingerprinted = fingerprint(upTo: end, descriptor: descriptor).map { (end, identity, $0) }
    }

    static func modificationDate(_ file: stat) -> Date {
        Date(timeIntervalSince1970: TimeInterval(file.st_mtimespec.tv_sec)
             + TimeInterval(file.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    /// False once the log no longer holds what was read: written again in
    /// place, perhaps past where reading stopped, which its size and inode
    /// alone do not show.
    func holdsWhatWasRead(descriptor: Int32?) -> Bool {
        guard let taken = fingerprinted, taken.identity == identity else { return true }
        return fingerprint(upTo: taken.offset, descriptor: descriptor) == taken.value
    }

    var saved: Saved {
        let end = boundary
        let sample: UInt64
        if let taken = fingerprinted, taken.offset == end, taken.identity == identity {
            sample = taken.value
        } else {
            sample = self.fingerprint(upTo: end) ?? 0
            fingerprinted = (end, identity, sample)
        }
        return Saved(path: path, provider: provider, offset: end, identity: identity, discarding: discarding,
                     modified: modified, state: state, fingerprint: provider == .cursor ? cursorPrefix.boundaryChecksum : sample,
                     cursorSample: provider == .cursor && !cursorPrefix.needsVerification ? sample : nil)
    }

    /// Nil when the path no longer holds the log that was read up to the
    /// saved offset: replaced by another file, or cut short and written
    /// again in place.
    convenience init?(saved: Saved, cursorRoot: URL? = nil, shouldContinue: () -> Bool = { true }) {
        let sample: UInt64
        if saved.provider == .cursor {
            guard let cursorRoot, let file = CursorTranscriptAccess(root: cursorRoot).openFile(at: saved.path),
                  UInt64(file.info.st_ino) == saved.identity,
                  let edges = file.fingerprint(upTo: saved.offset) else { return nil }
            let unchanged = UInt64(max(0, file.info.st_size)) == saved.offset
                && Self.modificationDate(file.info) == saved.modified && saved.cursorSample == edges
            guard unchanged || CursorTranscriptPrefix.matches(file, upTo: saved.offset, checksum: saved.fingerprint,
                                                              shouldContinue: shouldContinue) == true else { return nil }
            sample = edges
        } else {
            var info = stat()
            guard stat(saved.path, &info) == 0, UInt64(info.st_ino) == saved.identity,
                  AgentLogReader.fingerprint(saved.path, upTo: saved.offset) == saved.fingerprint else { return nil }
            sample = saved.fingerprint
        }
        self.init(path: saved.path, provider: saved.provider, cursorRoot: cursorRoot)
        offset = saved.offset
        identity = saved.identity
        discarding = saved.discarding
        modified = saved.modified
        state = saved.state
        fingerprinted = (saved.offset, saved.identity, sample)
        if provider == .cursor { cursorPrefix = CursorTranscriptPrefix(restoring: saved.fingerprint) }
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

    /// Cursor can replace a transcript at the end of a turn. During a replay,
    /// keep only the final turn. Only a turn that was already open can finish
    /// with a notice, using the start observed before the rewrite.
    static func readCursor(_ cursor: AgentLogCursor, into store: AgentUsageStore, now: Date,
                           since horizon: Date = .distantPast, shouldContinue: () -> Bool = { true }, report: (AgentUsageEvent) -> Void) -> Bool {
        guard shouldContinue() else { return false }
        guard let file = cursor.cursorAccess?.openFile(at: cursor.path) else {
            let hadActivity = cursor.state.cursorLastActivity != nil
            cursor.startOver(identity: 0)
            return store.forget(files: [cursor.path]) || hadActivity
        }
        let coverageStart = max(horizon, now.addingTimeInterval(-AgentUsageSnapshot.historyDuration))
        var changed = cursor.dropCursorCoverage(before: coverageStart)
        let previous = (turnOpen: cursor.state.turnOpen, cursorPromptCount: cursor.state.cursorPromptCount,
                        cursorPromptTimestamp: cursor.state.cursorPromptTimestamp, cursorLastActivity: cursor.state.cursorLastActivity)
        let previousPrompt = cursor.cursorPromptFingerprint
        defer { if !cursor.state.turnOpen { cursor.cursorPromptFingerprint = nil } }
        var preservedPrefix = false
        var replay = cursor.offset == 0
        var replayStart: Date?
        var succeeded = false
        func apply(_ entries: [AgentLogEntry]) {
            store.apply(entries, file: cursor.path, provider: .cursor, tracksTurns: true,
                        modified: cursor.modified, now: now).forEach(report)
        }
        readRegularFile(cursor, secured: file, shouldContinue: shouldContinue, onRestart: {
            // After a cache restore there is no in-memory prompt fingerprint.
            // An atomic replacement may still contain the saved file prefix.
            if previous.turnOpen && previousPrompt == nil && cursor.offset > 0 {
                guard let matches = CursorTranscriptPrefix.matches(file, upTo: cursor.boundary, checksum: cursor.cursorPrefix.boundaryChecksum,
                                                                   shouldContinue: shouldContinue) else { return false }
                preservedPrefix = matches
            }
            replay = true
            if cursor.offset > 0 { changed = store.forgetUsage(files: [cursor.path]) || changed }
            return true
        }) { line in
            cursor.cachedCoverage = nil
            let moment = min(cursor.modified, now)
            let promptCount = cursor.state.cursorPromptCount
            let entries = CursorReader(replaying: replay, coverageWindow: (coverageStart, now))
                .parse(line, state: &cursor.state, now: moment)
            guard !entries.isEmpty else { return }
            if cursor.state.cursorPromptCount != promptCount {
                cursor.cursorPromptFingerprint = CursorReader.promptFingerprint(line)
            }
            changed = true
            for entry in entries {
                if case .usage(_, let record, _) = entry {
                    // An incomplete set of replies cannot measure this live turn.
                    if record.date >= horizon, record.date <= now {
                        store.apply([entry], file: cursor.path, provider: .cursor, tracksTurns: false,
                                    modified: cursor.modified, now: now)
                    }
                } else if replay {
                    switch entry {
                    case .turnBegan(let date): replayStart = date; succeeded = false
                    case .turnEnded(_, let completed, _): succeeded = completed
                    default: break
                    }
                } else {
                    apply([entry])
                }
            }
        }
        guard replay else { return changed }
        guard shouldContinue(), cursor.offset == UInt64(max(0, file.info.st_size)) else {
            // No partial replay is a valid checkpoint for a later launch.
            cursor.startOver(identity: cursor.identity)
            return store.forget(files: [cursor.path]) || changed
        }
        let sameTurn = previous.turnOpen && previous.cursorPromptCount > 0
            && previous.cursorPromptCount == cursor.state.cursorPromptCount
            && previous.cursorPromptTimestamp == cursor.state.cursorPromptTimestamp
            && (previousPrompt.map { $0 == cursor.cursorPromptFingerprint } ?? preservedPrefix)
        let moment = min(cursor.modified, now)
        if cursor.state.turnOpen, let start = replayStart, let last = cursor.state.cursorLastActivity {
            if !sameTurn || (store.turns[cursor.path] == nil && store.waiting[cursor.path] == nil) {
                store.forget(file: cursor.path)
                // An attached file can already contain history. The clock on a
                // newly observed live turn starts at its last write.
                apply([.turnBegan(store.reportsTransitions ? moment : start)])
            }
            apply([.turnActive(last), .turnContext(model: "", project: cursor.state.project)])
        } else if previous.turnOpen {
            apply([.turnEnded(moment, completed: sameTurn && succeeded, duration: nil)])
            changed = true
        }
        return changed || previous.cursorLastActivity != cursor.state.cursorLastActivity
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
        return fingerprint(descriptor, upTo: offset)
    }

    static func fingerprint(_ descriptor: Int32, upTo offset: UInt64) -> UInt64? {
        guard offset <= UInt64(Int64.max) else { return nil }
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
            let subagent = root.provider == .claude && AgentLogCursor.parent(of: url.path) != nil
            found.append((url.path, root.provider, modified, subagent))
        }
        for root in roots {
            // Cursor keeps tools, terminals and canvases beside transcripts.
            // Enumerate only the two expected directory levels under the root.
            if root.provider == .cursor {
                let access = CursorTranscriptAccess(root: root.url)
                for project in access.entries(at: []) {
                    let directory = root.url.appending(path: project, directoryHint: .isDirectory)
                        .appending(path: "agent-transcripts", directoryHint: .isDirectory)
                    let entries = access.entries(at: [project, "agent-transcripts"])
                    let sessions = Set(entries.map { $0.hasSuffix(".jsonl") ? String($0.dropLast(6)) : $0 })
                    for session in sessions {
                        let files = CursorTranscriptFiles(directory: directory, session: session)
                        if let file = files.preferred(in: access), file.modified >= horizon {
                            found.append((file.path, .cursor, file.modified, false))
                        }
                    }
                }
                continue
            }
            guard root.exists else { continue }
            // OpenCode keeps its database beside the snapshots, clones and
            // logs of its data folder, which are never walked.
            if root.provider == .opencode {
                let path = root.url.appending(path: AgentOpenCodeReader.database).path
                if let modified = AgentOpenCodeReader.modified(path), modified >= horizon {
                    found.append((path, root.provider, modified, false))
                }
                continue
            }
            // A Copilot session can contain a complete workspace checkout,
            // databases and checkpoints. Its log has one fixed shallow path;
            // recursively walking the workspace can delay the first snapshot
            // indefinitely on a large repository.
            if root.provider == .copilot {
                let sessions = (try? FileManager.default.contentsOfDirectory(
                    at: root.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for session in sessions { include(session.appending(path: "events.jsonl"), from: root) }
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: keys,
                                                                  options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.path.hasSuffix(".jsonl") {
                include(url, from: root)
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
                             shouldContinue: () -> Bool = { true },
                             including: ((Data, Range<Int>) -> Bool)? = nil, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        if cursor.provider == .opencode {
            AgentOpenCodeReader.readAppended(cursor, since: horizon, shouldContinue: shouldContinue, line: line)
            return
        }
        if cursor.provider == .cursor {
            guard let file = cursor.cursorAccess?.openFile(at: cursor.path) else { return }
            readRegularFile(cursor, secured: file, shouldContinue: shouldContinue, including: including, line: line)
        } else {
            readRegularFile(cursor, secured: nil, shouldContinue: shouldContinue, including: including, line: line)
        }
    }

    private static func readRegularFile(_ cursor: AgentLogCursor, secured: CursorTranscriptAccess.File?,
                                        shouldContinue: () -> Bool, onRestart: () -> Bool = { true },
                                        including: ((Data, Range<Int>) -> Bool)? = nil, line: (Data) -> Void) {
        var info = stat()
        if let secured {
            info = secured.info
        } else {
            guard cursor.provider != .cursor, stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        }
        let size = UInt64(max(0, info.st_size))
        let identity = UInt64(info.st_ino)
        let modified = AgentLogCursor.modificationDate(info)
        let sameSizeRewrite = cursor.provider == .cursor && size == cursor.offset && cursor.modified != modified
        func cursorPrefixChanged() -> Bool {
            guard let secured else { return false }
            return !cursor.cursorPrefix.matches(secured, offset: cursor.offset, grew: size > cursor.offset)
        }
        // A same-length edit can change counters in the unsampled middle.
        if cursor.needsUsageReplay || identity != cursor.identity || size < cursor.offset || sameSizeRewrite
            || (size > cursor.offset && !cursor.holdsWhatWasRead(descriptor: secured?.handle.fileDescriptor))
            || cursorPrefixChanged() {
            guard onRestart() else { return }
            cursor.needsUsageReplay = false
            cursor.startOver(identity: identity)
        }
        cursor.modified = modified
        defer { cursor.fingerprintRead(descriptor: secured?.handle.fileDescriptor) }
        guard size > cursor.offset, let handle = secured?.handle ?? FileHandle(forReadingAtPath: cursor.path) else { return }
        defer { if secured == nil { try? handle.close() } }
        do { try handle.seek(toOffset: cursor.offset) } catch { return }
        while cursor.offset < size, shouldContinue() {
            let wanted = Int(min(UInt64(chunkSize), size - cursor.offset))
            // A first read can cover gigabytes; each chunk and what was parsed
            // from it are released before the next one.
            let read: Bool = autoreleasepool {
                guard let chunk = try? handle.read(upToCount: wanted), !chunk.isEmpty else { return false }
                cursor.offset += UInt64(chunk.count)
                split(chunk, cursor: cursor, including: including, line: line)
                if secured != nil { cursor.cursorPrefix.append(chunk, pending: cursor.pending.count) }
                return true
            }
            guard read else { break }
        }
    }

    /// Skip unrelated payloads before copying a line. Only top-level event
    /// types count, including in whitespace-formatted logs or nested results.
    static func copilotHistoryLine(_ buffer: Data, range: Range<Int>) -> Bool {
        guard let type = AgentLogObject(buffer, range: range)?.string("type") else { return false }
        return AgentLogParser.copilotEvent(type)
    }

    /// Streams every structural event so responses keep their original date
    /// and model, and the final turn state is restored. The line filter keeps
    /// unrelated workspace output from being copied or decoded.
    static func readCopilotHistory(_ cursor: AgentLogCursor, shouldContinue: () -> Bool = { true },
                                   line: (Data) -> Void) {
        readAppended(cursor, shouldContinue: shouldContinue, including: copilotHistoryLine, line: line)
    }

    private static func split(_ chunk: Data, cursor: AgentLogCursor,
                              including: ((Data, Range<Int>) -> Bool)?, line: (Data) -> Void) {
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
            if !range.isEmpty, range.count <= maximumLine, including?(buffer, range) != false {
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
