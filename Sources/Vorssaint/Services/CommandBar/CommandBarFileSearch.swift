// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreServices
import Foundation

/// Finds files by name in the folders on the list, the visible folders of
/// home unless the person changed it, through the index macOS already keeps.
///
/// Nothing is indexed, watched or remembered here: an empty field does no
/// work, a query is asked of Spotlight once and its answer is thrown away when
/// the bar closes. No permission is asked for either, because what comes back
/// is filtered down to what the person can already see in Finder.
///
/// `MDQuery` rather than `NSMetadataQuery` for one reason: it can be told to
/// stop at a thousand names. A broad word has hundreds of thousands of answers
/// on a full disk, and the newer class has no way to say no to them.
///
/// Not part of the pure-function test harness (`./build.sh --test`): the rules
/// live in `CommandBarFileSearchSupport` and are tested there; what is left is
/// a timer and a call into Spotlight.
final class CommandBarFileSearch {
    /// How long the field has to sit still before Spotlight is asked. Typing
    /// is faster than this, which is the point: a query per keystroke would
    /// ask for eight searches to answer one.
    static let debounce: TimeInterval = 0.12

    /// Called on the main thread when results for some query become ready.
    var onResult: (() -> Void)?

    private var cache: [String: [String]] = [:]
    private var inFlight: Set<String> = []
    private var pendingWorkItem: DispatchWorkItem?
    private var generation = 0
    private var currentQuery: String?
    private let searchQueue = DispatchQueue(label: "com.vorssaint.commandbar.files",
                                            qos: .userInitiated)
    private let activeQueryLock = NSLock()
    private var cancellationGeneration = 0
    private var activeQuery: (generation: Int, query: MDQuery)?

    /// One opening of the bar owns its results. Clearing the session also
    /// stops a search started before it closed from publishing into the next.
    func reset() {
        generation &+= 1
        cancelPending()
        cache.removeAll()
        inFlight.removeAll()
    }

    func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        currentQuery = nil
        stopActiveQuery()
    }

    /// The paths already found for exactly this query, or nil while nothing
    /// has been asked for it yet.
    func cachedPaths(for query: String) -> [String]? {
        cache[query]
    }

    /// Asks for this query once the field stops moving. A query already
    /// answered, or already being answered, is left alone.
    func schedule(query: String, scopes: [String], patterns: [String]) {
        currentQuery = query
        guard !scopes.isEmpty,
              CommandBarFileSearchSupport.expression(for: query) != nil,
              cache[query] == nil, !inFlight.contains(query)
        else { return }
        // The newest query is the only one worth waiting for: a search whose
        // text the person has already typed past must never land.
        pendingWorkItem?.cancel()
        stopActiveQuery()
        let runCancellationGeneration = activeQueryLock.withLock { cancellationGeneration }
        let workItem = DispatchWorkItem { [weak self] in
            self?.execute(query: query, scopes: scopes, patterns: patterns,
                          cancellationGeneration: runCancellationGeneration)
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: workItem)
    }

    /// A search waits out its debounce or is going.
    var isAwaiting: Bool { pendingWorkItem != nil || !inFlight.isEmpty }

    private func execute(query: String, scopes: [String], patterns: [String],
                         cancellationGeneration runCancellationGeneration: Int) {
        guard let expression = CommandBarFileSearchSupport.expression(for: query) else { return }
        let parsed = CommandBarFileSearchSupport.parse(query)
        let home = NSHomeDirectory()
        pendingWorkItem = nil
        let runGeneration = generation
        inFlight.insert(query)
        searchQueue.async { [weak self] in
            guard let self else { return }
            let found = self.search(expression: expression,
                                    scopes: scopes,
                                    sort: parsed.sort,
                                    limit: parsed.isFocused
                                        ? CommandBarFileSearchSupport.focusedCandidateLimit
                                        : CommandBarFileSearchSupport.candidateLimit,
                                    cancellationGeneration: runCancellationGeneration)
            // Spotlight cannot match a path, so the words that name a folder
            // are checked here, before the order is settled.
            let matching = found.filter {
                CommandBarFileSearchSupport.matchesPathWords(
                    path: $0.path, words: parsed.pathWords, homeDirectory: home)
            }
            let paths = CommandBarFileSearchSupport.offerable(
                paths: CommandBarFileSearchSupport.sorted(matching, by: parsed.sort),
                patterns: patterns,
                isPackage: { Self.isPackage(atPath: $0) })
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == runGeneration else { return }
                self.inFlight.remove(query)
                guard self.activeQueryLock.withLock({
                    self.cancellationGeneration == runCancellationGeneration
                }) else { return }
                self.cache[query] = paths
                guard CommandBarFileSearchSupport.shouldPublishResult(
                    for: query, currentQuery: self.currentQuery) else { return }
                self.onResult?()
            }
        }
    }

    /// The Spotlight call itself, kept inside one synchronous function so the
    /// query object never outlives it.
    private func search(expression: String,
                        scopes: [String],
                        sort: CommandBarFileSearchSupport.SortOrder,
                        limit: Int,
                        cancellationGeneration runGeneration: Int)
        -> [CommandBarFileSearchSupport.Candidate] {
        let liveScopes = scopes.filter(Self.isSearchableDirectory)
        guard !liveScopes.isEmpty else { return [] }
        guard let query = MDQueryCreate(kCFAllocatorDefault, expression as CFString, nil, nil)
        else { return [] }
        let canStart = activeQueryLock.withLock {
            guard cancellationGeneration == runGeneration else { return false }
            activeQuery = (runGeneration, query)
            return true
        }
        guard canStart else { return [] }
        defer {
            activeQueryLock.withLock {
                if activeQuery?.generation == runGeneration { activeQuery = nil }
            }
        }
        MDQuerySetMaxCount(query, CFIndex(limit))
        MDQuerySetSearchScope(query, liveScopes as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        let count = MDQueryGetResultCount(query)
        var candidates: [CommandBarFileSearchSupport.Candidate] = []
        candidates.reserveCapacity(min(count, limit))
        for index in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = unsafeBitCast(raw, to: MDItem.self)
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            var candidate = CommandBarFileSearchSupport.Candidate(path: path)
            // Only the attribute the sort reads is asked for: each one is a
            // round trip into the index for every answer.
            switch sort {
            case .size:
                candidate.size = (MDItemCopyAttribute(item, kMDItemFSSize) as? NSNumber)?.int64Value
            case .modified:
                candidate.modified = MDItemCopyAttribute(item, kMDItemFSContentChangeDate) as? Date
            case .name, .path:
                break
            }
            candidates.append(candidate)
        }
        return candidates
    }

    /// Stops the synchronous Spotlight query itself, not merely its callback.
    /// The queue is serial, so a slow old query can never overlap the text the
    /// person is typing now or keep working after the bar closes.
    private func stopActiveQuery() {
        activeQueryLock.withLock {
            cancellationGeneration &+= 1
            if let activeQuery { MDQueryStop(activeQuery.query) }
            activeQuery = nil
        }
    }

    /// Finder package status comes from the filesystem, so document bundles
    /// and future package types are sealed without maintaining an extension list.
    private static func isPackage(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        return (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }

    /// A restored preference can point at something that moved or became a
    /// file. Only live, ordinary directories become Spotlight scopes.
    static func isSearchableDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        return !isPackage(atPath: path)
    }
}
