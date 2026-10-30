// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import Network

/// Reads Claude Code, Codex and GitHub Copilot usage from local session logs, and
/// OpenCode usage from its database, while the AI section is on, along with
/// the plan limits the Claude app saves. The files are read where they are,
/// incrementally, and nothing is copied or sent: only counters are kept, in
/// memory and in the app's private folder so the next launch reads only what
/// the agents wrote meanwhile. OpenCode's stay in memory only, and its
/// database is read again at each launch. Claude Code checks account-wide
/// limits through its own CLI, including use on other machines. The public
/// price list is fetched only when the person keeps prices up to date.
///
/// Reading happens on a private queue; the main thread and that queue hand
/// work to each other asynchronously, except that a stop waits for progress
/// to be saved. The queue never waits for the main thread.
final class AgentUsageService: ObservableObject {
    static let shared = AgentUsageService()

    @Published private(set) var snapshot = AgentUsageSnapshot()
    /// When the Claude app last saved the plan's limits; nil when it never has.
    @Published private(set) var claudeAppChecked: Date?
    @Published private(set) var claudeAccountChecking = false
    @Published private(set) var claudeAccountFailure: AgentClaudeServer.Failure?
    @Published private(set) var claudeProfile = ClaudeAccountProfile()
    @Published private(set) var claudeAccountIdentity: ClaudeAccountProfile.Identity?
    /// Antigravity status
    @Published private(set) var agyChecking = false
    @Published private(set) var agyFailure: AgentAgyServer.Failure?
    /// The day of the price list in use.
    @Published private(set) var pricesUpdated: Date?
    let events = PassthroughSubject<AgentUsageEvent, Never>()

    /// The history the island can show: thirteen weeks for the activity map.
    static let horizon = TimeInterval(AgentUsageSnapshot.dayCount) * 86_400
    private static let tick: TimeInterval = 30
    /// File events report a written file only once it closes, and some
    /// agents keep their log open for the whole session: logs written in the
    /// last half hour, or holding a turn, are checked this often instead.
    private static let poll: TimeInterval = 2
    private static let pollWindow: TimeInterval = 30 * 60
    /// Coalesce a live log's bursts into one history and display update.
    private static let publishDelay: TimeInterval = 1
    /// How often progress is saved while agents write, besides on quit and
    /// pause; a launch after a crash reads again only what came after.
    private static let saveInterval: TimeInterval = 5 * 60

    private let queue = DispatchQueue(label: "com.vorssaint.agent-usage", qos: .utility, autoreleaseFrequency: .workItem)
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Lets a stop end a first read that is still going on the queue.
    private final class Cancellation {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    // Main thread.
    private var running = false
    /// Reading waits while the island is away; what was read stays.
    private var paused = false
    private var session = 0
    private var cancellation = Cancellation()
    private var timer: Timer?
    private var providers: [AgentProvider] = []
    private var pricesInFlight = false
    private var pricesAttempted = Date.distantPast
    private var pricesFailed = false
    /// When the list on disk was downloaded; nil until the queue has looked.
    private var pricesSaved: Date?
    private let claudeAccountQueue = DispatchQueue(label: "com.vorssaint.claude-limits", qos: .utility)
    private var claudeAccountRequest: AgentClaudeServer.Request?
    private var claudeAccountAttempted = Date.distantPast
    /// Checks in a row that Claude Code did not answer, counted again from
    /// zero once the Mac is back online.
    private var claudeAccountUnreachable = 0
    private let agyAccountQueue = DispatchQueue(label: "com.vorssaint.agy-limits", qos: .utility)
    private var agyRequest: AgentAgyServer.Request?
    private var agyAttempted = Date.distantPast
    /// Whether the Mac has a network, as the reading queue last heard.
    private var online = true
    /// The AI page is on the island, which asks Claude Code more often.
    private var pageVisible = false

    // Confined to `queue`.
    private var readerSession = -1
    private var readerCancellation: Cancellation?
    private var enabled: Set<AgentProvider> = []
    private var store = AgentUsageStore()
    private let agyConversationReader = AgentAgyConversationReader()
    private var cursors: [String: AgentLogCursor] = [:]
    private var watcher: AgentLogWatcher?
    private var watchedRoots: [AgentLogRoot] = []
    private var poller: DispatchSourceTimer?
    private var polling = false
    private var network: NWPathMonitor?
    /// When the Mac lost its network, and the uptime then, which leaves out
    /// sleep; nil while it has one.
    private var offlineSince: (date: Date, uptime: TimeInterval)?
    private var publishScheduled = false
    /// The last snapshot handed over, to tell when time alone changes it.
    private var published = AgentUsageSnapshot()
    private var claudePlan: AgentPlan?
    /// The organization Claude Code signs in to, when its profile says.
    private var claudeOrganization: String?
    private var claudeIdentity: ClaudeAccountProfile.Identity?
    private var readerClaudeProfile = ClaudeAccountProfile()
    private var claudeProfileModified: Date?
    private var claudeAppModified: Date?
    private var claudeAppSamples: [AgentClaudeAppUsage.Sample] = []
    private var claudeAccountLimits: AgentLimits?
    private var shippedPrices: AgentPriceList?
    private var previousLimits: [AgentProvider: AgentLimits] = [:]
    /// Warned windows, each waiting for its renewal.
    private var warned: [String: (provider: AgentProvider, window: AgentLimitWindow)] = [:]
    private var budgetDay: Date?
    private var lastRootCheck = Date.distantPast
    /// Tells whether reading moved on since progress was last saved.
    /// Nil until this reading saved or resumed progress: the first save
    /// always replaces what is on disk, which may hold agents now off.
    private var savedMark: Int?
    private var lastSave = Date.distantPast

