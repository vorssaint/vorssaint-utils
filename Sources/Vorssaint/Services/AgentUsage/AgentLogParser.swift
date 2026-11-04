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
    /// A later chunk can identify the model of an already-counted request.
    case usageModel(key: String, model: String)
    case limits(AgentLimits)
    case plan(String, observedAt: Date)
    case turnBegan(Date)
    /// Model and folder context known before usage is reported.
    case turnContext(model: String, project: String)
    /// Work continues; nil when the line was not worth decoding for its time.
    case turnActive(Date?)
    /// A step ended expecting the agent to go on; unless work follows soon,
    /// the agent stopped there and its turn is over.
    case turnSettled(Date)
    case turnEnded(Date?, completed: Bool, duration: TimeInterval?)
    case reset(Date)
}

/// Per-file context carried from line to line.
struct AgentLogState: Equatable {
    var session = ""
    var project = ""
    var model = ""
    var turnOpen = false
    /// Newer logs write one usage record per response; older ones only carry
    /// running totals, which are the fallback until a record appears.
    var sawUsageRecords = false
    var lastTotal: AgentTokens?
    /// Codex runs the thread on the fast tier, which bills at a premium.
    var fast = false
    /// A Codex subagent, review or memory task owns no turn. Only the log's
    /// metadata says so: a reverted thread goes on in a log named after both
    /// the thread and a new rollout.
    var codexSubagent = false
    /// The first Codex metadata line describes the log's own thread; a later
    /// one is history copied from the thread it came from.
    var codexHeaderRead = false
    /// The thread a person started that a Codex subagent works for, whose
    /// turn its responses count toward.
    var codexRoot = ""
    /// The thread whose running totals the lines read now report: history
    /// copied from another thread keeps that thread's, as in its own log.
    var codexTotalsSession = ""
    /// Copilot shutdown counters are cumulative for the life of a session.
    var copilotTotals: [String: AgentTokens] = [:]
    /// Counted requests by model; the empty key holds unresolved attribution.
    var copilotRequests: [String: Int] = [:]
    var copilotRequestModels: [String: String] = [:]
    var copilotReportedRequests: [String: Int] = [:]
    var copilotTurnID: String?
    var copilotFinalResponse = false
    /// The parent session when a database row belongs to a subagent.
    var parentSession = ""
    /// OpenCode stores all sessions in one database, tracking per-session state.
    var openCodeSessions: [String: OpenCodeSessionState] = [:]
    /// Claude's shell commands still waiting for their result, by tool call.
    /// They run on the Mac, so the turn goes on without the network.
    var runningCommands: Set<String> = []
}

/// Per-session turn and model tracking for OpenCode databases.
struct OpenCodeSessionState: Equatable {
    var project = ""
    var model = ""
    var turnOpen = false
    var turnStarted: Date?
    var activeUserMessageID = ""
    /// The newest moment the session's rows tell of.
    var lastActivity: Date?
    /// When a step ended expecting the loop to go on, until a row follows.
    var settledAt: Date?
    /// The reply being written, until it completes.
    var writingReplyID = ""
    /// When the prompt the session answers now was written.
    var activePromptDate: Date?
    var seenUserMessageIDs: Set<String> = []
    var completedAssistantMessageIDs: Set<String> = []
    var completedUserMessageIDs: Set<String> = []
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

