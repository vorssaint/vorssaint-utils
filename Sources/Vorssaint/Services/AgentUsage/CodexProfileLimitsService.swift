// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

struct CodexProfileLimitsState: Equatable, Identifiable {
    var profile: CodexAccountProfile
    var limits: AgentLimits?
    var plan: String?
    /// Waiting for its turn or being checked.
    var checking = false
    var failure: CodexAccountUsageError?
    /// When the last check began; nil until one has.
    var attempted: Date?
    var id: String { profile.id }

    /// An expired window is unknown, not a freshly replenished allowance.
    func currentLimits(at now: Date) -> AgentLimits? {
        guard var limits else { return nil }
        limits.windows.removeAll { $0.resetsAt.map { $0 <= now } ?? false }
        return limits.windows.isEmpty ? nil : limits
    }

    func isDue(at now: Date) -> Bool {
        guard let attempted else { return true }
        // Only a window that renewed after the reading asks sooner, so a
        // Codex that answers with a past renewal is not asked every minute.
        let renewed = limits.map { reading in
            reading.windows.contains { $0.resetsAt.map { $0 > reading.observedAt && $0 <= now } ?? false }
        } ?? false
        return now.timeIntervalSince(attempted) >= CodexAccountUsageReader.interval(after: failure, renewed: renewed)
    }
}

/// The limits of each Codex home the person added, kept apart from the
/// provider-wide reading of the logs and in memory only. One home is checked
/// at a time: when the AI page shows them and they are due, or when a card
/// or Settings asks, and never while the island is away or Codex is off.
final class CodexProfileLimitsService: ObservableObject {
    typealias Reader = (CodexAccountProfile, _ searchPath: String?, BoundedProcessCancellation)
        -> Result<CodexAccountReading, CodexAccountUsageError>
    static let shared = CodexProfileLimitsService()

    @Published private(set) var states: [CodexProfileLimitsState] = []
    /// Asks the due homes again while the page shows any; nil otherwise.
    private(set) var timer: Timer?

    private let queue = DispatchQueue(label: "com.vorssaint.codex-profile-limits", qos: .utility)
    private let defaults: UserDefaults
    private let reader: Reader?
    private let loginShellPath: () -> String?
    private var running: (id: String, cancellation: BoundedProcessCancellation)?
    /// Checks waiting their turn. Those the person asked for still run after
    /// the page closes; the page's own wait for it to show again.
    private var waiting: [(id: String, asked: Bool)] = []
    private var visible = false
    /// A Terminal window's PATH, asked of the login shell only when the
    /// person checks again for a Codex that was not found, as on the Resets
    /// card: that runs their shell's startup files.
    private var shellPath: String?

    init(defaults: UserDefaults = .standard, reader: Reader? = nil,
         loginShellPath: @escaping () -> String? = AgentCodexServer.loginShellPath) {
        self.defaults = defaults
        self.reader = reader
        self.loginShellPath = loginShellPath
    }

    /// Only while an account card can show: a hidden Limits card asks nothing.
    var isEnabled: Bool {
        NotchAgentSupport.isEnabled(in: defaults) && NotchAgentSupport.showsCodexAccounts(in: defaults)
    }

    /// Follows the saved homes and whether Codex is on. Asks only what is
    /// due, and only while the page shows.
    func synchronize() {
        if !isEnabled { cancelChecks() }
        let wanted = CodexAccountProfile.decode(defaults.string(forKey: DefaultsKey.notchAgentsCodexProfiles) ?? "")
        if states.map(\.profile) != wanted {
            let previous = states
            states = wanted.map { profile in
                // A renamed home keeps its reading and its check.
                guard var state = previous.first(where: { $0.id == profile.id && $0.profile.directory == profile.directory })
                else { return CodexProfileLimitsState(profile: profile) }
                state.profile = profile
                return state
            }
            let kept = Set(states.filter(\.checking).map(\.id))
            waiting.removeAll { !kept.contains($0.id) }
            if let running, !kept.contains(running.id) {
                running.cancellation.cancel()
                self.running = nil
                startNext()
            }
        }
        syncTimer()
        if visible { refresh() }
    }

