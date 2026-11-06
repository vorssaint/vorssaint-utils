// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

struct ClaudeSeatState: Equatable, Identifiable {
    var profile: ClaudeSeatProfile
    var identity: ClaudeSeatIdentity?
    var limits: AgentLimits?
    /// Waiting for its turn or being checked.
    var checking = false
    var failure: AgentClaudeServer.Failure?
    /// When the last check began, or when a session's saved copy was
    /// fetched; nil until either happened.
    var attempted: Date?
    /// Checks in a row that Claude Code did not answer.
    var unreachable = 0
    var id: String { profile.id }

    func isDue(at now: Date, onScreen: Bool) -> Bool {
        guard let attempted else { return true }
        return now.timeIntervalSince(attempted) >= AgentClaudeServer.interval(after: failure, repeated: unreachable,
                                                                               pageVisible: onScreen)
    }
}

/// The limits of each Claude seat the person added, each through its own
/// Claude Code profile with the same no-model check as the usual account,
/// and the saved copy every session of that profile keeps. One seat is
/// checked at a time, only while something uses the limits, and never while
/// the island is away or Claude is off. Nothing is kept on disk.
final class ClaudeSeatLimitsService: ObservableObject {
    static let shared = ClaudeSeatLimitsService()

    @Published private(set) var states: [ClaudeSeatState] = []
    /// The account the Claude app is signed in to, as it last recorded it.
    @Published private(set) var activeAccount: String?

    private let defaults: UserDefaults
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let queue = DispatchQueue(label: "com.vorssaint.claude-seat-limits", qos: .utility)
    private var running: (id: String, request: AgentClaudeServer.Request)?
    private var waiting: [String] = []
    private var timer: Timer?
    private var paused = true
    private var pageVisible = false
    private var identityModified: [String: Date] = [:]
    // Confined to `queue`.
    private var watchers: [String: AgentFileWatcher] = [:]
    // Alerts, main thread: each seat's last reading and its warned windows.
    private var previous: [String: AgentLimits] = [:]
    private var warned: [String: (email: String, window: AgentLimitWindow)] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Claude is read and the person added seats.
    var isActive: Bool {
        NotchAgentSupport.isEnabled(in: defaults) && NotchAgentSupport.providers(in: defaults).contains(.claude)
            && !states.isEmpty
    }

    /// Follows the saved seats and whether Claude is on, and resumes after
    /// a pause.
    func synchronize() {
        let wanted = ClaudeSeatProfile.decode(defaults.string(forKey: DefaultsKey.notchAgentsClaudeSeats) ?? "")
        if states.map(\.profile) != wanted {
            let before = states
            states = wanted.map { profile in
                before.first { $0.profile == profile } ?? ClaudeSeatState(profile: profile)
            }
            let kept = Set(states.map(\.id))
            waiting.removeAll { !kept.contains($0) }
            if let running, !kept.contains(running.id) {
                running.request.cancel()
                self.running = nil
            }
            identityModified = identityModified.filter { kept.contains($0.key) }
        }
        guard NotchAgentSupport.isEnabled(in: defaults), NotchAgentSupport.providers(in: defaults).contains(.claude) else {
            pause()
            publish()
            return
        }
        paused = false
        readIdentities()
        readActiveAccount()
        syncWatchers()
        syncTimer()
        refresh()
        publish()
    }

    func pageDidAppear() {
        pageVisible = true
        refresh()
    }

    func pageDidDisappear() {
        pageVisible = false
    }

    /// The island is away or the section stops: nothing runs or watches.
    func pause() {
        paused = true
        pageVisible = false
        cancelChecks()
        syncTimer()
        syncWatchers()
    }

    /// Queues the seats that are due, or every seat when the person asks.
    func refresh(force: Bool = false, now: Date = Date()) {
        guard !paused, isActive, force || NotchAgentSupport.limitsInUse(pageShown: pageVisible, in: defaults) else { return }
        let onScreen = NotchAgentSupport.limitsOnScreen(pageShown: pageVisible, in: defaults)
        for index in states.indices where !states[index].checking && shown(states[index]) {
            guard force || states[index].isDue(at: now, onScreen: onScreen) else { continue }
            states[index].checking = true
            waiting.append(states[index].id)
        }
        startNext()
        publish()
    }

