// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// What one log line says, reduced to the few facts the island keeps. Only
/// usage counters, model names, times and folder names leave a line; prompts,
/// replies and tool output are never decoded into anything that is stored.
enum AgentLogEntry: Equatable {
    /// `key` identifies the response across duplicate lines and files.
    case usage(key: String, record: AgentUsageRecord, billable: AgentBillable)
    case limits(AgentLimits)
    case plan(String)
    case turnBegan(Date)
    /// Work continues; nil when the line was not worth decoding for its time.
    case turnActive(Date?)
    case turnEnded(Date?, completed: Bool, duration: TimeInterval?)
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

    private static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    // MARK: Claude Code

    static func parseClaude(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        if contains(line, #""type":"assistant""#) { return claudeAssistant(line, state: &state, now: now) }
        guard contains(line, #""type":"user""#) else { return [] }
        // A local command prints its output without asking the model anything,
        // so the command line that opened a turn closes it again. Only the
        // person's own text counts: a tool result can quote the same words.
        if contains(line, "[Request interrupted by user") || contains(line, "<local-command-std"),
           let json = object(line), json["type"] as? String == "user", endsTurn(json) {
            let open = state.turnOpen
            state.turnOpen = false
            return open ? [.turnEnded(nil, completed: false, duration: nil)] : []
        }
        // Tool results arrive inside a turn and can be large; while a turn is
        // open, the line only has to say that work goes on.
        if state.turnOpen { return [.turnActive(nil)] }
        guard let json = object(line), json["type"] as? String == "user",
              json["isMeta"] as? Bool != true, json["isSidechain"] as? Bool != true else { return [] }
        adopt(json, into: &state)
        state.turnOpen = true
        return [.turnBegan(timestamp(json["timestamp"]) ?? now)]
    }

    private static func claudeAssistant(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = object(line), json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any] else { return [] }
        adopt(json, into: &state)
        let date = timestamp(json["timestamp"]) ?? now
        var entries: [AgentLogEntry] = []
        let model = message["model"] as? String ?? ""
        if let usage = message["usage"] as? [String: Any], !model.isEmpty, !model.hasPrefix("<") {
            state.model = model
            var billable = AgentBillable()
            billable.tokens = AgentTokens(
                input: int(usage["input_tokens"]),
                cacheWrite: int(usage["cache_creation_input_tokens"]),
                cacheRead: int(usage["cache_read_input_tokens"]),
                output: int(usage["output_tokens"]),
                reasoning: int((usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"]))
            billable.longCacheWrite = int((usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"])
            billable.fast = usage["speed"] as? String == "fast"
            billable.domestic = usage["inference_geo"] as? String == "us"
            billable.webSearches = int((usage["server_tool_use"] as? [String: Any])?["web_search_requests"])
            let id = message["id"] as? String ?? ""
            let request = json["requestId"] as? String ?? ""
            let key = id.isEmpty && request.isEmpty
                ? "claude:\(state.session):\(date.timeIntervalSince1970)" : "claude:\(id):\(request)"
            let priced = AgentPricing.cost(billable, model: model)
            entries.append(.usage(key: key, record: AgentUsageRecord(
                provider: .claude, date: date, model: model, project: state.project, session: state.session,
                tokens: billable.tokens, cost: priced.cost, savings: priced.savings), billable: billable))
        }
        // A subagent's own ending is not the end of the turn it serves.
        guard json["isSidechain"] as? Bool != true else { return entries }
        switch message["stop_reason"] as? String {
        case "end_turn", "stop_sequence", "max_tokens", "refusal":
            if state.turnOpen { entries.append(.turnEnded(date, completed: true, duration: nil)) }
            state.turnOpen = false
        default:
            if !state.turnOpen { entries.append(.turnBegan(date)) }
            else { entries.append(.turnActive(date)) }
            state.turnOpen = true
        }
        return entries
    }

    /// The interruption or local command output the person's message holds,
    /// never text inside a tool result.
    private static func endsTurn(_ json: [String: Any]) -> Bool {
        let content = (json["message"] as? [String: Any])?["content"]
        let texts: [String]
        if let text = content as? String {
            texts = [text]
        } else if let blocks = content as? [[String: Any]] {
            texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        } else {
            texts = []
        }
        return texts.contains {
            $0.hasPrefix("[Request interrupted by user") || $0.hasPrefix("<local-command-std")
        }
    }

    private static func adopt(_ json: [String: Any], into state: inout AgentLogState) {
        if let session = json["sessionId"] as? String, !session.isEmpty { state.session = session }
        if let cwd = json["cwd"] as? String, !cwd.isEmpty { state.project = projectName(cwd) }
    }

    // MARK: Codex

    static func parseCodex(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        let record = contains(line, #""type":"token_usage_record""#)
        let event = !record && contains(line, #""type":"event_msg""#)
        let context = !record && !event
            && (contains(line, #""type":"turn_context""#) || contains(line, #""type":"session_meta""#))
        guard record || event || context else { return [] }
        if event, !contains(line, #""type":"token_count""#), !contains(line, #""type":"task_started""#),
           !contains(line, #""type":"task_complete""#), !contains(line, #""type":"turn_aborted""#),
           !contains(line, #""type":"thread_settings_applied""#) {
            return []
        }
        guard let json = object(line), let payload = json["payload"] as? [String: Any] else { return [] }
        let date = timestamp(json["timestamp"]) ?? now
        switch json["type"] as? String {
        case "session_meta":
            if let id = payload["id"] as? String, !id.isEmpty { state.session = id }
            if let cwd = payload["cwd"] as? String, !cwd.isEmpty { state.project = projectName(cwd) }
            return []
        case "turn_context":
            if let model = payload["model"] as? String, !model.isEmpty { state.model = model }
            if let cwd = payload["cwd"] as? String, !cwd.isEmpty { state.project = projectName(cwd) }
            if let tier = payload["service_tier"] as? String { state.fast = fastTier(tier) }
            return []
        case "token_usage_record":
            guard let usage = payload["usage"] as? [String: Any] else { return [] }
            state.sawUsageRecords = true
            if let session = payload["session_id"] as? String, !session.isEmpty, state.session.isEmpty {
                state.session = session
            }
            let response = payload["response_id"] as? String ?? ""
            let key = response.isEmpty ? "codex:\(state.session):\(date.timeIntervalSince1970)" : "codex:\(response)"
            return [codexUsage(codexTokens(usage), key: key, date: date, state: state)]
        case "event_msg":
            return codexEvent(payload, date: date, state: &state)
        default:
            return []
        }
    }

    private static func codexEvent(_ payload: [String: Any], date: Date, state: inout AgentLogState) -> [AgentLogEntry] {
        switch payload["type"] as? String {
        case "token_count":
            var entries: [AgentLogEntry] = []
            if let limits = payload["rate_limits"] as? [String: Any] {
                if let windows = codexWindows(limits, observed: date), !windows.isEmpty {
                    entries.append(.limits(AgentLimits(provider: .codex, windows: windows,
                                                       observedAt: date, source: .sessionLog)))
                }
                if let plan = limits["plan_type"] as? String, !plan.isEmpty { entries.append(.plan(plan)) }
            }
            // Running totals repeat when only the limits changed; a response
            // is whatever the total grew by since the previous reading.
            if !state.sawUsageRecords, let info = payload["info"] as? [String: Any],
               let totalUsage = info["total_token_usage"] as? [String: Any] {
                let total = codexTokens(totalUsage)
                if total != state.lastTotal, total.total > (state.lastTotal?.total ?? 0) {
                    let delta: AgentTokens
                    if let last = info["last_token_usage"] as? [String: Any] {
                        delta = codexTokens(last)
                    } else {
                        let previous = state.lastTotal ?? AgentTokens()
                        delta = AgentTokens(input: max(0, total.input - previous.input),
                                            cacheWrite: max(0, total.cacheWrite - previous.cacheWrite),
                                            cacheRead: max(0, total.cacheRead - previous.cacheRead),
                                            output: max(0, total.output - previous.output),
                                            reasoning: max(0, total.reasoning - previous.reasoning))
                    }
                    let key = "codex:\(state.session):total:\(total.total)"
                    entries.append(codexUsage(delta, key: key, date: date, state: state))
                }
                state.lastTotal = total
            }
            return entries
        case "thread_settings_applied":
            if let tier = (payload["thread_settings"] as? [String: Any])?["service_tier"] as? String {
                state.fast = fastTier(tier)
            }
            return []
        case "task_started":
            state.turnOpen = true
            return [.turnBegan(seconds(payload["started_at"]) ?? date)]
        case "task_complete", "turn_aborted":
            let open = state.turnOpen
            state.turnOpen = false
            guard open else { return [] }
            let duration = (payload["duration_ms"] as? NSNumber).map { $0.doubleValue / 1000 }
            return [.turnEnded(seconds(payload["completed_at"]) ?? date,
                               completed: payload["type"] as? String == "task_complete", duration: duration)]
        default:
            return []
        }
    }

    /// Fast mode, named priority before July 2026.
    static func fastTier(_ tier: String) -> Bool {
        ["fast", "priority"].contains(tier.lowercased())
    }

    private static func codexUsage(_ tokens: AgentTokens, key: String, date: Date, state: AgentLogState) -> AgentLogEntry {
        var billable = AgentBillable(tokens: tokens)
        billable.fast = state.fast
        let priced = AgentPricing.cost(billable, model: state.model)
        return .usage(key: key, record: AgentUsageRecord(
            provider: .codex, date: date, model: state.model, project: state.project, session: state.session,
            tokens: tokens, cost: priced.cost, savings: priced.savings), billable: billable)
    }

    /// Input counts include what came from the cache.
    static func codexTokens(_ usage: [String: Any]) -> AgentTokens {
        let input = int(usage["input_tokens"])
        let cached = min(input, int(usage["cached_input_tokens"]))
        let written = min(input - cached, int(usage["cache_write_input_tokens"]))
        return AgentTokens(input: input - cached - written, cacheWrite: written, cacheRead: cached,
                           output: int(usage["output_tokens"]), reasoning: int(usage["reasoning_output_tokens"]))
    }

    /// Windows are told apart by their length, never by their slot: an
    /// account can report only its weekly window, and in either slot.
    static func codexWindows(_ limits: [String: Any], observed: Date) -> [AgentLimitWindow]? {
        var windows: [AgentLimitWindow] = []
        for slot in ["primary", "secondary"] {
            guard let window = limits[slot] as? [String: Any],
                  let used = (window["used_percent"] as? NSNumber)?.doubleValue, used.isFinite else { continue }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue
            var resets = seconds(window["resets_at"])
            if resets == nil, let delay = (window["resets_in_seconds"] as? NSNumber)?.doubleValue, delay.isFinite {
                resets = observed.addingTimeInterval(max(0, delay))
            }
            windows.append(AgentLimitWindow(id: "codex.\(minutes.map(String.init) ?? slot)",
                                            kind: kind(minutes: minutes), minutes: minutes, scope: nil,
                                            usedPercent: min(100, max(0, used)), resetsAt: resets))
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
        return (path as NSString).lastPathComponent
    }

    static func int(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        let double = number.doubleValue
        guard double.isFinite, double > 0 else { return 0 }
        return double >= Double(Int.max) ? Int.max : Int(double)
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
