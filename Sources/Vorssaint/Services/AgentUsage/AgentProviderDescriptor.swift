// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Everything that differs between the agents the island reads, in one row.
/// A new agent is a descriptor here, not a switch in the store, the archive,
/// the readers and every view.
struct AgentProviderDescriptor {
    /// Where a provider keeps its session logs.
    enum LogSource: Equatable {
        /// A folder under the home folder.
        case home(String)
        /// The folders of the Claude Code account chosen on this Mac.
        case claudeProfile
    }

    /// How the logs under a root are named.
    enum LogLayout: Equatable {
        /// Any `.jsonl` file.
        case jsonl
        /// The single database file OpenCode writes.
        case openCodeDatabase
        /// `<session>/events.jsonl`, as GitHub Copilot writes.
        case copilotSession
        /// `<workspace>/agent-transcripts/<session>[/<session>.jsonl]`.
        case cursorTranscripts
    }

    /// An account this app adds itself and whose cards the provider follows.
    enum Account: Equatable {
        case none, claude, codex
    }

    let id: AgentProvider
    let displayName: String
    let symbol: String
    /// The island's on/off switch for this agent.
    let defaultsKey: String
    /// The maker's desktop apps, the one that runs the agent first.
    let appIdentifiers: [String]
    /// What those apps name the mark they show in the menu bar.
    let menuBarImageNames: [String]
    let markScale: CGFloat
    let logSources: [LogSource]
    let logLayout: LogLayout
    /// The parser for this provider's log lines.
    let makeReader: () -> any AgentHarnessReader
    /// Whether the provider records a plan allowance in its local logs.
    let reportsLimits: Bool
    /// Whether cards follow an account this app adds itself.
    let account: Account
    /// A provider known from transcripts before any counted tokens: its cards
    /// show once its projects are found.
    let showsWithProjects: Bool
    /// A provider with no token history to chart: only its Now card shows.
    let activityOnly: Bool
    /// Whether a provider writes subagent sessions beside their session's log.
    let hasSubagentSessions: Bool
    /// Whether all of a provider's usage records are history, never a live turn.
    let usageIsHistoryOnly: Bool
    /// How long a quiet turn waits for its work to resume before it is over.
    let resumeWindow: TimeInterval
}

extension AgentProviderDescriptor {
    /// The one row per provider. Order follows `AgentProvider.allCases` so log
    /// discovery and reading keep their order.
    static let all: [AgentProviderDescriptor] = [
        AgentProviderDescriptor(
            id: .claude,
            displayName: "Claude",
            symbol: "sparkle",
            defaultsKey: DefaultsKey.notchAgentsClaude,
            appIdentifiers: [AgentClaudeAppUsage.bundleIdentifier],
            menuBarImageNames: ["TrayIconTemplate"],
            markScale: 1.45,
            logSources: [.claudeProfile],
            logLayout: .jsonl,
            makeReader: { ClaudeReader() },
            reportsLimits: true,
            account: .claude,
            showsWithProjects: false,
            activityOnly: false,
            hasSubagentSessions: true,
            usageIsHistoryOnly: false,
            resumeWindow: 3600),
        AgentProviderDescriptor(
            id: .codex,
            displayName: "Codex",
            symbol: "chevron.left.forwardslash.chevron.right",
            defaultsKey: DefaultsKey.notchAgentsCodex,
            appIdentifiers: AgentCodexServer.appIdentifiers,
            menuBarImageNames: ["chatgptTemplate"],
            markScale: 1.2,
            logSources: [.home(".codex/sessions"), .home(".codex/archived_sessions")],
            logLayout: .jsonl,
            makeReader: { CodexReader() },
            reportsLimits: true,
            account: .codex,
            showsWithProjects: false,
            activityOnly: false,
            hasSubagentSessions: false,
            usageIsHistoryOnly: false,
            resumeWindow: 6 * 3600),
        AgentProviderDescriptor(
            id: .opencode,
            displayName: "OpenCode",
            symbol: "terminal",
            defaultsKey: DefaultsKey.notchAgentsOpenCode,
            appIdentifiers: ["ai.opencode.desktop", "ai.opencode.desktop.beta", "ai.opencode.desktop.dev"],
            menuBarImageNames: [],
            markScale: 1.2,
            logSources: [.home(".local/share/opencode")],
            logLayout: .openCodeDatabase,
            makeReader: { OpenCodeReader() },
            reportsLimits: true,
            account: .none,
            showsWithProjects: false,
            activityOnly: false,
            hasSubagentSessions: false,
            usageIsHistoryOnly: false,
            resumeWindow: 6 * 3600),
        AgentProviderDescriptor(
            id: .copilot,
            displayName: "GitHub Copilot",
            symbol: "infinity",
            defaultsKey: DefaultsKey.notchAgentsCopilot,
            appIdentifiers: ["com.github.githubapp"],
            menuBarImageNames: [],
            markScale: 1.2,
            logSources: [.home(".copilot/session-state")],
            logLayout: .copilotSession,
            makeReader: { CopilotReader() },
            reportsLimits: false,
            account: .none,
            showsWithProjects: false,
            activityOnly: false,
            hasSubagentSessions: false,
            usageIsHistoryOnly: true,
            resumeWindow: 6 * 3600),
        AgentProviderDescriptor(
            id: .cursor,
            displayName: "Cursor",
            symbol: "cursorarrow",
            defaultsKey: DefaultsKey.notchAgentsCursor,
            appIdentifiers: ["com.todesktop.230313mzl4w4u92"],
            menuBarImageNames: [],
            markScale: 1.2,
            logSources: [.home(".cursor/projects")],
            logLayout: .cursorTranscripts,
            makeReader: { CursorReader() },
            reportsLimits: false,
            account: .none,
            showsWithProjects: true,
            activityOnly: true,
            hasSubagentSessions: false,
            usageIsHistoryOnly: false,
            resumeWindow: 6 * 3600)
    ]

    /// The rows by provider. Two rows for one provider would make the table
    /// ambiguous, so the table refuses to build.
    static let table: [AgentProvider: AgentProviderDescriptor] = {
        var table: [AgentProvider: AgentProviderDescriptor] = [:]
        for descriptor in all {
            precondition(table.updateValue(descriptor, forKey: descriptor.id) == nil,
                         "\(descriptor.id.rawValue) is described more than once")
        }
        return table
    }()

    /// This provider's session log folders, canonicalized by `AgentLogRoot`.
    func logRoots(home: URL, claudeProfile: ClaudeAccountProfile) -> [URL] {
        logSources.flatMap { source -> [URL] in
            switch source {
            case .home(let path): return [home.appending(path: path, directoryHint: .isDirectory)]
            case .claudeProfile: return claudeProfile.logURLs(home: home)
            }
        }
    }
}

extension AgentProvider {
    /// The row describing this provider. The exhaustive table makes this a
    /// lookup, never a switch: a missing row fails at the table's first use.
    var descriptor: AgentProviderDescriptor {
        guard let descriptor = AgentProviderDescriptor.table[self] else {
            preconditionFailure("\(rawValue) has no provider descriptor")
        }
        return descriptor
    }
}
