// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Command Code session logs. A session line establishes session and project
/// context; user text messages open turns, assistant replies record usage and continue
/// or complete turns based on the presence of tool use.
struct CommandCodeReader: AgentHarnessReader {
    var provider: AgentProvider { .commandcode }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        if AgentLogParser.contains(line, #""type":"session""#) {
            guard let json = AgentLogParser.object(line),
                  json["type"] as? String == "session" else { return [] }
            let sessionId = json["id"] as? String ?? json["sessionId"] as? String ?? ""
            if !sessionId.isEmpty {
                state.session = AgentLogParser.native(sessionId)
            }
            if let cwd = json["cwd"] as? String, !cwd.isEmpty {
                state.project = AgentLogParser.projectName(cwd)
            }
            return []
        }

        guard AgentLogParser.contains(line, #""type":"message""#),
              let json = AgentLogParser.object(line),
              json["type"] as? String == "message",
              let message = json["message"] as? [String: Any],
              let role = message["role"] as? String else { return [] }

        let date = AgentLogParser.timestamp(json["timestamp"]) ?? now

        if role == "user" {
            guard isUserText(message["content"]) else { return [] }
            let entry: AgentLogEntry = state.turnOpen ? .turnActive(date) : .turnBegan(date)
            state.turnOpen = true
            return [entry, .turnContext(model: state.model, project: state.project)]
        }

        if role == "assistant" {
            guard let usage = json["usage"] as? [String: Any] else { return [] }
            let rawModel = AgentLogParser.native(json["model"] as? String ?? "")
            let model = rawModel.isEmpty ? state.model : rawModel
            if !rawModel.isEmpty {
                state.model = rawModel
            }
            let inputTokens = AgentLogParser.int(usage["inputTokens"])
            let cacheReadTokens = AgentLogParser.int(usage["cacheReadTokens"])
            let cacheWriteTokens = AgentLogParser.int(usage["cacheWriteTokens"])
            let outputTokens = AgentLogParser.int(usage["outputTokens"])
            let tokens = AgentTokens(
                input: max(0, inputTokens - cacheReadTokens),
                cacheWrite: cacheWriteTokens,
                cacheRead: cacheReadTokens,
                output: outputTokens,
                reasoning: 0
            )

            let costUsd: Double
            if let costNum = (usage["costUsd"] as? NSNumber)?.doubleValue, costNum.isFinite {
                costUsd = max(0, costNum)
            } else {
                costUsd = 0
            }

            var billable = AgentBillable()
            billable.tokens = tokens

            let session = state.session.isEmpty ? "unknown" : state.session
            let messageId = json["id"] as? String ?? message["id"] as? String ?? String(date.timeIntervalSince1970)
            let key = "commandcode:\(session):\(messageId)"

            let record = AgentUsageRecord(
                provider: .commandcode,
                date: date,
                model: model,
                project: state.project,
                session: state.session,
                tokens: tokens,
                cost: costUsd,
                savings: 0,
                reportedCost: true
            )

            let toolUse = hasToolUse(message["content"])
            var entries: [AgentLogEntry] = []
            if toolUse {
                entries.append(.turnActive(date))
                entries.append(.usage(key: key, record: record, billable: billable))
                state.turnOpen = true
            } else {
                entries.append(.usage(key: key, record: record, billable: billable))
                if state.turnOpen {
                    entries.append(.turnEnded(date, completed: true, duration: nil))
                }
                state.turnOpen = false
            }
            return entries
        }

        return []
    }

    private func isUserText(_ content: Any?) -> Bool {
        if let list = content as? [[String: Any]] {
            return list.contains { ($0["type"] as? String) == "text" }
        }
        if let text = content as? String {
            return !text.isEmpty
        }
        return false
    }

    private func hasToolUse(_ content: Any?) -> Bool {
        if let list = content as? [[String: Any]] {
            return list.contains { ($0["type"] as? String) == "tool_use" }
        }
        return false
    }
}
