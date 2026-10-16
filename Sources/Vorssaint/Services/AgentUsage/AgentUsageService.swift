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
/// database is read again at each launch. The one request it makes fetches
/// the public price list, when the person keeps prices up to date.
///
/// Reading happens on a private queue; the main thread and that queue hand
/// work to each other asynchronously, except that a stop waits for progress
/// to be saved. The queue never waits for the main thread.
final class AgentUsageService: ObservableObject {
    static let shared = AgentUsageService()

    @Published private(set) var snapshot = AgentUsageSnapshot()
    /// When the Claude app last saved the plan's limits; nil when it never has.
    @Published private(set) var claudeAppChecked: Date?
    /// The day of the price list in use.
    @Published private(set) var pricesUpdated: Date?
    /// Meter accounts that stopped for an answer. Cursor reads it from the
    /// transcript. Claude reads it from the session record, which is updated
    /// while the question is on screen and before the transcript catches up.
    @Published private(set) var meterWaiting: Set<AgentProvider> = []
    /// Short reason each waiting account is showing, when one is known.
    @Published private(set) var meterWaitingDetail: [AgentProvider: String] = [:]
    /// Meter accounts whose latest line is a finished reply. The ring stays up and does not spin.
    @Published private(set) var meterSettled: Set<AgentProvider> = []
    /// Claude, Codex and Cursor with a live CLI session; rings and live UI stay hidden until then.
    @Published private(set) var meterSignedIn: Set<AgentProvider> = []
    /// Enabled meter assistants that still need `login` in the terminal.
    @Published private(set) var meterSignInAccounts: [AgentAccount] = []
    let events = PassthroughSubject<AgentUsageEvent, Never>()

    /// The history the island can show: thirteen weeks for the activity map.
    static let horizon = TimeInterval(AgentUsageSnapshot.dayCount) * 86_400
    private static let tick: TimeInterval = 30
    /// File events report a written file only once it closes, and some
    /// agents keep their log open for the whole session: logs written in the
    /// last half hour, or holding a turn, are checked this often instead.
    /// Short, so a Cursor turn shows on the island as it starts planning.
    private static let poll: TimeInterval = 0.35
    private static let pollWindow: TimeInterval = 30 * 60
    /// Coalesce a live log's bursts into one history and display update.
    private static let publishDelay: TimeInterval = 1
    /// How often progress is saved while agents write, besides on quit and
    /// pause; a launch after a crash reads again only what came after.
    private static let saveInterval: TimeInterval = 5 * 60

    private let queue = DispatchQueue(label: "com.vorssaint.agent-usage", qos: .userInitiated, autoreleaseFrequency: .workItem)
    /// Claude session ids currently stopped for input.
    private var claudeAsked: Set<String> = []
    /// `waitingFor` labels from Claude session records, by session id.
    private var claudeAskedReasons: [String: String] = [:]
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

    // Confined to `queue`.
    private var readerSession = -1
    private var readerCancellation: Cancellation?
    private var enabled: Set<AgentProvider> = []
    private var store = AgentUsageStore()
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
    /// Plan name Cursor's usage summary reported, when it did.
    private var cursorPlan: AgentPlan?
    private var cursorUsageChecked = Date.distantPast
    private var cursorUsageInFlight = false
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
    private var lastMeterSignInCheck = Date.distantPast

    private init() {}

