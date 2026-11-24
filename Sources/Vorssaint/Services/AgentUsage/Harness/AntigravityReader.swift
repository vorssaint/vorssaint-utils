// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Google Antigravity session transcripts (`transcript.jsonl`) from the
/// CLI, desktop app and IDE brain folders. Only measured token counts, model
/// names, timestamps, turn edges and structural workspace or subagent metadata
/// leave a line; prompts, replies, thinking and tool output are never stored.
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    private static let maxTokenCount = 1_000_000_000_000

    /// Extracts `<conversation-id>` from `<root>/<conversation-id>/.system_generated/logs/transcript.jsonl`.
    static func adopt(path: String, into state: inout AgentLogState) {
        guard state.session.isEmpty else { return }
        let session = AgentLogParser.antigravitySession(from: path)
        if !session.isEmpty { state.session = session }
    }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line),
              let type = envelope.string("type", maxBytes: 64) else { return [] }
        let date = envelope.string("created_at", maxBytes: 64).flatMap(AgentTimestamp.parse) ?? now
        let stepIndex = envelope.unsignedInteger("step_index")
        let status = envelope.string("status", maxBytes: 64)?.uppercased() ?? ""

        switch type {
        case "USER_INPUT":
            return userInput(envelope, date: date, state: &state)
        case "PLANNER_RESPONSE":
            return plannerResponse(envelope, date: date, stepIndex: stepIndex, status: status, state: &state)
        case "CHECKPOINT":
            return checkpoint(envelope, date: date, stepIndex: stepIndex, status: status, state: &state)
        case "ERROR_MESSAGE":
            guard state.turnOpen, !state.antigravitySubagent else { return [] }
            state.turnOpen = false
            return [.turnEnded(date, completed: false, duration: nil)]
        case "SYSTEM_MESSAGE":
            if stepIndex == 0, state.antigravityParent.isEmpty,
               let sender = subagentSender(in: envelope), sender != state.session {
                state.antigravitySubagent = true
                state.antigravityParent = sender
                return []
            }
            guard state.turnOpen, !state.antigravitySubagent else { return [] }
            if Self.abortedStatuses.contains(status) {
                state.turnOpen = false
                return [.turnEnded(date, completed: false, duration: nil)]
            }
            return [.turnActive(date)]
        default:
            // Generic and tool-output steps can carry large payloads. Never
            // decode their content to search for models or file paths.
            guard state.turnOpen, !state.antigravitySubagent else { return [] }
            if Self.abortedStatuses.contains(status) {
                state.turnOpen = false
                return [.turnEnded(date, completed: false, duration: nil)]
            }
            return [.turnActive(date)]
        }
    }

    private static let abortedStatuses: Set<String> = [
        "CANCELED", "CANCELLED", "ABORTED",
    ]

    private static let failedPlannerStatuses: Set<String> = [
        "ERROR", "CANCELED", "CANCELLED", "ABORTED", "FAILED", "INVALID",
    ]

    private static let runningStatuses: Set<String> = [
        "RUNNING", "IN_PROGRESS", "PENDING",
    ]

    private func userInput(_ envelope: AgentLogObject, date: Date, state: inout AgentLogState) -> [AgentLogEntry] {
        // Inspect only system-injected metadata blocks outside <USER_REQUEST>
        // so text typed by the person cannot spoof model or workspace changes.
        if let content = envelope.string("content", maxBytes: 256 * 1024) {
            let metadata = Self.metadataOutsideUserRequest(content)
            if !metadata.isEmpty {
                if let selected = Self.extractModelSelection(from: metadata), !selected.isEmpty {
                    state.model = AgentLogParser.native(selected)
                }
                if state.project.isEmpty, let workspace = Self.extractWorkspace(from: metadata), !workspace.isEmpty {
                    state.project = AgentLogParser.projectName(workspace)
                }
            }
        }
        guard !state.antigravitySubagent else { return [] }
        var entries: [AgentLogEntry] = []
        // A new prompt while a previous turn stayed open means the earlier
        // turn was interrupted or stopped without writing a final answer.
        if state.turnOpen {
            entries.append(.turnEnded(date, completed: false, duration: nil))
        }
        state.turnOpen = true
        entries.append(.turnBegan(date))
        entries.append(.turnContext(model: state.model, project: state.project))
        return entries
    }

    private func plannerResponse(_ envelope: AgentLogObject, date: Date, stepIndex: Int?,
                                 status: String, state: inout AgentLogState) -> [AgentLogEntry] {
        let reportedModel = envelope.string("model", maxBytes: 256)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { !$0.isEmpty && !$0.hasPrefix("<") ? AgentLogParser.native($0) : nil }
        if let reportedModel { state.model = reportedModel }
        let model = reportedModel ?? state.model

        var entries: [AgentLogEntry] = []
        let hasTools = envelope.hasItems("tool_calls")
        let failed = Self.failedPlannerStatuses.contains(status)
        let running = Self.runningStatuses.contains(status)

        if !state.antigravitySubagent {
            if failed {
                if state.turnOpen {
                    entries.append(.turnEnded(date, completed: false, duration: nil))
                }
                state.turnOpen = false
            } else if running || hasTools {
                // Emit before usage so the response's tokens and cost attach
                // to the turn even if the log attached mid-turn.
                entries.append(state.turnOpen ? .turnActive(date) : .turnBegan(date))
                entries.append(.turnContext(model: state.model, project: state.project))
                state.turnOpen = true
            }
        }

        if let usage = measuredUsage(envelope, date: date, stepIndex: stepIndex, model: model,
                                     keyTag: "step", state: state) {
            entries.append(usage)
        } else if !failed && !running {
            // Legacy pre-1.5 transcripts omit token counters entirely. Record
            // activity without inventing tokens or inflating unpriced counts
            // that would turn other providers' dollar views into token views.
            let key = stepIndex.map { "antigravity:\(state.session):step:\($0)" }
                ?? "antigravity:\(state.session):\(date.timeIntervalSince1970)"
            let record = AgentUsageRecord(provider: .antigravity, date: date, model: model,
                                          project: state.project, session: state.session,
                                          tokens: AgentTokens(), cost: 0, savings: 0)
            entries.append(.usage(key: key, record: record, billable: AgentBillable(isAggregate: true)))
        }

        if !state.antigravitySubagent && !failed && !running && !hasTools {
            if state.turnOpen {
                entries.append(.turnEnded(date, completed: true, duration: nil))
            }
            state.turnOpen = false
        }
        return entries
    }

    private func checkpoint(_ envelope: AgentLogObject, date: Date, stepIndex: Int?,
                            status: String, state: inout AgentLogState) -> [AgentLogEntry] {
        var entries: [AgentLogEntry] = []
        let aborted = Self.abortedStatuses.contains(status)
        if state.turnOpen, !state.antigravitySubagent, !aborted {
            entries.append(.turnActive(date))
        }
        let reportedModel = envelope.string("model", maxBytes: 256)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { !$0.isEmpty && !$0.hasPrefix("<") ? AgentLogParser.native($0) : nil }
        let model = reportedModel ?? state.model
        if let usage = measuredUsage(envelope, date: date, stepIndex: stepIndex, model: model,
                                     keyTag: "checkpoint", state: state) {
            entries.append(usage)
        }
        if aborted, state.turnOpen, !state.antigravitySubagent {
            state.turnOpen = false
            entries.append(.turnEnded(date, completed: false, duration: nil))
        }
        return entries
    }

    private func measuredUsage(_ envelope: AgentLogObject, date: Date, stepIndex: Int?, model: String,
                               keyTag: String, state: AgentLogState) -> AgentLogEntry? {
        let inputRaw = envelope.unsignedInteger("input_tokens")
        let cacheReadRaw = envelope.unsignedInteger("cache_read_tokens")
        let cacheWriteRaw = envelope.unsignedInteger("cache_write_tokens")
        let outputRaw = envelope.unsignedInteger("output_tokens")
        let reasoningRaw = envelope.unsignedInteger("thinking_tokens") ?? envelope.unsignedInteger("reasoning_tokens")
        guard inputRaw != nil || cacheReadRaw != nil || cacheWriteRaw != nil || outputRaw != nil || reasoningRaw != nil
        else { return nil }

        let input = min(inputRaw ?? 0, Self.maxTokenCount)
        let cacheRead = min(cacheReadRaw ?? 0, Self.maxTokenCount)
        let cacheWrite = min(cacheWriteRaw ?? 0, Self.maxTokenCount)
        let output = min(outputRaw ?? 0, Self.maxTokenCount)
        let reasoning = min(min(reasoningRaw ?? 0, Self.maxTokenCount), output)
        let tokens = AgentTokens(input: input, cacheWrite: cacheWrite, cacheRead: cacheRead,
                                 output: output, reasoning: reasoning)
        guard tokens.total > 0 else { return nil }

        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        let key = stepIndex.map { "antigravity:\(state.session):\(keyTag):\($0)" }
            ?? "antigravity:\(state.session):\(keyTag):\(date.timeIntervalSince1970)"
        let record = AgentUsageRecord(provider: .antigravity, date: date, model: model,
                                      project: state.project, session: state.session,
                                      tokens: tokens, cost: priced.cost, savings: priced.savings)
        return .usage(key: key, record: record, billable: billable)
    }

    /// Reads the parent conversation ID from a step-0 subagent system message,
    /// e.g. `[Message] timestamp=... sender=<uuid>`.
    private func subagentSender(in envelope: AgentLogObject) -> String? {
        guard let prefixData = envelope.stringPrefix("content", maxBytes: 1024) else { return nil }
        let prefix = String(decoding: prefixData, as: UTF8.self)
        guard prefix.contains("<SYSTEM_MESSAGE>"),
              let range = prefix.range(of: "sender=") else { return nil }
        let rest = prefix[range.upperBound...]
        let id = rest.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        guard id.count >= 8 else { return nil }
        return AgentLogParser.native(String(id))
    }

    /// Removes the `<USER_REQUEST>...</USER_REQUEST>` body so only harness-owned
    /// metadata blocks remain.
    static func metadataOutsideUserRequest(_ content: String) -> String {
        var remaining = content
        if let start = remaining.range(of: "<USER_REQUEST>") {
            if let end = remaining.range(of: "</USER_REQUEST>", range: start.upperBound..<remaining.endIndex) {
                remaining.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                // Truncated request without closing tag: never scan prompt text.
                remaining = String(remaining[..<start.lowerBound])
            }
        }
        var blocks: [String] = []
        for (open, close) in [("<USER_SETTINGS_CHANGE>", "</USER_SETTINGS_CHANGE>"),
                              ("<ADDITIONAL_METADATA>", "</ADDITIONAL_METADATA>"),
                              ("<user_information>", "</user_information>")] {
            var cursor = remaining.startIndex
            while let s = remaining.range(of: open, range: cursor..<remaining.endIndex) {
                let end = remaining.range(of: close, range: s.upperBound..<remaining.endIndex)?.lowerBound
                    ?? remaining.endIndex
                blocks.append(String(remaining[s.upperBound..<end]))
                cursor = end
            }
        }
        return blocks.joined(separator: "\n")
    }

    /// Parses `The user changed setting `Model Selection` from ... to <Name>.`
    static func extractModelSelection(from metadata: String) -> String? {
        guard let anchor = metadata.range(of: "`Model Selection`") else { return nil }
        let tail = metadata[anchor.upperBound...]
        guard let toRange = tail.range(of: " to ") else { return nil }
        let rest = tail[toRange.upperBound...]
        let line = rest.prefix { $0 != "\n" && $0 != "\r" }
        // The sentence ends with a period followed by a space or end-of-line.
        let value: Substring
        if let sentenceEnd = line.range(of: ". ") {
            value = line[..<sentenceEnd.lowerBound]
        } else if line.hasSuffix(".") {
            value = line.dropLast()
        } else {
            value = line
        }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.lowercased() != "none" else { return nil }
        return canonicalModelID(from: cleaned)
    }

    /// Extracts a workspace path from `Active Workspaces:` or
    /// `Command Working Directory:` inside harness metadata.
    static func extractWorkspace(from metadata: String) -> String? {
        let lines = metadata.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        for (index, line) in lines.enumerated() {
            if line == "Active Workspaces:", index + 1 < lines.count {
                let candidate = lines[index + 1]
                if candidate.hasPrefix("- ") {
                    let path = String(candidate.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if path.hasPrefix("/") { return path }
                }
            }
        }
        for line in lines where line.hasPrefix("Command Working Directory:") {
            let path = line.dropFirst("Command Working Directory:".count).trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("/") { return path }
        }
        return nil
    }

    /// Converts a human-readable Antigravity display name such as
    /// `"Gemini 4 Neon (XHigh)"` or `"Claude Opus 5.5 (High)"` into the model
    /// identifier used by `PLANNER_RESPONSE` and `AgentPricing`.
    static func canonicalModelID(from displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Already an identifier (no spaces or parentheses).
        if !trimmed.contains(" ") && !trimmed.contains("(") { return trimmed.lowercased() }
        var base = trimmed
        var effort: String?
        if let open = trimmed.lastIndex(of: "("), trimmed.hasSuffix(")") {
            let inside = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
                .trimmingCharacters(in: .whitespaces).lowercased()
            base = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
            if ["low", "medium", "high", "xhigh", "max"].contains(inside) {
                effort = inside
            } else if base.lowercased() == "orchestrator" {
                switch inside {
                case "neon": return "gemini-pro-orchestrator-neon"
                case "argon": return "gemini-pro-orchestrator-argon"
                case "carbon": return "gemini-pro-orchestrator"
                default: return "gemini-pro-orchestrator-\(inside)"
                }
            }
        }
        let lower = base.lowercased()
        let slug: String
        if lower.hasPrefix("claude ") {
            slug = lower.replacingOccurrences(of: ".", with: "-")
                .split(whereSeparator: \.isWhitespace).joined(separator: "-")
        } else {
            slug = lower.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        }
        if let effort { return "\(slug)-\(effort)" }
        return slug
    }
}
