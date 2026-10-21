// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the append-only event log Copilot CLI and the GitHub Copilot app
/// share. Only session context, turn boundaries and cumulative model
/// counters are decoded; prompts, replies, reasoning and tool arguments are
/// ignored.
struct CopilotReader: AgentHarnessReader {
    var provider: AgentProvider { .copilot }

    var readsFullHistoryFirst: Bool { true }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), let type = envelope.string("type"),
              AgentLogParser.copilotEvent(type), let data = envelope.object("data") else { return [] }
        let agent = envelope.string("agentId").flatMap { $0.isEmpty ? nil : $0 }
        let root = agent == nil
        // Subagents share the root log. Their responses count as activity,
        // but their lifecycle and model changes never change the root task.
        guard root || type == "assistant.message" else { return [] }
        let date = AgentLogParser.timestamp(envelope.value("timestamp")) ?? now
        switch type {
        case "user.message", "assistant.turn_start":
            state.copilotFinalResponse = false
            state.copilotTurnID = type == "assistant.turn_start" ? data.string("turnId") : nil
            if let model = data.string("model"), !model.isEmpty { state.model = AgentLogParser.native(model) }
            let entry: AgentLogEntry = state.turnOpen ? .turnActive(date) : .turnBegan(date)
            state.turnOpen = true
            return [entry, .turnContext(model: state.model, project: state.project)]
        case "assistant.message":
            // A subagent can choose a different model; missing metadata is
            // unknown, not evidence that it used the root's selected model.
            let model = data.string("model").flatMap { $0.isEmpty ? nil : AgentLogParser.native($0) } ?? (root ? state.model : "")
            var entries = copilotActivity(data, envelope: envelope, agent: agent, model: model,
                                          date: date, state: &state)
            guard root else { return entries }
            state.model = model
            // Each tool iteration has its own turn_end. Only an iteration
            // delivering a final response can finish the person's task.
            state.copilotFinalResponse = !data.hasItems("toolRequests")
                && !["thinking", "commentary"].contains(data.string("phase") ?? "")
            if state.turnOpen {
                entries += [.turnContext(model: state.model, project: state.project), .turnActive(date)]
            }
            return entries
        case "assistant.turn_end":
            guard state.turnOpen,
                  state.copilotTurnID == nil || state.copilotTurnID == data.string("turnId") else { return [] }
            guard state.copilotFinalResponse else { return [.turnActive(date)] }
            state.turnOpen = false
            state.copilotFinalResponse = false
            return [.turnEnded(date, completed: true, duration: nil)]
        case "session.start":
            if let session = data.string("sessionId"), !session.isEmpty {
                state.session = AgentLogParser.native(session)
            }
            if let model = data.string("selectedModel"), !model.isEmpty {
                state.model = AgentLogParser.native(model)
            }
            if let context = data.object("context"),
               let path = ["gitRoot", "cwd", "repository"].compactMap({ context.string($0) }).first(where: { !$0.isEmpty }) {
                state.project = AgentLogParser.projectName(path)
            }
            return []
        case "session.context_changed":
            if let path = ["gitRoot", "cwd", "repository"].compactMap({ data.string($0) }).first(where: { !$0.isEmpty }) {
                state.project = AgentLogParser.projectName(path)
            }
            return state.turnOpen ? [.turnContext(model: state.model, project: state.project)] : []
        case "session.model_change":
            if let model = data.string("newModel"), !model.isEmpty { state.model = AgentLogParser.native(model) }
            return state.turnOpen ? [.turnContext(model: state.model, project: state.project)] : []
        case "abort":
            guard state.turnOpen else { return [] }
            state.turnOpen = false
            state.copilotFinalResponse = false
            return [.turnEnded(date, completed: false, duration: nil)]
        case "session.shutdown":
            var entries = copilotUsage(data.value("modelMetrics") as? [String: Any], event: envelope.string("id"),
                                       date: date, state: &state)
            if state.turnOpen {
                state.turnOpen = false
                entries.append(.turnEnded(date, completed: false, duration: nil))
            }
            return entries
        default:
            return []
        }
    }

    private func copilotActivity(_ data: AgentLogObject, envelope: AgentLogObject, agent: String?,
                                 model: String, date: Date, state: inout AgentLogState) -> [AgentLogEntry] {
        let call = data.string("apiCallId").flatMap { $0.isEmpty ? nil : $0 }
        let message = data.string("messageId").flatMap { $0.isEmpty ? nil : $0 }
            ?? envelope.string("id") ?? String(date.timeIntervalSince1970)
        // Each API call can emit several messages. Older logs lack apiCallId,
        // so they retain message-level deduplication. Namespace IDs by kind
        // and agent so independent calls cannot collide with those fallbacks.
        let request = (agent.map { "agent:\($0)" } ?? "root") + ":"
            + (call.map { "api:\($0)" } ?? "message:\(message)")
        let key = "copilot:\(state.session):\(request):activity"
        if let previous = state.copilotRequestModels[request] {
            guard previous.isEmpty, !model.isEmpty else { return [] }
            state.copilotRequestModels[request] = model
            state.copilotRequests[previous, default: 0] -= 1
            state.copilotRequests[model, default: 0] += 1
            return [.usageModel(key: key, model: model)]
        }
        state.copilotRequestModels[request] = model
        state.copilotRequests[model, default: 0] += 1
        return [.usage(key: key, record: AgentUsageRecord(
            provider: .copilot, date: date, model: model, project: state.project, session: state.session,
            tokens: AgentTokens(), cost: 0, savings: 0), billable: AgentBillable(isAggregate: true))]
    }

    private func copilotUsage(_ metrics: [String: Any]?, event: String?, date: Date,
                              state: inout AgentLogState) -> [AgentLogEntry] {
        guard let metrics else { return [] }
        var growth: [String: AgentTokens] = [:]
        for (model, value) in metrics {
            guard let metric = value as? [String: Any] else { continue }
            let total = copilotTokens(metric)
            growth[model] = tokenGrowth(total, after: state.copilotTotals[model])
            state.copilotTotals[model] = total
            let reported = AgentLogParser.int((metric["requests"] as? [String: Any])?["count"])
            state.copilotReportedRequests[model] = max(state.copilotReportedRequests[model, default: 0],
                                                       max(reported, total.total > 0 ? 1 : 0))
        }
        let deficits = state.copilotReportedRequests
            .map { (model: $0.key, count: max(0, $0.value - state.copilotRequests[$0.key, default: 0])) }
        let unresolved = state.copilotRequests["", default: 0]
        var missing = max(0, deficits.reduce(0) { $0 + $1.count } - unresolved)
        var requests: [String: Int] = [:]
        // Unknown responses can cover any model's deficit, but only once
        // across the whole session. Attribute only the excess that must be
        // this model; retain ambiguous requests in the unknown bucket.
        for deficit in deficits {
            let certain = max(0, deficit.count - unresolved)
            requests[deficit.model] = certain
            missing -= certain
        }
        if missing > 0 { requests["", default: 0] += missing }
        var entries: [AgentLogEntry] = []
        for model in Set(growth.keys).union(requests.keys).sorted() {
            let tokens = growth[model] ?? AgentTokens()
            let count = requests[model, default: 0]
            state.copilotRequests[model, default: 0] += count
            guard tokens.total > 0 || count > 0 else { continue }
            let billable = AgentBillable(tokens: tokens, isAggregate: true)
            let name = AgentLogParser.native(model)
            let priced = AgentPricing.cost(billable, model: name)
            let checkpoint = event.flatMap { $0.isEmpty ? nil : AgentLogParser.native($0) }
                ?? String(date.timeIntervalSince1970)
            entries.append(.usage(key: "copilot:\(state.session):\(checkpoint):\(name)", record: AgentUsageRecord(
                provider: .copilot, date: date, model: name, project: state.project, session: state.session,
                requests: count, tokens: tokens, cost: priced.cost, savings: priced.savings), billable: billable))
        }
        return entries
    }

    private func copilotTokens(_ metric: [String: Any]) -> AgentTokens {
        let details = metric["tokenDetails"] as? [String: Any] ?? [:]
        let usage = metric["usage"] as? [String: Any] ?? [:]
        func count(_ detail: String, _ fallback: String) -> Int {
            if let value = (details[detail] as? [String: Any])?["tokenCount"] { return AgentLogParser.int(value) }
            return AgentLogParser.int(usage[fallback])
        }
        return AgentTokens(input: count("input", "inputTokens"),
                           cacheWrite: count("cache_write", "cacheWriteTokens"),
                           cacheRead: count("cache_read", "cacheReadTokens"),
                           output: count("output", "outputTokens"),
                           reasoning: AgentLogParser.int(usage["reasoningTokens"]))
    }

    private func tokenGrowth(_ total: AgentTokens, after previous: AgentTokens?) -> AgentTokens {
        guard let previous, total.total >= previous.total else { return total }
        return AgentTokens(input: max(0, total.input - previous.input),
                           cacheWrite: max(0, total.cacheWrite - previous.cacheWrite),
                           cacheRead: max(0, total.cacheRead - previous.cacheRead),
                           output: max(0, total.output - previous.output),
                           reasoning: max(0, total.reasoning - previous.reasoning))
    }
}
