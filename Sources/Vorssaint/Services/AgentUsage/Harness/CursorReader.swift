// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Cursor's transcript records turn edges but no token counts or prices.
struct CursorReader: AgentHarnessReader {
    var provider: AgentProvider { .cursor }
    var replaying = false

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line) else { return [] }
        if let type = envelope.string("type") {
            guard type == "turn_ended", state.turnOpen else { return [] }
            state.turnOpen = false
            state.cursorLastActivity = now
            return [.turnEnded(now, completed: envelope.string("status") == "success", duration: nil)]
        }

        let context = AgentLogEntry.turnContext(model: state.model, project: state.project)
        switch envelope.string("role") {
        case "user":
            state.cursorPromptCount += 1
            let timestamp = Self.promptTimestamp(envelope)
            state.cursorPromptTimestamp = timestamp?.date
            // Cursor's prompt tag has minute precision. Measure a new turn
            // from observation so a short task cannot earn a long-task alert.
            // When attaching mid-turn, the latest possible start within that
            // minute gives a lower bound on the elapsed time.
            let date = replaying ? min(timestamp?.latest ?? now, now) : now
            var entries: [AgentLogEntry] = []
            if state.turnOpen { entries.append(.turnEnded(date, completed: false, duration: nil)) }
            state.turnOpen = true
            state.cursorLastActivity = replaying ? min(timestamp?.date ?? now, now) : now
            entries.append(.turnBegan(date))
            entries.append(context)
            return entries
        case "assistant":
            let event: AgentLogEntry = state.turnOpen ? .turnActive(now) : .turnBegan(now)
            state.turnOpen = true
            state.cursorLastActivity = now
            return [event, context]
        default:
            return []
        }
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

    /// Compared only within this process when a transcript is rewritten.
    static func promptFingerprint(_ line: Data) -> UInt64 {
        var hasher = Hasher()
        line.withUnsafeBytes { hasher.combine(bytes: $0) }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private static let tag = Data("<timestamp>".utf8)
    private static let endTag = Data("</timestamp>".utf8)
    private static let escapedEndTag = Data(#"<\/timestamp>"#.utf8)

    /// Cursor prefixes the first user text block with metadata. Tags quoted
    /// in the query, replies and tool inputs do not describe the turn.
    private static func promptTimestamp(_ envelope: AgentLogObject) -> (date: Date, latest: Date)? {
        guard let first = envelope.object("message")?.firstObject(inArray: "content"),
              first.string("type") == "text", let prefix = first.stringPrefix("text", maxBytes: 160),
              prefix.starts(with: tag) else { return nil }
        let body = prefix.dropFirst(tag.count)
        guard let close = body.firstIndex(of: 0x3C),
              body[close...].starts(with: endTag) || body[close...].starts(with: escapedEndTag) else { return nil }
        let text = String(decoding: body[..<close], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = AgentTimestamp.parseCursor(text) else { return nil }
        return (date, text.first?.isNumber == true ? date : date.addingTimeInterval(60))
    }
}

extension AgentTimestamp {
    private static let cursorWallClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEEE, MMM d, yyyy, h:mm a"
        return formatter
    }()

    /// Cursor writes local time like `Wednesday, Nov 18, 2026, 6:09 PM (UTC+8)`.
    static func parseCursor(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first?.isNumber == true {
            guard validCursorISODay(trimmed),
                  trimmed.hasSuffix("Z") || (trimmed.count >= 6 && cursorOffset(trimmed.suffix(6)) != nil)
            else { return nil }
            return parse(trimmed)
        }
        guard trimmed.hasSuffix(")"), let open = trimmed.range(of: " (UTC", options: .backwards),
              let date = cursorWallClock.date(from: String(trimmed[..<open.lowerBound])) else { return nil }
        let zone = trimmed[open.upperBound...].dropLast()
        guard let offset = cursorOffset(zone) else { return nil }
        return date.addingTimeInterval(-TimeInterval(offset))
    }

    /// The shared ISO reader converts days arithmetically, so an impossible
    /// day would otherwise roll into the following month.
    private static func validCursorISODay(_ text: String) -> Bool {
        let fields = text.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0].utf8.count == 4, fields[1].utf8.count == 2, fields[2].utf8.count == 2,
              fields.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]),
              (1...12).contains(month) else { return false }
        let lastDay: Int
        switch month {
        case 2:
            let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
            lastDay = leap ? 29 : 28
        case 4, 6, 9, 11: lastDay = 30
        default: lastDay = 31
        }
        return (1...lastDay).contains(day)
    }

    private static func cursorOffset(_ zone: Substring) -> Int? {
        if zone.isEmpty { return 0 }
        guard zone.first == "+" || zone.first == "-" else { return nil }
        let parts = zone.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), (1...2).contains(parts[0].utf8.count),
              parts[0].utf8.allSatisfy({ (48...57).contains($0) }),
              let hours = Int(parts[0]), hours <= 23 else { return nil }
        var minutes = 0
        if parts.count == 2 {
            guard parts[1].utf8.count == 2, parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  let value = Int(parts[1]), value < 60 else { return nil }
            minutes = value
        }
        return (hours * 3600 + minutes * 60) * (zone.first == "-" ? -1 : 1)
    }
}