    /// A seat the island and the lock screen both leave out is not checked,
    /// watched or warned about.
    private func shown(_ state: ClaudeSeatState) -> Bool {
        NotchLimitVisibility.isChecked(.profile(state.id), defaults: defaults)
    }

    private func tick() {
        readIdentities()
        readActiveAccount()
        reportRenewals(now: Date())
        refresh()
        // A window that renews or ages out reads differently with nothing new.
        publish()
    }

    // MARK: Checks

    private func startNext() {
        guard running == nil, !waiting.isEmpty else { return }
        let id = waiting.removeFirst()
        guard let index = states.firstIndex(where: { $0.id == id }),
              let folder = states[index].profile.canonicalDirectory else {
            if let index = states.firstIndex(where: { $0.id == id }) {
                states[index].checking = false
                states[index].failure = .needsSignIn
                states[index].attempted = Date()
            }
            return startNext()
        }
        states[index].attempted = Date()
        let request = AgentClaudeServer.Request()
        running = (id, request)
        let home = self.home
        queue.async { [weak self] in
            let result: Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure>
            if let executable = AgentClaudeServer.executable(home: home, searchPath: ProcessInfo.processInfo.environment["PATH"]) {
                var environment = AgentCodexServer.environment(for: executable, searchPath: nil)
                environment["PATH"] = AgentClaudeServer.searchPath(after: environment["PATH"] ?? "", home: home)
                result = request.run(executable, location: .seat(folder), environment: environment)
            } else {
                result = .failure(.missing)
            }
            DispatchQueue.main.async {
                guard let self, self.running?.request === request else { return }
                self.running = nil
                self.finish(id, result)
                self.startNext()
            }
        }
    }

    private func finish(_ id: String, _ result: Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure>) {
        guard let index = states.firstIndex(where: { $0.id == id }) else { return }
        states[index].checking = false
        switch result {
        case .success(let summary):
            states[index].failure = nil
            states[index].unreachable = 0
            // A session's saved copy may be newer than what the check read.
            if summary.account == states[index].identity?.account || states[index].identity == nil,
               summary.limits.observedAt >= states[index].limits?.observedAt ?? .distantPast {
                states[index].limits = summary.limits
            }
        case .failure(let failure):
            states[index].failure = failure
            states[index].unreachable = failure == .unreachable ? states[index].unreachable + 1 : 0
            // Signed out: another account may be behind the folder next.
            if failure == .needsSignIn { states[index].limits = nil }
        }
        readIdentities()
        noteLimits()
        publish()
    }

    private func cancelChecks() {
        running?.request.cancel()
        // Asked again once checks can run.
        if let running, let index = states.firstIndex(where: { $0.id == running.id }) { states[index].attempted = nil }
        running = nil
        waiting.removeAll()
        for index in states.indices where states[index].checking { states[index].checking = false }
    }

