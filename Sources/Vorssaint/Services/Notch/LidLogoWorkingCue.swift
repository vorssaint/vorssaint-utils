// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Schedules the working indication. The completion cue owns all hardware writes and recovery.
@MainActor
final class LidLogoWorkingCue {
    enum StartResult { case started, busy, unavailable }

    private let startBreath: () -> StartResult
    private let stopBreath: () -> Void
    private let startupDelay: TimeInterval
    private let cycleDuration: TimeInterval
    private let busyRetryDelay: TimeInterval
    private let unavailableRetryDelay: TimeInterval
    private var expires: Date?
    private var nextAttempt: ContinuousClock.Instant?
    private var task: Task<Void, Never>?

    init(startBreath: @escaping () -> StartResult, stopBreath: @escaping () -> Void,
         startupDelay: TimeInterval = 2, cycleDuration: TimeInterval = 6.5,
         busyRetryDelay: TimeInterval = 2, unavailableRetryDelay: TimeInterval = 20) {
        self.startBreath = startBreath
        self.stopBreath = stopBreath
        self.startupDelay = startupDelay
        self.cycleDuration = cycleDuration
        self.busyRetryDelay = busyRetryDelay
        self.unavailableRetryDelay = unavailableRetryDelay
    }

    nonisolated static func expiration(for sessions: [AgentLiveSession], enabledProviders: [AgentProvider],
                                      now: Date = Date()) -> Date? {
        guard let last = sessions.lazy.filter({ enabledProviders.contains($0.provider) }).map(\.lastActivity).max()
        else { return nil }
        // Use the same silence limit as the live Agents view, even if its log reader has stopped publishing.
        let expiration = last.addingTimeInterval(NotchAgentSupport.idleTurn)
        return expiration > now ? expiration : nil
    }

    func update(expires: Date?) {
        let now = Date()
        guard let expires, expires > now else { stop(); return }
        // A departing agent can move the deadline earlier while another agent is still working.
        let nowOnClock = ContinuousClock.now
        let attempt = nextAttempt ?? nowOnClock + .seconds(startupDelay)
        let untilAttempt = attempt - nowOnClock
        let oldDelay = self.expires.map { min(.seconds($0.timeIntervalSince(now)), untilAttempt) }
        let newDelay = min(.seconds(expires.timeIntervalSince(now)), untilAttempt)
        self.expires = expires
        nextAttempt = attempt
        if task == nil || oldDelay != newDelay { schedule() }
    }

    func stop() {
        task?.cancel()
        task = nil
        expires = nil
        guard nextAttempt != nil else { return }
        nextAttempt = nil
        stopBreath()
    }

    private func schedule() {
        guard let expires, let nextAttempt else { return }
        task?.cancel()
        let delay = max(.zero, min(.seconds(expires.timeIntervalSinceNow), nextAttempt - ContinuousClock.now))
        task = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func advance() {
        let now = Date()
        guard let expires, expires > now, let nextAttempt else { stop(); return }
        let nowOnClock = ContinuousClock.now
        if nextAttempt <= nowOnClock {
            let delay: TimeInterval
            switch startBreath() {
            case .started: delay = cycleDuration
            case .busy: delay = busyRetryDelay
            case .unavailable: delay = unavailableRetryDelay
            }
            self.nextAttempt = nowOnClock + .seconds(delay)
        }
        schedule()
    }
}
