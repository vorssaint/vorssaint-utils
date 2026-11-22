// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Codex session logs. Token records and running-total events become
/// usage, task events open and close turns, and limit readings become the
/// account's allowance windows.
struct CodexReader: AgentHarnessReader {
    var provider: AgentProvider { .codex }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let kind = AgentLogParser.firstType(line) else { return [] }
        switch kind.name {
        case "token_usage_record", "turn_context", "session_meta": break
        case "event_msg":
            guard let event = AgentLogParser.firstType(line, from: kind.end), AgentLogParser.codexEvents.contains(event.name) else { return [] }
        case "response_item":
            guard let item = AgentLogParser.firstType(line, from: kind.end),
                  ["message", "function_call", "custom_tool_call"].contains(item.name),
                  AgentLogParser.contains(line, "/SKILL.md") || AgentLogParser.contains(line, "<skill>") else { return [] }
        default: return []
        }
        guard let json = AgentLogParser.object(line), let payload = json["payload"] as? [String: Any] else { return [] }
        let date = AgentLogParser.timestamp(json["timestamp"]) ?? now
        switch json["type"] as? String {
        case "session_meta":
            // History copied from another thread repeats that thread's
            // metadata; only the first line describes this log's own thread.
            let id = payload["id"] as? String ?? ""
            if !id.isEmpty { state.codexTotalsSession = AgentLogParser.native(id) }
            guard !state.codexHeaderRead else { return [] }
            state.codexHeaderRead = true
            if !id.isEmpty { state.session = AgentLogParser.native(id) }
            if let cwd = payload["cwd"] as? String, !cwd.isEmpty { state.project = AgentLogParser.projectName(cwd) }
            // Subagents, reviews and memory tasks Codex starts itself name
            // `subagent` or `internal`; a person's thread names its client.
            let source = payload["source"] as? [String: Any]
            state.codexSubagent = source?["subagent"] != nil || source?["internal"] != nil
            // A subagent's session is the thread a person started, however
            // deep it runs; its parent thread stands in when that is missing.
            let root = payload["session_id"] as? String ?? payload["parent_thread_id"] as? String ?? ""
            if state.codexSubagent, !root.isEmpty, root != state.session { state.codexRoot = AgentLogParser.native(root) }
            return []
        case "turn_context":
            if let model = payload["model"] as? String, !model.isEmpty { state.model = AgentLogParser.native(model) }
            if let cwd = payload["cwd"] as? String, !cwd.isEmpty { state.project = AgentLogParser.projectName(cwd) }
            if let tier = payload["service_tier"] as? String { state.fast = AgentLogParser.fastTier(tier) }
            return []
        case "token_usage_record":
            guard let usage = payload["usage"] as? [String: Any] else { return [] }
            state.sawUsageRecords = true
            if let session = payload["session_id"] as? String, !session.isEmpty, state.session.isEmpty {
                state.session = AgentLogParser.native(session)
            }
            let response = payload["response_id"] as? String ?? ""
            let key = response.isEmpty ? "codex:\(state.session):\(date.timeIntervalSince1970)" : "codex:\(response)"
            return [codexUsage(AgentLogParser.codexTokens(usage), key: key, date: date, state: &state)]
        case "response_item":
            for skill in codexSkills(payload) where state.turnSkills.insert(skill.name).inserted {
                state.pendingSkills[skill, default: 0] += 1
            }
            return []
        case "event_msg":
            return codexEvent(payload, date: date, state: &state)
        default:
            return []
        }
    }

    private func codexEvent(_ payload: [String: Any], date: Date, state: inout AgentLogState) -> [AgentLogEntry] {
        switch payload["type"] as? String {
        case "token_count":
            var entries: [AgentLogEntry] = []
            if let limits = payload["rate_limits"] as? [String: Any] {
                if AgentLogParser.isMainBucket(limits), let windows = AgentLogParser.codexWindows(limits, observed: date), !windows.isEmpty {
                    entries.append(.limits(AgentLimits(provider: .codex, windows: windows,
                                                       observedAt: date, source: .sessionLog)))
                }
                if let plan = limits["plan_type"] as? String, !plan.isEmpty {
                    entries.append(.plan(plan, observedAt: date))
                }
            }
            // Running totals repeat when only the limits changed; a response
            // is whatever the total grew by since the previous reading.
            if !state.sawUsageRecords, let info = payload["info"] as? [String: Any],
               let totalUsage = info["total_token_usage"] as? [String: Any] {
                let total = AgentLogParser.codexTokens(totalUsage)
                if total != state.lastTotal, total.total > (state.lastTotal?.total ?? 0) {
                    let delta: AgentTokens
                    if let last = info["last_token_usage"] as? [String: Any] {
                        delta = AgentLogParser.codexTokens(last)
                    } else {
                        let previous = state.lastTotal ?? AgentTokens()
                        delta = AgentTokens(input: max(0, total.input - previous.input),
                                            cacheWrite: max(0, total.cacheWrite - previous.cacheWrite),
                                            cacheRead: max(0, total.cacheRead - previous.cacheRead),
                                            output: max(0, total.output - previous.output),
                                            reasoning: max(0, total.reasoning - previous.reasoning))
                    }
                    let key = "codex:\(state.codexTotalsSession):total:\(total.total)"
                    entries.append(codexUsage(delta, key: key, date: date, state: &state))
                }
                state.lastTotal = total
            }
            return entries
        case "thread_settings_applied":
            if let tier = (payload["thread_settings"] as? [String: Any])?["service_tier"] as? String {
                state.fast = AgentLogParser.fastTier(tier)
            }
            return []
        case "task_started":
            state.turnOpen = true
            state.turnSkills = []
            return [.turnBegan(AgentLogParser.seconds(payload["started_at"]) ?? date)]
        case "task_complete", "turn_aborted":
            let open = state.turnOpen
            state.turnOpen = false
            guard open else { return [] }
            let duration = (payload["duration_ms"] as? NSNumber).map { $0.doubleValue / 1000 }
            return [.turnEnded(AgentLogParser.seconds(payload["completed_at"]) ?? date,
                               completed: payload["type"] as? String == "task_complete", duration: duration)]
        default:
            return []
        }
    }

    private func codexUsage(_ tokens: AgentTokens, key: String, date: Date, state: inout AgentLogState) -> AgentLogEntry {
        var billable = AgentBillable(tokens: tokens)
        billable.fast = state.fast
        let priced = AgentPricing.cost(billable, model: state.model)
        let skills = state.pendingSkills
        state.pendingSkills = [:]
        return .usage(key: key, record: AgentUsageRecord(
            provider: .codex, date: date, model: state.model, project: state.project, session: state.session,
            tokens: tokens, cost: priced.cost, savings: priced.savings, skills: skills), billable: billable)
    }

    private func codexSkills(_ payload: [String: Any]) -> [AgentSkill] {
        switch payload["type"] as? String {
        case "message":
            guard payload["role"] as? String == "user",
                  let content = payload["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { block in
                guard let text = block["text"] as? String,
                      let open = text.range(of: "<name>"),
                      let close = text.range(of: "</name>", range: open.upperBound..<text.endIndex) else { return nil }
                return skillName(String(text[open.upperBound..<close.lowerBound])).map {
                    AgentSkill(name: $0, byPerson: true)
                }
            }
        case "function_call", "custom_tool_call":
            guard payload["name"] as? String != "apply_patch" else { return [] }
            let command = payload["arguments"] as? String ?? payload["input"] as? String ?? ""
            return command.components(separatedBy: "/SKILL.md").dropLast().compactMap {
                $0.split(whereSeparator: { "/\"' ".contains($0) }).last.flatMap {
                    skillName(String($0)).map { AgentSkill(name: $0, byPerson: false) }
                }
            }
        default:
            return []
        }
    }

    private func skillName(_ raw: String) -> String? {
        let name = raw.split(separator: ":").last.map(String.init) ?? ""
        guard !name.isEmpty, name.count <= 80,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return AgentLogParser.native(name)
    }
}
