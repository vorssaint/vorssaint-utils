// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
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
    /// Whether the Mac has a network, as the reading queue last heard.
    private var online = true
    /// The AI page is on the island, which asks Claude Code more often.
    private var pageVisible = false
    /// Seats the person added stand in for the usual profile, which is not
    /// checked meanwhile.
    private var claudeSeatsInUse = false
    private var frontmostObserver: NSObjectProtocol?

    // Confined to `queue`.
    private var readerSession = -1
    private var readerCancellation: Cancellation?
    private var enabled: Set<AgentProvider> = []
    private var store = AgentUsageStore()
    /// Every day's spending, kept after its logs are gone. Loaded on first use.
    private lazy var ledger = AgentUsageLedger()
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
    private var claudeProfileModified: Date?
    private var claudeAppModified: Date?
    private var claudeAppSamples: [AgentClaudeAppUsage.Sample] = []
    private var claudeAccountLimits: AgentLimits?
    /// Watches the profile where every running Claude Code saves the
    /// account's usage, while the limits are in use.
    private var claudeCacheWatcher: AgentFileWatcher?
    /// The seats as the seat service last reported them.
    private var claudeSeats: [ClaudeSeat] = []
    private var claudeSeatsActive = false
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
    /// When the sessions waiting on the person are told about.
    private var attentionSchedule = AgentAttentionSchedule()
    /// What each Claude session's record says, by its log, from the last read.
    private var claudeRecords: [String: AgentSessionRegistry.Status] = [:]
    /// The app in front, as the main thread last heard.
    private var frontmost: (pid: Int32, bundleID: String?)?
    /// The most turns open at once since none was, so the last of several
    /// finishing is heard as all of them done.
    private var peakTurns = 0

    private init() {}

    func syncWithPreferences() {
        CodexProfileLimitsService.shared.synchronize()
        guard NotchAgentSupport.isEnabled() else { stop(); return }
        let wanted = NotchAgentSupport.providers()
        // An agent turned off is no longer read at all, and one turned on is
        // read from its start: both take a fresh reading, which would not
        // resume progress saved for the old set, so it goes at once. Codex
        // accounts keep their checks: they read no log.
        if running, wanted != providers { stop(keepingProgress: false, pausingAccounts: false) }
        if !running {
            running = true
            session += 1
            cancellation = Cancellation()
            providers = wanted
            start(session: session, providers: Set(wanted), cancellation: cancellation)
        } else if paused {
            resume()
        }
        syncPrices()
        // After the reading starts, so the seats reach its first snapshot.
        ClaudeSeatLimitsService.shared.synchronize()
        syncClaudeCache()
        refreshClaudeLimits()
    }

    /// Stops reading while the island is away, as with the display asleep or
    /// the Mac locked, and keeps what was read: reading every log again on the
    /// way back costs far more than the pause saves.
    func pause() {
        CodexProfileLimitsService.shared.pause()
        ClaudeSeatLimitsService.shared.pause()
        // A page torn down with the island never reports leaving, so the
        // minute cadence would outlive it.
        pageVisible = false
        guard running, !paused else { return }
        paused = true
        cancelClaudeLimits()
        timer?.invalidate()
        timer = nil
        queue.async { [self] in
            poller?.cancel()
            poller = nil
            watcher?.stop()
            claudeCacheWatcher?.stop()
            saveProgress()
        }
    }

    /// Reads what the agents wrote meanwhile, from where each log stopped.
    private func resume() {
        paused = false
        startTimer()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            // What came due while the island was away is told once, a moment
            // after it comes back.
            attentionSchedule.hold(until: Date().addingTimeInterval(AgentAttentionPolicy.resumeSettle))
            watch(AgentLogRoot.all(home: home).filter { enabled.contains($0.provider) })
            filesChanged([], rescan: true)
            startPolling()
            // Time went by meanwhile: a window or the day may have moved on.
            schedulePublish()
        }
    }

    func stop(keepingProgress keeps: Bool = true, pausingAccounts: Bool = true) {
        if pausingAccounts {
            CodexProfileLimitsService.shared.pause()
            ClaudeSeatLimitsService.shared.pause()
        }
        pageVisible = false
        // A first read still going stops at its next chunk, so the wait
        // below is short.
        if running { cancellation.cancel() }
        settleArchive(keeping: keeps && NotchAgentSupport.isEnabled())
        guard running else { return }
        running = false
        cancelClaudeLimits()
        claudeAccountAttempted = .distantPast
        claudeAccountFailure = nil
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
        if let frontmostObserver { NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver) }
        frontmostObserver = nil
        queue.async { [self] in
            readerSession = -1
            readerCancellation = nil
            poller?.cancel()
            poller = nil
            watcher?.stop()
            watcher = nil
            claudeCacheWatcher?.stop()
            claudeCacheWatcher = nil
            watchedRoots = []
            network?.cancel()
            network = nil
            offlineSince = nil
            store = AgentUsageStore()
            cursors.removeAll()
            published = AgentUsageSnapshot()
            previousLimits.removeAll()
            warned.removeAll()
            budgetDay = nil
            claudePlan = nil
            claudeOrganization = nil
            claudeProfileModified = nil
            claudeAppModified = nil
            claudeAppSamples = []
            claudeAccountLimits = nil
            claudeSeats = []
            claudeSeatsActive = false
            savedMark = nil
            lastSave = .distantPast
            attentionSchedule = AgentAttentionSchedule()
            claudeRecords = [:]
            frontmost = nil
            peakTurns = 0
        }
    }

    /// The person looked at a waiting session, as by tapping its notice:
    /// no more reminders for that wait. Main thread.
    func noteSeen(_ target: AgentSessionTarget) {
        guard running else { return }
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            attentionSchedule.markSeen(file: target.file, in: store.attention)
        }
    }

    /// Hands the app in front to the queue, where a waiting session's app
    /// in front holds its reminder back. Main thread.
    private func observeFrontmost() {
        guard frontmostObserver == nil else { return }
        let note = { [weak self] (app: NSRunningApplication?) in
            guard let self else { return }
            let front = app.map { (pid: $0.processIdentifier, bundleID: $0.bundleIdentifier) }
            self.queue.async { self.frontmost = front }
        }
        note(NSWorkspace.shared.frontmostApplication)
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
            note(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
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
        if !preview {
            pageVisible = true
            ClaudeSeatLimitsService.shared.pageDidAppear()
        }
        guard running else { return }
        if !preview { syncClaudeCache() }
        refreshClaudeLimits(pageShows: true)
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
        ClaudeSeatLimitsService.shared.pageDidDisappear()
        syncClaudeCache()
    }

    /// The Claude seats' identities, limits and checks, from the seat
    /// service. Main thread.
    func noteClaudeSeats(_ seats: [ClaudeSeat]) {
        let inUse = !seats.isEmpty
        if inUse != claudeSeatsInUse {
            claudeSeatsInUse = inUse
            if inUse { cancelClaudeLimits() }
        }
        guard running else { return }
        queue.async { [self] in
            guard readerSession >= 0, seats != claudeSeats else { return }
            claudeSeats = seats
            claudeSeatsActive = inUse
            publish()
        }
    }

    /// A seat's limit alert, filtered as the account's are. Main thread.
    func reportSeat(_ event: AgentUsageEvent) {
        guard running, providers.contains(.claude) else { return }
        if case .seatLimitWarning = event { AppSoundService.shared.play(.agentLimitWarning) }
        if case .seatLimitReset = event { AppSoundService.shared.play(.agentLimitReset) }
        guard NotchAgentSupport.limitThreshold() != nil else { return }
        events.send(event)
    }

    // MARK: Reading

    private func startTimer() {
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.tickTimer() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func start(session: Int, providers: Set<AgentProvider>, cancellation: Cancellation) {
        startTimer()
        observeFrontmost()
        queue.async { [self] in
            readerSession = session
            readerCancellation = cancellation
            enabled = providers
            store = AgentUsageStore()
            cursors.removeAll()
            // Prices first, so the first read is already priced.
            loadPrices()
            // Keep the loading state until all initial history has been read.
            let horizon = Date().addingTimeInterval(-Self.horizon)
            let roots = AgentLogRoot.all(home: home).filter { providers.contains($0.provider) }
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
            guard !cancellation.isCancelled else { return }
            let now = Date()
            // A turn left open by a crash would otherwise stay working.
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
            closeEndedTurns(roots, atLaunch: true)
            // The account Claude Code uses picks the Claude app's readings.
            readClaudePlan()
            readClaudeApp(now: now)
            store.reportsTransitions = true
            store.turnStarted = { [weak self] (provider: AgentProvider) in self?.reportStart(provider) }
            store.turnInterrupted = { [weak self] (provider: AgentProvider) in self?.reportInterrupt(provider) }
            // A session found waiting at launch is told once the app settles.
            attentionSchedule.hold(until: now.addingTimeInterval(AgentAttentionPolicy.resumeSettle))
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
        ledger.save()
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
            let closed = self.closeEndedTurns(self.watchedRoots)
            self.checkAttention(now: Date())
            guard closed || read || stopped else { return }
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
        let wanted = !store.turns.isEmpty || !store.waiting.isEmpty || !store.attention.isEmpty
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

    /// Ends the Claude turns whose process is gone, and takes what each
    /// session's record says it waits on. True when a turn was showing.
    @discardableResult
    private func closeEndedTurns(_ roots: [AgentLogRoot], atLaunch: Bool = false) -> Bool {
        guard store.showsClaudeTurn || store.awaitsClaude else { return false }
        let folders = roots.filter { $0.provider == .claude }
            .map { $0.url.deletingLastPathComponent().appending(path: "sessions", directoryHint: .isDirectory) }
        let registry = AgentSessionRegistry.read(folders)
        let closed = store.closeEndedTurns(registry, atLaunch: atLaunch)
        var logs: [String: String] = [:]
        for cursor in cursors.values where cursor.provider == .claude && cursor.parent == nil {
            logs[AgentUsageStore.session(of: cursor.path)] = cursor.path
        }
        store.applyClaudeStatuses(registry, files: logs, now: Date())
        claudeRecords = [:]
        for (session, status) in registry.statuses { if let file = logs[session] { claudeRecords[file] = status } }
        return closed
    }

    /// The logs whose turn waits on a tool call that may need an approval:
    /// Claude's calls other than commands, and Codex's unless it never asks.
    /// Runs on `queue`.
    private var pendingCalls: Set<String> {
        Set(cursors.filter { _, cursor in
            guard cursor.tracksTurns else { return false }
            switch cursor.provider {
            case .claude: return !cursor.state.pendingTools.isEmpty
            case .codex: return !cursor.state.codexPendingCalls.isEmpty && cursor.state.codexApprovalPolicy != "never"
            default: return false
            }
        }.keys)
    }

    /// What a tap on a wait's notice brings forward. Runs on `queue`.
    private func target(for wait: AgentAttention) -> AgentSessionTarget {
        var target = AgentSessionTarget(file: wait.file)
        target.pid = wait.provider == .claude ? claudeRecords[wait.file]?.pid : nil
        if wait.place == .app {
            switch wait.provider {
            case .claude: target.bundleID = AgentClaudeAppUsage.bundleIdentifier
            case .codex: target.bundleID = AgentCodexServer.appIdentifiers.first
            default: break
            }
        }
        return target
    }

    /// The waits whose app is in front, where the person can already see
    /// them. A terminal counts whichever of its tabs is showing. Runs on `queue`.
    private func focusedWaits() -> Set<String> {
        guard let frontmost else { return [] }
        var files = Set<String>()
        for wait in store.attention.values {
            let target = target(for: wait)
            if let pid = target.pid {
                if AgentProcessTree.ancestors(of: pid).contains(frontmost.pid) { files.insert(wait.file) }
            } else if let bundleID = target.bundleID, bundleID == frontmost.bundleID {
                files.insert(wait.file)
            }
        }
        return files
    }

    /// Tells the sessions that have waited on the person long enough, as
    /// one notice. Runs on `queue`.
    private func checkAttention(now: Date) {
        guard readerSession >= 0, store.reportsTransitions else { return }
        let inferred = NotchAgentSupport.inputInferred()
        store.inferQuietWaits(now: now, pending: inferred ? pendingCalls : [],
                              recorded: Set(claudeRecords.keys))
        guard !store.attention.isEmpty else { return }
        let due = attentionSchedule.due(store.attention, now: now, delay: NotchAgentSupport.inputDelay(),
                                        repeats: NotchAgentSupport.inputRepeats(),
                                        interruptions: NotchAgentSupport.interruptAlert(), inferred: inferred,
                                        focused: focusedWaits())
        guard let first = due.first else { return }
        report(.needsInput(AgentAttentionNotice(
            provider: first.provider, project: first.project, cause: first.cause, inferred: first.inferred,
            waited: max(0, now.timeIntervalSince(first.since)), place: first.place,
            others: due.dropFirst().map(\.project), reminder: attentionSchedule.isReminder(first),
            target: target(for: first))))
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
        let cursor = cursors[path] ?? AgentLogCursor(path: path, provider: provider)
        cursors[path] = cursor
        var changed = false
        let now = Date()
        let consume: (Data) -> Void = { [self] line in
            // Apply in log order while the chunk is alive instead of retaining
            // every parsed entry until a potentially multi-gigabyte file ends.
            let entries = provider.reader.parse(line, state: &cursor.state, now: now)
            guard !entries.isEmpty else { return }
            changed = true
            let isSubagent = provider == .opencode && !cursor.state.parentSession.isEmpty
            let turnFile = provider == .opencode && !cursor.state.session.isEmpty ? "\(path)#\(cursor.state.session)" : path
            let tracksTurns = isSubagent ? false : cursor.tracksTurns
            let parent = isSubagent ? "\(path)#\(cursor.state.parentSession)"
                : cursor.parent ?? cursor.codexParent(among: cursors)
            let finished = store.apply(entries, file: turnFile, provider: provider, tracksTurns: tracksTurns,
                                       parent: parent, modified: cursor.modified, now: now)
            peakTurns = max(peakTurns, store.turns.count)
            // The last of several turns that ran together.
            let allDone = store.turns.isEmpty && peakTurns >= 2
            if store.turns.isEmpty { peakTurns = 0 }
            for event in finished { report(event, allDone: allDone) }
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
        if existing.isEmpty { watcher?.stop() } else { watcher?.start(existing.map(\.url.path)) }
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
        syncClaudeCache()
        refreshClaudeLimits()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            let now = Date()
            defer { syncPolling(now: now) }
            let before = inputs
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
            if store.turns.isEmpty { peakTurns = 0 }
            checkAttention(now: now)
            store.dropRecords(before: now.addingTimeInterval(-Self.horizon))
            // A log kept open through a long pause reports nothing when work
            // resumes; the day's logs are looked at less often than recent ones.
            var changed = pollOpenLogs(within: 86_400)
            // A folder that appears later, like a first Codex session, is
            // picked up without a restart.
            if now.timeIntervalSince(lastRootCheck) > 300 {
                let roots = AgentLogRoot.all(home: home).filter { enabled.contains($0.provider) }
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
        let claudeApp: [AgentClaudeAppUsage.Sample]
    }

    /// Runs on `queue`.
    private var inputs: Inputs {
        Inputs(records: store.records.count, turns: store.turns, limits: store.limits, codexPlan: store.codexPlan,
               claudePlan: claudePlan, claudeOrganization: claudeOrganization, claudeApp: claudeAppSamples)
    }

    /// Runs on `queue` and hands the finished snapshot to the main thread.
    private func publish() {
        let session = readerSession
        guard session >= 0 else { return }
        var plans: [AgentProvider: AgentPlan] = [:]
        if let claudePlan { plans[.claude] = claudePlan }
        if let codex = AgentPlans.codex(planType: store.codexPlan) { plans[.codex] = codex }
        var next = store.snapshot(plans: plans, providers: enabled, now: Date())
        attachClaudeSeats(&next)
        ledger.merge(next)
        next.lifetime = ledger.usage(providers: enabled)
        published = next
        checkBudget(next)
        let checked = enabled.contains(.claude) ? claudeAppSamples.last(where: {
            claudeOrganization == nil || $0.organization == nil || $0.organization == claudeOrganization
        })?.date : nil
        let listed = AgentPricing.list.updated
        let prices = listed == AgentPriceList.empty.updated ? nil : listed
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            if self.claudeAppChecked != checked { self.claudeAppChecked = checked }
            if self.pricesUpdated != prices { self.pricesUpdated = prices }
            if self.snapshot != next { self.snapshot = next }
        }
    }

    /// Each seat's limits, as current at the snapshot's time, and the
    /// Claude app's work under it: this session's value, this month's and
    /// the sessions running now. The seat the app is signed in to stands for
    /// Claude wherever one reading shows. Runs on `queue`.
    private func attachClaudeSeats(_ snapshot: inout AgentUsageSnapshot) {
        guard claudeSeatsActive, enabled.contains(.claude) else { return }
        let now = snapshot.now
        let index = ClaudeAppAccounts.SessionIndex.shared
        index.refresh(for: Set(claudeSeats.compactMap(\.owner)))
        var seatOf: [ClaudeAppAccounts.Owner: String] = [:]
        for seat in claudeSeats { if let owner = seat.owner, seatOf[owner] == nil { seatOf[owner] = seat.id } }
        let calendar = Calendar.autoupdatingCurrent
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let recent = now.addingTimeInterval(-AgentUsageSummary.blockHistory)
        let earliest = min(month, recent)
        var monthly: [String: Double] = [:]
        var latest: [String: [AgentUsageRecord]] = [:]
        for record in store.records where record.provider == .claude && record.claudeApp && record.date >= earliest {
            guard let owner = index.owner(of: record.session), let seat = seatOf[owner] else { continue }
            if record.date >= month { monthly[seat, default: 0] += record.cost ?? 0 }
            if record.date > recent, record.date <= now { latest[seat, default: []].append(record) }
        }
        snapshot.claudeSeats = claudeSeats.map { seat in
            var seat = seat
            seat.limits = AgentClaudeServer.current(seat.limits, now: now)
            seat.monthValue = monthly[seat.id] ?? 0
            seat.sessionValue = AgentUsageSummary.currentBlock(latest[seat.id] ?? [], now: now,
                                                               after: seat.limits?.sessionStart(at: now))?.totals.cost
            return seat
        }
        for session in snapshot.live where session.provider == .claude && session.place == .app {
            if let owner = index.owner(of: session.id), let seat = seatOf[owner] { snapshot.claudeLiveSeats[session.id] = seat }
        }
        let active = snapshot.activeClaudeSeat
        snapshot.limits[.claude] = active?.limits
        if let plan = active?.plan { snapshot.plans[.claude] = AgentPlan(name: plan, monthlyPrice: nil) }
        if snapshot.limits[.claude] != nil { snapshot.seen.insert(.claude) }
    }

    // MARK: Alerts

    /// A turn opening is only ever heard: the working strip already shows it.
    private func reportStart(_ provider: AgentProvider) {
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session, self.providers.contains(provider) else { return }
            AppSoundService.shared.play(.agentStarted, context: self.soundContext(provider))
        }
    }

    /// The agent a sound is about, and where its sessions run when the live
    /// ones all agree: a turn's place is often learned after it opens, and
    /// a finished one may already be gone, so it is a hint.
    private func soundContext(_ provider: AgentProvider) -> AppSoundContext {
        let places = snapshot.live.filter { $0.provider == provider }.map(\.place)
        let place = places.first.flatMap { first in places.allSatisfy { $0 == first } ? first : nil }
        return AppSoundContext(provider: provider, place: place)
    }

    /// A turn the person interrupted, or an error stopped, is only heard.
    private func reportInterrupt(_ provider: AgentProvider) {
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session, self.providers.contains(provider) else { return }
            AppSoundService.shared.play(.agentInterrupted, context: self.soundContext(provider))
        }
    }

    /// Filters by the person's choices on the main thread, where they live.
    /// Each event's sound has choices of its own, apart from the notice.
    /// `allDone` marks the last of several turns that ran together.
    private func report(_ event: AgentUsageEvent, allDone: Bool = false) {
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            switch event {
            case .finished(let provider, let duration, _, _, _):
                guard self.providers.contains(provider) else { return }
                AppSoundService.shared.play(allDone && AppSoundSupport.isOn(.agentsAllDone) ? .agentsAllDone : .agentFinished,
                                            context: self.soundContext(provider))
                guard let minimum = NotchAgentSupport.finishMinimum(), duration >= minimum else { return }
            case .limitWarning(let provider, _), .limitReset(let provider, _):
                guard self.providers.contains(provider) else { return }
                if case .limitWarning = event { AppSoundService.shared.play(.agentLimitWarning) }
                else { AppSoundService.shared.play(.agentLimitReset) }
                guard NotchAgentSupport.limitThreshold() != nil else { return }
            case .seatLimitWarning, .seatLimitReset:
                // The seats report through `reportSeat`, which plays their sounds.
                guard self.providers.contains(.claude), NotchAgentSupport.limitThreshold() != nil else { return }
            case .budgetReached:
                AppSoundService.shared.play(.agentBudgetReached)
                guard NotchAgentSupport.dailyBudget() != nil else { return }
            case .needsInput(let notice):
                guard self.providers.contains(notice.provider) else { return }
                AppSoundService.shared.play(.agentNeedsInput, context: self.soundContext(notice.provider))
                guard notice.cause == .interrupted ? NotchAgentSupport.interruptAlert()
                        : NotchAgentSupport.inputAlert() else { return }
            }
            self.events.send(event)
        }
    }

    /// Runs on `queue` whenever limits may have changed.
    private func checkLimits() {
        guard store.reportsTransitions else { return }
        let threshold = NotchAgentSupport.limitThreshold() ?? NotchAgentSupport.defaultLimitThreshold
        // The seats warn for themselves, each under its own email.
        for (provider, limits) in store.limits where !(provider == .claude && claudeSeatsActive) {
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

    /// The plan comes from the account profile Claude Code caches; nothing
    /// else in that file is kept.
    private func readClaudePlan() {
        guard enabled.contains(.claude) else { return }
        let url = home.appending(path: ".claude.json")
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != claudeProfileModified else { return }
        claudeProfileModified = modified
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any] else {
            claudePlan = nil
            claudeOrganization = nil
            claudeAccountLimits = nil
            store.clearLimits(.claude)
            return
        }
        let organization = account["organizationUuid"] as? String
        if organization != claudeOrganization {
            claudeAccountLimits = nil
            store.clearLimits(.claude)
        }
        claudeOrganization = organization
        claudePlan = AgentPlans.claude(organizationType: account["organizationType"] as? String,
                                       rateLimitTier: account["organizationRateLimitTier"] as? String
                                        ?? account["userRateLimitTier"] as? String)
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
        let url = AgentClaudeAppUsage.historyURL(home: home)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if modified != claudeAppModified {
            claudeAppModified = modified
            claudeAppSamples = modified == nil ? []
                : (try? Data(contentsOf: url)).flatMap(AgentClaudeAppUsage.samples) ?? []
        }
        // Claude Code's own first request can place the session's start,
        // unless an API key pays for it and the plan never sees it.
        let start = AgentClaudeBilling.usesAPI(home: home) ? nil
            : AgentClaudeAppUsage.sessionStart(store.records, samples: claudeAppSamples, organization: claudeOrganization)
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
        claudeAccountQueue.async { [weak self] in
            let result: Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure>
            if let executable = AgentClaudeServer.executable(home: home, searchPath: ProcessInfo.processInfo.environment["PATH"]) {
                var environment = AgentCodexServer.environment(for: executable, searchPath: nil)
                environment["PATH"] = AgentClaudeServer.searchPath(after: environment["PATH"] ?? "", home: home)
                result = request.run(executable, home: home, environment: environment)
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
                        // A copy a Claude Code session saved meanwhile may be newer.
                        guard self.claudeOrganization == summary.organization,
                              summary.limits.observedAt >= self.claudeAccountLimits?.observedAt ?? .distantPast
                        else { return }
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
        guard running, !paused, online, providers.contains(.claude), !claudeSeatsInUse, claudeAccountRequest == nil,
              NotchLimitVisibility.isChecked(.claude),
              NotchAgentSupport.limitsInUse(pageShown: pageVisible || pageShows) else { return false }
        // The resting island shows the plan's limits all day, as the page does.
        return now.timeIntervalSince(claudeAccountAttempted) >= AgentClaudeServer.interval(
            after: claudeAccountFailure, repeated: claudeAccountUnreachable,
            pageVisible: NotchAgentSupport.limitsOnScreen(pageShown: pageVisible || pageShows))
    }

    /// Main thread.
    private func noteClaudeCheck(_ failure: AgentClaudeServer.Failure?) {
        claudeAccountFailure = failure
        claudeAccountUnreachable = failure == .unreachable ? claudeAccountUnreachable + 1 : 0
    }

    /// A copy of the account's usage that a Claude Code session fetched
    /// counts as a check that answered then, so Claude Code is started only
    /// once that copy has aged as a check's would. Main thread.
    private func noteClaudeCache(_ fetched: Date) {
        guard fetched > claudeAccountAttempted else { return }
        claudeAccountAttempted = fetched
        noteClaudeCheck(nil)
    }

    /// Watches Claude Code's profile only while the feature reads Claude and
    /// something uses the limits; pause, sleep and stop end it. Main thread.
    private func syncClaudeCache() {
        let wanted = running && !paused && providers.contains(.claude) && NotchLimitVisibility.isChecked(.claude)
            && NotchAgentSupport.limitsInUse(pageShown: pageVisible)
        queue.async { [self] in
            guard wanted, readerSession >= 0, enabled.contains(.claude) else {
                claudeCacheWatcher?.stop()
                claudeCacheWatcher = nil
                return
            }
            guard claudeCacheWatcher == nil else { return }
            let watcher = AgentFileWatcher(home.appending(path: ".claude.json"), queue: queue) { [weak self] in
                self?.readClaudeCache(now: Date())
            }
            watcher.start()
            claudeCacheWatcher = watcher
            readClaudeCache(now: Date())
        }
    }

    /// Reads the account usage a Claude Code session saved in its profile.
    /// Runs on `queue`.
    private func readClaudeCache(now: Date) {
        guard readerSession >= 0, enabled.contains(.claude), claudeCacheWatcher != nil else { return }
        readClaudePlan()
        guard let fetched = takeClaudeCache(AgentClaudeServer.cache(home: home, now: now), now: now) else { return }
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            self.noteClaudeCache(fetched)
        }
    }

    /// Shows a saved copy that belongs to the organization in use and is
    /// newer than the reading in hand, and says when it was fetched; nil
    /// when it is left out. Runs on `queue`.
    private func takeClaudeCache(_ cache: AgentClaudeServer.Cache?, now: Date) -> Date? {
        guard let cache, cache.organization == claudeOrganization,
              cache.limits.observedAt > claudeAccountLimits?.observedAt ?? .distantPast else { return nil }
        claudeAccountLimits = cache.limits
        readClaudeApp(now: now)
        checkLimits()
        schedulePublish()
        return cache.limits.observedAt
    }

    /// Back online, the checks start over from the shortest wait: those the
    /// network failed say nothing about how Claude Code is set up. Main thread.
    private func networkChanged(online: Bool) {
        guard online != self.online else { return }
        self.online = online
        if online { claudeAccountUnreachable = 0 }
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
