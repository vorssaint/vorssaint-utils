// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Antigravity transcript logs. A user prompt opens a turn, replies
/// and tool steps keep it active, and terminal planner responses or errors
/// close the turn. Planner responses and checkpoints record measured token
/// counts where available; older transcripts without tokens keep cost nil.
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        let response = AgentLogParser.contains(line, #""type":"PLANNER_RESPONSE""#)
        let checkpoint = AgentLogParser.contains(line, #""type":"CHECKPOINT""#)
        guard response || checkpoint || AgentLogParser.contains(line, #""type":"USER_INPUT""#) else {
            // Other steps carry tool output such as file contents and command
            // results; while a turn is open they only say that work goes on.
            return state.turnOpen && AgentLogParser.contains(line, #""type":""#) ? [.turnActive(nil)] : []
        }
        guard let json = AgentLogParser.object(line), let type = json["type"] as? String else { return [] }
        let date = AgentLogParser.timestamp(json["created_at"]) ?? now

        switch type {
        case "USER_INPUT":
            var entries: [AgentLogEntry] = []
            // The previous turn never wrote its final response, as after
            // stopping the agent: it ends without finishing.
            if state.turnOpen {
                entries.append(.turnEnded(date, completed: false, duration: nil))
            }
            state.turnOpen = true
            if let content = json["content"] as? String {
                let metadata = metadataRegion(in: content)
                if let model = antigravityModel(metadata) { state.model = AgentLogParser.native(model) }
                if let workspace = antigravityWorkspace(metadata) {
                    state.project = workspace
                    state.namedWorkspace = true
                }
                if state.session.isEmpty, let session = antigravitySession(metadata) {
                    state.session = AgentLogParser.native(session)
                }
            }
            entries.append(.turnBegan(date))
            if !state.model.isEmpty || !state.project.isEmpty {
                entries.append(.turnContext(model: state.model, project: state.project))
            }
            return entries

        case "PLANNER_RESPONSE":
            if let model = json["model"] as? String, !model.isEmpty {
                state.model = AgentLogParser.native(model)
            }
            let toolCalls = json["tool_calls"] as? [[String: Any]] ?? []
            // A command's working folder stands in only until the person's
            // message names the workspace; a file's folder never does.
            if !state.namedWorkspace {
                for tool in toolCalls {
                    guard let cwd = (tool["args"] as? [String: Any])?["Cwd"] as? String else { continue }
                    let folder = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if !folder.isEmpty { state.project = AgentLogParser.projectName(folder) }
                }
            }

            let step = json["step_index"] as? Int ?? 0
            let tokens = antigravityTokens(json)
            let (billable, cost, savings) = pricedUsage(tokens: tokens, model: state.model)
            let record = AgentUsageRecord(
                provider: .antigravity, date: date, model: state.model, project: state.project,
                session: state.session, tokens: tokens, cost: cost, savings: savings
            )
            var entries: [AgentLogEntry] = []
            if !state.turnOpen {
                state.turnOpen = true
                entries.append(.turnBegan(date))
            }
            entries.append(.usage(key: "antigravity:\(state.session):\(step)", record: record, billable: billable))

            let status = json["status"] as? String
            // agy 1.5.9 saves every planner response as DONE, a stopped one
            // too; the next message ends that turn. Only an ERROR status
            // ends it here, without announcing completion. API errors come
            // as separate ERROR_MESSAGE steps that are usually retried, so
            // they keep the turn active and the idle check closes it.
            if status == "ERROR" {
                state.turnOpen = false
                entries.append(.turnEnded(date, completed: false, duration: nil))
            } else if toolCalls.isEmpty && (status == "DONE" || status == nil) {
                state.turnOpen = false
                entries.append(.turnEnded(date, completed: true, duration: nil))
            } else {
                entries.append(.turnActive(date))
            }
            return entries

        case "CHECKPOINT":
            let tokens = antigravityTokens(json)
            var entries: [AgentLogEntry] = []
            if tokens.total > 0 {
                let step = json["step_index"] as? Int ?? 0
                let (billable, cost, savings) = pricedUsage(tokens: tokens, model: state.model)
                let record = AgentUsageRecord(
                    provider: .antigravity, date: date, model: state.model, project: state.project,
                    session: state.session, tokens: tokens, cost: cost, savings: savings
                )
                entries.append(.usage(key: "antigravity:\(state.session):checkpoint:\(step)", record: record, billable: billable))
            }
            if state.turnOpen { entries.append(.turnActive(date)) }
            return entries

        default:
            return []
        }
    }

    private func antigravityTokens(_ json: [String: Any]) -> AgentTokens {
        AgentTokens(
            input: AgentLogParser.int(json["input_tokens"]),
            cacheWrite: AgentLogParser.int(json["cache_write_tokens"]),
            cacheRead: AgentLogParser.int(json["cache_read_tokens"]),
            output: AgentLogParser.int(json["output_tokens"]),
            reasoning: AgentLogParser.int(json["thinking_tokens"])
        )
    }

    private func pricedUsage(tokens: AgentTokens, model: String) -> (AgentBillable, Double?, Double) {
        guard tokens.total > 0 else { return (AgentBillable(), nil, 0) }
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        return (billable, priced.cost, priced.savings)
    }

    /// Searches outside the `<USER_REQUEST>` wrapper so prompt text cannot
    /// spoof Antigravity's settings, workspace, or conversation metadata,
    /// while preserving pre-wrapper transcripts that have no wrapper tag.
    private func metadataRegion(in content: String) -> Substring {
        if let close = content.range(of: "</USER_REQUEST>", options: .backwards) {
            return content[close.upperBound...]
        }
        if let open = content.range(of: "<USER_REQUEST>") {
            return content[..<open.lowerBound]
        }
        return content[...]
    }

    /// The model the person picked, from the settings change Antigravity
    /// adds to their message.
    private func antigravityModel(_ content: Substring) -> String? {
        guard let change = content.range(of: "<USER_SETTINGS_CHANGE>"),
              let range = content[change.upperBound...].range(of: "Model Selection`") else { return nil }
        let tail = content[range.upperBound...]
        guard let toRange = tail.range(of: " to ") else { return nil }
        let afterTo = tail[toRange.upperBound...]
        var endIndex = afterTo.endIndex
        for candidate in [". No need", ". If reporting", ".</USER_SETTINGS_CHANGE>", "</USER_SETTINGS_CHANGE>", ".\n", "\n"] {
            if let found = afterTo.range(of: candidate), found.lowerBound < endIndex { endIndex = found.lowerBound }
        }
        let model = String(afterTo[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? nil : model
    }

    private func antigravityWorkspace(_ content: Substring) -> String? {
        guard let range = content.range(of: "[URI] -> [CorpusName]:\n") else { return nil }
        let tail = content[range.upperBound...]
        guard let lineEnd = tail.firstIndex(of: "\n"),
              let arrow = tail[..<lineEnd].range(of: " -> ") else { return nil }
        let name = AgentLogParser.projectName(String(tail[..<arrow.lowerBound]))
        return name.isEmpty ? nil : name
    }

    private func antigravitySession(_ content: Substring) -> String? {
        guard let range = content.range(of: "Conversation ID: ") else { return nil }
        let session = content[range.upperBound...].prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        return session.isEmpty ? nil : String(session)
    }
}