    /// A Settings preview shows what is known without asking.
    func pageDidAppear(preview: Bool = false) {
        if !preview { visible = true }
        synchronize()
    }

    /// A check under way finishes and keeps its time, so looking at the page
    /// again does not start it over.
    func pageDidDisappear() {
        visible = false
        syncTimer()
        let dropped = Set(waiting.filter { !$0.asked }.map(\.id))
        guard !dropped.isEmpty else { return }
        waiting.removeAll { !$0.asked }
        for index in states.indices where dropped.contains(states[index].id) { states[index].checking = false }
    }

    /// The island is away, the section stops or Codex is off: nothing runs.
    func pause() {
        visible = false
        cancelChecks()
        syncTimer()
    }

    /// Queues the homes that are due, or, when the person asks, `id` or every
    /// home. One already waiting or under way is not asked twice.
    func refresh(id: String? = nil, force: Bool = false, now: Date = Date()) {
        guard isEnabled, visible || force else { return }
        for index in states.indices where id == nil || states[index].id == id {
            let state = states[index]
            if state.checking {
                if force, let place = waiting.firstIndex(where: { $0.id == state.id }) { waiting[place].asked = true }
                continue
            }
            guard force || state.isDue(at: now) else { continue }
            states[index].checking = true
            waiting.append((state.id, force))
        }
        startNext()
    }

    private func startNext() {
        guard running == nil, !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        guard let index = states.firstIndex(where: { $0.id == next.id }) else { return startNext() }
        let profile = states[index].profile
        let searching = next.asked && states[index].failure == .missingCLI && shellPath == nil
        states[index].attempted = Date()
        let cancellation = BoundedProcessCancellation()
        running = (next.id, cancellation)
        let known = shellPath, shell = loginShellPath
        let read = reader ?? Self.reader(apps: Self.apps())
        queue.async { [weak self] in
            let path = searching ? shell() : known
            let result = read(profile, path, cancellation)
            DispatchQueue.main.async {
                guard let self, self.running?.cancellation === cancellation else { return }
                self.running = nil
                if let path { self.shellPath = path }
                self.finish(profile, result)
                self.startNext()
            }
        }
    }

    private func finish(_ profile: CodexAccountProfile, _ result: Result<CodexAccountReading, CodexAccountUsageError>) {
        guard let index = states.firstIndex(where: { $0.id == profile.id && $0.profile.directory == profile.directory })
        else { return }
        var state = states[index]
        state.checking = false
        switch result {
        case .success(let reading):
            state.limits = reading.limits
            state.plan = reading.plan
            state.failure = nil
        case .failure(.cancelled):
            state.attempted = nil
        case .failure(let failure):
            // Another sign-in may be behind the home now. A check that could
            // not finish leaves the last reading standing.
            if failure == .needsSignIn || failure == .invalidProfile {
                state.limits = nil
                state.plan = nil
            }
            state.failure = failure
        }
        states[index] = state
    }

    private func cancelChecks() {
        guard running != nil || !waiting.isEmpty else { return }
        if let running {
            running.cancellation.cancel()
            // Asked again once checks can run.
            if let index = states.firstIndex(where: { $0.id == running.id }) { states[index].attempted = nil }
        }
        running = nil
        waiting.removeAll()
        for index in states.indices where states[index].checking { states[index].checking = false }
    }

    private func syncTimer() {
        guard visible, isEnabled, !states.isEmpty else {
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

    private static func reader(apps: [URL]) -> Reader {
        { profile, searchPath, cancellation in
            guard let executable = AgentCodexServer.executable(apps: apps, home: FileManager.default.homeDirectoryForCurrentUser,
                                                               searchPath: searchPath) else { return .failure(.missingCLI) }
            return CodexAccountUsageReader.read(profile, executable: executable, searchPath: searchPath,
                                                cancellation: cancellation)
        }
    }

    private static func apps() -> [URL] {
        AgentCodexServer.appIdentifiers.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
    }
}
