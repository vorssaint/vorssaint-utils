// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Antigravity steps handed over by `AgentAntigravityReader`.
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    static let abandoned: TimeInterval = 600
    static let live: TimeInterval = 900
    static let models = ["gemini-pro-default": "gemini-3.1-pro"]

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line), let type = json["type"] as? String else { return [] }
        switch type {
        case "reset":
            state.turnOpen = false
            return [.reset(now)]
        case "tail":
            guard state.turnOpen, let date = AgentLogParser.seconds(json["time"]) else { return [] }
            if json["settled"] as? Bool == true {
                state.turnOpen = false
                return [.turnSettled(date)]
            }
            guard now.timeIntervalSince(date) > Self.abandoned else { return [] }
            state.turnOpen = false
            return [.turnEnded(date, completed: false, duration: nil)]
        case "step":
            break
        default:
            return []
        }
        guard let date = AgentLogParser.seconds(json["time"]) else { return [] }
        let end = AgentLogParser.seconds(json["end"]) ?? date
        if let conversation = json["conversation"] as? String, !conversation.isEmpty { state.session = AgentLogParser.native(conversation) }
        if let project = json["project"] as? String, !project.isEmpty { state.project = AgentLogParser.native(project) }
        let live = now.timeIntervalSince(end) < Self.live
        var entries: [AgentLogEntry] = []

        for usage in json["usage"] as? [[String: Any]] ?? [] {
            let model = AgentLogParser.native(usage["model"] as? String ?? "")
            if !model.isEmpty { state.model = Self.models[model] ?? model }
            let tokens = AgentTokens(input: AgentLogParser.int(usage["input"]), cacheRead: AgentLogParser.int(usage["cacheRead"]),
                                     output: AgentLogParser.int(usage["output"]), reasoning: AgentLogParser.int(usage["reasoning"]))
            let billable = AgentBillable(tokens: tokens)
            let priced = AgentPricing.cost(billable, model: state.model)
            // A response copied into another conversation keeps its id, so it
            // counts once wherever it is read.
            let step = "antigravity:\(state.session):\(AgentLogParser.int(json["idx"]))"
            let key = (usage["id"] as? String).map { "antigravity:\(AgentLogParser.native($0))" }
                ?? (usage["attempt"] as? Int).map { "\(step):attempt:\($0)" } ?? step
            entries.append(.usage(key: key, record: AgentUsageRecord(
                provider: .antigravity, date: end, model: state.model, project: state.project, session: state.session,
                tokens: tokens, cost: priced.cost, savings: priced.savings), billable: billable))
        }
        guard live else { return entries }
        if AgentLogParser.int(json["kind"]) == Int(AgentAntigravityReader.Kind.userInput) && !state.turnOpen {
            state.turnOpen = true
            entries.append(.turnBegan(date))
        } else {
            state.turnOpen = true
            entries.append(.turnActive(end))
        }
        entries.append(.turnContext(model: state.model, project: state.project))
        return entries
    }
}
