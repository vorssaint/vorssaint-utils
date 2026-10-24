// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Google Antigravity (agy) session transcripts.
/// Each conversation stores its transcript at:
/// brain/<conversation-id>/.system_generated/logs/transcript.jsonl
struct AgyReader: AgentHarnessReader {
    var provider: AgentProvider { .agy }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let obj = AgentLogObject(line) else { return [] }
        let type = obj.string("type") ?? ""
        let source = obj.string("source") ?? ""
        let date = AgentLogParser.timestamp(obj.value("created_at")) ?? now
        let step = (obj.value("step_index") as? NSNumber)?.intValue ?? 0

        if source == "USER_EXPLICIT" && type == "USER_INPUT" {
            state.turnOpen = true
            if let content = obj.string("content") {
                if let model = extractModel(from: content) {
                    state.model = AgentLogParser.native(model)
                } else if state.model.isEmpty {
                    state.model = "gemini-3.8-flash"
                }
                if let project = extractProject(from: content) {
                    state.project = AgentLogParser.projectName(project)
                }
            }
            if state.project.isEmpty {
                state.project = "Antigravity Workspace"
            }
            return [.turnBegan(date), .turnContext(model: state.model, project: state.project)]
        }

        if source == "MODEL" {
            if type == "PLANNER_RESPONSE" {
                let content = obj.string("content") ?? ""
                let thinking = obj.string("thinking") ?? ""
                let hasTools = obj.hasItems("tool_calls")

                let contentTokens = max(1, content.count / 4)
                let reasoningTokens = thinking.isEmpty ? 0 : max(1, thinking.count / 4)
                let outputTokens = contentTokens + reasoningTokens
                let inputTokens = max(10, (content.count + thinking.count) / 2)
                let tokens = AgentTokens(input: inputTokens, cacheWrite: 0, cacheRead: 0,
                                         output: outputTokens, reasoning: reasoningTokens)
                let billable = AgentBillable(tokens: tokens)
                let model = state.model.isEmpty ? "gemini-3.8-flash" : state.model
                let project = state.project.isEmpty ? "Antigravity Workspace" : state.project
                let (cost, savings) = AgentPricing.cost(billable, model: model)
                let key = "agy:\(state.session):\(step)"
                let record = AgentUsageRecord(provider: .agy, date: date,
                                              model: model,
                                              project: project,
                                              session: state.session,
                                              tokens: tokens, cost: cost, savings: savings)

                let rawLine = String(decoding: line, as: UTF8.self)
                let needsApproval = rawLine.contains("\"ask_question\"")
                    || rawLine.contains("\"confirm\"")
                    || obj.string("status") == "WAITING_FOR_USER"

                if hasTools {
                    state.turnOpen = true
                    let entry: AgentLogEntry = needsApproval ? .turnNeedsApproval(date) : .turnActive(date)
                    return [entry, .usage(key: key, record: record, billable: billable)]
                } else {
                    state.turnOpen = false
                    return [.usage(key: key, record: record, billable: billable), .turnEnded(date, completed: true, duration: nil)]
                }
            } else if state.turnOpen {
                let rawLine = String(decoding: line, as: UTF8.self)
                if rawLine.contains("\"ask_question\"") || rawLine.contains("\"confirm\"") {
                    return [.turnNeedsApproval(date)]
                }
                return [.turnActive(date)]
            }
        }

        return []
    }

    private func extractModel(from content: String) -> String? {
        if content.contains("Gemini 3.8 Flash") || content.contains("gemini-3.8-flash") {
            return "gemini-3.8-flash"
        }
        if content.contains("Gemini 2.5 Pro") || content.contains("gemini-2.5-pro") {
            return "gemini-2.5-pro"
        }
        if content.contains("Gemini 1.5 Pro") || content.contains("gemini-1.5-pro") {
            return "gemini-1.5-pro"
        }
        return nil
    }

    private func extractProject(from content: String) -> String? {
        if let match = content.range(of: "CWD: ") {
            let rest = content[match.upperBound...]
            if let lineEnd = rest.firstIndex(of: "\n") {
                return String(rest[..<lineEnd]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let match = content.range(of: "Active Document: ") {
            let rest = content[match.upperBound...]
            if let lineEnd = rest.firstIndex(of: "\n") {
                return String(rest[..<lineEnd]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
