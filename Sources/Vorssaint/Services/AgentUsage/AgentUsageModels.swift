// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The coding agents whose session logs the island reads. Their names are
/// product names and stay untranslated.
enum AgentProvider: String, CaseIterable, Identifiable, Codable {
    case claude, codex, opencode, copilot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .copilot: return "GitHub Copilot"
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .opencode: return "terminal"
        case .copilot: return "infinity"
        }
    }

    /// Whether the provider records a plan allowance in its local logs.
    var reportsLimits: Bool { self != .copilot }
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
    /// Model requests represented by this record; checkpoints may hold several.
    let requests: Int
    var tokens: AgentTokens
    /// What the response would cost at API list prices, in US dollars. Nil
    /// when the model has no known price.
    var cost: Double?
    /// What cache reads saved against paying the full input price.
    var savings: Double
    /// Whether cost was reported directly by the provider rather than derived from list pricing.
    var reportedCost: Bool = false
    /// The service OpenCode routed this response to, independently of the agent.
    var serviceID: String?

    init(provider: AgentProvider, date: Date, model: String, project: String, session: String,
         requests: Int = 1, tokens: AgentTokens, cost: Double?, savings: Double, reportedCost: Bool = false,
         serviceID: String? = nil) {
        self.provider = provider
        self.date = date
        self.model = model
        self.project = project
        self.session = session
        self.requests = requests
        self.tokens = tokens
        self.cost = cost
        self.savings = savings
        self.reportedCost = reportedCost
        self.serviceID = AgentModelService.identifier(serviceID)
    }

    var modelShareID: String { provider.rawValue + ":" + (serviceID ?? "") + ":" + model }
    var serviceShareID: String { provider.rawValue + ":" + (serviceID ?? "") }
    var serviceName: String { serviceID.map(AgentModelService.name) ?? provider.displayName }
    var isFreeModel: Bool {
        (serviceID == "openrouter" && (model.hasSuffix(":free") || model == "openrouter/free"))
            || (serviceID == "opencode" && model.hasSuffix("-free"))
    }
}

/// Provider identifiers are metadata, never URLs, credentials or inferred model vendors.
enum AgentModelService {
    static func identifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 128,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || [45, 46, 95].contains($0) }) else { return nil }
        return value.lowercased()
    }

    static func name(_ id: String) -> String {
        switch id {
        case "opencode": return "OpenCode Zen"
        case "opencode-go": return "OpenCode Go"
        case "github-copilot": return "GitHub Copilot"
        case "github-copilot-enterprise": return "GitHub Copilot Enterprise"
        case "antigravity", "google-antigravity": return "Antigravity"
        case "cursor": return "Cursor"
        case "groq": return "GroqCloud"
        case "openrouter": return "OpenRouter"
        case "mistral": return "Mistral API"
        case "cloudflare-workers-ai": return "Cloudflare Workers AI"
        case "cloudflare-ai-gateway": return "Cloudflare AI Gateway"
        case "grok-build": return "Grok Build"
        case "xai": return "xAI API"
        case "ollama-cloud": return "Ollama Cloud"
        case "ollama": return "Ollama"
        case "anthropic": return "Anthropic API"
        case "openai": return "OpenAI API"
        case "google": return "Google AI"
        default: return id
        }
    }
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
    /// A presentation estimate, never a deadline for clearing usage or alerts.
    var estimatedResetsAt: Date? = nil

    var usedFraction: Double { min(1, max(0, usedPercent / 100)) }
    var remainingFraction: Double { 1 - usedFraction }
}

struct AgentLimits: Equatable {
    enum Source: Equatable {
        /// Saved on this Mac by the Claude app, which checks them itself.
        case claudeApp
        /// Copied by the agent into its session log with each response.
        case sessionLog
        /// Asked of the agent on request, which checks the account itself.
        case account
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
