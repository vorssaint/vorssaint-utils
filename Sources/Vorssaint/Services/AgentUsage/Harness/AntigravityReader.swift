// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Antigravity IDE and CLI session transcripts (`transcript.jsonl`).
/// Only step counters, timestamps, measured token counts, model names and
/// workspace folder names are kept; prompts, replies, thinking traces and
/// tool payloads are never stored.
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let first = line.first(where: { ![9, 10, 13, 32].contains($0) }), first == 0x7B,
              let object = AgentLogObject(line), let type = object.string("type") else { return [] }
        let firstLine = !state.codexHeaderRead
        state.codexHeaderRead = true
        guard ["SYSTEM_MESSAGE", "USER_INPUT", "PLANNER_RESPONSE",
               "GENERIC", "TOOL_RESULT", "MEMORY_OPERATION"].contains(type) else { return [] }
        let date = object.string("created_at").flatMap(AgentTimestamp.parse)
            ?? AgentLogParser.timestamp(object.value("created_at")) ?? now

        switch type {
        case "SYSTEM_MESSAGE":
            let step = Self.int(object, "step_index")
            if (step.map { $0 == 0 } ?? firstLine), object.string("source") == "SYSTEM" {
                let content = object.string("content") ?? ""
                if let sender = Self.extractSubagentSender(from: content) {
                    state.antigravitySubagent = true
                    state.antigravityRoot = AgentLogParser.native(sender)
                }
                Self.adoptWorkspace(from: content, into: &state)
            }
            return []

        case "USER_INPUT":
            let source = object.string("source")
            guard source == "USER_EXPLICIT" || source == nil else { return [] }
            let content = object.string("content") ?? ""
            Self.adoptWorkspace(from: content, into: &state)
            if let selected = Self.extractModelSelection(from: content) {
                state.model = AgentLogParser.native(selected)
            }
            guard !state.antigravitySubagent else { return [] }
            var entries: [AgentLogEntry] = []
            if state.turnOpen {
                entries.append(.turnEnded(nil, completed: false, duration: nil))
            }
            state.turnOpen = true
            entries.append(.turnBegan(date))
            if !state.model.isEmpty || !state.project.isEmpty {
                entries.append(.turnContext(model: state.model, project: state.project))
            }
            return entries

        case "PLANNER_RESPONSE":
            if let explicit = (object.string("model") ?? object.string("modelName"))?
                .trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
                state.model = AgentLogParser.native(explicit)
            }
            let toolCalls = object.hasItems("tool_calls")
                ? (object.value("tool_calls") as? [[String: Any]] ?? []) : []
            if state.antigravityNamedWorkspace.isEmpty, state.project.isEmpty,
               let cwd = Self.extractCommandDirectory(from: toolCalls) {
                let name = AgentLogParser.projectName(cwd)
                if !name.isEmpty { state.project = name }
            }

            let step = Self.int(object, "step_index")
            let key: String
            if let step {
                key = "antigravity:\(state.session):\(step)"
            } else {
                let stamp = object.string("created_at") ?? "\(date.timeIntervalSince1970)"
                key = "antigravity:\(state.session):\(stamp)"
            }

            let input = Self.int(object, "input_tokens")
            let cacheWrite = Self.int(object, "cache_creation_input_tokens")
            let cacheRead = Self.int(object, "cache_read_tokens")
            let output = Self.int(object, "output_tokens")
            let reasoning = Self.int(object, "thinking_tokens")
            let hasMeasuredTokens = input != nil || cacheWrite != nil || cacheRead != nil
                || output != nil || reasoning != nil

            var entries: [AgentLogEntry] = []
            if hasMeasuredTokens {
                let tokens = AgentTokens(input: max(0, input ?? 0),
                                         cacheWrite: max(0, cacheWrite ?? 0),
                                         cacheRead: max(0, cacheRead ?? 0),
                                         output: max(0, output ?? 0),
                                         reasoning: max(0, reasoning ?? 0))
                let billable = AgentBillable(tokens: tokens)
                let priced = state.model.isEmpty
                    ? (cost: nil as Double?, savings: 0.0) : AgentPricing.cost(billable, model: state.model)
                entries.append(.usage(key: key, record: AgentUsageRecord(
                    provider: .antigravity, date: date, model: state.model, project: state.project,
                    session: state.session, tokens: tokens, cost: priced.cost, savings: priced.savings),
                    billable: billable))
            } else {
                entries.append(.usage(key: key, record: AgentUsageRecord(
                    provider: .antigravity, date: date, model: state.model, project: state.project,
                    session: state.session, tokens: AgentTokens(), cost: nil, savings: 0),
                    billable: AgentBillable()))
            }

            guard !state.antigravitySubagent else { return entries }
            let status = object.string("status") ?? ""
            let rawError = object.value("error")
            let hasError = status == "ERROR" || (rawError != nil && !(rawError is NSNull))
            let hasToolCalls = !toolCalls.isEmpty

            if hasError {
                if state.turnOpen {
                    state.turnOpen = false
                    entries.append(.turnEnded(date, completed: false, duration: nil))
                }
            } else if hasToolCalls {
                if !state.turnOpen {
                    state.turnOpen = true
                    entries.append(.turnBegan(date))
                } else {
                    entries.append(.turnActive(date))
                }
                if !state.model.isEmpty || !state.project.isEmpty {
                    entries.append(.turnContext(model: state.model, project: state.project))
                }
            } else if status == "DONE" || status.isEmpty {
                if state.turnOpen {
                    state.turnOpen = false
                    entries.append(.turnEnded(date, completed: true, duration: nil))
                }
            }
            return entries

        case "GENERIC", "TOOL_RESULT", "MEMORY_OPERATION":
            guard !state.antigravitySubagent, state.turnOpen else { return [] }
            return [.turnActive(date)]

        default:
            return []
        }
    }

    // MARK: Metadata helpers

    private static func int(_ object: AgentLogObject, _ key: String) -> Int? {
        guard let number = object.value(key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              double >= Double(Int.min), double <= 1e12 else { return nil }
        return Int(double)
    }

    private static func extractSubagentSender(from content: String) -> String? {
        guard content.contains("[Message]"), let range = content.range(of: "sender=") else { return nil }
        let suffix = content[range.upperBound...]
        let token = suffix.prefix { byte in
            ("a"..."z").contains(byte) || ("A"..."Z").contains(byte) || ("0"..."9").contains(byte) || byte == "-"
        }
        return token.isEmpty ? nil : String(token)
    }

    private static func adoptWorkspace(from content: String, into state: inout AgentLogState) {
        if let range = content.range(of: "Active Workspaces:\n- ") {
            let line = Self.lineValue(after: range.upperBound, in: content)
            if !line.isEmpty {
                let project = AgentLogParser.projectName(line)
                if !project.isEmpty {
                    state.antigravityNamedWorkspace = project
                    state.project = project
                    return
                }
            }
        }
        guard state.antigravityNamedWorkspace.isEmpty,
              let range = content.range(of: "Command Working Directory: ") else { return }
        let line = Self.lineValue(after: range.upperBound, in: content)
        guard !line.isEmpty else { return }
        let project = AgentLogParser.projectName(line)
        if !project.isEmpty { state.project = project }
    }

    private static func lineValue(after start: String.Index, in text: String) -> String {
        let rest = text[start...]
        let end = rest.firstIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "<" }) ?? rest.endIndex
        return rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractModelSelection(from content: String) -> String? {
        let marker = "changed setting `Model Selection` from "
        guard content.contains(marker) else { return nil }
        // agy 1.5 writes the change in its own `<USER_SETTINGS_CHANGE>` block beside
        // `<ADDITIONAL_METADATA>`; older builds put it inside the metadata block.
        let systemTags = ["ADDITIONAL_METADATA", "USER_SETTINGS_CHANGE"]
        var slices: [Substring] = []
        for tag in systemTags {
            var cursor = content.startIndex
            while let open = content.range(of: "<\(tag)>", range: cursor..<content.endIndex) {
                let end = content.range(of: "</\(tag)>", range: open.upperBound..<content.endIndex)
                slices.append(content[open.upperBound..<(end?.lowerBound ?? content.endIndex)])
                cursor = end?.upperBound ?? content.endIndex
            }
        }
        if slices.isEmpty, !content.contains("<USER_REQUEST>") {
            slices.append(content[...])
        }
        var selected: String?
        for slice in slices {
            var search = slice.startIndex
            while let found = slice.range(of: marker, range: search..<slice.endIndex) {
                let afterFrom = slice[found.upperBound...]
                let lineEnd = afterFrom.firstIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "<" }) ?? afterFrom.endIndex
                let line = afterFrom[..<lineEnd]
                let toStart: Substring.Index?
                if line.first == "`",
                   let closingTick = line.dropFirst().firstIndex(of: "`") {
                    let afterTick = line.index(after: closingTick)
                    toStart = line[afterTick...].range(of: " to ")?.upperBound
                } else {
                    toStart = line.range(of: " to ")?.upperBound
                }
                if let toStart {
                    var candidate = line[toStart...]
                    for delimiter in [".\n", ".<", ". "] {
                        if let cut = candidate.range(of: delimiter) {
                            candidate = candidate[..<cut.lowerBound]
                        }
                    }
                    var cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.hasSuffix(".") { cleaned.removeLast() }
                    cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "` \t"))
                    if !cleaned.isEmpty { selected = cleaned }
                }
                search = lineEnd
            }
        }
        return selected
    }

    private static func toolName(_ call: [String: Any]) -> String? {
        if let name = call["name"] as? String { return name }
        return (call["function"] as? [String: Any])?["name"] as? String
    }

    private static func extractCommandDirectory(from toolCalls: [[String: Any]]) -> String? {
        for call in toolCalls where toolName(call) == "run_command" {
            let args: [String: Any]?
            if let dict = call["args"] as? [String: Any] {
                args = dict
            } else if let dict = call["arguments"] as? [String: Any] {
                args = dict
            } else if let raw = call["arguments"] as? String,
                      let data = raw.data(using: .utf8),
                      let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                args = dict
            } else {
                args = nil
            }
            if let cwd = (args?["Cwd"] as? String ?? args?["cwd"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
                return cwd
            }
        }
        return nil
    }
}

extension AgentLogParser {
    // MARK: Antigravity

    static func parseAntigravity(_ line: Data, state: inout AgentLogState, now: Date = Date()) -> [AgentLogEntry] {
        AntigravityReader().parse(line, state: &state, now: now)
    }
}