    private func syncTimer() {
        guard !paused, isActive else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        // The resting island's cadence: a switch of account in the app shows
        // within one tick.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Profiles

    /// Who each folder is signed in as, read again when its profile changes.
    private func readIdentities() {
        for index in states.indices {
            let url = states[index].profile.profileURL
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard modified != identityModified[states[index].id] || states[index].identity == nil && modified != nil
            else { continue }
            identityModified[states[index].id] = modified
            let identity = ClaudeSeatIdentity.read(url)
            if identity?.account != states[index].identity?.account { states[index].limits = nil }
            states[index].identity = identity
        }
    }

    private func readActiveAccount() {
        let account = ClaudeAppAccounts.signedIn(home: home)
        if account != activeAccount { activeAccount = account }
    }

    /// Each seat's profile, where its Claude Code sessions save the usage
    /// they fetch: a copy newer than the reading in hand is taken, and
    /// counts as a check that answered then.
    private func syncWatchers() {
        let wanted = paused || !isActive ? [:]
            : Dictionary(uniqueKeysWithValues: states.filter(shown).map { ($0.id, $0.profile.profileURL) })
        queue.async { [weak self] in
            guard let self else { return }
            for (id, watcher) in self.watchers where wanted[id] == nil {
                watcher.stop()
                self.watchers[id] = nil
            }
            for (id, url) in wanted where self.watchers[id] == nil {
                let watcher = AgentFileWatcher(url, queue: self.queue) { [weak self] in self?.readCache(id: id, url: url) }
                watcher.start()
                self.watchers[id] = watcher
                self.readCache(id: id, url: url)
            }
        }
    }

    /// Runs on `queue`.
    private func readCache(id: String, url: URL) {
        let now = Date()
        guard let cache = AgentClaudeServer.cache(at: url, now: now) else { return }
        let account = ClaudeSeatIdentity.read(url)?.account
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.paused, let index = self.states.firstIndex(where: { $0.id == id }),
                  account != nil, account == self.states[index].identity?.account || self.states[index].identity == nil,
                  cache.limits.observedAt > self.states[index].limits?.observedAt ?? .distantPast else { return }
            self.states[index].limits = cache.limits
            if cache.limits.observedAt > self.states[index].attempted ?? .distantPast {
                self.states[index].attempted = cache.limits.observedAt
                self.states[index].failure = nil
                self.states[index].unreachable = 0
            }
            self.readIdentities()
            self.noteLimits()
            self.publish()
        }
    }

    // MARK: Alerts

    /// Warns once a seat's window crosses the threshold, and again when it
    /// renews, as the usual account does.
    private func noteLimits() {
        let threshold = NotchAgentSupport.limitThreshold(in: defaults) ?? NotchAgentSupport.defaultLimitThreshold
        for state in states where shown(state) {
            guard let account = state.identity?.account, let limits = state.limits else { continue }
            let email = state.identity?.email ?? ""
            for window in AgentLimitSupport.crossings(previous: previous[account], current: limits, threshold: threshold) {
                warned[account + "." + window.id] = (email, window)
                AgentUsageService.shared.reportSeat(.seatLimitWarning(email: email, window: window))
            }
            for (key, entry) in warned where key.hasPrefix(account + ".") {
                guard let window = limits.windows.first(where: { $0.id == entry.window.id }), window.usedPercent < threshold,
                      AgentLimitSupport.renewed(entry.window, to: window, observedAt: limits.observedAt) else { continue }
                warned[key] = nil
                AgentUsageService.shared.reportSeat(.seatLimitReset(email: entry.email, window: window))
            }
            previous[account] = limits
        }
    }

    private func reportRenewals(now: Date) {
        let hidden = Set(states.filter { !shown($0) }.compactMap { $0.identity?.account })
        for (key, entry) in warned {
            guard let resets = entry.window.resetsAt, resets <= now else { continue }
            if hidden.contains(where: { key.hasPrefix($0 + ".") }) {
                warned[key] = nil
                continue
            }
            warned[key] = nil
            AgentUsageService.shared.reportSeat(.seatLimitReset(email: entry.email, window: entry.window))
        }
    }

    // MARK: Snapshot

    /// What the island shows of each seat, handed to the usage service.
    var seats: [ClaudeSeat] {
        guard isActive else { return [] }
        return states.map { state in
            ClaudeSeat(id: state.id, directory: state.profile.directory, account: state.identity?.account,
                       organization: state.identity?.organization, email: state.identity?.email ?? "",
                       plan: state.identity?.plan?.name, limits: state.limits,
                       checking: state.checking, failure: state.failure,
                       active: state.identity?.account != nil && state.identity?.account == activeAccount,
                       checked: state.limits?.observedAt)
        }
    }

    private func publish() {
        AgentUsageService.shared.noteClaudeSeats(seats)
    }
}
