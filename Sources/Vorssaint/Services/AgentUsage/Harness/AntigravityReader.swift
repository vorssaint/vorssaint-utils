// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// Reads Antigravity (AGY) session transcript logs. Each JSONL line in a
/// transcript represents one step of a conversation:
/// - `USER_INPUT` from the user opens a turn (`.turnBegan`).
/// - `PLANNER_RESPONSE` carries token counters (`input_tokens`, `output_tokens`, `cache_read_tokens`).
///   If it contains active `tool_calls`, work continues (`.turnActive`).
///   If it has no `tool_calls`, it delivers the final response, ending the turn (`.turnEnded`).
/// - `GENERIC` steps represent tool results while work is in flight (`.turnActive`).
///
/// Transcripts live under:
/// `~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript.jsonl`
/// and `~/.gemini/antigravity/brain/...`.
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line) else { return [] }
        let type = json["type"] as? String ?? ""
        let date = AgentLogParser.timestamp(json["created_at"]) ?? now

        switch type {
        case "USER_INPUT":
            return handleUserInput(json, date: date, state: &state)
        case "PLANNER_RESPONSE":
            return handlePlannerResponse(json, date: date, state: &state)
        case "GENERIC":
            return handleGenericToolResult(date: date, state: &state)
        default:
            return []
        }
    }

    private func handleUserInput(_ json: [String: Any], date: Date, state: inout AgentLogState) -> [AgentLogEntry] {
        guard json["source"] as? String == "USER_EXPLICIT" else { return [] }

        adoptContext(json, state: &state)

        let wasOpen = state.turnOpen
        state.turnOpen = true
        state.runningCommands = []
        let context = AgentLogEntry.turnContext(model: state.model, project: state.project)
        let end: [AgentLogEntry] = wasOpen ? [.turnEnded(date, completed: false, duration: nil)] : []
        return end + [.turnBegan(date), context]
    }

    private func handlePlannerResponse(_ json: [String: Any], date: Date,
                                       state: inout AgentLogState) -> [AgentLogEntry] {
        if let model = json["model"] as? String, !model.isEmpty {
            state.model = AgentLogParser.native(model)
        }

        var entries: [AgentLogEntry] = []

        let inputTokens = AgentLogParser.int(json["input_tokens"])
        let cacheRead = AgentLogParser.int(json["cache_read_tokens"])
        let outputTokens = AgentLogParser.int(json["output_tokens"])
        let reasoning = AgentLogParser.int(json["thinking_tokens"])

        if inputTokens > 0 || outputTokens > 0 || reasoning > 0 {
            let tokens = AgentTokens(
                input: max(0, inputTokens - cacheRead),
                cacheWrite: 0,
                cacheRead: min(inputTokens, cacheRead),
                output: outputTokens,
                reasoning: reasoning
            )
            let billable = AgentBillable(tokens: tokens)
            let priced = AgentPricing.cost(billable, model: state.model)
            // A missing step index must not overwrite every other response.
            // Canonical JSON keeps the fallback stable across rereads and copies.
            let identity: String
            if let step = json["step_index"] as? Int, step >= 0, !state.session.isEmpty {
                identity = String(step)
            } else {
                let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
                identity = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
            let key = "antigravity:\(state.session):\(identity)"
            entries.append(.usage(
                key: key,
                record: AgentUsageRecord(
                    provider: .antigravity,
                    date: date,
                    model: state.model,
                    project: state.project,
                    session: state.session,
                    tokens: tokens,
                    cost: priced.cost,
                    savings: priced.savings
                ),
                billable: billable
            ))
        }

        let toolCalls = json["tool_calls"] as? [[String: Any]] ?? []
        let hasTools = !toolCalls.isEmpty
        let status = json["status"] as? String ?? ""

        if status == "ERROR" {
            let wasOpen = state.turnOpen
            state.turnOpen = false
            state.runningCommands.removeAll()
            if wasOpen { entries.append(.turnEnded(date, completed: false, duration: nil)) }
        } else if hasTools || status == "RUNNING" {
            // Agent invoked tools; turn is still running in background.
            for call in toolCalls {
                if let name = call["name"] as? String {
                    state.runningCommands.insert(name)
                    if name == "ask_question" {
                        let question = ((call["args"] as? [String: Any])?["questions"] as? [[String: Any]])?
                            .first?["question"] as? String ?? ""
                        entries.append(.confirmationNeeded(date, project: state.project, detail: question))
                    } else if let metadata = (call["args"] as? [String: Any])?["ArtifactMetadata"] as? [String: Any],
                              metadata["RequestFeedback"] as? Bool == true {
                        let summary = metadata["Summary"] as? String ?? ""
                        entries.append(.confirmationNeeded(date, project: state.project, detail: summary))
                    }
                }
            }
            if state.turnOpen {
                entries.append(.turnActive(date))
            } else {
                state.turnOpen = true
                entries.append(.turnBegan(date))
            }
        } else {
            // No further tool calls: final answer produced, turn is done.
            let wasOpen = state.turnOpen
            state.turnOpen = false
            state.runningCommands.removeAll()
            if wasOpen || status == "DONE" {
                entries.append(.turnEnded(date, completed: status == "DONE", duration: nil))
            }
        }

        return entries
    }

    private func handleGenericToolResult(date: Date, state: inout AgentLogState) -> [AgentLogEntry] {
        guard state.turnOpen else { return [] }
        return [.turnActive(date)]
    }

    private func adoptContext(_ json: [String: Any], state: inout AgentLogState) {
        if let session = json["conversation_id"] as? String, !session.isEmpty {
            state.session = AgentLogParser.native(session)
        }
        if let cwd = json["cwd"] as? String, !cwd.isEmpty {
            state.project = AgentLogParser.projectName(cwd)
        }
        guard let content = json["content"] as? String else { return }
        // Metadata is appended by AGY outside the request. Text the person
        // typed inside USER_REQUEST must never choose a model or workspace.
        guard let request = content.range(of: "<USER_REQUEST>"),
              let end = content.range(of: "</USER_REQUEST>", options: .backwards),
              request.upperBound <= end.lowerBound else { return }
        let suffix = String(content[end.upperBound...])
        for tag in ["ADDITIONAL_METADATA", "USER_SETTINGS_CHANGE"] {
            guard let start = suffix.range(of: "<" + tag + ">"),
                  let end = suffix.range(of: "</" + tag + ">", range: start.upperBound..<suffix.endIndex) else { continue }
            let metadata = String(suffix[start.upperBound..<end.lowerBound])
            if let range = metadata.range(of: "`Model Selection` from "),
               let to = metadata.range(of: " to ", range: range.upperBound..<metadata.endIndex),
               let stop = metadata.range(of: ". No need", range: to.upperBound..<metadata.endIndex) {
                state.model = AgentLogParser.native(String(metadata[to.upperBound..<stop.lowerBound]))
            }
            if state.project.isEmpty {
                for marker in ["Active Workspaces:\n- ", "Command Working Directory: "] {
                    guard let range = metadata.range(of: marker) else { continue }
                    let path = metadata[range.upperBound...].prefix(while: { !$0.isNewline })
                    if !path.isEmpty { state.project = AgentLogParser.projectName(String(path)); break }
                }
            }
        }
    }
}

/// A one-time Settings snapshot; disk access stays off the drawing path.
struct AntigravityLogInfo {
    let conversations: Int
    let model: String
    let folder: URL?

    static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AntigravityLogInfo {
        let manager = FileManager.default
        let roots = AgentLogRoot.all(home: home).filter { $0.provider == .antigravity }
        var folders: [URL] = []
        var sessions = Set<String>()
        for root in roots {
            guard let children = try? manager.contentsOfDirectory(at: root.url,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            folders.append(root.url)
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let logs = child.appending(path: ".system_generated/logs")
                if ["transcript.jsonl", "transcript_full.jsonl"].contains(where: {
                    manager.fileExists(atPath: logs.appending(path: $0).path)
                }) { sessions.insert(child.lastPathComponent) }
            }
        }
        let settings = home.appending(path: ".gemini/antigravity-cli/settings.json")
        let model = (try? Data(contentsOf: settings)).flatMap(AgentLogParser.object)?["model"] as? String ?? ""
        return AntigravityLogInfo(conversations: sessions.count, model: model, folder: folders.first)
    }
}
