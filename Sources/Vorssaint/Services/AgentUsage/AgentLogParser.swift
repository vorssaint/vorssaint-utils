// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// What one log line says, reduced to the few facts the island keeps. Only
/// usage counters, model names, times and folder names leave a line, besides
/// the identifiers of Claude's shell commands still running, held in memory
/// only; prompts, replies and tool output are never decoded into anything
/// that is stored.
enum AgentLogEntry: Equatable {
    /// `key` identifies the response across duplicate lines and files.
    case usage(key: String, record: AgentUsageRecord, billable: AgentBillable)
    case turnBegan(Date)
    /// Work continues; nil when the line was not worth decoding for its time.
    case turnActive(Date?)
    case turnEnded(Date?, completed: Bool, duration: TimeInterval?)
    /// The turn stopped on something only the person can answer; `inferred`
    /// when the log only suggests it.
    case turnAwaiting(AgentAwait, Date, inferred: Bool)
}

extension AgentLogEntry {
    /// What a log only counted, never followed, still gives.
    var isUsage: Bool {
        switch self {
        case .usage: return true
        default: return false
        }
    }
}

/// Why a turn now waits on the person.
enum AgentAwait: String, Equatable {
    case permission, question, plan, dialog, interrupted
}

/// Per-file context carried from line to line.
struct AgentLogState: Equatable {
    var session = ""
    var project = ""
    var model = ""
    var turnOpen = false
    /// Claude's shell commands still waiting for their result, by tool call.
    /// They run on the Mac, so the turn goes on without the network.
    var runningCommands: Set<String> = []
    /// Claude's questions and plans still waiting for the person, by tool
    /// call. In memory only, like the commands.
    var awaitedTools: [String: AgentAwait] = [:]
    /// Claude's other tool calls still waiting for their result, by call,
    /// which may wait on an approval the log never mentions.
    var pendingTools: Set<String> = []
}

enum AgentLogParser {
    // MARK: Byte tests

    /// Structural keys are written without spaces and never appear unescaped
    /// inside a string value, so a byte match is a safe first filter.
    static func contains(_ line: Data, _ needle: StaticString) -> Bool {
        line.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, bytes.count >= needle.utf8CodeUnitCount else { return false }
            return memmem(base, bytes.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
        }
    }

    /// Every tool call a tool result line answers. The key is structural, so
    /// a result quoting it holds it escaped and never matches.
    static func toolResultIDs(_ line: Data) -> [String] {
        let key: StaticString = #""tool_use_id":""#
        return line.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return [] }
            var ids: [String] = []
            var start = 0
            while start < bytes.count,
                  let found = memmem(base + start, bytes.count - start, key.utf8Start, key.utf8CodeUnitCount) {
                let value = base.distance(to: found) + key.utf8CodeUnitCount
                let limit = min(bytes.count, value + 128)
                guard value < limit, let quote = memchr(base + value, 0x22, limit - value) else { break }
                let end = base.distance(to: UnsafeRawPointer(quote))
                ids.append(String(decoding: UnsafeRawBufferPointer(rebasing: bytes[value..<end]), as: UTF8.self))
                start = end + 1
            }
            return ids
        }
    }

    static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    // MARK: Claude Code

    static func parseClaude(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        ClaudeReader().parse(line, state: &state, now: now)
    }

    // MARK: Shared values

    /// The folder an agent ran in names the project. A worktree kept inside
    /// the repository still belongs to that repository.
    static func projectName(_ path: String) -> String {
        var path = path
        // A log synced from a Windows computer names its folder as C:\code\app.
        let windows = path.hasPrefix("\\\\") || path.dropFirst().hasPrefix(":\\") || path.dropFirst().hasPrefix(":/")
        if windows { path = path.replacingOccurrences(of: "\\", with: "/") }
        if let range = path.range(of: "/.claude/worktrees/") { path = String(path[..<range.lowerBound]) }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let name = (path as NSString).lastPathComponent
        // A drive's root names no project.
        return windows && name.hasSuffix(":") ? "" : native(name)
    }

    /// Text decoded from a line arrives bridged from Foundation, and every
    /// record keeps it. The summary hashes and compares these per response on
    /// each refresh, which bridged text does through Unicode normalization,
    /// many times slower than with Swift's own UTF-8 storage.
    static func native(_ text: String) -> String {
        String(decoding: text.utf8, as: UTF8.self)
    }

    static func int(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        let double = number.doubleValue
        guard double.isFinite, double > 0 else { return 0 }
        // A damaged line must not overflow the sums it joins.
        return Int(min(double, 1e12))
    }

    /// Unix seconds, or milliseconds from agents that write those.
    static func seconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
    }

    static func timestamp(_ value: Any?) -> Date? {
        guard let text = value as? String else { return seconds(value) }
        return AgentTimestamp.parse(text)
    }
}

/// ISO 8601 times as both agents write them, "2026-09-21T23:42:45.078Z",
/// read without a formatter; anything else goes through one.
enum AgentTimestamp {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let whole = ISO8601DateFormatter()
    private static let lock = NSLock()

    static func parse(_ text: String) -> Date? {
        if let date = fast(Array(text.utf8)) { return date }
        return lock.withLock { fractional.date(from: text) ?? whole.date(from: text) }
    }

    private static func fast(_ b: [UInt8]) -> Date? {
        guard b.count >= 20, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(b[index]) - 0x30
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }
        var index = 19
        var fraction = 0.0
        if b[index] == 0x2E {
            var scale = 0.1
            index += 1
            while index < b.count, (0x30...0x39).contains(b[index]) {
                fraction += Double(b[index] - 0x30) * scale
                scale /= 10
                index += 1
            }
        }
        guard index < b.count else { return nil }
        var offset = 0
        if b[index] == 0x5A {
            guard index == b.count - 1 else { return nil }
        } else if b[index] == 0x2B || b[index] == 0x2D, b.count == index + 6, b[index + 3] == 0x3A,
                  let hours = number(index + 1..<index + 3), let minutes = number(index + 4..<index + 6) {
            offset = (hours * 3600 + minutes * 60) * (b[index] == 0x2B ? 1 : -1)
        } else {
            return nil
        }
        // Days since 1970 from the civil date, valid for every Gregorian year.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        let seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second - offset) + fraction
        return Date(timeIntervalSince1970: seconds)
    }
}
