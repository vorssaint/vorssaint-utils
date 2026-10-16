// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One harness's line parser. Each agent owns the storage its logs keep and
/// the shape only its lines parse into, so adding a harness is a new type
/// here rather than another case across the service.
protocol AgentHarnessReader {
    /// The provider this reader parses for.
    var provider: AgentProvider { get }
    /// What one log line says, reduced to the facts the island keeps.
    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry]
    /// True when the first pass streams the whole history instead of only
    /// what was appended, as cumulative counters require.
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
        }
    }
}
