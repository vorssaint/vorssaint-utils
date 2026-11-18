// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Reads Cursor agent transcripts under `~/.cursor/projects/*/agent-transcripts/`.
/// Only turn edges, times and the project folder name are taken; prompts,
/// replies and tool arguments stay unread beyond the structural keys needed
/// to tell a user prompt from an assistant step or a finished turn.
struct CursorReader: AgentHarnessReader {
    var provider: AgentProvider { .cursor }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        if AgentLogParser.contains(line, #""type":"turn_ended"#) {
            return turnEnded(line, state: &state, now: now)
        }
        if AgentLogParser.contains(line, #""role":"user"#) {
            return user(line, state: &state, now: now)
        }
        if AgentLogParser.contains(line, #""role":"assistant"#) {
            return assistant(line, state: &state, now: now)
        }
        return []
    }

    /// Session id and project folder taken from the transcript path, so the
    /// live strip has a name before any line is decoded.
    static func adopt(path: String, into state: inout AgentLogState) {
        if state.session.isEmpty {
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if !name.isEmpty { state.session = AgentLogParser.native(name) }
        }
        if state.project.isEmpty {
            let project = AgentLogParser.cursorProject(from: path)
            if !project.isEmpty { state.project = project }
        }
    }

    private func user(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), envelope.string("role") == "user" else { return [] }
        let date = cursorTimestamp(line) ?? now
        var entries: [AgentLogEntry] = []
        if state.turnOpen {
            state.turnOpen = false
            entries.append(.turnEnded(date, completed: false, duration: nil))
        }
        state.turnOpen = true
        entries.append(.turnBegan(date))
        if !state.project.isEmpty || !state.model.isEmpty {
            entries.append(.turnContext(model: state.model, project: state.project))
        }
        // A zero-token row marks Cursor as seen, like Copilot's activity rows.
        entries.append(activity(at: date, state: state))
        return entries
    }

    private func assistant(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), envelope.string("role") == "assistant" else { return [] }
        let date = cursorTimestamp(line) ?? now
        if state.turnOpen {
            return [.turnActive(date), .turnContext(model: state.model, project: state.project)]
        }
        // A resumed transcript can start mid-turn with an assistant line.
        state.turnOpen = true
        return [.turnBegan(date), .turnContext(model: state.model, project: state.project)]
    }

    private func turnEnded(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), envelope.string("type") == "turn_ended" else { return [] }
        guard state.turnOpen else { return [] }
        state.turnOpen = false
        let status = envelope.string("status") ?? "success"
        let completed = status == "success"
        return [.turnEnded(now, completed: completed, duration: nil)]
    }

    private func activity(at date: Date, state: AgentLogState) -> AgentLogEntry {
        let key = "cursor:\(state.session):\(date.timeIntervalSince1970):activity"
        return .usage(key: key, record: AgentUsageRecord(
            provider: .cursor, date: date, model: state.model, project: state.project, session: state.session,
            tokens: AgentTokens(), cost: 0, savings: 0), billable: AgentBillable())
    }

    /// Only the short `<timestamp>…</timestamp>` tag is decoded, never the
    /// surrounding prompt text.
    private func cursorTimestamp(_ line: Data) -> Date? {
        let open: StaticString = "<timestamp>"
        let close: StaticString = "</timestamp>"
        return line.withUnsafeBytes { raw -> Date? in
            guard let base = raw.baseAddress,
                  let start = memmem(base, raw.count, open.utf8Start, open.utf8CodeUnitCount) else { return nil }
            let value = base.distance(to: start) + open.utf8CodeUnitCount
            guard value < raw.count,
                  let end = memmem(base + value, raw.count - value, close.utf8Start, close.utf8CodeUnitCount)
            else { return nil }
            let stop = base.distance(to: end)
            guard stop > value, stop - value < 128 else { return nil }
            let text = String(decoding: UnsafeRawBufferPointer(rebasing: raw[value..<stop]), as: UTF8.self)
            return AgentTimestamp.parseCursor(text)
        }
    }
}

extension AgentTimestamp {
    /// Cursor agent transcripts write wall times like
    /// `Wednesday, Nov 18, 2026, 6:09 PM (UTC+8)`.
    static func parseCursor(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let iso = parse(trimmed) { return iso }
        guard let open = trimmed.lastIndex(of: "("), let close = trimmed.lastIndex(of: ")"),
              open < close else { return parseCursorBody(trimmed, offset: 0) }
        let body = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let zone = trimmed[trimmed.index(after: open)..<close]
        let offset: Int
        if zone.uppercased().hasPrefix("UTC") {
            let signIndex = zone.firstIndex(where: { $0 == "+" || $0 == "-" })
            if let signIndex {
                let sign = zone[signIndex] == "+" ? 1 : -1
                let digits = zone[zone.index(after: signIndex)...]
                    .split(separator: ":", omittingEmptySubsequences: false)
                let hours = Int(digits.first ?? "0") ?? 0
                let minutes = digits.count > 1 ? (Int(digits[1]) ?? 0) : 0
                offset = sign * (hours * 3600 + minutes * 60)
            } else {
                offset = 0
            }
        } else {
            offset = 0
        }
        return parseCursorBody(String(body), offset: offset)
    }

    private static func parseCursorBody(_ text: String, offset: Int) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEEE, MMM d, yyyy, h:mm a"
        guard let date = formatter.date(from: text) else { return nil }
        return date.addingTimeInterval(TimeInterval(-offset))
    }
}
