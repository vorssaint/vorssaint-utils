// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Oh My Pi's session JSONL. Main and side-channel replies all count
/// toward usage; only main session files own live turns. `AgentLogObject`
/// reads envelope fields without decoding prompts, replies or tool output.
struct OMPReader: AgentHarnessReader {
    var provider: AgentProvider { .omp }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let object = AgentLogObject(line), let type = object.string("type"),
              ["session", "model_change", "message", "model_usage"].contains(type)
        else { return [] }

        switch type {
        case "session":
            state.session = object.string("id") ?? ""
            state.project = object.string("cwd").map(AgentLogParser.projectName) ?? ""
            state.model = ""
            state.turnOpen = false
            return []

        case "model_change":
            if let role = object.string("role"), role != "default" { return [] }
            guard let model = object.string("model"), !model.isEmpty else { return [] }
            state.model = AgentLogParser.native(model)
            return state.turnOpen ? [.turnContext(model: state.model, project: state.project)] : []

        case "model_usage":
            guard let date = AgentLogParser.timestamp(object.value("timestamp")),
                  let usage = object.object("usage")
            else { return [] }
            let model = object.string("model").map(AgentLogParser.native) ?? state.model
            return usageRecord(id: object.string("id") ?? "", usage: usage, date: date,
                               model: model, state: state).map { [$0] } ?? []

        case "message":
            guard let message = object.object("message"), let role = message.string("role"),
                  let date = AgentLogParser.timestamp(object.value("timestamp"))
            else { return [] }
            switch role {
            case "user":
                if state.turnOpen { return [.turnActive(date)] }
                state.turnOpen = true
                return [.turnBegan(date), .turnContext(model: state.model, project: state.project)]

            case "toolResult":
                return state.turnOpen ? [.turnActive(date)] : []

            case "assistant":
                if let model = message.string("model"), !model.isEmpty {
                    state.model = AgentLogParser.native(model)
                }
                var entries: [AgentLogEntry] = []
                if let usage = message.object("usage"),
                   let record = usageRecord(id: object.string("id") ?? "", usage: usage, date: date,
                                            model: state.model, state: state) {
                    entries.append(record)
                }
                guard state.turnOpen else { return entries }
                let stop = message.string("stopReason")
                let failed = message.value("error").map { !($0 is NSNull) } ?? false
                if !failed && (stop == nil || stop == "toolUse") {
                    entries.append(.turnActive(date))
                } else {
                    state.turnOpen = false
                    entries.append(.turnEnded(date, completed: !failed && stop != "aborted" && stop != "error",
                                              duration: nil))
                }
                return entries

            default:
                return []
            }

        default:
            return []
        }
    }

    /// Main sessions have Oh My Pi's timestamp-and-UUID filename. Named
    /// subagent sessions and the advisor sidecar contribute usage, not turns.
    static func isMainSession(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.range(of: #"^\d{4}-\d{2}-\d{2}T[^_]+_[0-9a-fA-F-]{36}\.jsonl$"#,
                          options: .regularExpression) != nil
    }

    /// The main log beside the session directory holding a sidecar or
    /// subagent, including subagents nested in folders of their own.
    static func parent(of path: String) -> String? {
        guard !isMainSession(path) else { return nil }
        var directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.deletingLastPathComponent()
                .appending(path: directory.lastPathComponent + ".jsonl", directoryHint: .notDirectory)
            if isMainSession(candidate.path) { return candidate.path }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    private func usageRecord(id: String, usage: AgentLogObject, date: Date,
                             model: String, state: AgentLogState) -> AgentLogEntry? {
        let tokens = AgentTokens(input: AgentLogParser.int(usage.value("input")),
                                 cacheWrite: AgentLogParser.int(usage.value("cacheWrite")),
                                 cacheRead: AgentLogParser.int(usage.value("cacheRead")),
                                 output: AgentLogParser.int(usage.value("output")))
        let rawCost = (usage.object("cost")?.value("total") as? NSNumber)?.doubleValue
        let recordedCost = rawCost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        guard tokens.total > 0 || (recordedCost ?? 0) > 0 else { return nil }
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        let cost: Double?
        let reported: Bool
        if let calculated = priced.cost {
            cost = calculated
            reported = false
        } else {
            cost = recordedCost
            reported = (recordedCost ?? 0) > 0
        }
        let identity = id.isEmpty ? "\(date.timeIntervalSince1970)" : id
        let key = "omp:\(state.session):\(identity)"
        let record = AgentUsageRecord(provider: .omp, date: date, model: model, project: state.project,
                                      session: state.session, tokens: tokens, cost: cost,
                                      savings: priced.savings, reportedCost: reported)
        return .usage(key: key, record: record, billable: billable)
    }
}