    /// The first `"type":"…"` value at or after `start`, and where it ends.
    /// A Codex rollout line writes its own type before its payload, and an
    /// event's payload opens with the event's type, so the search stops
    /// within the first hundred bytes instead of crossing tool output or
    /// compacted history that can run to tens of megabytes per line.
    static func firstType(_ line: Data, from start: Int = 0) -> (name: String, end: Int)? {
        let key: StaticString = #""type":""#
        return line.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, start < bytes.count,
                  let found = memmem(base + start, bytes.count - start, key.utf8Start, key.utf8CodeUnitCount)
            else { return nil }
            let value = base.distance(to: found) + key.utf8CodeUnitCount
            // Type names are short identifiers.
            let limit = min(bytes.count, value + 64)
            guard value < limit, let quote = memchr(base + value, 0x22, limit - value) else { return nil }
            let end = base.distance(to: UnsafeRawPointer(quote))
            return (String(decoding: UnsafeRawBufferPointer(rebasing: bytes[value..<end]), as: UTF8.self), end + 1)
        }
    }

    static let codexEvents: Set<String> = [
        "token_count", "task_started", "task_complete", "turn_aborted", "thread_settings_applied",
    ]

    static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    // MARK: Claude Code

    static func parseClaude(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        ClaudeReader().parse(line, state: &state, now: now)
    }

    // MARK: Codex

    static func parseCodex(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        CodexReader().parse(line, state: &state, now: now)
    }

    /// Input counts include what came from the cache.
    static func codexTokens(_ usage: [String: Any]) -> AgentTokens {
        let input = int(usage["input_tokens"])
        let cached = min(input, int(usage["cached_input_tokens"]))
        let written = min(input - cached, int(usage["cache_write_input_tokens"]))
        return AgentTokens(input: input - cached - written, cacheWrite: written, cacheRead: cached,
                           output: int(usage["output_tokens"]), reasoning: int(usage["reasoning_output_tokens"]))
    }

    /// Fast mode, named priority before July 2026.
    static func fastTier(_ tier: String) -> Bool {
        ["fast", "priority"].contains(tier.lowercased())
    }

    // MARK: OpenCode

    /// OpenCode starts the next step the moment a step's tools return, so
    /// a turn that goes this long without one after a step ended has stopped,
    /// as when a permission was rejected or a question dismissed.
    static let openCodeSettle: TimeInterval = 30

    static func parseOpenCode(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        OpenCodeReader().parse(line, state: &state, now: now)
    }

    // MARK: GitHub Copilot

    /// Copilot CLI and the GitHub Copilot app share an append-only event log.
    /// Only session context, turn boundaries and cumulative model counters are
    /// decoded; prompts, replies, reasoning and tool arguments are ignored.
    static func parseCopilot(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        CopilotReader().parse(line, state: &state, now: now)
    }

    static func copilotEvent(_ type: String) -> Bool {
        ["user.message", "assistant.turn_start", "assistant.message", "assistant.turn_end",
         "session.start", "session.context_changed", "session.model_change", "session.shutdown", "abort"].contains(type)
    }

    /// Codex logs a reading for each allowance: the main one under "codex",
    /// which older logs leave unnamed, and one for each model that has its
    /// own. Only the main one is kept, so a model's windows never replace it
    /// or warn again.
    static func isMainBucket(_ limits: [String: Any]) -> Bool {
        let id = (limits["limit_id"] as? String ?? "").lowercased()
        return id.isEmpty || id == "codex"
    }

    /// The names a log gives a window's figures; Codex's server spells the
    /// same ones in camel case.
    typealias WindowKeys = (used: String, minutes: String, resets: String, individual: String, remaining: String)
    static let logWindowKeys: WindowKeys = ("used_percent", "window_minutes", "resets_at",
                                            "individual_limit", "remaining_percent")

    /// Windows are told apart by their length, never by their slot: an
    /// account can report only its weekly window, and in either slot. A
    /// Business account can leave both slots empty and report its allowance
    /// as the share left of its own limit instead.
    static func codexWindows(_ limits: [String: Any], observed: Date,
                             keys: WindowKeys = logWindowKeys) -> [AgentLimitWindow]? {
        var windows: [AgentLimitWindow] = []
        for slot in ["primary", "secondary"] {
            guard let window = limits[slot] as? [String: Any],
                  let used = (window[keys.used] as? NSNumber)?.doubleValue, used.isFinite else { continue }
            let minutes = (window[keys.minutes] as? NSNumber)?.intValue
            var resets = seconds(window[keys.resets])
            if resets == nil, let delay = (window["resets_in_seconds"] as? NSNumber)?.doubleValue, delay.isFinite {
                resets = observed.addingTimeInterval(max(0, delay))
            }
            windows.append(AgentLimitWindow(id: "codex.\(minutes.map(String.init) ?? slot)",
                                            kind: kind(minutes: minutes), minutes: minutes, scope: nil,
                                            usedPercent: min(100, max(0, used)), resetsAt: resets))
        }
        if windows.isEmpty, let individual = limits[keys.individual] as? [String: Any],
           let remaining = (individual[keys.remaining] as? NSNumber)?.doubleValue, remaining.isFinite {
            windows.append(AgentLimitWindow(id: "codex.individual", kind: .other, minutes: nil, scope: nil,
                                            usedPercent: min(100, max(0, 100 - remaining)),
                                            resetsAt: seconds(individual[keys.resets])))
        }
        return windows.sorted { ($0.minutes ?? .max) < ($1.minutes ?? .max) }
    }

    static func kind(minutes: Int?) -> AgentLimitWindow.Kind {
        guard let minutes, minutes > 0 else { return .other }
        if minutes <= 12 * 60 { return .session }
        if (6 * 1440...8 * 1440).contains(minutes) { return .weekly }
        return .other
    }

    // MARK: Shared values

    /// The folder an agent ran in names the project. A worktree kept inside
    /// the repository still belongs to that repository.
    static func projectName(_ path: String) -> String {
        var path = path
        if let range = path.range(of: "/.claude/worktrees/") { path = String(path[..<range.lowerBound]) }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return native((path as NSString).lastPathComponent)
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
