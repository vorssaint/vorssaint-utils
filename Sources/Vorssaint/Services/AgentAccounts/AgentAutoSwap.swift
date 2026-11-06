// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the automatic swap looks at for one provider.
struct AutoSwapInput {
    /// Nil when the live login is not a saved one, as while the person is
    /// signing in to another account: never swapped away from.
    let active: AgentAccountState?
    /// The provider's other saved logins.
    let candidates: [AgentAccountState]
    /// Percent of a limit at which the active login is left.
    let threshold: Double
    let now: Date
    /// The last automatic swap of this provider.
    let lastAutoSwap: Date?
    /// The active login's limits as the AI section reads them from the
    /// tool's own records, which cost no request; nil when it has none.
    let logLimits: AgentLimits?
}

enum AutoSwapDecision: Equatable {
    case stay
    /// `reason` is for logs.
    case swap(to: AgentAccount.ID, reason: String)
    /// Every login is near its limit; `nextReset` is when the first one renews.
    case exhausted(nextReset: Date?)
}

/// Decides when the active login is left for another saved one. A parent
/// agent and its subagents all draw on the active login, so its use can jump
/// between two readings: the decision takes whichever reading is newer and
/// leaves early rather than at the last percent.
enum AgentAutoSwap {
    /// A reading older than this says nothing about now.
    static let freshness: TimeInterval = 10 * 60
    /// A login this far under the threshold is worth swapping to; one any
    /// closer would be left again within minutes.
    static let hysteresis = 10.0
    /// Two logins both near the threshold would otherwise trade places.
    static let cooldown: TimeInterval = 5 * 60

    /// An automatic swap is for long runs nobody watches: with it on for any
    /// provider, limits are still read while the island is away, as with the
    /// display asleep or the Mac locked.
    static func runsWhileAway(_ providers: [AgentProvider], autoSwaps: (AgentProvider) -> Bool) -> Bool {
        providers.contains(where: autoSwaps)
    }

    /// The share of a login's tightest limit that is used, whichever window
    /// that is. Nil without a reading.
    static func binding(_ limits: AgentLimits?) -> Double? {
        limits.map { $0.windows.map(\.usedPercent).max() ?? 0 }
    }

    /// The newer of the limits fetched for the active login and the ones the
    /// AI section read.
    static func current(_ fetched: AgentLimits?, _ logged: AgentLimits?) -> AgentLimits? {
        guard let fetched else { return logged }
        guard let logged else { return fetched }
        return logged.observedAt > fetched.observedAt ? logged : fetched
    }

    static func decide(_ input: AutoSwapInput) -> AutoSwapDecision {
        func fresh(_ limits: AgentLimits) -> Bool { input.now.timeIntervalSince(limits.observedAt) <= freshness }
        guard let active = input.active, let limits = current(active.limits, input.logLimits), fresh(limits),
              let used = binding(limits), used >= input.threshold else { return .stay }
        // At the very end nothing is gained by waiting.
        if let last = input.lastAutoSwap, input.now.timeIntervalSince(last) < cooldown, used < 100 { return .stay }

        let usable = input.candidates.filter { !$0.account.needsLogin }
        let known = usable.compactMap { candidate -> (id: AgentAccount.ID, used: Double)? in
            guard let limits = candidate.limits, fresh(limits), let used = binding(limits) else { return nil }
            return (candidate.id, used)
        }
        if let target = known.filter({ $0.used <= input.threshold - hysteresis }).min(by: { $0.used < $1.used }) {
            return .swap(to: target.id, reason: "active at \(Int(used.rounded())) %, target at \(Int(target.used.rounded())) %")
        }
        // A login nobody has read lately may still have room: its reading
        // comes first, and saying that all are used up would be a guess.
        guard known.count == usable.count else { return .stay }
        let resets = ([limits] + input.candidates.compactMap(\.limits)).compactMap { nextReset($0, now: input.now) }
        return .exhausted(nextReset: resets.min())
    }

    /// When a login's tightest limit renews.
    private static func nextReset(_ limits: AgentLimits, now: Date) -> Date? {
        guard let window = limits.windows.max(by: { $0.usedPercent < $1.usedPercent }),
              let resets = window.resetsAt, resets > now else { return nil }
        return resets
    }
}
