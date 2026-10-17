// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Kiro CLI's session event logs, and the turn summaries its older
/// chat sessions keep, which `AgentKiroLog` hands over as lines of their own.
/// Only turn boundaries, model names, the workspace folder and the credits
/// each turn used are decoded; prompts, replies and tool output are ignored.
struct KiroReader: AgentHarnessReader {
    var provider: AgentProvider { .kiro }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line) else { return [] }
        // Lines `AgentKiroLog` builds carry their type at the top; Kiro's
        // own lines carry it inside their payload.
        if let type = envelope.string("type") { return synthetic(type, envelope, state: &state, now: now) }
        guard let payload = envelope.object("payload"), let type = payload.string("type") else { return [] }
        let date = AgentLogParser.timestamp(envelope.value("timestamp")) ?? now
        switch type {
        case "turn_start":
            let entry: AgentLogEntry = state.turnOpen ? .turnActive(date) : .turnBegan(date)
            state.turnOpen = true
            return [entry, .turnContext(model: state.model, project: state.project)]
        case "assistant":
            if let model = payload.string("reasoningModelId").map(Self.model), !model.isEmpty { state.model = model }
            guard state.turnOpen else { return [] }
            return [.turnContext(model: state.model, project: state.project), .turnActive(date)]
        case "tool_call", "tool_result", "session_metadata", "interaction_resolved":
            // A pending approval writes nothing until it is resolved, so the
            // turn goes quiet meanwhile and resumes with the next line.
            return state.turnOpen ? [.turnActive(date)] : []
        case "usage_summary":
            let summaries = payload.value("promptTurnSummaries") as? [[String: Any]] ?? []
            let credits = summaries.reduce(0.0) { sum, summary in
                guard (summary["unit"] as? String)?.lowercased() == "credit",
                      let usage = (summary["usage"] as? NSNumber)?.doubleValue, usage.isFinite, usage > 0
                else { return sum }
                return sum + usage
            }
            let requests = (payload.value("requestIds") as? [Any])?.count ?? 0
            guard credits > 0 || requests > 0 else { return [] }
            let execution = payload.string("executionId").flatMap { $0.isEmpty ? nil : $0 }
                ?? envelope.string("id") ?? String(date.timeIntervalSince1970)
            return [usage(key: "kiro:\(state.session):\(AgentLogParser.native(execution))", date: date,
                          model: state.model, project: state.project, session: state.session,
                          requests: requests, credits: credits)]
        case "turn_end":
            guard state.turnOpen else { return [] }
            state.turnOpen = false
            return [.turnEnded(date, completed: payload.string("stopReason") == "end_turn", duration: nil)]
        default:
            return []
        }
    }

    private func synthetic(_ type: String, _ line: AgentLogObject, state: inout AgentLogState,
                           now: Date) -> [AgentLogEntry] {
        switch type {
        case AgentKiroLog.sessionType:
            if let session = line.string("session"), !session.isEmpty { state.session = AgentLogParser.native(session) }
            if let folder = line.string("workspace"), !folder.isEmpty { state.project = AgentLogParser.projectName(folder) }
            if state.model.isEmpty, let model = line.string("model").map(Self.model), !model.isEmpty {
                state.model = model
            }
            return []
        case AgentKiroLog.legacyTurnType:
            guard let session = line.string("session"), !session.isEmpty, let end = line.string("end"), !end.isEmpty,
                  let date = AgentLogParser.timestamp(end) else { return [] }
            let credits = (line.value("credits") as? NSNumber)?.doubleValue ?? 0
            let requests = AgentLogParser.int(line.value("requests"))
            guard credits.isFinite, credits > 0 || requests > 0 else { return [] }
            let name = AgentLogParser.native(session)
            return [usage(key: "kiro:\(name):\(AgentLogParser.native(end))", date: date,
                          model: line.string("model").map(Self.model) ?? "",
                          project: line.string("cwd").map(AgentLogParser.projectName) ?? "",
                          session: name, requests: requests, credits: max(0, credits))]
        default:
            return []
        }
    }

    /// A turn's credits come out of the plan's monthly allowance, which
    /// costs the plan's fixed price whatever is used of it, so a turn costs
    /// nothing on its own. Only credits past the allowance are billed, and
    /// only the account knows when that starts: `AgentKiroServer` records
    /// those charges as the account reports them.
    private func usage(key: String, date: Date, model: String, project: String, session: String,
                       requests: Int, credits: Double) -> AgentLogEntry {
        .usage(key: key, record: AgentUsageRecord(
            provider: .kiro, date: date, model: model, project: project, session: session,
            requests: requests, tokens: AgentTokens(), cost: 0, savings: 0,
            reportedCost: true, credits: credits), billable: AgentBillable(isAggregate: true))
    }

    /// Kiro names models by their backend, as in "qdev::claude-opus-5.5".
    static func model(_ id: String) -> String {
        let name = id.range(of: "::", options: .backwards).map { String(id[$0.upperBound...]) } ?? id
        return AgentLogParser.native(name)
    }
}
