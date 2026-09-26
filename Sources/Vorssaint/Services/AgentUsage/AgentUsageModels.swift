// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The coding agents whose session logs the island reads. Their names are
/// product names and stay untranslated.
enum AgentProvider: String, CaseIterable, Identifiable, Codable {
    case claude, codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Token counts in the shape both logs can be reduced to. `input` excludes
/// cache traffic, and `output` already contains the reasoning tokens.
struct AgentTokens: Equatable {
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0
    var reasoning = 0

    var total: Int { input + cacheWrite + cacheRead + output }
    /// Everything the model read, cached or not.
    var prompt: Int { input + cacheWrite + cacheRead }
    var cacheHitRate: Double? { prompt > 0 ? Double(cacheRead) / Double(prompt) : nil }

    static func += (lhs: inout AgentTokens, rhs: AgentTokens) {
        lhs.input += rhs.input
        lhs.cacheWrite += rhs.cacheWrite
        lhs.cacheRead += rhs.cacheRead
        lhs.output += rhs.output
        lhs.reasoning += rhs.reasoning
    }

    /// Streamed replies are logged once per content block, and the earlier
    /// blocks carry the output counted so far. The largest reading is final.
    func merged(with other: AgentTokens) -> AgentTokens {
        AgentTokens(input: max(input, other.input), cacheWrite: max(cacheWrite, other.cacheWrite),
                    cacheRead: max(cacheRead, other.cacheRead), output: max(output, other.output),
                    reasoning: max(reasoning, other.reasoning))
    }
}

/// One billed model response.
struct AgentUsageRecord: Equatable {
    let provider: AgentProvider
    let date: Date
    let model: String
    let project: String
    let session: String
    var tokens: AgentTokens
    /// What the response would cost at API list prices, in US dollars. Nil
    /// when the model has no known price.
    var cost: Double?
    /// What cache reads saved against paying the full input price.
    var savings: Double
}

/// A usage allowance and how much of it is spent, as the provider reports it.
struct AgentLimitWindow: Equatable, Identifiable {
    enum Kind: String {
        case session, weekly, other
    }

    let id: String
    let kind: Kind
    /// How long the window lasts, when the provider says so.
    let minutes: Int?
    /// A model the allowance applies to; nil when it covers everything.
    let scope: String?
    let usedPercent: Double
    let resetsAt: Date?

    var usedFraction: Double { min(1, max(0, usedPercent / 100)) }
    var remainingFraction: Double { 1 - usedFraction }
}

struct AgentLimits: Equatable {
    enum Source: Equatable {
        /// Saved on this Mac by the Claude app, which checks them itself.
        case claudeApp
        /// Copied by the agent into its session log with each response.
        case sessionLog
    }

    let provider: AgentProvider
    var windows: [AgentLimitWindow]
    let observedAt: Date
    let source: Source
}

/// The subscription an account is on, when the agent's local files say.
struct AgentPlan: Equatable {
    let name: String
    /// Monthly list price in US dollars, used only to compare API value.
    let monthlyPrice: Double?
}

/// A turn an agent is working on right now, from its session log.
struct AgentLiveSession: Equatable, Identifiable {
    let id: String
    let provider: AgentProvider
    let started: Date
    var lastActivity: Date
    var model: String
    var project: String
    var tokens: AgentTokens
    var cost: Double
}

/// Something worth a moment in the closed island.
enum AgentUsageEvent: Equatable {
    case finished(provider: AgentProvider, duration: TimeInterval, cost: Double, tokens: Int, project: String)
    case limitWarning(provider: AgentProvider, window: AgentLimitWindow)
    case limitReset(provider: AgentProvider, window: AgentLimitWindow)
    case budgetReached(spent: Double, budget: Double)
}
