// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// The Codex account's banked resets for the AI page: read when their card
/// shows, at most every few minutes, and used only when the person confirms.
final class AgentCodexResetService: ObservableObject {
    static let shared = AgentCodexResetService()

    /// A use of a reset that ended, told on the card for a moment.
    struct Finished: Equatable {
        /// Nil when the server never answered.
        let outcome: AgentCodexServer.Outcome?
        let date: Date
    }

    @Published private(set) var summary: AgentCodexResetSummary?
    @Published private(set) var failure: AgentCodexServer.Failure?
    @Published private(set) var checking = false
    @Published private(set) var redeeming = false
    @Published private(set) var finished: Finished?

    /// A reading this recent still stands; a failed one is tried sooner.
    static let freshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 60
    /// Long enough for any reply still on its way; after it, a fresh reading
    /// tells whether an unanswered use happened.
    static let retryWindow: TimeInterval = 10 * 60

    private let queue = DispatchQueue(label: "com.vorssaint.codex-resets", qos: .userInitiated)
    private var attempted = Date.distantPast
    /// A Terminal window's PATH, asked of the login shell only when the
    /// person looks again for a Codex that was not found: that runs their
    /// shell's startup files.
    private var shellPath: String?
    /// One use of a reset, kept until the server answers it, so trying the
    /// same use again after a lost reply never spends a second one.
    private struct Attempt {
        let key: String
        let credit: String?
        let date: Date
    }
    private var pending: Attempt?

    private init() {}

    func refreshIfStale(now: Date = Date()) {
        // Only the person can sign Codex in or update it, so those wait as long as a reading.
        let settled = failure == nil || failure == .needsSignIn || failure == .outdated
        guard now.timeIntervalSince(attempted) >= (settled ? Self.freshness : Self.retryAfter) else { return }
        refresh()
    }

    func refresh(searchingShell: Bool = false) {
        guard !checking, !redeeming else { return }
        checking = true
        attempted = Date()
        let apps = Self.apps()
        let known = shellPath
        queue.async { [weak self] in
            let path = searchingShell && known == nil ? Self.loginShellPath() : known
            let result: Result<AgentCodexResetSummary, AgentCodexServer.Failure>
            if let executable = Self.executable(apps: apps, searchPath: path) {
                result = AgentCodexServer.check(executable, environment: AgentCodexServer.environment(for: executable,
                                                                                                     searchPath: path))
            } else {
                result = .failure(.missing)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.shellPath = path
                self.checking = false
                switch result {
                case .success(let summary): self.accept(summary)
                case .failure(let failure): self.fail(failure)
                }
            }
        }
    }

    /// Waits behind a check still running, then uses the reset that expires
    /// first, or tries the use that went unanswered again.
    func redeem() {
        guard !redeeming, let summary, summary.available > 0 else { return }
        redeeming = true
        let now = Date()
        let attempt = pending.flatMap { now.timeIntervalSince($0.date) < Self.retryWindow ? $0 : nil }
            ?? Attempt(key: UUID().uuidString, credit: summary.resets.first?.id, date: now)
        pending = attempt
        let apps = Self.apps()
        let path = shellPath
        queue.async { [weak self] in
            guard let executable = Self.executable(apps: apps, searchPath: path) else {
                DispatchQueue.main.async { self?.finishRedeem(.failure(.missing), summary: nil) }
                return
            }
            let result = AgentCodexServer.redeem(executable, environment: AgentCodexServer.environment(for: executable,
                                                                                                      searchPath: path),
                                                 credit: attempt.credit, key: attempt.key)
            DispatchQueue.main.async { self?.finishRedeem(result.outcome, summary: result.summary) }
        }
    }

    private func finishRedeem(_ outcome: Result<AgentCodexServer.Outcome, AgentCodexServer.Failure>,
                              summary: AgentCodexResetSummary?) {
        redeeming = false
        switch outcome {
        case .success(let outcome):
            pending = nil
            finished = Finished(outcome: outcome, date: Date())
        case .failure(.unreachable), .failure(.refused):
            // No outcome came back. Codex also answers with an error when its
            // own request to the account timed out or its reply was lost, so
            // the use may have happened on the way: it keeps its key.
            finished = Finished(outcome: nil, date: Date())
        case .failure(let failure):
            pending = nil
            fail(failure)
        }
        if let summary { accept(summary) } else if [nil, .unreachable, .refused].contains(self.failure) { refresh() }
    }

    private func accept(_ summary: AgentCodexResetSummary) {
        self.summary = summary
        failure = nil
        attempted = summary.checkedAt
        if let limits = summary.limits { AgentUsageService.shared.noteLimits(limits) }
    }

    private func fail(_ failure: AgentCodexServer.Failure) {
        self.failure = failure
        // A lost or refused reply leaves the last count standing; the rest make it moot.
        if failure != .unreachable, failure != .refused { summary = nil }
    }

    private static func apps() -> [URL] {
        AgentCodexServer.appIdentifiers.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
    }

    private static func executable(apps: [URL], searchPath: String?) -> URL? {
        AgentCodexServer.executable(apps: apps, home: FileManager.default.homeDirectoryForCurrentUser,
                                    searchPath: searchPath)
    }

    private static func loginShellPath() -> String? {
        HomebrewEnvironment.loginShellExports(shellPath: HomebrewCommandBuilder.currentShellPath)["PATH"]
    }
}
