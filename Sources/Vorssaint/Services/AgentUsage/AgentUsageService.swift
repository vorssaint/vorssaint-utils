// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Reads Claude Code and Codex usage from their local session logs while the
/// AI section is on, along with the plan limits the Claude app saves. The
/// files are read where they are, incrementally, and nothing is copied,
/// stored or sent: only counters stay in memory. The one request it makes
/// fetches the public price list, when the person keeps prices up to date.
///
/// Reading happens on a private queue; the main thread and that queue only
/// ever hand work to each other asynchronously.
final class AgentUsageService: ObservableObject {
    static let shared = AgentUsageService()

    @Published private(set) var snapshot = AgentUsageSnapshot()
    /// When the Claude app last saved the plan's limits; nil when it never has.
    @Published private(set) var claudeAppChecked: Date?
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
    /// A live log may append many times per second; one summary per second
    /// keeps the island current without repeatedly totaling 13 weeks of use.
    private static let publishDelay: TimeInterval = 1

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

    // Confined to `queue`.
    private var readerSession = -1
    private var enabled: Set<AgentProvider> = []
    private var store = AgentUsageStore()
    private var cursors: [String: AgentLogCursor] = [:]
    private var watcher: AgentLogWatcher?
    private var watchedRoots: [AgentLogRoot] = []
    private var poller: DispatchSourceTimer?
    private var publishScheduled = false
    /// The last snapshot handed over, to tell when time alone changes it.
    private var published = AgentUsageSnapshot()
    private var claudePlan: AgentPlan?
    /// The organization Claude Code signs in to, when its profile says.
    private var claudeOrganization: String?
    private var claudeProfileModified: Date?
    private var claudeAppModified: Date?
    private var claudeAppSamples: [AgentClaudeAppUsage.Sample] = []
    private var shippedPrices: AgentPriceList?
    private var previousLimits: [AgentProvider: AgentLimits] = [:]
    /// Warned windows, each waiting for its renewal.
    private var warned: [String: (provider: AgentProvider, window: AgentLimitWindow)] = [:]
    private var budgetDay: Date?
    private var lastRootCheck = Date.distantPast

    private init() {}

    func syncWithPreferences() {
        guard NotchAgentSupport.isEnabled() else { stop(); return }
        let wanted = NotchAgentSupport.providers()
        // An agent turned off is no longer read at all, and one turned on is
        // read from its start: both take a fresh reading.
        if running, wanted != providers { stop() }
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

    func stop() {
        guard running else { return }
        running = false
        paused = false
        session += 1
        cancellation.cancel()
        timer?.invalidate()
        timer = nil
        providers = []
        pricesInFlight = false
        pricesSaved = nil
        snapshot = AgentUsageSnapshot()
        claudeAppChecked = nil
        queue.async { [self] in
            readerSession = -1
            poller?.cancel()
            poller = nil
            watcher?.stop()
            watcher = nil
            watchedRoots = []
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
        }
    }

    /// Opening the page shows the latest limits the Claude app saved.
    func pageDidAppear() {
        guard running else { return }
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            readClaudeApp(now: Date())
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
        queue.async { [self] in
            readerSession = session
            enabled = providers
            store = AgentUsageStore()
            cursors.removeAll()
            // Prices first, so the first read is already priced.
            loadPrices()
            let roots = AgentLogRoot.all(home: home).filter { providers.contains($0.provider) }
            for file in AgentLogReader.discover(roots, since: Date().addingTimeInterval(-Self.horizon)) {
                // A stop while reading leaves the rest for the next start.
                guard !cancellation.isCancelled else { return }
                read(file.path, provider: file.provider)
            }
            guard !cancellation.isCancelled else { return }
            let now = Date()
            // A turn left open by a crash would otherwise stay working.
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
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
            publish()
        }
    }

    /// Runs on `queue`.
    private func startPolling() {
        poller?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.poll, repeating: Self.poll, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self, self.pollOpenLogs(within: Self.pollWindow) else { return }
            self.checkLimits()
            self.schedulePublish()
        }
        timer.resume()
        poller = timer
    }

    /// Reads the logs that grew, were replaced or disappeared since the last
    /// look, among those an agent may still be writing. True when that
    /// changed what is stored.
    private func pollOpenLogs(within window: TimeInterval) -> Bool {
        guard readerSession >= 0 else { return false }
        let now = Date()
        // A turn gone quiet, as while it waits for an approval, is noticed
        // as soon as its work resumes.
        let working = Set(store.turns.keys).union(store.waiting.keys)
        var changed = false
        for (path, cursor) in cursors
        where working.contains(path) || now.timeIntervalSince(cursor.modified) < window {
            var info = stat()
            let exists = stat(path, &info) == 0
            guard !exists || UInt64(max(0, info.st_size)) != cursor.offset
                    || UInt64(info.st_ino) != cursor.identity else { continue }
            if read(path, provider: cursor.provider) { changed = true }
        }
        return changed
    }

    /// True when the log had entries to apply, or was gone and took a
    /// working turn with it.
    @discardableResult
    private func read(_ path: String, provider: AgentProvider) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            cursors[path] = nil
            return store.forget(file: path)
        }
        let cursor = cursors[path] ?? AgentLogCursor(path: path, provider: provider)
        cursors[path] = cursor
        var entries: [AgentLogEntry] = []
        let now = Date()
        AgentLogReader.readAppended(cursor) { line in
            switch provider {
            case .claude: entries += AgentLogParser.parseClaude(line, state: &cursor.state, now: now)
            case .codex: entries += AgentLogParser.parseCodex(line, state: &cursor.state, now: now)
            }
        }
        guard !entries.isEmpty else { return false }
        let finished = store.apply(entries, file: path, provider: provider, tracksTurns: cursor.tracksTurns,
                                   parent: cursor.parent, modified: cursor.modified, now: now)
        finished.forEach(report)
        return true
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
        var changed = false
        if rescan {
            for file in AgentLogReader.discover(watchedRoots, since: Date().addingTimeInterval(-Self.horizon)) {
                if read(file.path, provider: file.provider) { changed = true }
            }
        } else {
            for path in Set(paths) where AgentLogReader.isLog(path) {
                guard let root = watchedRoots.first(where: { path.hasPrefix($0.url.path + "/") }) else { continue }
                if read(path, provider: root.provider) { changed = true }
            }
        }
        // Every snapshot adds up the whole history; saved tool output and
        // lines with nothing to keep change nothing it shows.
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
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            let now = Date()
            let before = inputs
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
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
            checkLimits()
            reportRenewals(now: now)
            // A snapshot adds up the whole history, so one is made only when
            // something it shows changed, or when time alone changes it.
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
        let next = AgentUsageSummary.snapshot(records: store.records, limits: store.limits, live: store.live,
                                              plans: plans, providers: enabled, now: Date())
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

    // MARK: Alerts

    /// Filters by the person's choices on the main thread, where they live.
    private func report(_ event: AgentUsageEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
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
        let recent = store.records.filter {
            $0.provider == .claude && $0.date <= now && now.timeIntervalSince($0.date) < AgentUsageSummary.blockHistory
        }
        let start = AgentUsageSummary.currentBlock(recent, now: now)?.start
        if let limits = AgentClaudeAppUsage.limits(from: claudeAppSamples, now: now, sessionStart: start,
                                                   organization: claudeOrganization) {
            store.setLimits(limits)
        } else if store.limits[.claude]?.source == .claudeApp {
            store.clearLimits(.claude)
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
