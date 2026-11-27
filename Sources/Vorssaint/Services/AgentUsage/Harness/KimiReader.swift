// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Kimi Code session wires. Each session's main agent appends one line
/// per event to its own `wire.jsonl`. A prompt opens a turn, each request's
/// usage record keeps it busy and counts its tokens, and the turn's own
/// ending closes it again. Prompts, replies and tool output are never read.
struct KimiReader: AgentHarnessReader {
    var provider: AgentProvider { .kimi }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        // Structural type tags are written without spaces and never appear
        // unescaped inside a string value, so a byte match is a safe filter.
        if AgentLogParser.contains(line, #""type":"usage.record""#) { return usage(line, state: &state, now: now) }
        if AgentLogParser.contains(line, #""type":"turn.prompt""#) { return prompt(line, state: &state, now: now) }
        if AgentLogParser.contains(line, #""type":"turn.ended""#) { return ended(line, state: &state, now: now) }
        if AgentLogParser.contains(line, #""type":"context.append_loop_event""#) {
            return loopEvent(line, state: &state, now: now)
        }
        if AgentLogParser.contains(line, #""type":"changeNotifier.snapshot""#) {
            adoptWorkspace(line, into: &state)
        }
        return []
    }

    /// The person's own prompt opens the turn; injected reminders and tool
    /// results arrive as plain context messages instead.
    private func prompt(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), envelope.string("type") == "turn.prompt",
              envelope.object("origin")?.string("kind") == "user" else { return [] }
        let date = Self.date(envelope) ?? now
        var entries: [AgentLogEntry] = []
        // A new prompt closes the turn before it unfinished, as after one
        // that was stopped or failed without its own ending.
        if state.turnOpen { entries.append(.turnEnded(date, completed: false, duration: nil)) }
        state.turnOpen = true
        entries.append(.turnBegan(date))
        return entries
    }

    /// Steps tell the loop is alive. A step expecting tool work to follow
    /// keeps the turn; its other endings are announced by `turn.ended`.
    private func loopEvent(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), envelope.string("type") == "context.append_loop_event",
              let event = envelope.object("event"), let type = event.string("type") else { return [] }
        let date = Self.date(envelope) ?? now
        switch type {
        case "step.begin":
            // A read that starts inside a turn still shows it working.
            let open = state.turnOpen
            state.turnOpen = true
            return [open ? .turnActive(date) : .turnBegan(date)]
        case "step.end":
            guard event.string("finishReason") == "tool_use" else { return [] }
            guard state.turnOpen else { return [] }
            return [.turnActive(date)]
        default:
            return []
        }
    }

    /// The turn's own ending, written however it finished: completed, failed
    /// or cancelled. A duration is recorded once it is done.
    private func ended(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), envelope.string("type") == "turn.ended",
              state.turnOpen else { return [] }
        let date = Self.date(envelope) ?? now
        let milliseconds = envelope.unsignedInteger("durationMs")
        state.turnOpen = false
        return [.turnEnded(date, completed: envelope.string("reason") == "completed",
                           duration: milliseconds.map { Double($0) / 1000 })]
    }

    /// One model request's counters. `step.end` repeats the same usage, so
    /// only these records count; a zero reading never does.
    private func usage(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), envelope.string("type") == "usage.record",
              let usage = envelope.object("usage") else { return [] }
        let tokens = AgentTokens(input: Self.count("inputOther", in: usage),
                                 cacheWrite: Self.count("inputCacheCreation", in: usage),
                                 cacheRead: Self.count("inputCacheRead", in: usage),
                                 output: Self.count("output", in: usage), reasoning: 0)
        guard tokens.total > 0 else { return [] }
        let model = envelope.string("model", maxBytes: 128).map(AgentLogParser.native) ?? ""
        if !model.isEmpty { state.model = model }
        let date = Self.date(envelope) ?? now
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        // The moment identifies the request across replays and restarts.
        let stamp = envelope.unsignedInteger("time").map(String.init) ?? String(date.timeIntervalSince1970)
        let key = "kimi:\(state.session):\(stamp)"
        let record = AgentUsageRecord(provider: .kimi, date: date, model: model, project: state.project,
                                      session: state.session, tokens: tokens, cost: priced.cost,
                                      savings: priced.savings)
        return [.usage(key: key, record: record, billable: billable)]
    }

    /// The workspace snapshot names the folders the session works in, so the
    /// project is known before any turn starts.
    private func adoptWorkspace(_ line: Data, into state: inout AgentLogState) {
        guard state.project.isEmpty, let json = AgentLogParser.object(line),
              json["type"] as? String == "changeNotifier.snapshot",
              let workspaces = json["workspacePrimaryByWorkspace"] as? [String: Any] else { return }
        let folders = workspaces.values.compactMap { $0 as? String }.sorted()
        guard let primary = folders.first else { return }
        state.project = AgentLogParser.projectName(primary)
    }

    /// The session id comes from the wire's path, so usage is attributed
    /// before any line is decoded.
    static func adopt(path: String, into state: inout AgentLogState) {
        guard state.session.isEmpty else { return }
        let session = (path as NSString).pathComponents.first { $0.hasPrefix("session_") } ?? ""
        if !session.isEmpty { state.session = AgentLogParser.native(session) }
    }

    private static func date(_ envelope: AgentLogObject) -> Date? {
        envelope.unsignedInteger("time").flatMap(AgentLogParser.seconds)
    }

    private static func count(_ field: String, in usage: AgentLogObject) -> Int {
        min(usage.unsignedInteger(field) ?? 0, 1_000_000_000_000)
    }
}