    private init() {}

    func syncWithPreferences() {
        CodexProfileLimitsService.shared.synchronize()
        guard NotchAgentSupport.isEnabled() else { stop(); return }
        let wanted = NotchAgentSupport.providers()
        let profile = ClaudeAccountProfile.selected()
        let showingPage = pageVisible
        // An agent turned off is no longer read at all, and one turned on is
        // read from its start: both take a fresh reading, which would not
        // resume progress saved for the old set, so it goes at once. Codex
        // accounts keep their checks: they read no log.
        if running, wanted != providers || profile != claudeProfile {
            stop(keepingProgress: false, pausingAccounts: false)
        }
        if claudeProfile != profile { claudeProfile = profile }
        pageVisible = showingPage
        if !running {
            running = true
            session += 1
            cancellation = Cancellation()
            providers = wanted
            start(session: session, providers: Set(wanted), cancellation: cancellation, claudeProfile: profile)
        } else if paused {
            resume()
        }
        syncPrices()
        refreshClaudeLimits()
        refreshAgyLimits()
    }

    /// Stops reading while the island is away, as with the display asleep or
    /// the Mac locked, and keeps what was read: reading every log again on the
    /// way back costs far more than the pause saves.
    func pause() {
        CodexProfileLimitsService.shared.pause()
        // A page torn down with the island never reports leaving, so the
        // minute cadence would outlive it.
        pageVisible = false
        guard running, !paused else { return }
        paused = true
        cancelClaudeLimits()
        cancelAgyLimits()
        timer?.invalidate()
        timer = nil
        queue.async { [self] in
            poller?.cancel()
            poller = nil
            watcher?.stop()
            saveProgress()
        }
    }

    /// Reads what the agents wrote meanwhile, from where each log stopped.
    private func resume() {
        paused = false
        startTimer()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            watch(AgentLogRoot.all(home: home, claudeProfile: readerClaudeProfile).filter { enabled.contains($0.provider) })
            filesChanged([], rescan: true)
            startPolling()
            // Time went by meanwhile: a window or the day may have moved on.
            schedulePublish()
        }
    }

    func stop(keepingProgress keeps: Bool = true, pausingAccounts: Bool = true) {
        if pausingAccounts { CodexProfileLimitsService.shared.pause() }
        pageVisible = false
        // A first read still going stops at its next chunk, so the wait
        // below is short.
        if running { cancellation.cancel() }
        settleArchive(keeping: keeps && NotchAgentSupport.isEnabled())
        guard running else { return }
        running = false
        cancelClaudeLimits()
        cancelAgyLimits()
        claudeAccountAttempted = .distantPast
        agyAttempted = .distantPast
        claudeAccountFailure = nil
        agyFailure = nil
        claudeAccountUnreachable = 0
        online = true
        paused = false
        session += 1
        timer?.invalidate()
        timer = nil
        providers = []
        pricesInFlight = false
        pricesSaved = nil
        snapshot = AgentUsageSnapshot()
        claudeAppChecked = nil
        claudeAccountIdentity = nil
        queue.async { [self] in
            readerSession = -1
            readerCancellation = nil
            poller?.cancel()
            poller = nil
            watcher?.stop()
            watcher = nil
            watchedRoots = []
            network?.cancel()
            network = nil
            offlineSince = nil
            store = AgentUsageStore()
            agyConversationReader.reset()
            cursors.removeAll()
            published = AgentUsageSnapshot()
            previousLimits.removeAll()
            warned.removeAll()
            budgetDay = nil
            claudePlan = nil
            claudeOrganization = nil
            claudeIdentity = nil
            claudeProfileModified = nil
            claudeAppModified = nil
            claudeAppSamples = []
            claudeAccountLimits = nil
            savedMark = nil
            lastSave = .distantPast
        }
    }

    /// Limits an agent read from the account on request, newer than its
    /// logs until it writes again: after a banked reset, right away.
    func noteLimits(_ reading: AgentLimits) {
        guard running else { return }
        queue.async { [self] in
            guard readerSession >= 0, enabled.contains(reading.provider) else { return }
            store.updateLimits(reading)
            checkLimits()
            schedulePublish()
        }
    }

