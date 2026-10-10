// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Antigravity transcript logs. A user prompt opens a turn, replies
/// and tool steps keep it active, and terminal planner responses or errors
/// close the turn. Because transcripts record no token counts, usage records
/// keep unmeasured usage with cost nil.
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        let response = AgentLogParser.contains(line, #""type":"PLANNER_RESPONSE""#)
        guard response || AgentLogParser.contains(line, #""type":"USER_INPUT""#) else {
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
                if let model = antigravityModel(content) { state.model = model }
                if let workspace = antigravityWorkspace(content) {
                    state.project = workspace
                    state.namedWorkspace = true
                }
                if state.session.isEmpty, let session = antigravitySession(content) { state.session = session }
            }
            entries.append(.turnBegan(date))
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

            // The transcript records no tokens, so the response has no cost to
            // price: it stays unavailable.
            let billable = AgentBillable()
            let step = json["step_index"] as? Int ?? 0
            let record = AgentUsageRecord(
                provider: .antigravity, date: date, model: state.model, project: state.project,
                session: state.session, tokens: AgentTokens(), cost: nil, savings: 0
            )
            var entries: [AgentLogEntry] = []
            if !state.turnOpen {
                state.turnOpen = true
                entries.append(.turnBegan(date))
            }
            entries.append(.usage(key: "antigravity:\(state.session):\(step)", record: record, billable: billable))

            let status = json["status"] as? String
            // A stopped response is still saved as DONE; the next message
            // ends that turn. Only a failure ends it here.
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

        default:
            return []
        }
    }

    /// The model the person picked, from the settings change Antigravity
    /// adds to their message.
    private func antigravityModel(_ content: String) -> String? {
        guard let change = content.range(of: "<USER_SETTINGS_CHANGE>"),
              let range = content[change.upperBound...].range(of: "Model Selection`") else { return nil }
        let tail = content[range.upperBound...]
        guard let toRange = tail.range(of: " to ") else { return nil }
        let afterTo = tail[toRange.upperBound...]
        var endIndex = afterTo.endIndex
        for candidate in [". No need", ".</USER_SETTINGS_CHANGE>", "</USER_SETTINGS_CHANGE>", ".\n", "\n"] {
            if let found = afterTo.range(of: candidate), found.lowerBound < endIndex { endIndex = found.lowerBound }
        }
        let model = String(afterTo[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? nil : model
    }

    private func antigravityWorkspace(_ content: String) -> String? {
        guard let range = content.range(of: "[URI] -> [CorpusName]:\n") else { return nil }
        let tail = content[range.upperBound...]
        guard let lineEnd = tail.firstIndex(of: "\n"),
              let arrow = tail[..<lineEnd].range(of: " -> ") else { return nil }
        let name = AgentLogParser.projectName(String(tail[..<arrow.lowerBound]))
        return name.isEmpty ? nil : name
    }

    private func antigravitySession(_ content: String) -> String? {
        guard let range = content.range(of: "Conversation ID: ") else { return nil }
        let session = content[range.upperBound...].prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        return session.isEmpty ? nil : String(session)
    }
}
