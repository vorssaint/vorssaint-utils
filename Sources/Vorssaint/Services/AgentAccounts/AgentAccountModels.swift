// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A saved login. `id` is provider-specific and stable:
/// Claude "<accountUuid>/<organizationUuid>", Codex "<chatgpt_account_id>".
struct AgentAccount: Codable, Equatable, Identifiable {
    let id: String
    /// `.claude` or `.codex` only.
    let provider: AgentProvider
    var email: String
    /// Organization name (Claude) or plan type (Codex); shown, never compared.
    var organization: String
    /// Chosen by the person; empty shows the email.
    var label: String
    let added: Date
    /// When the credential copy was last refreshed.
    var savedAt: Date
    /// The refresh token is dead; cleared when the login is captured again.
    var needsLogin: Bool
    /// Claude: the whole `oauthAccount` object as Claude Code wrote it, which a
    /// swap writes back. Codex: empty, its identity lives inside the credential.
    var identity: Data

    var displayName: String { label.isEmpty ? email : label }
}

/// The login a provider's tool uses right now, with the credential a capture
/// copies. Read fresh each time: the tool rotates its tokens while it runs.
struct AgentLiveLogin: Equatable {
    let id: AgentAccount.ID
    let provider: AgentProvider
    let email: String
    let organization: String
    let identity: Data
    let credential: Data
}

/// What the island says about a provider's current login.
enum LiveLoginStatus: Equatable {
    case signedOut
    case saved(AgentAccount.ID)
    case unsaved(email: String)
    /// Signed in a way that has no plan to swap, such as an API key.
    case unsupported
}

/// Why a login's limits could not be read.
enum AgentUsageFailure: Error, Equatable {
    /// The saved login no longer signs in; the person has to log in again.
    case needsLogin
    /// The provider asked to wait, for `retryAfter` seconds when it said so.
    case rateLimited(retryAfter: TimeInterval?)
    /// The provider's tool is not on this Mac.
    case toolMissing
    /// Anything else; the text is for logs and support, not for the person.
    case unavailable(String)
}

/// A saved login as the island shows it.
struct AgentAccountState: Equatable, Identifiable {
    var account: AgentAccount
    var limits: AgentLimits?
    /// When `limits` were read.
    var fetchedAt: Date?
    var usageError: AgentUsageFailure?
    var isActive: Bool

    var id: AgentAccount.ID { account.id }
}

/// The last swap, for the page to say what happened and when.
struct SwapRecord: Equatable {
    let provider: AgentProvider
    /// Nil when the login swapped away from was not a saved one.
    let from: AgentAccount.ID?
    let to: AgentAccount.ID
    let date: Date
    let automatic: Bool
}

/// Something worth a moment in the closed island.
enum AgentAccountEvent: Equatable {
    /// `from` carries the limits that caused an automatic swap.
    case swapped(provider: AgentProvider, from: AgentAccountState?, to: AgentAccountState, automatic: Bool)
    /// Every saved login of the provider is near its limit.
    case exhausted(provider: AgentProvider, nextReset: Date?)
}

/// Where adding a login stands, from the tap on Add login to the saved login.
enum AddLoginState: Equatable {
    case starting(AgentProvider)
    /// Claude Code opened this page; the code it shows is typed in here.
    case claude(url: URL)
    /// Codex waits for this code to be typed into this page.
    case codex(url: URL, code: String)
    case finishing(AgentProvider)
    /// The text is the sign-in tool's own last line, for the person to read.
    case failed(AgentProvider, message: String)
    /// The provider's tool is not on this Mac.
    case toolMissing(AgentProvider)

    var provider: AgentProvider {
        switch self {
        case .starting(let provider), .finishing(let provider), .failed(let provider, _), .toolMissing(let provider):
            return provider
        case .claude: return .claude
        case .codex: return .codex
        }
    }

    /// False once it has ended and only says how.
    var isUnderWay: Bool {
        switch self {
        case .failed, .toolMissing: return false
        case .starting, .claude, .codex, .finishing: return true
        }
    }
}

/// Why the last action on the page did nothing.
enum AgentAccountError: Equatable {
    /// The provider is nil when the login to swap to is no longer saved.
    case switchFailed(AgentProvider?, AgentAccountSwitcher.SwitchFailure)
    /// Saving the live login failed; the text is for logs and support.
    case saveFailed(AgentProvider, String)
    case removeFailed(String)
}
