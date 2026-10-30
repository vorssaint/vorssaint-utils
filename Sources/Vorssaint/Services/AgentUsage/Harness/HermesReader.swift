// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Hermes Agent's running totals as handed over by `AgentHermesReader`.
/// Hermes only drives models on other accounts, so each total is given to
/// the card of the account it was billed to and Hermes keeps no card or turn
/// of its own.
struct HermesReader: AgentHarnessReader {
    var provider: AgentProvider { .hermes }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line) else { return [] }
        switch json["type"] as? String {
        case "usage_snapshot":
            guard let rows = json["records"] as? [[String: Any]] else { return [] }
            return [.usageCounters(rows.compactMap(counter))]
        case "reset":
            return [.reset(now)]
        default:
            return []
        }
    }

    private func counter(_ row: [String: Any]) -> AgentUsageCounter? {
        guard let key = row["key"] as? String, !key.isEmpty,
              let session = row["session_id"] as? String,
              let provider = (row["provider"] as? String).flatMap(AgentProvider.init(rawValue:)),
              provider == .claude || provider == .codex,
              let date = AgentLogParser.seconds(row["time_created"]) else { return nil }
        let tokens = AgentTokens(input: AgentLogParser.int(row["input_tokens"]),
                                 cacheWrite: AgentLogParser.int(row["cache_write_tokens"]),
                                 cacheRead: AgentLogParser.int(row["cache_read_tokens"]),
                                 output: AgentLogParser.int(row["output_tokens"]),
                                 reasoning: AgentLogParser.int(row["reasoning_tokens"]))
        let record = AgentUsageRecord(provider: provider, date: date,
            model: AgentLogParser.native(row["model"] as? String ?? ""),
            project: AgentLogParser.projectName(row["directory"] as? String ?? ""),
            session: AgentLogParser.native(session), requests: AgentLogParser.int(row["requests"]),
            tokens: tokens, cost: nil, savings: 0)
        return AgentUsageCounter(key: key, record: record)
    }
}
