// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

struct ClaudeProfileLimitsState: Equatable, Identifiable {
    var account: ClaudeMonitoredAccount
    var limits: AgentLimits?
    var plan: AgentPlan?
    var identity: ClaudeAccountProfile.Identity?
    var failure: AgentClaudeServer.Failure?
    var checking = false
    var attempted: Date?
    var failures = 0
    var id: String { account.id }

    func isDue(at now: Date) -> Bool {
        attempted.map { now.timeIntervalSince($0) >= AgentClaudeServer.interval(after: failure,
            repeated: failures, pageVisible: true) } ?? true
    }
}

/// Additional profiles are checked serially while the AI page shows limits.
/// The first profile retains the existing background limits and alert behavior.
final class ClaudeProfileLimitsService: ObservableObject {
    struct Check {
        var metadata: ClaudeAccountProfile.Reading
        var result: Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure>
    }
    typealias Reader = (ClaudeAccountProfile, AgentClaudeServer.Request) -> Check
    static let shared = ClaudeProfileLimitsService()
    @Published private(set) var states: [ClaudeProfileLimitsState] = []
    private(set) var timer: Timer?
    private let defaults: UserDefaults
    private let reader: Reader
    private let queue = DispatchQueue(label: "com.vorssaint.claude-profile-limits", qos: .utility)
    private var running: (id: String, request: AgentClaudeServer.Request)?
    private var waiting: [(id: String, asked: Bool)] = []
    private var visible = false
    private var online = true

    init(defaults: UserDefaults = .standard, reader: @escaping Reader = ClaudeProfileLimitsService.read) {
        self.defaults = defaults
        self.reader = reader
    }

    var isEnabled: Bool {
        NotchAgentSupport.isEnabled(in: defaults) && NotchAgentSupport.providers(in: defaults).contains(.claude)
            && !NotchAgentSupport.hiddenCards(in: defaults).contains(.limits)
    }

    func synchronize() {
        if !isEnabled { cancelChecks() }
        let wanted = Array(ClaudeMonitoredAccount.configured(in: defaults).dropFirst())
        if states.map(\.account) != wanted {
            states = wanted.map { account in
                var state = states.first { $0.id == account.id } ?? ClaudeProfileLimitsState(account: account)
                state.account = account
                return state
            }
            waiting.removeAll { item in !states.contains { $0.id == item.id } }
            if let running, !states.contains(where: { $0.id == running.id }) {
                running.request.cancel()
                self.running = nil
            }
        }
        syncTimer()
        refresh()
    }

    func pageDidAppear(preview: Bool = false) {
        if !preview { visible = true }
        synchronize()
    }

    func pageDidDisappear() {
        visible = false
        let dropped = Set(waiting.filter { !$0.asked }.map(\.id))
        waiting.removeAll { !$0.asked }
        for index in states.indices where dropped.contains(states[index].id) { states[index].checking = false }
        syncTimer()
    }

    func pause() {
        visible = false
        cancelChecks()
        syncTimer()
    }

    func setOnline(_ value: Bool) {
        online = value
        if !value { cancelChecks() }
        else { for index in states.indices { states[index].failures = 0 } }
    }

    func refresh(id: String? = nil, force: Bool = false, now: Date = Date()) {
        guard isEnabled, online, visible || force else { return }
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
        guard running == nil, !waiting.isEmpty, isEnabled, online else { return }
        let next = waiting.removeFirst()
        guard let index = states.firstIndex(where: { $0.id == next.id }) else { return startNext() }
        let profile = states[index].account.profile
        states[index].attempted = Date()
        let request = AgentClaudeServer.Request()
        running = (next.id, request)
        let read = reader
        queue.async { [weak self] in
            let check = read(profile, request)
            DispatchQueue.main.async {
                guard let self, self.running?.request === request else { return }
                self.running = nil
                if let index = self.states.firstIndex(where: { $0.id == next.id }) {
                    var state = self.states[index]
                    state.checking = false
                    if state.identity != check.metadata.identity { state.limits = nil }
                    state.identity = check.metadata.identity
                    state.plan = check.metadata.plan
                    switch check.result {
                    case .success(let reading) where reading.identity == state.identity:
                        state.limits = reading.limits
                        state.failure = nil
                        state.failures = 0
                    case .success:
                        state.limits = nil
                        state.failure = .unreachable
                        state.failures += 1
                    case .failure(let failure):
                        if failure == .needsSignIn { state.limits = nil }
                        state.failure = failure
                        state.failures = failure == .unreachable ? state.failures + 1 : 0
                    }
                    self.states[index] = state
                }
                self.startNext()
            }
        }
    }

    private func cancelChecks() {
        running?.request.cancel()
        if let running, let index = states.firstIndex(where: { $0.id == running.id }) { states[index].attempted = nil }
        running = nil
        waiting.removeAll()
        for index in states.indices { states[index].checking = false }
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

    private static func read(_ profile: ClaudeAccountProfile, _ request: AgentClaudeServer.Request) -> Check {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result: Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure>
        if let executable = AgentClaudeServer.executable(home: home, searchPath: ProcessInfo.processInfo.environment["PATH"]) {
            var environment = AgentCodexServer.environment(for: executable, searchPath: nil)
            environment["PATH"] = AgentClaudeServer.searchPath(after: environment["PATH"] ?? "", home: home)
            result = request.run(executable, home: home, environment: environment, profile: profile)
        } else { result = .failure(.missing) }
        return Check(metadata: profile.read(home: home), result: result)
    }
}
