// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

struct AgentHubStatus: Equatable, Identifiable {
    var hub: AgentHub
    /// Nil until the hub is first asked.
    var state: AgentHubState?
    /// The hub's accounts as last listed, each with its latest reading. A hub
    /// that stops answering keeps them, so their cards can say how old they are.
    var accounts: [AgentHubAccount] = []
    var checking = false
    /// When the last reading began; nil until one has.
    var attempted: Date?
    var id: String { hub.id }

    /// A wrong key is never sent again on its own, since each one counts
    /// toward the hub's ban; only adding the hub again with a key asks it.
    func isDue(at now: Date) -> Bool {
        if state == .wrongKey { return false }
        guard let attempted else { return true }
        let interval: TimeInterval
        switch state {
        case .wrongKey?: return false
        case .blocked?, .remoteDisabled?, .managementOff?, .insecure?: interval = AgentHubLimitsService.settledRetry
        case .ready?:
            // Only a window that renewed after its reading asks sooner.
            let renewed = accounts.contains { account in
                guard let limits = account.limits else { return false }
                return limits.windows.contains { $0.resetsAt.map { $0 > limits.observedAt && $0 <= now } ?? false }
            }
            interval = renewed ? AgentHubLimitsService.renewedInterval : AgentHubLimitsService.refreshInterval
        case .checking?, .unreachable?, .failed?, nil: interval = AgentHubLimitsService.refreshInterval
        }
        return now.timeIntervalSince(attempted) >= interval
    }
}

/// The accounts of each CLIProxyAPI hub the person added, with their limits,
/// kept in memory. Hubs are asked when the AI page shows them and they are
/// due, or when a card or Settings asks, and never while the island is away,
/// the section is off or the Limits card is hidden.
final class AgentHubLimitsService: ObservableObject {
    typealias Reader = @Sendable (AgentHub) async -> AgentHubClient.Reading
    static let shared = AgentHubLimitsService()
    static let refreshInterval: TimeInterval = 5 * 60
    static let renewedInterval: TimeInterval = 60
    /// Only the person, or the hub's owner, can fix these.
    static let settledRetry: TimeInterval = 30 * 60

    @Published private(set) var hubs: [AgentHubStatus] = []
    /// Asks the due hubs again while the page shows any; nil otherwise.
    private(set) var timer: Timer?

    private let defaults: UserDefaults
    private let reader: Reader
    private let load: () -> [AgentHub]
    private let store: ([AgentHub]) -> Bool
    private var loaded = false
    private var visible = false
    private var running: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    /// A refused key whose flag could not be saved yet. Until it is, the
    /// key still is not sent, and each later sync tries the save again.
    private var refusalUnsaved = false

    init(defaults: UserDefaults = .standard, reader: @escaping Reader = { await AgentHubClient.read($0) },
         load: @escaping () -> [AgentHub] = { AgentHubStore.load() },
         store: @escaping ([AgentHub]) -> Bool = { AgentHubStore.save($0) }) {
        self.defaults = defaults
        self.reader = reader
        self.load = load
        self.store = store
    }

    /// Every hub account, whether or not its agent is on.
    var accounts: [AgentHubAccount] { hubs.flatMap(\.accounts) }

    /// Only while a hub account's card can show.
    var isEnabled: Bool {
        NotchAgentSupport.isEnabled(in: defaults) && NotchAgentSupport.showsHubAccounts(in: defaults)
    }

    func status(of account: AgentHubAccount) -> AgentHubStatus? { hubs.first { $0.id == account.hub } }

    /// Follows the saved hubs and the page's switches. Asks only what is due,
    /// and only while the page shows.
    func synchronize() {
        synchronizeLoaded()
        if !isEnabled { stopChecks() }
        syncTimer()
        if visible { refresh() }
    }

    /// A Settings preview shows what is known without asking.
    func pageDidAppear(preview: Bool = false) {
        if !preview { visible = true }
        synchronize()
    }

    /// A reading under way finishes, so looking at the page again does not
    /// start it over.
    func pageDidDisappear() {
        visible = false
        syncTimer()
    }

