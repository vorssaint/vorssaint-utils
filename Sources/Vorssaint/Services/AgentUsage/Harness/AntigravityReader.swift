// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reduces the primary transcript to turn boundaries and measured model responses.
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    static let transcript = ".system_generated/logs/transcript.jsonl"

    static func sessionID(_ name: Substring) -> String? {
        guard name.count == 36, let id = UUID(uuidString: String(name)) else { return nil }
        return id.uuidString.lowercased()
    }

    /// The accepted path ends with <session>/.system_generated/logs/transcript.jsonl.
    static func location(_ path: String) -> (root: URL, session: String)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 6, let session = sessionID(parts[parts.count - 4]) else { return nil }
        let root = URL(fileURLWithPath: parts.dropLast(4).joined(separator: "/"), isDirectory: true)
        return (root, session)
    }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let log = AgentLogObject(line), let type = log.string("type", maxBytes: 32),
              let timestamp = log.string("created_at", maxBytes: 48) ?? log.string("timestamp", maxBytes: 48),
              let date = AgentTimestamp.parse(timestamp), date <= now.addingTimeInterval(5) else { return [] }
        let status = log.string("status", maxBytes: 32)

        if type == "USER_INPUT", log.string("source", maxBytes: 16) != "SYSTEM" {
            guard status != "ERROR", status != "CANCELED" else { return [] }
            state.turnOpen = true
            return [.turnBegan(date)]
        }

        var entries: [AgentLogEntry] = []
        if type == "PLANNER_RESPONSE" {
            if let usage = usage(log, date: date, session: state.session) { entries.append(usage) }
        }
        guard state.turnOpen else { return entries }
        switch type {
        case "PLANNER_RESPONSE":
            if let model = log.string("model", maxBytes: 128), !model.isEmpty {
                entries.append(.turnContext(model: model, project: ""))
            }
            if status == "ERROR" || status == "CANCELED" {
                state.turnOpen = false
                entries.append(.turnEnded(date, completed: false, duration: nil))
            } else if status == "DONE" && !log.hasItems("tool_calls") {
                state.turnOpen = false
                entries.append(.turnEnded(date, completed: true, duration: nil))
            } else {
                entries.append(.turnActive(date))
            }
        case "GENERIC", "TOOL_RESPONSE":
            entries.append(.turnActive(date))
        case "ERROR_MESSAGE":
            state.turnOpen = false
            entries.append(.turnEnded(date, completed: false, duration: nil))
        default:
            break
        }
        return entries
    }

    private func usage(_ log: AgentLogObject, date: Date, session: String) -> AgentLogEntry? {
        guard !session.isEmpty, let step = log.unsignedInteger("step_index") else { return nil }
        func count(_ field: String) -> Int {
            min(log.unsignedInteger(field) ?? 0, 1_000_000_000_000)
        }
        let output = count("output_tokens")
        let tokens = AgentTokens(input: count("input_tokens"), cacheWrite: count("cache_write_tokens"),
                                 cacheRead: count("cache_read_tokens"), output: output,
                                 reasoning: min(output, count("thinking_tokens")))
        guard tokens.total > 0 else { return nil }

        let model = log.string("model", maxBytes: 128) ?? ""
        let billable = AgentBillable(tokens: tokens)
        let price = AgentPricing.cost(billable, model: model, at: date)
        let record = AgentUsageRecord(provider: provider, date: date, model: model, project: "", session: session,
                                      tokens: tokens, cost: price.cost, savings: price.savings)
        return .usage(key: "antigravity:\(session):\(step):\(date.timeIntervalSince1970)", record: record, billable: billable)
    }
}
