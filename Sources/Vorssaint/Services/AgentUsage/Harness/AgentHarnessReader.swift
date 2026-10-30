// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One harness's log line parser, chosen by `AgentProvider.reader`. What it
/// carries from line to line lives in the shared `AgentLogState`.
protocol AgentHarnessReader {
    /// The provider this reader parses for.
    var provider: AgentProvider { get }
    /// What one log line says, reduced to the facts the island keeps.
    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry]
    /// True when a log's first reading goes through `readCopilotHistory`,
    /// which passes on only Copilot's event lines; only Copilot sets it.
    var readsFullHistoryFirst: Bool { get }
}

extension AgentHarnessReader {
    var readsFullHistoryFirst: Bool { false }
}

extension AgentProvider {
    /// The reader that parses this provider's logs.
    var reader: any AgentHarnessReader {
        switch self {
        case .claude: ClaudeReader()
        case .codex: CodexReader()
        case .opencode: OpenCodeReader()
        case .copilot: CopilotReader()
        case .antigravity: AntigravityReader()
        }
    }
}
