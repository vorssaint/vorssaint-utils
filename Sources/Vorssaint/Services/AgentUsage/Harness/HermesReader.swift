// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Hermes Agent database rows as handed over by `AgentHermesReader`.
/// Hermes reports no plan limits and keeps no price list of its own, so only
/// its turns are tracked: whether it works, on what, and for how long.
struct HermesReader: AgentHarnessReader {
    var provider: AgentProvider { .hermes }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line) else { return [] }
        if json["type"] as? String == "usage_snapshot" {
            guard let rows = json["records"] as? [[String: Any]] else { return [] }
            // One snapshot owns the database, not whichever turn was read last.
            state.session = ""
            state.parentSession = ""
            let records = rows.compactMap { row -> AgentUsageRecord? in
                guard let session = row["session_id"] as? String,
                      let date = AgentLogParser.seconds(row["time_created"]) else { return nil }
                let tokens = AgentTokens(input: AgentLogParser.int(row["input_tokens"]),
                    cacheWrite: AgentLogParser.int(row["cache_write_tokens"]),
                    cacheRead: AgentLogParser.int(row["cache_read_tokens"]),
                    output: AgentLogParser.int(row["output_tokens"]),
                    reasoning: AgentLogParser.int(row["reasoning_tokens"]))
                let project = AgentLogParser.projectName(row["directory"] as? String ?? "")
                // Zero placeholders on an included/unknown route are not API charges.
                let rawCost = row["cost"] as? Double
                let cost = rawCost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                return AgentUsageRecord(provider: .hermes, date: date,
                    model: AgentLogParser.native(row["model"] as? String ?? ""), project: project,
                    session: AgentLogParser.native(session), requests: AgentLogParser.int(row["requests"]),
                    tokens: tokens, cost: cost, savings: 0, reportedCost: cost != nil)
            }
            return [.usageSnapshot(records)]
        }
        if json["type"] as? String == "reset" {
            state.hermesSessions.removeAll()
            state.turnOpen = false
            return [.reset(now)]
        }
        guard let role = json["role"] as? String,
              let session = json["session_id"] as? String, !session.isEmpty else { return [] }
        let date = AgentLogParser.seconds(json["time_created"]) ?? now
        let sessionID = AgentLogParser.native(session)
        state.session = sessionID
        state.parentSession = AgentLogParser.native(json["parent_session_id"] as? String ?? "")
        var sessionState = state.hermesSessions[sessionID] ?? HermesSessionState()
        // A session quiet this long with no turn open starts its next prompt
        // as a task of its own, so what it kept can go. Sessions are looked
        // over only as a new one appears.
        if state.hermesSessions[sessionID] == nil {
            state.hermesSessions = state.hermesSessions.filter { _, kept in
                kept.turnOpen || date.timeIntervalSince(kept.lastActivity ?? date) < NotchAgentSupport.idleTurn
            }
        }
        sessionState.lastActivity = max(sessionState.lastActivity ?? date, date)
        let title = json["title"] as? String ?? ""
        if !title.isEmpty {
            sessionState.project = AgentLogParser.native(title)
        } else if let cwd = json["directory"] as? String, !cwd.isEmpty {
            sessionState.project = AgentLogParser.projectName(cwd)
        }
        if let model = json["model"] as? String, !model.isEmpty {
            sessionState.model = AgentLogParser.native(model)
        }
        state.hermesSessions[sessionID] = sessionState
        state.project = sessionState.project
        state.model = sessionState.model

        var entries: [AgentLogEntry] = [.turnContext(model: sessionState.model, project: sessionState.project)]
        switch role {
        case "user":
            if sessionState.turnOpen {
                // A prompt sent while Hermes still works joins the running turn.
                entries.append(.turnActive(date))
            } else {
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
        case "tool":
            guard sessionState.turnOpen else { return [] }
            entries.append(.turnActive(date))
        case "assistant":
            // shortcut: every finish a reply can carry ends its turn except tool_calls; a finish
            // reason Hermes adds later needs a case here, <when one exists>.
            if let finish = json["finish"] as? String, finish != "tool_calls" {
                guard sessionState.turnOpen else { return [] }
                var duration: TimeInterval?
                if let started = sessionState.turnStarted, date >= started {
                    duration = date.timeIntervalSince(started)
                }
                sessionState.turnOpen = false
                sessionState.turnStarted = nil
                entries.append(.turnEnded(date, completed: true, duration: duration))
            } else if sessionState.turnOpen {
                entries.append(.turnActive(date))
            } else {
                // The reading window began mid-turn: the reply being written
                // is work going on all the same.
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
        default:
            return []
        }
        state.hermesSessions[sessionID] = sessionState
        state.turnOpen = sessionState.turnOpen
        return entries
    }
}
