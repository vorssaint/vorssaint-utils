// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Cursor's agent transcripts, the Anthropic-shaped JSONL lines the
/// Cursor IDE and CLI keep under `~/.cursor/projects/`. A prompt opens a
/// turn, a reply keeps it going and records its usage when the line carries
/// one, and the transcript's own turn control line closes it. Only session
/// identity, turn edges, model names and usage counters are decoded; the
/// prompt and reply text is searched for the turn's time and left alone.
struct CursorReader: AgentHarnessReader {
    var provider: AgentProvider { .cursor }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        if AgentLogParser.contains(line, #""type":"turn_ended""#) { return turnEnded(line, state: &state, now: now) }
        // A reply can quote a role field inside its text; the byte tests only
        // keep candidate lines, the decoded role decides.
        guard AgentLogParser.contains(line, #""role":"user""#) || AgentLogParser.contains(line, #""role":"assistant""#), let json = AgentLogParser.object(line), let message = json["message"] as? [String: Any] else { return [] }
        switch json["role"] as? String {
        case "user": return user(message, json: json, state: &state, now: now)
        case "assistant": return assistant(json, message: message, state: &state, now: now)
        default: return []
        }
    }

    private func user(_ message: [String: Any], json: [String: Any], state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        let date = AgentLogParser.timestamp(json["timestamp"]) ?? stamp(message) ?? now
        var entries: [AgentLogEntry] = []
        entries.append(state.turnOpen ? .turnActive(date) : .turnBegan(date))
        state.turnOpen = true
        // The transcript's path names the session and project: the turn
        // keeps what the cursor gave it, whatever the lines say.
        entries.append(.turnContext(model: state.model, project: state.project))
        return entries
    }

    private func assistant(_ json: [String: Any], message: [String: Any], state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        let date = AgentLogParser.timestamp(json["timestamp"]) ?? now
        var entries: [AgentLogEntry] = []
        // Not every transcript writes a model; unknown stays the way the
        // island shows an unknown model, empty.
        if let model = model(message) { state.model = model }
        if let usage = usage(message, date: date, state: state) {
            entries.append(usage)
        }
        entries.insert(state.turnOpen ? .turnActive(date) : .turnBegan(date), at: 0)
        state.turnOpen = true
        return entries
    }

    private func turnEnded(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line), state.turnOpen else { return [] }
        state.turnOpen = false
        let date = AgentLogParser.timestamp(json["timestamp"]) ?? now
        let status = AgentLogParser.native(json["status"] as? String ?? "")
        let finished = !["error", "failed", "aborted", "interrupted", "cancelled"].contains(status.lowercased())
        return [.turnEnded(date, completed: finished, duration: nil)]
    }

    /// The model a reply names, when the transcript carries one at all: the
    /// flat field the manager writes beside the message, or Anthropic's
    /// dictionary shape when present.
    private func model(_ message: [String: Any]) -> String? {
        if let model = message["model"] as? String, !model.isEmpty, !model.hasPrefix("<") {
            return AgentLogParser.native(model)
        }
        if let model = (message["modelInfo"] as? [String: Any])?["modelId"] as? String, !model.isEmpty {
            return AgentLogParser.native(model)
        }
        return nil
    }

    /// What one reply used, priced from the list when it knows the model.
    /// Older or IDE transcripts carry no usage at all; a reply without any
    /// is activity only, which is all the island has to show.
    private func usage(_ message: [String: Any], date: Date, state: AgentLogState) -> AgentLogEntry? {
        guard let usage = message["usage"] as? [String: Any] else { return nil }
        let reasoning = AgentLogParser.int((usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"])
        let tokens = AgentTokens(
            input: AgentLogParser.int(usage["input_tokens"]),
            cacheWrite: AgentLogParser.int(usage["cache_creation_input_tokens"]),
            cacheRead: AgentLogParser.int(usage["cache_read_input_tokens"]),
            output: AgentLogParser.int(usage["output_tokens"]) + reasoning, reasoning: reasoning)
        guard tokens.total > 0 else { return nil }
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: state.model)
        let id = AgentLogParser.native(usage["message_id"] as? String ?? "")
        let key = id.isEmpty
            ? "cursor:\(state.session):\(date.timeIntervalSince1970)"
            : "cursor:\(state.session):\(id)"
        let record = AgentUsageRecord(provider: .cursor, date: date, model: state.model, project: state.project,
                                      session: state.session, tokens: tokens, cost: priced.cost,
                                      savings: priced.savings)
        return .usage(key: key, record: record, billable: billable)
    }

    // MARK: Times

    /// The block Cursor writes ahead of a person's words:
    /// `<timestamp>Sunday, Jul 26, 2026, 1:06 PM (UTC+3)</timestamp>`. The
    /// rest of the text is looked at no further than this block.
    private func stamp(_ message: [String: Any]) -> Date? {
        for block in message["content"] as? [[String: Any]] ?? []
        where block["type"] as? String == "text" {
            if let date = turnStamp(block["text"] as? String ?? "") { return date }
        }
        return nil
    }

    /// Reads that block without a regular expression: the block's own
    /// layout is fixed, and the zone is an offset from UTC spelled the way
    /// the shell prints it. A transcript without one, or with a shape this
    /// cannot read, keeps the moment the line was read.
    private func turnStamp(_ text: String) -> Date? {
        guard let opening = text.range(of: "<timestamp>"),
              let closing = text.range(of: "</timestamp>", range: opening.upperBound..<text.endIndex) else { return nil }
        var stamp = String(text[opening.upperBound..<closing.lowerBound]).trimmingCharacters(in: .whitespaces)
        var offsetSeconds = 0
        // The day of the week the person's zone prints first is decoration;
        // the date that follows it is all that is read.
        if let comma = stamp.firstIndex(of: ","), !stamp[..<comma].contains(where: { $0.isNumber }) {
            stamp = String(stamp[stamp.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        }
        if stamp.contains("(UTC"), let sign = stamp.first(where: { $0 == "+" || $0 == "-" }) {
            let hoursMinutes = String(stamp[stamp.firstIndex(of: sign)!...]).dropFirst()
                .prefix { $0.isNumber || $0 == ":" }
            let parts = hoursMinutes.split(separator: ":")
            guard let hours = Int(parts.first ?? ""), (0...14).contains(hours) else { return nil }
            let minutes = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            offsetSeconds = (hours * 3600 + minutes * 60) * (sign == "+" ? 1 : -1)
            stamp = String(stamp[..<(stamp.range(of: "(")!.lowerBound)]).trimmingCharacters(in: .whitespaces)
        }
        let format = Self.formats.first { $0.date(from: stamp) != nil }
        guard let read = format?.date(from: stamp) else { return nil }
        return read.addingTimeInterval(TimeInterval(-offsetSeconds))
    }

    private static var formats: [DateFormatter] {
        [
            { let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "MMMM d, yyyy, h:mm a"; return format }(),
            { let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "MMM d, yyyy, h:mm a"; return format }(),
        ]
    }
}
