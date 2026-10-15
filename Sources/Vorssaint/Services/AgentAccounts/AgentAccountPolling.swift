// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// When each saved login is next asked for its limits. The providers allow
/// few such requests, about thirty an hour for a Claude login, and answer
/// too many with a block that can last over an hour: every rule here spends
/// that allowance where a fresh reading matters.
struct AgentAccountPolling {
    /// The login in use, which is the one whose limits move.
    static let activeInterval: TimeInterval = 5 * 60
    /// The login in use once it nears the point of an automatic swap.
    static let urgentInterval: TimeInterval = 2 * 60
    static let idleInterval: TimeInterval = 10 * 60
    /// The other logins while one of them may be swapped to any minute: a
    /// swap needs a reading no older than `AgentAutoSwap.freshness`.
    static let candidateInterval: TimeInterval = 5 * 60
    /// Opening the page reads again what is older than this.
    static let appearAge: TimeInterval = 3 * 60
    /// Never two requests for one login closer together than this.
    static let minimumGap: TimeInterval = 2 * 60
    /// Within this many points of the threshold, a login is near it.
    static let urgentMargin = 15.0
    static let maximumBackoff: TimeInterval = 10 * 60

    /// How a login is read just now.
    enum Pace {
        case active, urgent, candidate, idle

        var interval: TimeInterval {
            switch self {
            case .active: return AgentAccountPolling.activeInterval
            case .urgent: return AgentAccountPolling.urgentInterval
            case .candidate: return AgentAccountPolling.candidateInterval
            case .idle: return AgentAccountPolling.idleInterval
            }
        }
    }

    private struct Entry {
        var attempted: Date
        var succeeded: Date?
        var failures = 0
        /// After a failure, nothing is asked before this.
        var waitUntil: Date?
    }

    private var entries: [AgentAccount.ID: Entry] = [:]

    func isDue(_ id: AgentAccount.ID, pace: Pace, appeared: Bool = false, now: Date) -> Bool {
        guard let entry = entries[id] else { return true }
        guard now.timeIntervalSince(entry.attempted) >= Self.minimumGap else { return false }
        if let wait = entry.waitUntil { return now >= wait }
        guard let succeeded = entry.succeeded else { return true }
        return now.timeIntervalSince(succeeded) >= (appeared ? min(Self.appearAge, pace.interval) : pace.interval)
    }

    mutating func succeeded(_ id: AgentAccount.ID, now: Date) {
        entries[id] = Entry(attempted: now, succeeded: now)
    }

    mutating func failed(_ id: AgentAccount.ID, _ failure: AgentUsageFailure, now: Date) {
        var entry = entries[id] ?? Entry(attempted: now)
        entry.attempted = now
        entry.failures += 1
        if case .rateLimited(let retryAfter) = failure {
            entry.waitUntil = now.addingTimeInterval(Self.hold(retryAfter: retryAfter))
        } else {
            entry.waitUntil = now.addingTimeInterval(Self.backoff(failures: entry.failures))
        }
        entries[id] = entry
    }

    /// A login saved again or removed starts over.
    mutating func forget(_ id: AgentAccount.ID) {
        entries[id] = nil
    }

    /// One minute, then twice as long after each further failure, up to ten.
    static func backoff(failures: Int) -> TimeInterval {
        min(maximumBackoff, 60 * pow(2, Double(max(0, min(failures, 10) - 1))))
    }

    /// How long a login rests after the provider said it asked too often:
    /// well past what it named, since asking early extends the block.
    static func hold(retryAfter: TimeInterval?) -> TimeInterval {
        max(20 * 60, (retryAfter ?? 0) + 15 * 60)
    }

    /// Whether a login's use is close enough to the threshold to watch it
    /// more often.
    static func isNear(_ limits: AgentLimits?, threshold: Double) -> Bool {
        guard let used = AgentAutoSwap.binding(limits) else { return false }
        return used >= threshold - urgentMargin
    }
}
