// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Oh My Pi (`omp`) session logs, `~/.omp/agent/sessions/<cwd>/<session>.jsonl`.
/// Each line is one entry: a `session` header names the folder, a person's
/// `message` opens a turn, an assistant `message` records its usage and keeps
/// the turn going while it calls tools, and its stop reason ends the turn.
/// A subagent writes its own log inside the session's folder; its responses
/// count toward the turn it works for. Only usage counters, model names,
/// times and the folder leave a line; prompts, replies and tool output are
/// never decoded into anything that is stored.
struct OmpReader: AgentHarnessReader {
    var provider: AgentProvider { .omp }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let type = AgentLogParser.firstType(line) else { return [] }
        switch type.name {
        case "session":
            guard let json = AgentLogParser.object(line) else { return [] }
            if let id = json["id"] as? String, !id.isEmpty { state.session = AgentLogParser.native(id) }
            if let cwd = json["cwd"] as? String, !cwd.isEmpty { state.project = AgentLogParser.projectName(cwd) }
            return []
        case "model_change":
            guard let json = AgentLogParser.object(line), let model = json["model"] as? String else { return [] }
            state.model = Self.modelName(model)
            return []
        case "model_usage":
            // Side requests such as naming the session bill like a reply but
            // are no part of the turn.
            guard let json = AgentLogParser.object(line) else { return [] }
            let date = AgentLogParser.timestamp(json["timestamp"]) ?? now
            let id = json["id"] as? String ?? ""
            return usage(json, key: "omp:\(state.session):side:\(id)", date: date, state: &state).map { [$0] } ?? []
        case "message":
            return message(line, state: &state, now: now)
        default:
            return []
        }
    }

    private func message(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        // Tool output can be large; while a turn is open, a result only has
        // to say that work goes on.
        if AgentLogParser.contains(line, #""role":"toolResult""#) {
            return state.turnOpen ? [.turnActive(nil)] : []
        }
        guard let json = AgentLogParser.object(line), let message = json["message"] as? [String: Any] else { return [] }
        let date = AgentLogParser.timestamp(json["timestamp"]) ?? now
        switch message["role"] as? String {
        case "user":
            // A message sent while the agent works steers the same turn.
            if state.turnOpen { return [.turnActive(date)] }
            state.turnOpen = true
            return [.turnBegan(date)]
        case "assistant":
            var entries: [AgentLogEntry] = []
            let id = (message["responseId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? json["id"] as? String ?? ""
            if let model = message["model"] as? String, !model.isEmpty { state.model = Self.modelName(model) }
            if let record = usage(message, key: "omp:\(state.session):\(id)", date: date, state: &state) {
                entries.append(record)
            }
            switch message["stopReason"] as? String {
            case "toolUse":
                // Ahead of the usage, so a reply that opens the turn again,
                // as after a retried error, counts toward it.
                entries.insert(state.turnOpen ? .turnActive(date) : .turnBegan(date), at: 0)
                state.turnOpen = true
            case "stop", "length":
                if state.turnOpen { entries.append(.turnEnded(date, completed: true, duration: nil)) }
                state.turnOpen = false
            case "aborted", "error":
                // An interruption or a failed request stops the turn without
                // finishing it; a retry opens it again.
                if state.turnOpen { entries.append(.turnEnded(date, completed: false, duration: nil)) }
                state.turnOpen = false
            default:
                if state.turnOpen { entries.insert(.turnActive(date), at: 0) }
            }
            return entries
        default:
            return []
        }
    }

    /// What one response used. omp records the price it charged for each
    /// response; the price list wins when it knows the model, as for OpenCode,
    /// so the island values every agent alike.
    private func usage(_ object: [String: Any], key: String, date: Date, state: inout AgentLogState) -> AgentLogEntry? {
        guard let usage = object["usage"] as? [String: Any] else { return nil }
        let model = (object["model"] as? String).map(Self.modelName) ?? state.model
        let tokens = AgentTokens(input: AgentLogParser.int(usage["input"]),
                                 cacheWrite: AgentLogParser.int(usage["cacheWrite"]),
                                 cacheRead: AgentLogParser.int(usage["cacheRead"]),
                                 output: AgentLogParser.int(usage["output"]))
        let recordedCost = (((usage["cost"] as? [String: Any])?["total"] as? NSNumber)?.doubleValue)
            .flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        guard tokens.total > 0 || (recordedCost ?? 0) > 0 else { return nil }
        var billable = AgentBillable(tokens: tokens)
        billable.longCacheWrite = AgentLogParser.int((usage["cttl"] as? [String: Any])?["ephemeral1h"])
        let priced = AgentPricing.cost(billable, model: model)
        let cost: Double?
        let isReported: Bool
        if let calculated = priced.cost {
            cost = calculated
            isReported = false
        } else if let recordedCost {
            cost = recordedCost
            isReported = recordedCost > 0
        } else {
            cost = nil
            isReported = false
        }
        let record = AgentUsageRecord(provider: .omp, date: date, model: model, project: state.project,
                                      session: state.session, tokens: tokens, cost: cost,
                                      savings: priced.savings, reportedCost: isReported)
        return .usage(key: key, record: record, billable: billable)
    }

    /// omp names a model with its provider, `anthropic/claude-opus-5-5`, and
    /// can add a thinking level, `…:high`. The price list knows the bare id.
    static func modelName(_ raw: String) -> String {
        var name = Substring(raw)
        if let slash = name.lastIndex(of: "/") { name = name[name.index(after: slash)...] }
        if let colon = name.firstIndex(of: ":") { name = name[..<colon] }
        return AgentLogParser.native(String(name))
    }
}
