// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

struct CodexProfileLimitsState: Equatable, Identifiable {
    var profile: CodexAccountProfile
    var limits: AgentLimits?
    var plan: String?
    var checking = false
    var error: String?
    var attempted: Date?
    var id: String { profile.id }

    /// An expired window is unknown, not a freshly replenished allowance.
    func currentLimits(at now: Date) -> AgentLimits? {
        guard var limits else { return nil }
        limits.windows.removeAll { $0.resetsAt.map { $0 <= now } ?? false }
        return limits.windows.isEmpty ? nil : limits
    }
}

/// Account readings never enter the provider-wide log snapshot. Each home
/// keeps its own limits, errors and refresh time, only while the page is open.
final class CodexProfileLimitsService: ObservableObject {
    typealias Reader = (CodexAccountProfile, BoundedProcessCancellation) throws -> (limits: AgentLimits, plan: String?)
    static let shared = CodexProfileLimitsService()
    @Published private(set) var states: [CodexProfileLimitsState] = []
    private let queue = DispatchQueue(label: "com.vorssaint.codex-profile-limits", qos: .utility)
    private let defaults: UserDefaults
    private let reader: Reader?
    private var cancellation = BoundedProcessCancellation()
    private var generation = 0
    private var timer: Timer?
    private var visible = false
    private var inFlight = false

    init(defaults: UserDefaults = .standard, reader: Reader? = nil) {
        self.defaults = defaults
        self.reader = reader
    }

    private var enabled: Bool {
        NotchAgentSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchAgentsCodex)
    }

    func synchronize() {
        if !enabled { pause() }
        let wanted = CodexAccountProfile.decode(defaults.string(forKey: DefaultsKey.notchAgentsCodexProfiles) ?? "")
        guard states.map(\.profile) != wanted else { return }
        let wasVisible = visible
        pause()
        states = wanted.map { profile in
            if var previous = states.first(where: { $0.id == profile.id && $0.profile.directory == profile.directory }) {
                previous.profile = profile; previous.checking = false
                return previous
            }
            return CodexProfileLimitsState(profile: profile)
        }
        if wasVisible { pageDidAppear() }
    }

    func pageDidAppear() {
        synchronize()
        guard enabled else { return }
        visible = true
        refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        visible = false
        timer?.invalidate(); timer = nil
        cancellation.cancel(); generation += 1; inFlight = false
        for index in states.indices {
            if states[index].checking { states[index].attempted = nil }
            states[index].checking = false
        }
    }

    func refresh(id: String? = nil, force: Bool = false) {
        guard enabled, !inFlight, visible || force else { return }
        let now = Date()
        let requested = states.filter {
            let renewed = $0.limits?.windows.contains { ($0.resetsAt ?? .distantFuture) <= now } == true
            let interval: TimeInterval = $0.error == nil ? (renewed ? 30 : CodexAccountUsageReader.refreshInterval) : 60
            return (id == nil || $0.id == id) && (force || now.timeIntervalSince($0.attempted ?? .distantPast) >= interval)
        }.map(\.profile)
        guard !requested.isEmpty else { return }
        inFlight = true
        cancellation = BoundedProcessCancellation()
        let token = cancellation, currentGeneration = generation
        for index in states.indices where requested.contains(states[index].profile) {
            states[index].checking = true; states[index].attempted = now
        }
        let apps = reader == nil ? AgentCodexServer.appIdentifiers.flatMap {
            NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0)
        } : []
        let read = reader
        queue.async { [weak self] in
            for profile in requested {
                if token.isCancelled { break }
                let result: Result<(limits: AgentLimits, plan: String?), Error>
                do {
                    if let read { result = .success(try read(profile, token)) }
                    else {
                        guard let executable = CodexAccountUsageReader.executable(apps: apps) else {
                            throw CodexAccountUsageError.missingCLI
                        }
                        result = .success(try CodexAccountUsageReader.read(profile, executable: executable, cancellation: token))
                    }
                } catch { result = .failure(error) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration, !token.isCancelled,
                          let index = self.states.firstIndex(where: { $0.profile == profile }) else { return }
                    self.states[index].checking = false
                    switch result {
                    case .success(let reading):
                        self.states[index].limits = reading.limits; self.states[index].plan = reading.plan
                        self.states[index].error = nil
                    case .failure(let error):
                        if (error as? AgentCodexServer.Failure) == .needsSignIn
                            || (error as? CodexAccountUsageError) == .invalidProfile {
                            self.states[index].limits = nil; self.states[index].plan = nil
                        }
                        self.states[index].error = Self.message(error)
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.inFlight = false
            }
        }
    }

    private static func message(_ error: Error) -> String {
        let language = L10n.shared.language
        let text = CodexAccountStrings.localized(language)
        switch error {
        case CodexAccountUsageError.missingCLI: return FeatureStrings.notchAgents(language).resetsNeedCodex
        case CodexAccountUsageError.invalidProfile: return text.chooseFolder
        case AgentCodexServer.Failure.needsSignIn: return text.signIn
        case AgentCodexServer.Failure.outdated: return text.update
        case CodexAccountUsageError.cancelled: return text.cancelled
        default: return text.failed
        }
    }
}
