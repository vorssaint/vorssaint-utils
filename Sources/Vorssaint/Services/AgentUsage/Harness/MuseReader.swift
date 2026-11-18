// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Muse session logs, one event record per line. Session metadata,
/// run boundaries and the token counts of each model call and automated
/// approval review are kept; prompts, replies, reasoning and tool output
/// are never read from the lines that hold them.
struct MuseReader: AgentHarnessReader {
    var provider: AgentProvider { .muse }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        // A run's start carries the prompt, and tool records their output, so
        // only lines with a structural kind worth reading are decoded.
        let run = AgentLogParser.contains(line, #""payload":{"kind":"run""#)
        guard run || AgentLogParser.contains(line, #""kind":"automated_review_completed""#)
                || AgentLogParser.contains(line, #""payload":{"kind":"metadata""#)
                || AgentLogParser.contains(line, #""payload":{"kind":"run_model""#),
              let envelope = AgentLogObject(line), let payload = envelope.object("payload") else { return [] }
        let date = Self.date(envelope.value("recorded_at")) ?? now
        if state.session.isEmpty, let stream = envelope.object("stream"), let id = stream.string("id"), !id.isEmpty {
            state.session = AgentLogParser.native(id)
        }
        switch payload.string("kind") {
        case "metadata":
            guard let record = payload.object("record") else { return [] }
            if let root = record.string("workspace_root"), !root.isEmpty { state.project = AgentLogParser.projectName(root) }
            if let model = record.string("model_id"), !model.isEmpty { state.model = AgentLogParser.native(model) }
            return []
        case "run_model":
            guard let model = payload.object("record")?.string("model_id"), !model.isEmpty else { return [] }
            state.model = AgentLogParser.native(model)
            return state.turnOpen ? [.turnContext(model: state.model, project: state.project)] : []
        case "run":
            guard let event = payload.object("event") else { return [] }
            return runEvent(event, id: envelope.string("id"), date: date, state: &state)
        case "approval":
            // A reviewer model checks a risky action. Its own log beside the
            // session is never read, so these calls are counted once, here.
            guard let event = payload.object("event"), event.string("kind") == "automated_review_completed",
                  let usage = event.value("usage") as? [String: Any] else { return [] }
            let model = event.object("model")?.string("model_id").flatMap { $0.isEmpty ? nil : AgentLogParser.native($0) }
            return call(usage, model: model ?? state.model, id: envelope.string("id"), date: date, state: state)
        default:
            return []
        }
    }

    private func runEvent(_ event: AgentLogObject, id: String?, date: Date, state: inout AgentLogState) -> [AgentLogEntry] {
        switch event.string("kind") {
        case "started":
            let entry: AgentLogEntry = state.turnOpen ? .turnActive(date) : .turnBegan(date)
            state.turnOpen = true
            return [entry, .turnContext(model: state.model, project: state.project)]
        case "model_completed":
            guard let usage = event.value("usage") as? [String: Any] else { return [] }
            if let model = event.string("model"), !model.isEmpty { state.model = AgentLogParser.native(model) }
            return call(usage, model: state.model, id: id, date: date, state: state)
        case "terminal":
            guard state.turnOpen else { return [] }
            state.turnOpen = false
            let duration = (event.value("turn_duration_ms") as? NSNumber).map { $0.doubleValue / 1000 }
            return [.turnEnded(date, completed: event.string("terminal") == "completed", duration: duration)]
        default:
            return []
        }
    }

    private func call(_ usage: [String: Any], model: String, id: String?, date: Date,
                      state: AgentLogState) -> [AgentLogEntry] {
        let tokens = Self.tokens(usage)
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        // Every record has its own id; one written twice is one call.
        let key = "muse:" + (id.flatMap { $0.isEmpty ? nil : AgentLogParser.native($0) }
                             ?? "\(state.session):\(date.timeIntervalSince1970)")
        var entries: [AgentLogEntry] = [.usage(key: key, record: AgentUsageRecord(
            provider: .muse, date: date, model: model, project: state.project, session: state.session,
            tokens: tokens, cost: priced.cost, savings: priced.savings), billable: billable)]
        if state.turnOpen { entries.append(.turnActive(date)) }
        return entries
    }

    /// Input counts include what came from the cache, which model calls
    /// name `cached_tokens` and approval reviews `cached_input_tokens`.
    static func tokens(_ usage: [String: Any]) -> AgentTokens {
        let input = AgentLogParser.int(usage["input_tokens"])
        let cached = ["cache_read_tokens", "cached_tokens", "cached_input_tokens"].map { AgentLogParser.int(usage[$0]) }.max() ?? 0
        let read = min(input, cached)
        let written = min(input - read, AgentLogParser.int(usage["cache_write_tokens"]))
        return AgentTokens(input: input - read - written, cacheWrite: written, cacheRead: read,
                           output: AgentLogParser.int(usage["output_tokens"]),
                           reasoning: AgentLogParser.int(usage["reasoning_tokens"]))
    }

    /// Muse stamps records in microseconds since 1970.
    static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw / 1_000_000)
    }
}
