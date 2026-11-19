// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// The Claude account's banked resets for the AI page: read when their card
/// shows, at most every few minutes, and used only when the person confirms.
final class AgentClaudeResetService: ObservableObject {
    static let shared = AgentClaudeResetService()

    /// A use of a reset that ended, told on the card for a moment.
    struct Finished: Equatable {
        /// Nil when claude.ai never answered.
        let outcome: AgentClaudeResets.Outcome?
        let date: Date
    }

    @Published private(set) var summary: AgentClaudeResetSummary?
    @Published private(set) var failure: AgentClaudeResets.Failure?
    @Published private(set) var checking = false
    @Published private(set) var redeeming = false
    @Published private(set) var finished: Finished?

    /// claude.ai answers the usage question sparingly, so a reading stands
    /// for five minutes and a failed one is tried again after two.
    static let freshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 2 * 60
    /// Long enough for any reply still on its way; after it, a fresh reading
    /// tells whether an unanswered use happened.
    static let retryWindow: TimeInterval = 10 * 60

    private let queue = DispatchQueue(label: "com.vorssaint.claude-resets", qos: .userInitiated)
    private var attempted = Date.distantPast
    /// The Claude Code a version was read from, with that version.
    private var known: (executable: URL, modified: Date?, version: String)?
    /// One use of a reset, kept until claude.ai answers it, so trying the same
    /// use again after a lost reply never spends a second one.
    private struct Attempt {
        let key: String
        let grant: String
        let date: Date
    }
    private var pending: Attempt?

    private init() {}

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    func refreshIfStale(now: Date = Date()) {
        switch failure {
        case .busy(let until)?: guard now >= until else { return }
        case .unreachable?: guard now.timeIntervalSince(attempted) >= Self.retryAfter else { return }
        // Only the person can install or sign in to Claude Code.
        case .missing?, .needsSignIn?, nil: guard now.timeIntervalSince(attempted) >= Self.freshness else { return }
        }
        refresh()
    }

    func refresh() {
        guard ClaudeAccountProfile.selected().isDefault, !checking, !redeeming else { return }
        if case .busy(let until)? = failure, Date() < until { return }
        checking = true
        attempted = Date()
        let home = self.home
        let known = self.known
        queue.async { [weak self] in
            let prepared = Self.prepare(home: home, known: known)
            let result = prepared.flatMap { prepared in
                AgentClaudeResets.check(prepared.credentials, version: prepared.version)
                    .map { (summary: $0, organization: prepared.organization) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let prepared) = prepared { self.known = prepared.known }
                self.checking = false
                switch result {
                case .success(let answer): self.accept(answer.summary, organization: answer.organization)
                case .failure(let failure): self.fail(failure)
                }
            }
        }
    }

    /// Uses a reset of the grant the account offers next, or tries the use
    /// that went unanswered again.
    func redeem() {
        guard ClaudeAccountProfile.selected().isDefault, !redeeming, !checking, let grant = summary?.usable else { return }
        redeeming = true
        let now = Date()
        let attempt = pending.flatMap { now.timeIntervalSince($0.date) < Self.retryWindow && $0.grant == grant.id ? $0 : nil }
            ?? Attempt(key: UUID().uuidString, grant: grant.id, date: now)
        pending = attempt
        let home = self.home
        let known = self.known
        queue.async { [weak self] in
            let prepared = Self.prepare(home: home, known: known)
            let outcome: Result<AgentClaudeResets.Outcome, AgentClaudeResets.Failure> = prepared.flatMap { prepared in
                guard let organization = prepared.organization else { return .failure(.needsSignIn) }
                return AgentClaudeResets.redeem(prepared.credentials, version: prepared.version, organization: organization,
                                                grant: attempt.grant, key: attempt.key)
            }
            // A use changes the limits and the count either way, or may have.
            let after = prepared.flatMap { prepared in
                AgentClaudeResets.check(prepared.credentials, version: prepared.version)
                    .map { (summary: $0, organization: prepared.organization) }
            }
            DispatchQueue.main.async { self?.finishRedeem(outcome, after: try? after.get()) }
        }
    }

    private func finishRedeem(_ outcome: Result<AgentClaudeResets.Outcome, AgentClaudeResets.Failure>,
                              after: (summary: AgentClaudeResetSummary, organization: String?)?) {
        redeeming = false
        switch outcome {
        case .success(let outcome):
            pending = nil
            finished = Finished(outcome: outcome, date: Date())
        case .failure(.unreachable):
            // No outcome came back, and the use may have happened on the way:
            // it keeps its key.
            finished = Finished(outcome: nil, date: Date())
        case .failure(let failure):
            pending = nil
            fail(failure)
        }
        attempted = Date()
        if let after { accept(after.summary, organization: after.organization) }
    }

    private func accept(_ summary: AgentClaudeResetSummary, organization: String?) {
        self.summary = summary
        failure = nil
        attempted = summary.checkedAt
        // Limits of an account Claude Code no longer signs in to are not this one's.
        if ClaudeAccountProfile.selected().isDefault, let limits = summary.limits,
           organization == ClaudeAccountProfile().read(home: home).identity?.organization {
            AgentUsageService.shared.noteLimits(limits)
        }
    }

    private func fail(_ failure: AgentClaudeResets.Failure) {
        self.failure = failure
        // A lost or delayed answer leaves the last count standing; the rest make it moot.
        switch failure {
        case .unreachable, .busy: break
        case .missing, .needsSignIn: summary = nil
        }
    }

    // MARK: Work queue

    private struct Prepared {
        let credentials: AgentClaudeResets.Credentials
        let version: String
        let organization: String?
        let known: (executable: URL, modified: Date?, version: String)
    }

    /// Claude Code's version and a current sign-in. A sign-in about to expire
    /// is renewed by Claude Code itself, in one short conversation that asks
    /// for nothing but usage, and read again.
    private static func prepare(home: URL, known: (executable: URL, modified: Date?, version: String)?)
        -> Result<Prepared, AgentClaudeResets.Failure> {
        guard let executable = AgentClaudeServer.executable(home: home,
                                                            searchPath: ProcessInfo.processInfo.environment["PATH"])
        else { return .failure(.missing) }
        let environment = AgentCodexServer.environment(for: executable, searchPath: nil)
        let modified = (try? executable.resolvingSymlinksInPath().resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        let version: String
        if let known, known.executable == executable, known.modified == modified {
            version = known.version
        } else if let read = AgentClaudeResets.version(of: executable, environment: environment) {
            version = read
        } else {
            return .failure(.missing)
        }
        guard var credentials = AgentClaudeResets.storedCredentials(home: home) else { return .failure(.missing) }
        if !credentials.current(at: Date()) {
            var renewed = environment
            renewed.removeValue(forKey: "CLAUDECODE")
            _ = AgentClaudeServer.Request().run(executable, home: home, environment: renewed)
            guard let fresh = AgentClaudeResets.storedCredentials(home: home), fresh.current(at: Date()) else {
                return .failure(.needsSignIn)
            }
            credentials = fresh
        }
        guard credentials.readsUsage else { return .failure(.needsSignIn) }
        return .success(Prepared(credentials: credentials, version: version,
                                 organization: ClaudeAccountProfile().read(home: home).identity?.organization,
                                 known: (executable, modified, version)))
    }
}
