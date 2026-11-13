// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DeepSeekReader: AgentHarnessReader {
    var provider: AgentProvider { .deepseek }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line), let type = json["type"] as? String else { return [] }
        let data = json["data"] as? [String: Any] ?? [:]
        if type == "session" {
            state.deepseekReady = (json["version"] as? Int) == 4
            state.deepseekSeeded = json["isSeeded"] as? Bool == true
            state.deepseekSubagent = AgentLogParser.int(json["delegationDepth"]) > 0
            if let id = json["id"] as? String { state.session = AgentLogParser.native(id) }
            if let cwd = json["cwd"] as? String { state.project = AgentLogParser.projectName(cwd) }
            return []
        }
        guard state.deepseekReady else { return [] }
        if state.deepseekSeeded {
            if type == "session/end-seed", data["inherited"] as? Bool == true { state.deepseekSeeded = false }
            return []
        }
        guard let time = json["time"] as? NSNumber, time.doubleValue.isFinite else { return [] }
        let date = Date(timeIntervalSince1970: time.doubleValue / 1000)
        switch type {
        case "turn/start":
            guard !state.deepseekSubagent else { return [] }
            state.turnOpen = true
            return [.turnBegan(date), .turnContext(model: state.model, project: state.project)]
        case "turn/end":
            let open = state.turnOpen
            state.turnOpen = false
            guard open else { return [] }
            let reason = (data["reason"] as? [String: Any])?["kind"] as? String
            return [.turnEnded(date, completed: reason == "completed" || reason == "max-tokens", duration: nil)]
        case "assistant/message":
            let message = data["message"] as? [String: Any] ?? [:]
            let source = message["source"] as? [String: Any] ?? [:]
            if let model = source["model"] as? String, !model.isEmpty { state.model = AgentLogParser.native(model) }
            var entries: [AgentLogEntry] = []
            if let usage = data["usage"] as? [String: Any], let model = source["model"] as? String,
               !model.isEmpty, let sequence = json["seq"] as? Int, sequence >= 0 {
                let tokens = AgentTokens(input: AgentLogParser.int(usage["inputTokens"]),
                                         cacheWrite: AgentLogParser.int(usage["cacheWriteTokens"]),
                                         cacheRead: AgentLogParser.int(usage["cacheReadTokens"]),
                                         output: AgentLogParser.int(usage["outputTokens"]),
                                         reasoning: AgentLogParser.int(usage["reasoningTokens"]))
                let billable = AgentBillable(tokens: tokens)
                let priced = AgentPricing.cost(billable, model: model)
                entries.append(.usage(key: "deepseek:\(state.session):\(sequence)", record: AgentUsageRecord(
                    provider: .deepseek, date: date, model: AgentLogParser.native(model), project: state.project,
                    session: state.session, tokens: tokens, cost: priced.cost, savings: priced.savings), billable: billable))
            }
            if state.turnOpen { entries += [.turnContext(model: state.model, project: state.project), .turnActive(date)] }
            return entries
        default:
            return state.turnOpen && ["step/start", "step/end", "tool/call", "tool/result"].contains(type)
                ? [.turnActive(date)] : []
        }
    }
}