    /// The island is away, the section stops or the Limits card is hidden:
    /// nothing new starts, and a reading under way sends no further request.
    func pause() {
        visible = false
        stopChecks()
        syncTimer()
    }

    /// Asks the hubs that are due, or, when the person asks, `id` or every
    /// hub. One under way is not asked twice.
    func refresh(id: String? = nil, force: Bool = false, now: Date = Date()) {
        synchronizeLoaded()
        guard isEnabled, visible || force else { return }
        for status in hubs where id == nil || status.id == id {
            guard !status.checking, force ? status.state != .wrongKey : status.isDue(at: now) else { continue }
            start(status.hub, now: now)
        }
    }

    /// Saves a hub, replacing one at the same address, and asks it at once
    /// when its cards can show. False when the file could not be written.
    @discardableResult
    func add(_ hub: AgentHub) -> Bool {
        synchronizeLoaded()
        var saved = hubs.map(\.hub)
        if let index = saved.firstIndex(where: { $0.id == hub.id }) {
            saved[index] = hub
        } else {
            guard saved.count < AgentHub.maximum else { return false }
            saved.append(hub)
        }
        guard store(saved) else { return false }
        cancel(hub.id)
        if let index = hubs.firstIndex(where: { $0.id == hub.id }) {
            hubs[index] = AgentHubStatus(hub: hub)
        } else {
            hubs.append(AgentHubStatus(hub: hub))
        }
        syncTimer()
        refresh(id: hub.id, force: true)
        return true
    }

    @discardableResult
    func remove(id: String) -> Bool {
        synchronizeLoaded()
        guard store(hubs.map(\.hub).filter { $0.id != id }) else { return false }
        cancel(id)
        hubs.removeAll { $0.id == id }
        syncTimer()
        return true
    }

    private func synchronizeLoaded() {
        if refusalUnsaved { refusalUnsaved = !store(hubs.map(\.hub)) }
        guard !loaded else { return }
        loaded = true
        hubs = load().map { AgentHubStatus(hub: $0, state: $0.keyRefused ? .wrongKey : nil) }
    }

    private func start(_ hub: AgentHub, now: Date) {
        guard let index = hubs.firstIndex(where: { $0.hub == hub }) else { return }
        hubs[index].checking = true
        hubs[index].attempted = now
        let token = UUID()
        let read = reader
        let task = Task { @MainActor [weak self] in
            let reading = await read(hub)
            self?.finish(hub, token: token, reading: reading)
        }
        running[hub.id] = (token, task)
    }

    private func finish(_ hub: AgentHub, token: UUID, reading: AgentHubClient.Reading) {
        guard running[hub.id]?.token == token else { return }
        running[hub.id] = nil
        guard let index = hubs.firstIndex(where: { $0.id == hub.id && $0.hub.key == hub.key }) else { return }
        var status = hubs[index]
        status.checking = false
        // Stopped before it learned anything: asked again once checks can run.
        guard reading.state != .checking else {
            status.attempted = nil
            hubs[index] = status
            return
        }
        status.state = reading.state
        if reading.state == .wrongKey, !status.hub.keyRefused {
            status.hub.keyRefused = true
            var saved = hubs.map(\.hub)
            saved[index] = status.hub
            refusalUnsaved = !store(saved)
        }
        if let fresh = reading.accounts {
            // An account whose check failed keeps its last reading.
            let previous = status.accounts
            status.accounts = fresh.map { account in
                guard account.failure != nil, let old = previous.first(where: { $0.id == account.id }) else { return account }
                var kept = account
                kept.limits = old.limits
                kept.plan = account.plan ?? old.plan
                return kept
            }
        }
        hubs[index] = status
    }

    /// Drops a reading for a hub that was removed or given a new key.
    private func cancel(_ id: String) {
        running.removeValue(forKey: id)?.task.cancel()
    }

    /// Readings under way start no further request but still report what they
    /// learned: the hub may already have counted a wrong key, and the next
    /// reading must not send it again.
    private func stopChecks() {
        for entry in running.values { entry.task.cancel() }
    }

    private func syncTimer() {
        guard visible, isEnabled, !hubs.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
