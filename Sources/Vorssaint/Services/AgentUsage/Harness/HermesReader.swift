// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Hermes Agent's running totals and messages as handed over by
/// `AgentHermesReader`. Hermes only drives models on other accounts, so its
/// usage and its turns go to the card of the account each session runs on,
/// and Hermes keeps no card of its own. A prompt opens a turn, tool calls and
/// their results keep it going, and a reply that calls no tool ends it.
struct HermesReader: AgentHarnessReader {
    var provider: AgentProvider { .hermes }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line) else { return [] }
        switch json["type"] as? String {
        case "usage_snapshot":
            guard let rows = json["records"] as? [[String: Any]] else { return [] }
            // The totals belong to the database, not to the session read last.
            state.session = ""
            state.parentSession = ""
            return [.usageCounters(rows.compactMap(counter))]
        case "message":
            return message(json, state: &state, now: now)
        case "reset":
            state.hermesSessions.removeAll()
            return [.reset(now)]
        default:
            return []
        }
    }

    private func message(_ json: [String: Any], state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let role = json["role"] as? String,
              let sessionID = json["session_id"] as? String, !sessionID.isEmpty,
              let provider = (json["provider"] as? String).flatMap(AgentProvider.init(rawValue:)),
              provider == .claude || provider == .codex else { return [] }
        let date = AgentLogParser.seconds(json["time_created"]) ?? now
        let id = AgentLogParser.native(sessionID)
        state.session = id
        state.parentSession = AgentLogParser.native(json["parent_session_id"] as? String ?? "")
        // Sessions quiet this long with no turn open are let go as a new one appears.
        if state.hermesSessions[id] == nil {
            state.hermesSessions = state.hermesSessions.filter { _, kept in
                kept.turnOpen || date.timeIntervalSince(kept.lastActivity ?? date) < NotchAgentSupport.idleTurn
            }
        }
        var session = state.hermesSessions[id] ?? HermesSessionState()
        session.lastActivity = max(session.lastActivity ?? date, date)
        let title = json["title"] as? String ?? ""
        let project = title.isEmpty ? AgentLogParser.projectName(json["directory"] as? String ?? "") : AgentLogParser.native(title)
        let model = AgentLogParser.native(json["model"] as? String ?? "")
        var entries: [AgentLogEntry] = [.turnProvider(provider)]
        func open() {
            session.turnOpen = true
            session.turnStarted = date
            entries.append(.turnBegan(date))
        }
        switch role {
        case "user":
            // A prompt sent while Hermes still works joins the running turn.
            if session.turnOpen { entries.append(.turnActive(date)) } else { open() }
        case "tool":
            guard session.turnOpen else { state.hermesSessions[id] = session; return [] }
            entries.append(.turnActive(date))
        case "assistant":
            if json["calls_tool"] as? Bool == true || json["finish"] as? String == "tool_calls" {
                // Found mid-turn when the reading began, it is work all the same.
                if session.turnOpen { entries.append(.turnActive(date)) } else { open() }
            } else {
                guard session.turnOpen else { state.hermesSessions[id] = session; return [] }
                let duration = session.turnStarted.map { max(0, date.timeIntervalSince($0)) }
                session.turnOpen = false
                session.turnStarted = nil
                entries.append(.turnEnded(date, completed: true, duration: duration))
            }
        default:
            return []
        }
        state.hermesSessions[id] = session
        state.turnOpen = session.turnOpen
        // After the turn entry, so a turn it just opened takes the context.
        if session.turnOpen { entries.append(.turnContext(model: model, project: project)) }
        return entries
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
