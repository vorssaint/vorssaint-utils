// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Antigravity `.system_generated/logs/transcript.jsonl` files.
/// Only step metadata, model identifiers, timestamps and token counters are
/// inspected; prompts, thoughts and response bodies are never decoded.
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let obj = AgentLogObject(line), let type = obj.string("type") else { return [] }
        let date = AgentLogParser.timestamp(obj.value("created_at")) ?? now
        let status = obj.string("status") ?? ""
        let stepIndex = AgentLogParser.int(obj.value("step_index"))

        switch type {
        case "USER_INPUT":
            state.turnOpen = true
            var entries: [AgentLogEntry] = [.turnBegan(date)]
            if !state.model.isEmpty || !state.project.isEmpty {
                entries.append(.turnContext(model: state.model, project: state.project))
            }
            return entries

        case "PLANNER_RESPONSE":
            if let rawModel = obj.string("model"), !rawModel.isEmpty {
                state.model = AgentLogParser.native(rawModel)
            }
            var entries: [AgentLogEntry] = []
            let tokens = Self.tokens(from: obj)
            if tokens.total > 0 {
                let model = state.model
                let billable = AgentBillable(tokens: tokens)
                let priced = AgentPricing.cost(billable, model: model)
                let sessionKey = state.session.isEmpty ? "session" : state.session
                let record = AgentUsageRecord(
                    provider: .antigravity,
                    date: date,
                    model: model,
                    project: state.project,
                    session: state.session,
                    requests: 1,
                    tokens: tokens,
                    cost: priced.cost,
                    savings: priced.savings
                )
                entries.append(.usage(key: "ag:\(sessionKey):\(stepIndex)", record: record, billable: billable))
            }
            if !state.turnOpen && status != "DONE" && status != "ERROR" {
                state.turnOpen = true
                entries.append(.turnBegan(date))
            }
            if state.turnOpen && (!state.model.isEmpty || !state.project.isEmpty) {
                entries.append(.turnContext(model: state.model, project: state.project))
            }
            let hasToolCalls = obj.hasItems("tool_calls")
            if status == "ERROR" {
                if state.turnOpen {
                    state.turnOpen = false
                    entries.append(.turnEnded(date, completed: false, duration: nil))
                }
            } else if status == "DONE" && !hasToolCalls {
                if state.turnOpen {
                    state.turnOpen = false
                    entries.append(.turnEnded(date, completed: true, duration: nil))
                }
            } else if state.turnOpen {
                entries.append(.turnActive(date))
            }
            return entries

        case "CHECKPOINT":
            var entries: [AgentLogEntry] = []
            let tokens = Self.tokens(from: obj)
            if tokens.total > 0 {
                let billable = AgentBillable(tokens: tokens)
                let priced = AgentPricing.cost(billable, model: state.model)
                let sessionKey = state.session.isEmpty ? "session" : state.session
                let record = AgentUsageRecord(
                    provider: .antigravity,
                    date: date,
                    model: state.model,
                    project: state.project,
                    session: state.session,
                    requests: 0,
                    tokens: tokens,
                    cost: priced.cost,
                    savings: priced.savings
                )
                entries.append(.usage(key: "ag:\(sessionKey):cp:\(stepIndex)", record: record, billable: billable))
            }
            if state.turnOpen {
                entries.append(.turnActive(date))
            }
            return entries

        case "ERROR_MESSAGE":
            if state.turnOpen {
                state.turnOpen = false
                return [.turnEnded(date, completed: false, duration: nil)]
            }
            return []

        case "GENERIC", "SYSTEM_MESSAGE", "EPHEMERAL_MESSAGE":
            return state.turnOpen ? [.turnActive(date)] : []

        default:
            return []
        }
    }

    private static func tokens(from obj: AgentLogObject) -> AgentTokens {
        AgentTokens(
            input: AgentLogParser.int(obj.value("input_tokens")),
            cacheWrite: 0,
            cacheRead: AgentLogParser.int(obj.value("cache_read_tokens")),
            output: AgentLogParser.int(obj.value("output_tokens")),
            reasoning: 0
        )
    }
}

extension AgentLogParser {
    static func parseAntigravity(_ line: Data, state: inout AgentLogState, now: Date = Date()) -> [AgentLogEntry] {
        AntigravityReader().parse(line, state: &state, now: now)
    }
}