    /// Re-reads CLI auth for the assistant meter. Safe from any thread.
    func refreshMeterSignIn() {
        let enabled = Set(NotchAgentSupport.providers())
        DispatchQueue.global(qos: .utility).async { [home] in
            let result = AgentMeterAccounts.refresh(enabled: enabled, home: home)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                if self.meterSignedIn != result.signedIn { self.meterSignedIn = result.signedIn }
                if self.meterSignInAccounts != result.needSignIn { self.meterSignInAccounts = result.needSignIn }
            }
        }
    }

    func syncWithPreferences() {
        guard NotchAgentSupport.isEnabled() else { stop(); return }
        let wanted = NotchAgentSupport.providers()
        // An agent turned off is no longer read at all, and one turned on is
        // read from its start: both take a fresh reading, which would not
        // resume progress saved for the old set, so it goes at once.
        if running, wanted != providers { stop(keepingProgress: false) }
        if !running {
            running = true
            session += 1
            cancellation = Cancellation()
            providers = wanted
            start(session: session, providers: Set(wanted), cancellation: cancellation)
            refreshMeterSignIn()
        } else if paused {
            resume()
        }
        syncPrices()
    }

    /// Stops reading while the island is away, as with the display asleep or
    /// the Mac locked, and keeps what was read: reading every log again on the
    /// way back costs far more than the pause saves.
    func pause() {
        guard running, !paused else { return }
        paused = true
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
            watch(AgentLogRoot.all(home: home).filter { enabled.contains($0.provider) })
            filesChanged([], rescan: true)
            startPolling()
            // Time went by meanwhile: a window or the day may have moved on.
            schedulePublish()
        }
    }

    func stop(keepingProgress keeps: Bool = true) {
        // A first read still going stops at its next chunk, so the wait
        // below is short.
        if running { cancellation.cancel() }
        settleArchive(keeping: keeps && NotchAgentSupport.isEnabled())
        guard running else { return }
        running = false
        paused = false
        session += 1
        timer?.invalidate()
        timer = nil
        providers = []
        pricesInFlight = false
        pricesSaved = nil
        snapshot = AgentUsageSnapshot()
        claudeAppChecked = nil
        meterWaiting = []
        meterWaitingDetail = [:]
        meterSettled = []
        meterSignedIn = []
        meterSignInAccounts = []
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
            claudeAsked = []
            claudeAskedReasons = [:]
            cursorPlan = nil
            cursorUsageChecked = .distantPast
            cursorUsageInFlight = false
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

    /// Opening the page shows the latest limits the Claude app saved, and asks
    /// Cursor for a fresh reading when the app session is present.
    func pageDidAppear() {
        guard running else { return }
        refreshMeterSignIn()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            readClaudeApp(now: Date())
            readCursorAccount(force: true)
            checkLimits()
            publish()
        }
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
        let recentCutoff = Date().addingTimeInterval(-30 * 60)
        func logModified(_ path: String) -> Date {
            var info = stat()
            guard stat(path, &info) == 0 else { return .distantPast }
            return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                        + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        }
        queue.async { [self] in
            readerSession = session
            readerCancellation = cancellation
            enabled = providers
            store = AgentUsageStore()
            cursors.removeAll()
            // Prices first, so the first read is already priced.
            loadPrices()
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
            // Recent Cursor transcripts first. The island can show a turn that
            // is already running before the older logs, which are much larger,
            // have been read. Discovery order is kept inside each group.
            let cutoff = recentCutoff
            var cursorNow: [(path: String, provider: AgentProvider)] = []
            var otherRecent: [(path: String, provider: AgentProvider)] = []
            var older: [(path: String, provider: AgentProvider)] = []
            var newestCursor: (path: String, provider: AgentProvider)?
            var newestCursorAt = Date.distantPast
            for file in files {
                let modified = logModified(file.path)
                if file.provider == .cursor, modified >= newestCursorAt {
                    newestCursor = file
                    newestCursorAt = modified
                }
                if modified >= cutoff {
                    if file.provider == .cursor { cursorNow.append(file) } else { otherRecent.append(file) }
                } else {
                    older.append(file)
                }
            }
            // The chat in progress is the transcript written last, even when
            // that was before the poll window. It has to be on the island
            // before the older logs are read.
            if let newestCursor, !cursorNow.contains(where: { $0.path == newestCursor.path }) {
                cursorNow.append(newestCursor)
                older.removeAll { $0.path == newestCursor.path }
            }
            guard self.readFiles(cursorNow, cancellation: cancellation) else { return }
            self.revealRunningTurns(roots)
            self.readHistory(otherRecent + older, from: 0, recent: Set(otherRecent.map(\.path)),
                             roots: roots, session: session, cancellation: cancellation)
        }
    }

    /// Reads each log. False when this launch was stopped mid-way.
    private func readFiles(_ files: [(path: String, provider: AgentProvider)], cancellation: Cancellation) -> Bool {
        for file in files {
            guard !cancellation.isCancelled else { return false }
            read(file.path, provider: file.provider)
        }
        return true
    }

    /// Puts a turn that is already running on the island and starts watching
    /// for the next line. Older logs read after this are still history: they
    /// must not replay as news.
    private func revealRunningTurns(_ roots: [AgentLogRoot]) {
        _ = pollOpenLogs(within: 30 * 60)
        let now = Date()
        store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn, keeping: cursorStillWorking())
        closeEndedTurns(roots, atLaunch: true)
        watch(roots)
        startPolling()
        watchNetwork()
        publishLive()
    }

    /// The newest Cursor transcript that has not written `turn_ended`. That
    /// turn stays up while the reply is still being written.
    private func cursorStillWorking() -> Set<String> {
        let open = cursors.values.filter { $0.provider == .cursor && $0.state.turnOpen }
        guard let latest = open.max(by: { $0.modified < $1.modified }) else { return [] }
        return [latest.path]
    }

    /// Older logs are read one at a time so a transcript that grows meanwhile
    /// is noticed between them, instead of after the whole history.
    private func readHistory(_ files: [(path: String, provider: AgentProvider)], from index: Int,
                             recent: Set<String>, roots: [AgentLogRoot], session: Int,
                             cancellation: Cancellation) {
        guard readerSession == session, !cancellation.isCancelled else { return }
        if index < files.count {
            let file = files[index]
            if read(file.path, provider: file.provider), recent.contains(file.path) {
                schedulePublish()
            }
            queue.async { [self] in
                self.readHistory(files, from: index + 1, recent: recent, roots: roots,
                                 session: session, cancellation: cancellation)
            }
            return
        }
        finishInitialRead(roots, session: session, cancellation: cancellation)
    }

    /// History is in. Endings from here on are news, and the first full
    /// snapshot replaces the one that only had the running turns.
    private func finishInitialRead(_ roots: [AgentLogRoot], session: Int, cancellation: Cancellation) {
        guard readerSession == session, !cancellation.isCancelled else { return }
        let now = Date()
        store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn, keeping: cursorStillWorking())
        closeEndedTurns(roots, atLaunch: true)
        // The account Claude Code uses picks the Claude app's readings.
        readClaudePlan()
        readClaudeApp(now: now)
        readCursorAccount(force: true)
        store.reportsTransitions = true
        previousLimits = store.limits
        // A budget already passed before launch is history, not news.
        let today = Calendar.autoupdatingCurrent.startOfDay(for: now)
        if let budget = NotchAgentSupport.dailyBudget(),
           store.records.lazy.filter({ $0.date >= today }).reduce(0.0, { $0 + ($1.cost ?? 0) }) >= budget {
            budgetDay = today
        }
        publish()
        saveProgress()
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
        let kept = cursors.values.filter { !$0.restarted && $0.provider != .opencode && $0.provider != .cursor }
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
            let cursorBefore = self.openCursorTurns()
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
            self.deliver(cursorBefore: cursorBefore)
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
    /// Mac stays offline. Runs on `queue`.
    private func watchNetwork() {
        guard network == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, self.readerSession >= 0 else { return }
            if path.status == .satisfied {
                self.offlineSince = nil
            } else if self.offlineSince == nil {
                self.offlineSince = (Date(), ProcessInfo.processInfo.systemUptime)
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

    /// Ends the Claude turns whose process is gone, and notices a session that
    /// stopped for input. True when a turn left the island or the waiting set changed.
    @discardableResult
    private func closeEndedTurns(_ roots: [AgentLogRoot], atLaunch: Bool = false) -> Bool {
        let folders = roots.filter { $0.provider == .claude }
            .map { $0.url.deletingLastPathComponent().appending(path: "sessions", directoryHint: .isDirectory) }
        let registry = AgentSessionRegistry.read(folders)
        let closed = store.showsClaudeTurn && store.closeEndedTurns(registry, atLaunch: atLaunch)
        let changed = registry.waiting != claudeAsked || registry.waitingReasons != claudeAskedReasons
        claudeAsked = registry.waiting
        claudeAskedReasons = registry.waitingReasons
        return closed || changed
    }

    /// Claude logs that are still the open turn and whose session record says
    /// the process stopped for input. They stay on the island past the quiet wait.
    private func claudeHeld() -> Set<String> {
        let asked = claudeAsked
        return Set(cursors.values.compactMap { cursor in
            guard cursor.provider == .claude else { return nil }
            let name = ((cursor.path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard asked.contains(name) else { return nil }
            if cursor.state.turnOpen { return cursor.path }
            if store.turns[cursor.path] != nil || store.waiting[cursor.path] != nil { return cursor.path }
            return nil
        })
    }

    /// Providers whose mark should turn amber: an unanswered Cursor question,
    /// or a Claude session record that says it is waiting.
    private func askedProviders() -> Set<AgentProvider> {
        var waiting = Set(cursors.values.filter { $0.cursorWaiting && $0.state.turnOpen }.map(\.provider))
        if !claudeHeld().isEmpty || (!claudeAsked.isEmpty && cursors.values.contains {
            $0.provider == .claude && claudeAsked.contains(claudeSessionName($0.path))
        }) {
            waiting.insert(.claude)
        }
        return waiting
    }

    /// Short waiting labels for the strip and ring hover, when known.
    private func waitingDetails() -> [AgentProvider: String] {
        var details: [AgentProvider: String] = [:]
        if let cursor = cursors.values
            .filter({ $0.provider == .cursor && $0.cursorWaiting && $0.state.turnOpen })
            .max(by: { $0.modified < $1.modified }),
           let reason = cursor.cursorWaitingReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            details[.cursor] = reason
        }
        for cursor in cursors.values where cursor.provider == .claude {
            let name = claudeSessionName(cursor.path)
            if let reason = claudeAskedReasons[name], !reason.isEmpty {
                details[.claude] = reason
                break
            }
        }
        if details[.claude] == nil, let reason = claudeAskedReasons.values.first(where: { !$0.isEmpty }) {
            details[.claude] = reason
        }
        return details
    }

    private func claudeSessionName(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
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
            if provider == .cursor, cursor.state.project.isEmpty {
                cursor.state.project = AgentCursorPath.project(in: path)
            }
            let entries: [AgentLogEntry]
            switch provider {
            case .claude: entries = AgentLogParser.parseClaude(line, state: &cursor.state, now: now)
            case .codex: entries = AgentLogParser.parseCodex(line, state: &cursor.state, now: now)
            case .opencode: entries = AgentLogParser.parseOpenCode(line, state: &cursor.state, now: now)
            case .copilot: entries = AgentLogParser.parseCopilot(line, state: &cursor.state, now: now)
            case .cursor:
                // The transcript's own mtime, so a chat left open earlier does
                // not look like work that just started. A turn read before the
                // rest of history keeps that time as well.
                let clock = cursor.modified == .distantPast ? now : min(now, cursor.modified)
                entries = AgentLogParser.parseCursor(line, state: &cursor.state, waiting: &cursor.cursorWaiting,
                                                     settled: &cursor.cursorSettled,
                                                     reason: &cursor.cursorWaitingReason, now: clock)
            }
            guard !entries.isEmpty else { return }
            changed = true
            let isSubagent = provider == .opencode && !cursor.state.parentSession.isEmpty
            let turnFile = provider == .opencode && !cursor.state.session.isEmpty ? "\(path)#\(cursor.state.session)" : path
            let tracksTurns = isSubagent ? false : cursor.tracksTurns
            let parent = isSubagent ? "\(path)#\(cursor.state.parentSession)" : cursor.parent
            let finished = store.apply(entries, file: turnFile, provider: provider, tracksTurns: tracksTurns,
                                       parent: parent, modified: cursor.modified, now: now)
            finished.forEach(report)
        }
        if provider == .copilot && cursor.offset == 0 {
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
        // Claude's waiting state lives in `sessions/<pid>.json` beside the
        // projects folder. Watch it so amber updates as soon as the record does.
        let sessions = existing.filter { $0.provider == .claude }
            .map { $0.url.deletingLastPathComponent().appending(path: "sessions").path }
        let paths = existing.map(\.url.path) + sessions
        if paths.isEmpty { watcher?.stop() } else { watcher?.start(paths) }
    }

    private func filesChanged(_ paths: [String], rescan: Bool) {
        guard readerSession >= 0, !watchedRoots.isEmpty else { return }
        defer { syncPolling() }
        let cursorBefore = openCursorTurns()
        var changed = false
        var sessionTouched = false
        if rescan {
            for file in AgentLogReader.discover(watchedRoots, since: Date().addingTimeInterval(-Self.horizon)) {
                if read(file.path, provider: file.provider) { changed = true }
            }
            sessionTouched = true
        } else {
            for path in Set(paths) {
                if path.contains("/sessions/"), path.hasSuffix(".json") {
                    sessionTouched = true
                    continue
                }
                guard AgentLogReader.isLog(path) else { continue }
                let actualPath = path.hasSuffix("-wal") ? String(path.dropLast(4)) : path
                guard let root = watchedRoots.first(where: { $0.accepts(actualPath) }) else { continue }
                if read(actualPath, provider: root.provider) { changed = true }
            }
        }
        let closed = sessionTouched && closeEndedTurns(watchedRoots)
        // Saved tool output and lines with nothing to keep do not change the
        // summary or require a display update.
        guard changed || closed else { return }
        checkLimits()
        deliver(cursorBefore: cursorBefore)
    }

    /// Cursor turns the island is showing, by transcript.
    private func openCursorTurns() -> Set<String> {
        Set(store.turns.compactMap { $0.value.provider == .cursor ? $0.key : nil })
    }

    /// A Cursor turn starting or ending updates the island at once. Other
    /// log growth still waits out the short burst. While history is loading,
    /// only the running turn is shown.
    private func deliver(cursorBefore: Set<String>) {
        if !store.reportsTransitions {
            publishLive()
        } else if openCursorTurns() != cursorBefore {
            publish()
        } else {
            schedulePublish()
        }
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
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            let now = Date()
            defer { syncPolling(now: now) }
            let before = inputs
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn,
                                 keeping: cursorStillWorking().union(claudeHeld()))
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
                readClaudePlan()
            }
            readClaudeApp(now: now)
            readCursorAccount(force: false)
            if now.timeIntervalSince(lastMeterSignInCheck) > 120 {
                lastMeterSignInCheck = now
                DispatchQueue.main.async { [weak self] in self?.refreshMeterSignIn() }
            }
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
        let waiting: Set<String>
        let settled: Set<String>
        let waitingDetail: [String: String]
        let cursorPlan: AgentPlan?
    }

    /// Runs on `queue`.
    private var inputs: Inputs {
        Inputs(records: store.records.count, turns: store.turns, limits: store.limits, codexPlan: store.codexPlan,
               claudePlan: claudePlan, claudeOrganization: claudeOrganization, claudeApp: claudeAppSamples,
               waiting: Set(cursors.compactMap { $0.value.cursorWaiting && $0.value.state.turnOpen ? $0.key : nil }),
               settled: Set(cursors.compactMap { $0.value.cursorSettled && $0.value.state.turnOpen ? $0.key : nil }),
               waitingDetail: Dictionary(uniqueKeysWithValues: waitingDetails().map { ($0.key.rawValue, $0.value) }),
               cursorPlan: cursorPlan)
    }

    /// Runs on `queue` and hands the finished snapshot to the main thread.
    /// Older Cursor chats stay out of the island. Only the transcript written
    /// last can show as thinking or as waiting for a reply.
    private func focusCursorPrompt() {
        let files = cursors.values.filter { $0.provider == .cursor }
        guard let latest = files.max(by: { $0.modified < $1.modified }) else { return }
        for other in files where other.path != latest.path {
            other.cursorWaiting = false
            other.cursorWaitingReason = nil
            other.cursorSettled = false
            other.state.turnOpen = false
            if store.turns[other.path] != nil || store.waiting[other.path] != nil {
                store.forget(file: other.path)
            }
        }
    }

    private func publish() {
        let session = readerSession
        guard session >= 0 else { return }
        focusCursorPrompt()
        var plans: [AgentProvider: AgentPlan] = [:]
        if let claudePlan { plans[.claude] = claudePlan }
        if let codex = AgentPlans.codex(planType: store.codexPlan) { plans[.codex] = codex }
        if let cursorPlan { plans[.cursor] = cursorPlan }
        let next = store.snapshot(plans: plans, providers: enabled, now: Date())
        published = next
        checkBudget(next)
        let checked = enabled.contains(.claude) ? claudeAppSamples.last(where: {
            claudeOrganization == nil || $0.organization == nil || $0.organization == claudeOrganization
        })?.date : nil
        let listed = AgentPricing.list.updated
        let prices = listed == AgentPriceList.empty.updated ? nil : listed
        let waiting = askedProviders()
        let details = waitingDetails()
        let settled = Set(cursors.values.filter { $0.cursorSettled && $0.state.turnOpen && !$0.cursorWaiting }.map(\.provider))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            if self.claudeAppChecked != checked { self.claudeAppChecked = checked }
            if self.pricesUpdated != prices { self.pricesUpdated = prices }
            if self.meterWaiting != waiting { self.meterWaiting = waiting }
            if self.meterWaitingDetail != details { self.meterWaitingDetail = details }
            if self.meterSettled != settled { self.meterSettled = settled }
            if self.snapshot != next { self.snapshot = next }
        }
    }

    /// The island's running turns, before history has finished loading.
    /// A later full publish replaces this. One that already landed is left
    /// alone, so a slow main-queue hop cannot put the page back to loading.
    private func publishLive() {
        let session = readerSession
        guard session >= 0 else { return }
        focusCursorPrompt()
        var plans: [AgentProvider: AgentPlan] = [:]
        if let claudePlan { plans[.claude] = claudePlan }
        if let codex = AgentPlans.codex(planType: store.codexPlan) { plans[.codex] = codex }
        if let cursorPlan { plans[.cursor] = cursorPlan }
        var next = store.snapshot(plans: plans, providers: enabled, now: Date())
        next.loaded = false
        let waiting = askedProviders()
        let details = waitingDetails()
        let settled = Set(cursors.values.filter { $0.cursorSettled && $0.state.turnOpen && !$0.cursorWaiting }.map(\.provider))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session, !self.snapshot.loaded else { return }
            if self.meterWaiting != waiting { self.meterWaiting = waiting }
            if self.meterWaitingDetail != details { self.meterWaitingDetail = details }
            if self.meterSettled != settled { self.meterSettled = settled }
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
            if threshold < 100 {
                for window in AgentLimitSupport.crossings(previous: previousLimits[provider], current: limits, threshold: 100) {
                    report(.limitWarning(provider: provider, window: window))
                }
            }
        }
        // A banked reset renews a warned window before its time, which is
        // news now rather than at the renewal it replaced.
        for (id, entry) in warned {
            guard let window = store.limits[entry.provider]?.windows.first(where: { $0.id == id }),
                  let was = entry.window.resetsAt, let resets = window.resetsAt,
                  resets.timeIntervalSince(was) > 60, window.usedPercent < threshold else { continue }
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
            return
        }
        claudeOrganization = account["organizationUuid"] as? String
        claudePlan = AgentPlans.claude(organizationType: account["organizationType"] as? String,
                                       rateLimitTier: account["organizationRateLimitTier"] as? String
                                        ?? account["userRateLimitTier"] as? String)
    }

    /// Reads the limits the Claude app saved when the file changes, and
    /// places them at `now` on every call, since a session ages out between
    /// saves. Runs on `queue`.
    private func readClaudeApp(now: Date) {
        guard enabled.contains(.claude) else {
            if store.limits[.claude]?.source == .claudeApp { store.clearLimits(.claude) }
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
        // Claude Code's own first request can place the session's start.
        let start = AgentClaudeAppUsage.sessionStart(store.records, samples: claudeAppSamples,
                                                     organization: claudeOrganization)
        if let limits = AgentClaudeAppUsage.limits(from: claudeAppSamples, now: now, sessionStart: start,
                                                   organization: claudeOrganization) {
            store.setLimits(limits)
        } else if store.limits[.claude]?.source == .claudeApp {
            store.clearLimits(.claude)
        }
    }

    /// Asks Cursor's account for plan usage when the app is signed in. A failed
    /// check leaves the last good reading alone. Runs on `queue`.
    private func readCursorAccount(force: Bool) {
        guard enabled.contains(.cursor) else {
            if store.limits[.cursor]?.source == .account { store.clearLimits(.cursor) }
            cursorPlan = nil
            cursorUsageInFlight = false
            return
        }
        let now = Date()
        let live = store.turns.values.contains { $0.provider == .cursor }
        let interval = live ? AgentCursorAccountUsage.liveInterval : AgentCursorAccountUsage.idleInterval
        guard force || now.timeIntervalSince(cursorUsageChecked) >= interval else { return }
        guard !cursorUsageInFlight else { return }
        guard let session = AgentCursorAccountUsage.session(home: home) else {
            cursorUsageChecked = now
            return
        }
        cursorUsageInFlight = true
        let reader = readerSession
        AgentCursorAccountUsage.fetch(session: session) { [weak self] reading in
            guard let self else { return }
            self.queue.async {
                self.cursorUsageInFlight = false
                guard self.readerSession == reader else { return }
                self.cursorUsageChecked = Date()
                guard let reading else { return }
                self.store.updateLimits(reading.limits)
                if let name = reading.planName {
                    self.cursorPlan = AgentPlan(name: name, monthlyPrice: nil)
                }
                self.checkLimits()
                self.schedulePublish()
            }
        }
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
