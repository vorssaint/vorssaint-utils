// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

struct ClaudeProfileLimitsState: Equatable, Identifiable {
    var profile: ClaudeAccountProfile
    var limits: AgentLimits?
    var plan: String?
    var checking = false
    var error: String?
    var attempted: Date?
    var id: String { profile.id }

    /// A renewed window has unknown usage until the next successful check.
    func currentLimits(at now: Date) -> AgentLimits? {
        guard var limits else { return nil }
        limits.windows.removeAll { ($0.resetsAt ?? .distantPast) <= now }
        return limits.windows.isEmpty ? nil : limits
    }
}

/// Each CLI invocation has its own config and secure-storage namespace.
/// Only percentages and reset times survive it. Reads are sequential and
/// bounded, run while the AI page is open, and stop on lock or disable.
final class ClaudeProfileLimitsService: ObservableObject {
    static let shared = ClaudeProfileLimitsService()
    @Published private(set) var states: [ClaudeProfileLimitsState] = []
    private let queue = DispatchQueue(label: "com.vorssaint.claude-profile-limits", qos: .utility)
    private var cancellation = BoundedProcessCancellation()
    private var generation = 0
    private var timer: Timer?
    private var visible = false
    private var inFlight = false

    func synchronize() {
        if !NotchAgentSupport.isEnabled() || !UserDefaults.standard.bool(forKey: DefaultsKey.notchAgentsClaude) { pause() }
        let wanted = ClaudeAccountProfile.decode(UserDefaults.standard.string(forKey: DefaultsKey.notchAgentsClaudeProfiles) ?? "")
        if states.map(\.profile) != wanted {
            pause()
            states = wanted.map { profile in
                if var previous = states.first(where: { $0.id == profile.id && $0.profile.directory == profile.directory }) {
                    previous.profile = profile; previous.checking = false
                    return previous
                }
                return ClaudeProfileLimitsState(profile: profile)
            }
        }
    }

    func pageDidAppear() {
        synchronize()
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
        guard NotchAgentSupport.isEnabled(), UserDefaults.standard.bool(forKey: DefaultsKey.notchAgentsClaude),
              !inFlight, visible || force else { return }
        let now = Date()
        let requested = states.filter {
            let renewed = $0.limits?.windows.contains { ($0.resetsAt ?? .distantFuture) <= now } == true
            let interval: TimeInterval = $0.error == nil ? (renewed ? 30 : ClaudeAccountUsageReader.refreshInterval) : 60
            return (id == nil || $0.id == id) && (force || now.timeIntervalSince($0.attempted ?? .distantPast) >= interval)
        }.map(\.profile)
        guard !requested.isEmpty else { return }
        inFlight = true
        cancellation = BoundedProcessCancellation()
        let token = cancellation, currentGeneration = generation
        for index in states.indices where requested.contains(states[index].profile) {
            states[index].checking = true; states[index].attempted = now
        }
        let workspaceRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.vorssaint.utils", isDirectory: true)
            .appendingPathComponent("ClaudeUsageChecks", isDirectory: true)
        queue.async { [weak self] in
            for profile in requested {
                if token.isCancelled { break }
                let result: Result<(limits: AgentLimits, plan: String?), Error>
                do {
                    guard let executable = ClaudeAccountUsageReader.executable() else { throw ClaudeAccountUsageError.missingCLI }
                    guard let workspaceRoot else { throw ClaudeAccountUsageError.unavailable }
                    result = .success(try ClaudeAccountUsageReader.read(profile, executable: executable,
                        workspace: workspaceRoot.appendingPathComponent(profile.id, isDirectory: true), cancellation: token))
                } catch { result = .failure(error) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration,
                          let index = self.states.firstIndex(where: { $0.profile == profile }) else { return }
                    self.states[index].checking = false
                    switch result {
                    case .success(let reading):
                        self.states[index].limits = reading.limits; self.states[index].plan = reading.plan
                        self.states[index].error = nil
                    case .failure(let error):
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
        switch error {
        case ClaudeAccountUsageError.missingCLI: return "Install Claude Code to check this account."
        case ClaudeAccountUsageError.invalidProfile: return "Choose this account’s Claude config folder."
        case ClaudeAccountUsageError.signedOut: return "Sign in to this account in Claude Code."
        case ClaudeAccountUsageError.cancelled: return "Check cancelled."
        default: return "Could not check limits. Try again."
        }
    }
}
