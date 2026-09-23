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
    private var index: [String: Int] = [:]
    private(set) var limits: [AgentProvider: AgentLimits] = [:]
    private(set) var codexPlan: String?
    /// Open turns by log file.
    private(set) var turns: [String: AgentLiveSession] = [:]
    /// Off while the logs are first read, so history never replays as news.
    var reportsTransitions = false
    /// A turn that ended longer ago than this is history found late, like a
    /// session an agent moved to its archive, not news.
    static let lateEnd: TimeInterval = 5 * 60

    var live: [AgentLiveSession] { Array(turns.values) }

    /// Applies one file's entries and returns the turns they finished.
    @discardableResult
    func apply(_ entries: [AgentLogEntry], file: String, provider: AgentProvider,
               tracksTurns: Bool, modified: Date, now: Date = Date()) -> [AgentUsageEvent] {
        var events: [AgentUsageEvent] = []
        for entry in entries {
            switch entry {
            case .usage(let key, let record, let billable):
                add(record, billable: billable, key: key, file: tracksTurns ? file : nil)
            case .limits(let reading):
                if (limits[reading.provider]?.observedAt ?? .distantPast) <= reading.observedAt {
                    limits[reading.provider] = reading
                }
            case .plan(let plan):
                codexPlan = plan
            case .turnBegan(let date):
                guard tracksTurns else { continue }
                // A log rewritten in place is read again from its start; the
                // turn it already holds keeps what its responses added, which
                // the second reading skips as repeats.
                if let turn = turns[file], abs(turn.started.timeIntervalSince(date)) < 1 { continue }
                turns[file] = AgentLiveSession(id: file, provider: provider, started: date,
                                               lastActivity: max(date, turns[file]?.lastActivity ?? date),
                                               model: "", project: "", tokens: AgentTokens(), cost: 0)
            case .turnActive(let date):
                guard tracksTurns else { continue }
                let moment = date ?? modified
                if var turn = turns[file] {
                    turn.lastActivity = max(turn.lastActivity, moment)
                    turns[file] = turn
                } else {
                    turns[file] = AgentLiveSession(id: file, provider: provider, started: moment, lastActivity: moment,
                                                   model: "", project: "", tokens: AgentTokens(), cost: 0)
                }
            case .turnEnded(let date, let completed, let duration):
                guard tracksTurns, let turn = turns.removeValue(forKey: file),
                      completed, reportsTransitions else { continue }
                let end = date ?? modified
                guard now.timeIntervalSince(end) <= Self.lateEnd else { continue }
                events.append(.finished(provider: provider,
                                        duration: max(0, duration ?? end.timeIntervalSince(turn.started)),
                                        cost: turn.cost, tokens: turn.tokens.total, project: turn.project))
            }
        }
        return events
    }

    /// A log removed while its turn ran, like a deleted chat, ends that turn
    /// without a notice: nothing finished. True when there was one.
    @discardableResult
    func forget(file: String) -> Bool { turns.removeValue(forKey: file) != nil }

    private func add(_ record: AgentUsageRecord, billable: AgentBillable, key: String, file: String?) {
        var delta = record.tokens
        var extra = record.cost ?? 0
        if let position = index[key] {
            let old = records[position]
            let merged = old.tokens.merged(with: record.tokens)
            guard merged != old.tokens else { return }
            var combined = billables[position]
            combined.tokens = merged
            combined.longCacheWrite = max(combined.longCacheWrite, billable.longCacheWrite)
            combined.webSearches = max(combined.webSearches, billable.webSearches)
            combined.fast = combined.fast || billable.fast
            combined.domestic = combined.domestic || billable.domestic
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
            index[key] = records.count
            records.append(record)
            billables.append(billable)
        }
        guard let file, var turn = turns[file], record.date >= turn.started.addingTimeInterval(-1) else { return }
        turn.tokens += delta
        turn.cost += extra
        turn.lastActivity = max(turn.lastActivity, record.date)
        if !record.model.isEmpty { turn.model = record.model }
        if !record.project.isEmpty { turn.project = record.project }
        turns[file] = turn
    }

    /// Prices every response again, after a newer list arrives.
    func reprice() {
        for position in records.indices {
            let priced = AgentPricing.cost(billables[position], model: records[position].model)
            records[position].cost = priced.cost
            records[position].savings = priced.savings
        }
    }

    func setLimits(_ reading: AgentLimits) {
        limits[reading.provider] = reading
    }

    func clearLimits(_ provider: AgentProvider) {
        limits[provider] = nil
    }

    /// A turn that has written nothing for this long is not being worked on:
    /// its process ended without a word, or it waits on something outside.
    func closeIdleTurns(now: Date, after idle: TimeInterval) {
        turns = turns.filter { now.timeIntervalSince($0.value.lastActivity) < idle }
    }

    /// Keeps memory bounded to the history the island can show.
    func dropRecords(before date: Date) {
        guard records.contains(where: { $0.date < date }) else { return }
        var kept: [AgentUsageRecord] = []
        var keptBillables: [AgentBillable] = []
        var positions: [Int: Int] = [:]
        for (offset, record) in records.enumerated() where record.date >= date {
            positions[offset] = kept.count
            kept.append(record)
            keptBillables.append(billables[offset])
        }
        index = index.compactMapValues { positions[$0] }
        records = kept
        billables = keptBillables
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
         (.codex, ".codex/sessions"), (.codex, ".codex/archived_sessions")].map { provider, path in
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

/// How far into one log file reading has got.
final class AgentLogCursor {
    let path: String
    let provider: AgentProvider
    /// Subagents and side threads report to a turn another file tracks.
    let tracksTurns: Bool
    var offset: UInt64 = 0
    var identity: UInt64 = 0
    var pending = Data()
    var discarding = false
    var state = AgentLogState()
    var modified = Date.distantPast

    init(path: String, provider: AgentProvider) {
        self.path = path
        self.provider = provider
        let name = (path as NSString).lastPathComponent
        tracksTurns = provider == .claude ? !path.contains("/subagents/") : !name.contains("_")
    }
}

enum AgentLogReader {
    static let chunkSize = 4 << 20
    /// A line longer than this is a pasted file or a tool's output, never a
    /// usage record; it is skipped rather than held in memory.
    static let maximumLine = 32 << 20

    static func isLog(_ path: String) -> Bool { path.hasSuffix(".jsonl") }

    /// Log files changed since `horizon`, newest last so live turns settle
    /// on the most recent state.
    static func discover(_ roots: [AgentLogRoot], since horizon: Date) -> [(path: String, provider: AgentProvider)] {
        var found: [(path: String, provider: AgentProvider, modified: Date)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for root in roots where root.exists {
            guard let enumerator = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: keys,
                                                                  options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where isLog(url.path) {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= horizon else { continue }
                found.append((url.path, root.provider, modified))
            }
        }
        return found.sorted { $0.modified < $1.modified }.map { ($0.path, $0.provider) }
    }

    /// Reads what was appended since the last call and hands over each
    /// complete line. A replaced or truncated file starts over.
    static func readAppended(_ cursor: AgentLogCursor, line: (Data) -> Void) {
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let size = UInt64(max(0, info.st_size))
        let identity = UInt64(info.st_ino)
        cursor.modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        if identity != cursor.identity || size < cursor.offset {
            cursor.identity = identity
            cursor.offset = 0
            cursor.pending = Data()
            cursor.discarding = false
            cursor.state = AgentLogState()
        }
        guard size > cursor.offset, let handle = FileHandle(forReadingAtPath: cursor.path) else { return }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: cursor.offset) } catch { return }
        while cursor.offset < size {
            let wanted = Int(min(UInt64(chunkSize), size - cursor.offset))
            guard let chunk = try? handle.read(upToCount: wanted), !chunk.isEmpty else { break }
            cursor.offset += UInt64(chunk.count)
            split(chunk, cursor: cursor, line: line)
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
            var position = 0
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
            if !range.isEmpty { line(buffer.subdata(in: range)) }
        }
        if count - start > maximumLine {
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