    /// Reads local fallbacks immediately and asks Claude for fresh account
    /// limits. A Settings preview reads too, without counting as the page.
    func pageDidAppear(preview: Bool = false) {
        if !preview { pageVisible = true }
        guard running else { return }
        refreshClaudeLimits(pageShows: true)
        refreshAgyLimits(pageShows: true)
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            readClaudePlan()
            readClaudeApp(now: Date())
            checkLimits()
            publish()
        }
    }

    func pageDidDisappear() {
        pageVisible = false
    }

    /// A deliberate retry after choosing or signing in to an account.
    func checkClaudeAccount() {
        guard running, !paused, claudeAccountRequest == nil else { return }
        claudeAccountAttempted = .distantPast
        refreshClaudeLimits(pageShows: true)
    }

    // MARK: Reading

    private func startTimer() {
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.tickTimer() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func start(session: Int, providers: Set<AgentProvider>, cancellation: Cancellation,
                       claudeProfile: ClaudeAccountProfile = ClaudeAccountProfile()) {
        startTimer()
        queue.async { [self] in
            readerSession = session
            readerCancellation = cancellation
            enabled = providers
            readerClaudeProfile = claudeProfile
            store = AgentUsageStore()
            agyConversationReader.reset()
            cursors.removeAll()
            // Prices first, so the first read is already priced.
            loadPrices()
            // Keep the loading state until all initial history has been read.
            let horizon = Date().addingTimeInterval(-Self.horizon)
            let roots = AgentLogRoot.all(home: home, claudeProfile: claudeProfile).filter { providers.contains($0.provider) }
            // Cursors find an Antigravity conversation relative to its root.
            watchedRoots = roots.filter(\.exists)
            let files = AgentLogReader.discover(roots, since: horizon)
            // Resumes where the last launch stopped, among the logs there now.
            if let saved = AgentUsageArchive.load(), saved.providers == providers {
                let resumed = AgentUsageArchive.resume(saved, logs: Set(files.map(\.path)), since: horizon)
                (store, cursors) = (resumed.store, resumed.cursors)
                // What the resume took back leaves the disk at the next save.
                if resumed.unchanged { savedMark = progressMark }
            }
            for file in files {
                // A stop while reading leaves the rest for the next start.
                guard !cancellation.isCancelled else { return }
                read(file.path, provider: file.provider)
            }
            let now = Date()
            // A turn left open by a crash would otherwise stay working.
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
            closeEndedTurns(roots, atLaunch: true)
            if providers.contains(.agy) {
                guard !cancellation.isCancelled else { return }
                agyConversationReader.scan(into: store, since: horizon, home: home,
                                          shouldContinue: { !cancellation.isCancelled })
            }
            guard !cancellation.isCancelled else { return }
            // The account Claude Code uses picks the Claude app's readings.
            readClaudePlan()
            readClaudeApp(now: now)
            store.reportsTransitions = true
            previousLimits = store.limits
            // A budget already passed before launch is history, not news.
            let today = Calendar.autoupdatingCurrent.startOfDay(for: now)
            if let budget = NotchAgentSupport.dailyBudget(),
               store.records.lazy.filter({ $0.date >= today }).reduce(0.0, { $0 + ($1.cost ?? 0) }) >= budget {
                budgetDay = today
            }
            watch(roots)
            startPolling()
            watchNetwork()
            publish()
            saveProgress()
        }
    }

    /// Saves progress, or removes it once the section is off, even what an
    /// earlier launch saved. Quitting stops the service too and ends the
    /// process right after, so this returns only once the file is settled.
    /// Main thread.
    private func settleArchive(keeping keeps: Bool) {
        queue.sync {
            if keeps { saveProgress() } else { AgentUsageArchive.remove() }
        }
    }

    /// Saves what was read, when reading moved on since the last save. Runs
    /// on `queue`.
    private func saveProgress() {
        guard readerSession >= 0 else { return }
        let mark = progressMark
        lastSave = Date()
        guard mark != savedMark else { return }
        // A log that started over while running still counts what its old
        // contents gave. Left out, the next launch reads it as rewritten.
        // Nothing from OpenCode's database is saved. Its open replies and
        // sessions live only in memory, so each launch reads it again.
        let kept = cursors.values.filter { !$0.restarted && $0.provider != .opencode }
        let contents = AgentUsageArchive.Contents(providers: enabled, store: store.saved, cursors: kept.map(\.saved))
        if AgentUsageArchive.save(contents) { savedMark = mark }
    }

    /// Changes whenever a log is read further, replaced or let go. OpenCode,
    /// which is never saved, leaves it alone.
    private var progressMark: Int {
        let records = store.records.reduce(0) { $1.provider == .opencode ? $0 : $0 + 1 }
        return cursors.values.reduce(records) { mark, cursor in
            guard cursor.provider != .opencode else { return mark }
            var hasher = Hasher()
            hasher.combine(cursor.path)
            hasher.combine(cursor.offset)
            hasher.combine(cursor.identity)
            return mark &+ hasher.finalize()
        }
    }

    /// Runs on `queue`.
    private func startPolling() {
        poller?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .distantFuture)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            defer { self.syncPolling() }
            let read = self.pollOpenLogs(within: Self.pollWindow)
            var stopped = self.store.closeSettledTurns(now: Date())
            // After the logs too, which can hold a reply or a command's
            // result written meanwhile.
            if let offline = self.offlineSince,
               self.store.closeOfflineTurns(since: offline.date,
                                            lasting: ProcessInfo.processInfo.systemUptime - offline.uptime,
                                            keeping: self.runningCommands) {
                stopped = true
            }
            // After the logs, so a turn its last lines ended ends as usual.
            guard self.closeEndedTurns(self.watchedRoots) || read || stopped else { return }
            self.checkLimits()
            self.schedulePublish()
        }
        poller = timer
        polling = false
        syncPolling()
        timer.resume()
    }

    /// The fast timer has no work once recent logs and active turns are gone.
    /// File events and the existing thirty-second sweep can arm it again.
    /// Never create a timer here: late work after pause or stop must stay idle.
    private func syncPolling(now: Date = Date()) {
        guard let poller else { return }
        let wanted = !store.turns.isEmpty || !store.waiting.isEmpty
            || cursors.values.contains { now.timeIntervalSince($0.modified) < Self.pollWindow }
        guard wanted != polling else { return }
        polling = wanted
        if wanted {
            poller.schedule(deadline: .now() + Self.poll, repeating: Self.poll, leeway: .milliseconds(500))
        } else {
            poller.schedule(deadline: .distantFuture)
        }
    }

    /// Reads the logs that grew, were replaced or disappeared since the last
    /// look, among those an agent may still be writing. True when that
    /// changed what is stored.
    private func pollOpenLogs(within window: TimeInterval) -> Bool {
        guard readerSession >= 0 else { return false }
        let now = Date()
        // A turn gone quiet, as while it waits for an approval, is noticed
        // as soon as its work resumes.
        var working = Set(store.turns.keys).union(store.waiting.keys)
        // An OpenCode turn is kept by database and session.
        for key in working {
            if let mark = key.firstIndex(of: "#") { working.insert(String(key[..<mark])) }
        }
        var changed = false
        for (path, cursor) in cursors
        where working.contains(path) || now.timeIntervalSince(cursor.modified) < window {
            if cursor.provider == .opencode {
                // A database changes in place: its write-ahead log grows instead.
                if let modified = AgentOpenCodeReader.modified(path), modified <= cursor.modified { continue }
                if read(path, provider: cursor.provider) { changed = true }
                continue
            }
            var info = stat()
            let exists = stat(path, &info) == 0
            guard !exists || UInt64(max(0, info.st_size)) != cursor.offset
                    || UInt64(info.st_ino) != cursor.identity else { continue }
            if read(path, provider: cursor.provider) { changed = true }
        }
        return changed
    }

    /// Claude Code retries for minutes without a word while the Mac is
    /// offline, then gives up; until it does, its turn would count on.
    /// Only notes when the network went: the poller, which reads the logs
    /// first and waits while the island is away, ends the turns once the
    /// Mac stays offline. The main thread hears it too, and starts no limits
    /// check meanwhile. Runs on `queue`.
    private func watchNetwork() {
        guard network == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, self.readerSession >= 0 else { return }
            let online = path.status == .satisfied
            if online {
                self.offlineSince = nil
            } else if self.offlineSince == nil {
                self.offlineSince = (Date(), ProcessInfo.processInfo.systemUptime)
            }
            let session = self.readerSession
            DispatchQueue.main.async {
                guard self.running, self.session == session else { return }
                self.networkChanged(online: online)
            }
        }
        monitor.start(queue: queue)
        network = monitor
    }

    /// The logs whose turn waits on a shell command of its own; a subagent's
    /// commands are not counted. Runs on `queue`.
    private var runningCommands: Set<String> {
        Set(cursors.filter { !$0.value.state.runningCommands.isEmpty }.keys)
    }

    /// Ends the Claude turns whose process is gone. True when one was showing.
    @discardableResult
    private func closeEndedTurns(_ roots: [AgentLogRoot], atLaunch: Bool = false) -> Bool {
        guard store.showsClaudeTurn else { return false }
        let folders = roots.filter { $0.provider == .claude }
            .map { $0.url.deletingLastPathComponent().appending(path: "sessions", directoryHint: .isDirectory) }
        return store.closeEndedTurns(AgentSessionRegistry.read(folders), atLaunch: atLaunch)
    }

    /// True when the log had entries to apply, or was gone and took a
    /// working turn with it.
    @discardableResult
    private func read(_ path: String, provider: AgentProvider) -> Bool {
        guard let cancellation = readerCancellation, !cancellation.isCancelled else { return false }
        guard FileManager.default.fileExists(atPath: path) else {
            cursors[path] = nil
            return store.forget(file: path)
        }
        let cursor = cursors[path] ?? AgentLogCursor(path: path, provider: provider, roots: watchedRoots)
        if cursor.modified == .distantPast {
            var info = stat()
            if stat(path, &info) == 0 {
                cursor.modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                                        + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
            }
        }
        cursors[path] = cursor
        var changed = false
        let now = Date()
        let consume: (Data) -> Void = { [self] line in
            // Apply in log order while the chunk is alive instead of retaining
            // every parsed entry until a potentially multi-gigabyte file ends.
            let fallbackDate = cursor.modified != .distantPast ? cursor.modified : now
            let entries = provider.reader.parse(line, state: &cursor.state, now: fallbackDate)
            guard !entries.isEmpty else { return }
            changed = true
            let isSubagent = provider == .opencode && !cursor.state.parentSession.isEmpty
            let turnFile = provider == .opencode && !cursor.state.session.isEmpty ? "\(path)#\(cursor.state.session)" : path
            let tracksTurns = isSubagent ? false : cursor.tracksTurns
            let parent = isSubagent ? "\(path)#\(cursor.state.parentSession)"
                : cursor.parent ?? cursor.codexParent(among: cursors)
            let finished = store.apply(entries, file: turnFile, provider: provider, tracksTurns: tracksTurns,
                                       parent: parent, modified: cursor.modified, now: now)
            finished.forEach(report)
        }
        if provider.reader.readsFullHistoryFirst && cursor.offset == 0 {
            AgentLogReader.readCopilotHistory(cursor, shouldContinue: { !cancellation.isCancelled }, line: consume)
        } else {
            AgentLogReader.readAppended(cursor, since: now.addingTimeInterval(-Self.horizon),
                                        shouldContinue: { !cancellation.isCancelled }, line: consume)
        }
        return changed
    }

    private func watch(_ roots: [AgentLogRoot]) {
        let existing = roots.filter(\.exists)
        watchedRoots = existing
        lastRootCheck = Date()
        if watcher == nil {
            watcher = AgentLogWatcher(queue: queue) { [weak self] paths, rescan in
                self?.filesChanged(paths, rescan: rescan)
            }
        }
        var watchPaths = existing.map(\.url.path)
        if enabled.contains(.agy) {
            for dir in AgentAgyConversationReader.directories(home: home) {
                if FileManager.default.fileExists(atPath: dir) {
                    watchPaths.append(dir)
                }
            }
        }
        if watchPaths.isEmpty { watcher?.stop() } else { watcher?.start(watchPaths) }
    }

    private func filesChanged(_ paths: [String], rescan: Bool) {
        guard readerSession >= 0, !watchedRoots.isEmpty else { return }
        defer { syncPolling() }
        var changed = false
        if rescan {
            for file in AgentLogReader.discover(watchedRoots, since: Date().addingTimeInterval(-Self.horizon)) {
                if read(file.path, provider: file.provider) { changed = true }
            }
        } else {
            for path in Set(paths) where AgentLogReader.isLog(path) {
                let actualPath = path.hasSuffix("-wal") ? String(path.dropLast(4)) : path
                guard let root = watchedRoots.first(where: { $0.accepts(actualPath) }) else { continue }
                if read(actualPath, provider: root.provider) { changed = true }
            }
        }
        if enabled.contains(.agy) {
            let agyDirs = AgentAgyConversationReader.directories(home: home)
            let agyRoots = watchedRoots.filter { $0.provider == .agy }
            let triggersScan = rescan || paths.contains { path in
                agyDirs.contains(where: { path.hasPrefix($0) })
                    || agyRoots.contains(where: { path.hasPrefix($0.url.path) })
                    || (path.contains("/.gemini/antigravity") && path.contains("/brain/"))
            }
            if triggersScan {
                if agyConversationReader.scan(into: store, since: Date().addingTimeInterval(-Self.horizon), home: home,
                                              shouldContinue: { !(self.readerCancellation?.isCancelled ?? true) }) {
                    changed = true
                }
            }
        }
        // Saved tool output and lines with nothing to keep do not change the
        // summary or require a display update.
        guard changed else { return }
        checkLimits()
        schedulePublish()
    }

    /// Bursts of writes publish once.
    private func schedulePublish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        queue.asyncAfter(deadline: .now() + Self.publishDelay) { [self] in
            publishScheduled = false
            publish()
        }
    }

    private func tickTimer() {
        guard running else { return }
        syncPrices()
        refreshClaudeLimits()
        refreshAgyLimits()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            let now = Date()
            defer { syncPolling(now: now) }
            let before = inputs
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
            store.dropRecords(before: now.addingTimeInterval(-Self.horizon))
            // A log kept open through a long pause reports nothing when work
            // resumes; the day's logs are looked at less often than recent ones.
            var changed = pollOpenLogs(within: 86_400)
            // A folder that appears later, like a first Codex session, is
            // picked up without a restart.
            if now.timeIntervalSince(lastRootCheck) > 300 {
                let roots = AgentLogRoot.all(home: home, claudeProfile: readerClaudeProfile).filter { enabled.contains($0.provider) }
                if roots.filter(\.exists) != watchedRoots {
                    for file in AgentLogReader.discover(roots, since: now.addingTimeInterval(-Self.horizon)) {
                        if read(file.path, provider: file.provider) { changed = true }
                    }
                    watch(roots)
                }
                lastRootCheck = now
            }
            readClaudePlan()
            readClaudeApp(now: now)
            checkLimits()
            reportRenewals(now: now)
            if now.timeIntervalSince(lastSave) >= Self.saveInterval { saveProgress() }
            // Publish only when stored values or sliding time windows change.
            if changed || inputs != before || AgentUsageSummary.movesWithClock(published, now: now) {
                schedulePublish()
            }
        }
    }

    /// The stored state a snapshot is made from, compared across a tick.
    private struct Inputs: Equatable {
        let records: Int
        let turns: [String: AgentLiveSession]
        let limits: [AgentProvider: AgentLimits]
        let codexPlan: String?
        let claudePlan: AgentPlan?
        let claudeOrganization: String?
        let claudeIdentity: ClaudeAccountProfile.Identity?
        let claudeApp: [AgentClaudeAppUsage.Sample]
    }

    /// Runs on `queue`.
    private var inputs: Inputs {
        Inputs(records: store.records.count, turns: store.turns, limits: store.limits, codexPlan: store.codexPlan,
               claudePlan: claudePlan, claudeOrganization: claudeOrganization, claudeIdentity: claudeIdentity,
               claudeApp: claudeAppSamples)
    }

    /// Runs on `queue` and hands the finished snapshot to the main thread.
    private func publish() {
        let session = readerSession
        guard session >= 0 else { return }
        var plans: [AgentProvider: AgentPlan] = [:]
        if let claudePlan { plans[.claude] = claudePlan }
        if let codex = AgentPlans.codex(planType: store.codexPlan) { plans[.codex] = codex }
        let next = store.snapshot(plans: plans, providers: enabled, now: Date())
        published = next
        checkBudget(next)
        let checked = enabled.contains(.claude) ? claudeAppSamples.last(where: {
            claudeOrganization == nil || $0.organization == nil || $0.organization == claudeOrganization
        })?.date : nil
        let listed = AgentPricing.list.updated
        let prices = listed == AgentPriceList.empty.updated ? nil : listed
        let identity = claudeIdentity
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            if self.claudeAppChecked != checked { self.claudeAppChecked = checked }
            if self.claudeAccountIdentity != identity { self.claudeAccountIdentity = identity }
            if self.pricesUpdated != prices { self.pricesUpdated = prices }
            if self.snapshot != next { self.snapshot = next }
        }
    }

    // MARK: Alerts

    /// Filters by the person's choices on the main thread, where they live.
    private func report(_ event: AgentUsageEvent) {
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            switch event {
            case .finished(let provider, let duration, _, _, _):
                guard self.providers.contains(provider), let minimum = NotchAgentSupport.finishMinimum(),
                      duration >= minimum else { return }
            case .limitWarning(let provider, _), .limitReset(let provider, _):
                guard self.providers.contains(provider), NotchAgentSupport.limitThreshold() != nil else { return }
            case .budgetReached:
                guard NotchAgentSupport.dailyBudget() != nil else { return }
            case .needsApproval(let provider, _):
                guard self.providers.contains(provider) else { return }
            }
            self.events.send(event)
        }
    }

    /// Runs on `queue` whenever limits may have changed.
    private func checkLimits() {
        guard store.reportsTransitions else { return }
        let threshold = NotchAgentSupport.limitThreshold() ?? NotchAgentSupport.defaultLimitThreshold
        for (provider, limits) in store.limits {
            for window in AgentLimitSupport.crossings(previous: previousLimits[provider], current: limits,
                                                      threshold: threshold) {
                warned[window.id] = (provider, window)
                report(.limitWarning(provider: provider, window: window))
            }
        }
        // A banked reset renews a warned window before its time, which is
        // news now rather than at the renewal it replaced or, as a Claude
        // week keeps its renewal, at that one.
        for (id, entry) in warned {
            guard let reading = store.limits[entry.provider],
                  let window = reading.windows.first(where: { $0.id == id }), window.usedPercent < threshold,
                  AgentLimitSupport.renewed(entry.window, to: window, observedAt: reading.observedAt) else { continue }
            warned[id] = nil
            report(.limitReset(provider: entry.provider, window: window))
        }
        previousLimits = store.limits
    }

    /// A warned window that renews brings its agent back: worth a word.
    private func reportRenewals(now: Date) {
        for (id, entry) in warned {
            guard let resets = entry.window.resetsAt, resets <= now else { continue }
            warned[id] = nil
            report(.limitReset(provider: entry.provider, window: entry.window))
        }
    }

    private func checkBudget(_ snapshot: AgentUsageSnapshot) {
        guard store.reportsTransitions, let budget = NotchAgentSupport.dailyBudget() else { return }
        let today = Calendar.autoupdatingCurrent.startOfDay(for: snapshot.now)
        let spent = snapshot.usage(.today).total.cost
        guard spent >= budget, budgetDay != today else { return }
        budgetDay = today
        report(.budgetReached(spent: spent, budget: budget))
    }

    // MARK: Plans and limits

    /// The plan and visible identity come from Claude Code's profile. Other
    /// fields are discarded, and the identity stays out of the usage archive.
    private func readClaudePlan() {
        guard enabled.contains(.claude) else { return }
        let url = readerClaudeProfile.profileURL(home: home)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != claudeProfileModified || !readerClaudeProfile.isAvailable(home: home) else { return }
        claudeProfileModified = modified
        let reading = readerClaudeProfile.read(home: home)
        if reading.identity != claudeIdentity {
            claudeAccountLimits = nil
            store.clearLimits(.claude)
            previousLimits[.claude] = nil
            warned = warned.filter { $0.value.provider != .claude }
        }
        guard let identity = reading.identity else {
            claudePlan = nil
            claudeOrganization = nil
            claudeIdentity = nil
            claudeAccountLimits = nil
            store.clearLimits(.claude)
            return
        }
        claudeIdentity = identity
        claudeOrganization = identity.organization
        claudePlan = reading.plan
    }

    /// Reads the limits the Claude app saved when the file changes, and
    /// places them at `now` on every call, since a session ages out between
    /// saves. Runs on `queue`.
    private func readClaudeApp(now: Date) {
        guard enabled.contains(.claude) else {
            store.clearLimits(.claude)
            claudeAccountLimits = nil
            claudeAppModified = nil
            claudeAppSamples = []
            return
        }
        // Desktop history identifies an organization, not an individual
        // account. A chosen profile uses only its own CLI reading, even if
        // the default app happens to be signed in to the same organization.
        if !readerClaudeProfile.isDefault {
            claudeAppModified = nil
            claudeAppSamples = []
            if let reading = AgentClaudeServer.current(claudeAccountLimits, now: now) {
                store.setLimits(reading)
            } else {
                store.clearLimits(.claude)
            }
            return
        }
        let url = AgentClaudeAppUsage.historyURL(home: home)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if modified != claudeAppModified {
            claudeAppModified = modified
            claudeAppSamples = modified == nil ? []
                : (try? Data(contentsOf: url)).flatMap(AgentClaudeAppUsage.samples) ?? []
        }
        // Claude Code's own first request can place the session's start.
        let start = AgentClaudeAppUsage.sessionStart(store.records, samples: claudeAppSamples,
                                                     organization: claudeOrganization)
        let desktop = AgentClaudeAppUsage.limits(from: claudeAppSamples, now: now, sessionStart: start,
                                                 organization: claudeOrganization)
        let account = AgentClaudeServer.current(claudeAccountLimits, now: now)
        // One source while the account answers. The app's session renewal is
        // the latest the session can end, so trading places with the exact
        // one at each save the app makes would read as a new window and warn
        // again; newer wins once the account reading is old.
        let recent = account.flatMap { now.timeIntervalSince($0.observedAt) < AgentClaudeAppUsage.freshness ? $0 : nil }
        if let latest = recent ?? [desktop, account].compactMap({ $0 }).max(by: { $0.observedAt < $1.observedAt }) {
            store.setLimits(latest)
        } else {
            store.clearLimits(.claude)
        }
    }

    // Main thread. Every minute only while the page shows; failures back
    // off, and looking at the page does not bypass that.
    func refreshClaudeLimits(now: Date = Date(), pageShows: Bool = false) {
        guard claudeLimitsDue(at: now, pageShows: pageShows) else { return }
        claudeAccountAttempted = now
        claudeAccountChecking = true
        let request = AgentClaudeServer.Request()
        claudeAccountRequest = request
        let session = self.session
        let home = self.home
        let profile = claudeProfile
        claudeAccountQueue.async { [weak self] in
            let result: Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure>
            if let executable = AgentClaudeServer.executable(home: home, searchPath: ProcessInfo.processInfo.environment["PATH"]) {
                var environment = AgentCodexServer.environment(for: executable, searchPath: nil)
                environment["PATH"] = AgentClaudeServer.searchPath(after: environment["PATH"] ?? "", home: home)
                result = request.run(executable, home: home, environment: environment, profile: profile)
            } else { result = .failure(.missing) }
            DispatchQueue.main.async {
                guard let self, self.running, !self.paused, self.session == session,
                      self.claudeAccountRequest === request else { return }
                self.claudeAccountRequest = nil
                self.claudeAccountChecking = false
                switch result {
                case .failure(let failure): self.noteClaudeCheck(failure)
                case .success(let summary):
                    self.noteClaudeCheck(nil)
                    self.queue.async {
                        guard self.readerSession == session, self.enabled.contains(.claude) else { return }
                        self.readClaudePlan()
                        guard self.readerClaudeProfile == profile, self.claudeIdentity == summary.identity else { return }
                        self.claudeAccountLimits = summary.limits
                        self.readClaudeApp(now: Date())
                        self.checkLimits()
                        self.schedulePublish()
                    }
                }
            }
        }
    }

    private func cancelClaudeLimits() {
        guard let request = claudeAccountRequest else { return }
        request.cancel()
        claudeAccountRequest = nil
        claudeAccountChecking = false
        // Resume asks again instead of waiting out a cancelled check; with
        // none in flight, the wait after a failure still holds.
        claudeAccountAttempted = .distantPast
    }

    /// Never while the feature is off, asleep, offline or already checking,
    /// nor while nothing shows or alerts on the limits. Main thread.
    private func claudeLimitsDue(at now: Date, pageShows: Bool) -> Bool {
        guard running, !paused, online, providers.contains(.claude), claudeAccountRequest == nil,
              NotchAgentSupport.limitsInUse(pageShown: pageVisible || pageShows) else { return false }
        return now.timeIntervalSince(claudeAccountAttempted) >= AgentClaudeServer.interval(
            after: claudeAccountFailure, repeated: claudeAccountUnreachable, pageVisible: pageVisible)
    }

    /// Main thread.
    private func noteClaudeCheck(_ failure: AgentClaudeServer.Failure?) {
        claudeAccountFailure = failure
        claudeAccountUnreachable = failure == .unreachable ? claudeAccountUnreachable + 1 : 0
    }

    /// Back online, the checks start over from the shortest wait: those the
    /// network failed say nothing about how Claude Code is set up. Main thread.
    private func networkChanged(online: Bool) {
        guard online != self.online else { return }
        self.online = online
        if online { claudeAccountUnreachable = 0 }
    }

    // MARK: Antigravity

    func refreshAgyLimits(now: Date = Date(), pageShows: Bool = false, force: Bool = false) {
        guard force || agyLimitsDue(at: now, pageShows: pageShows) else { return }
        agyAttempted = now
        agyChecking = true
        let request = AgentAgyServer.Request()
        agyRequest = request
        let session = self.session
        let home = self.home
        agyAccountQueue.async { [weak self] in
            let result: Result<AgentLimits, AgentAgyServer.Failure>
            if let executable = AgentAgyServer.executable(home: home, searchPath: ProcessInfo.processInfo.environment["PATH"]) {
                result = request.run(executable: executable, home: home)
            } else {
                result = .failure(.missing)
            }
            DispatchQueue.main.async {
                guard let self, self.running, !self.paused, self.session == session,
                      self.agyRequest === request else { return }
                self.agyRequest = nil
                self.agyChecking = false
                switch result {
                case .failure(let failure):
                    self.agyFailure = failure
                case .success(let limits):
                    self.agyFailure = nil
                    self.queue.async {
                        guard self.readerSession == session, self.enabled.contains(.agy) else { return }
                        self.store.setLimits(limits)
                        self.checkLimits()
                        self.schedulePublish()
                    }
                }
            }
        }
    }

    private func cancelAgyLimits() {
        guard let request = agyRequest else { return }
        request.cancel()
        agyRequest = nil
        agyChecking = false
        agyAttempted = .distantPast
    }

    private func agyLimitsDue(at now: Date, pageShows: Bool) -> Bool {
        guard running, !paused, online, providers.contains(.agy), agyRequest == nil,
              NotchAgentSupport.limitsInUse(pageShown: pageVisible || pageShows) else { return false }
        let freshness = (pageVisible || pageShows) ? AgentAgyServer.freshness : AgentAgyServer.backgroundFreshness
        return now.timeIntervalSince(agyAttempted) >= freshness
    }

    // MARK: Prices

    /// The newer of the list inside the app and the last one downloaded.
    /// Runs on `queue`.
    private func loadPrices() {
        if shippedPrices == nil { shippedPrices = AgentPriceSource.bundled() }
        let cached = AgentPriceSource.cached()
        AgentPricing.install(AgentPriceList.newer(shippedPrices, cached?.list) ?? .empty)
        let saved = cached?.saved ?? .distantPast
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            self.pricesSaved = saved
            self.syncPrices()
        }
    }

    /// Looks for a newer price list at most once a day, and again a few hours
    /// after a failure. The last good list stays in use meanwhile.
    private func syncPrices() {
        guard running, NotchAgentSupport.updatesPrices(), !pricesInFlight, let saved = pricesSaved else { return }
        let now = Date()
        let wait = pricesFailed ? AgentPriceSource.retryInterval : AgentPriceSource.refreshInterval
        guard now.timeIntervalSince(saved) >= AgentPriceSource.refreshInterval,
              now.timeIntervalSince(pricesAttempted) >= wait else { return }
        pricesInFlight = true
        pricesAttempted = now
        let session = self.session
        AgentPriceSource.download { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.session == session else { return }
                self.pricesInFlight = false
                guard let result else {
                    self.pricesFailed = true
                    return
                }
                let (data, list) = result
                self.pricesFailed = false
                self.pricesSaved = Date()
                self.queue.async {
                    AgentPriceSource.save(data)
                    guard self.readerSession == session,
                          AgentPricing.install(AgentPriceList.newer(self.shippedPrices, list) ?? list) else { return }
                    self.store.reprice()
                    self.publish()
                }
            }
        }
    }
}
