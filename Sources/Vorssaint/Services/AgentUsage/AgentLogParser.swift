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

    private static let codexEvents: Set<String> = [
        "token_count", "task_started", "task_complete", "turn_aborted", "thread_settings_applied",
    ]

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
        // A tool that ends the turn, like the structured output a scripted
        // session returns, gets no reply after its result: the session is done.
        if contains(line, #""toolEndsTurn":true"#), let json = object(line), json["type"] as? String == "user",
           json["toolEndsTurn"] as? Bool == true, json["isSidechain"] as? Bool != true {
            let open = state.turnOpen
            state.turnOpen = false
            return open ? [.turnEnded(timestamp(json["timestamp"]) ?? now, completed: true, duration: nil)] : []
        }
        // Tool results arrive inside a turn and can be large; while a turn is
        // open, the line only has to say that work goes on.
        if state.turnOpen {
            if !state.runningCommands.isEmpty {
                if contains(line, #""tool_use_id""#) {
                    state.runningCommands = state.runningCommands.filter { line.range(of: Data($0.utf8)) == nil }
                } else if let json = object(line), json["type"] as? String == "user",
                          json["isMeta"] as? Bool != true, json["isSidechain"] as? Bool != true {
                    // A prompt inside an open turn, as when a session killed
                    // in the middle of a command resumes, leaves it behind.
                    state.runningCommands = []
                }
            }
            return [.turnActive(nil)]
        }
        // A subagent's prompts and tool output never open a turn, and its
        // tool output can be large: no need to decode it to know that.
        if contains(line, #""isSidechain":true"#) { return [] }
        guard let json = object(line), json["type"] as? String == "user",
              json["isMeta"] as? Bool != true, json["isSidechain"] as? Bool != true else { return [] }
        adopt(json, into: &state)
        state.turnOpen = true
        state.runningCommands = []
        return [.turnBegan(timestamp(json["timestamp"]) ?? now)]
    }

    private static func claudeAssistant(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = object(line), json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any] else { return [] }
        adopt(json, into: &state)
        let date = timestamp(json["timestamp"]) ?? now
        var entries: [AgentLogEntry] = []
        let model = native(message["model"] as? String ?? "")
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
            // An error written in place of a reply, like a spent limit, stops
            // the turn without finishing it.
            let failed = json["isApiErrorMessage"] as? Bool == true || model.hasPrefix("<")
            if state.turnOpen { entries.append(.turnEnded(date, completed: !failed, duration: nil)) }
            state.turnOpen = false
        default:
            for block in message["content"] as? [[String: Any]] ?? []
            where block["type"] as? String == "tool_use" && block["name"] as? String == "Bash" {
                if let id = block["id"] as? String { state.runningCommands.insert(id) }
            }
            // Ahead of the usage, so a reply that opens the turn again, as
            // after an offline end, counts toward it.
            entries.insert(state.turnOpen ? .turnActive(date) : .turnBegan(date), at: 0)
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
        if let session = json["sessionId"] as? String, !session.isEmpty { state.session = native(session) }
        if let cwd = json["cwd"] as? String, !cwd.isEmpty { state.project = projectName(cwd) }
    }

    // MARK: Codex

    static func parseCodex(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let kind = firstType(line) else { return [] }
        switch kind.name {
        case "token_usage_record", "turn_context", "session_meta": break
        case "event_msg":
            guard let event = firstType(line, from: kind.end), codexEvents.contains(event.name) else { return [] }
        default: return []
        }
        guard let json = object(line), let payload = json["payload"] as? [String: Any] else { return [] }
        let date = timestamp(json["timestamp"]) ?? now
        switch json["type"] as? String {
        case "session_meta":
            if let id = payload["id"] as? String, !id.isEmpty { state.session = native(id) }
            if let cwd = payload["cwd"] as? String, !cwd.isEmpty { state.project = projectName(cwd) }
            return []
        case "turn_context":
            if let model = payload["model"] as? String, !model.isEmpty { state.model = native(model) }
            if let cwd = payload["cwd"] as? String, !cwd.isEmpty { state.project = projectName(cwd) }
            if let tier = payload["service_tier"] as? String { state.fast = fastTier(tier) }
            return []
        case "token_usage_record":
            guard let usage = payload["usage"] as? [String: Any] else { return [] }
            state.sawUsageRecords = true
            if let session = payload["session_id"] as? String, !session.isEmpty, state.session.isEmpty {
                state.session = native(session)
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
                if isMainBucket(limits), let windows = codexWindows(limits, observed: date), !windows.isEmpty {
                    entries.append(.limits(AgentLimits(provider: .codex, windows: windows,
                                                       observedAt: date, source: .sessionLog)))
                }
                if let plan = limits["plan_type"] as? String, !plan.isEmpty {
                    entries.append(.plan(plan, observedAt: date))
                }
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

    // MARK: OpenCode

    /// OpenCode starts the next step the moment a step's tools return, so
    /// a turn that goes this long without one after a step ended has stopped,
    /// as when a permission was rejected or a question dismissed.
    static let openCodeSettle: TimeInterval = 30

    static func parseOpenCode(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard contains(line, #""role":""#) || contains(line, #""type":"reset""#) else { return [] }
        guard let json = object(line) else { return [] }
        if json["type"] as? String == "reset" {
            state.openCodeSessions.removeAll()
            state.turnOpen = false
            return [.reset(now)]
        }
        guard let role = json["role"] as? String else { return [] }
        let id = json["id"] as? String ?? ""
        let session = json["session_id"] as? String ?? ""
        let sessionID = session.isEmpty ? state.session : native(session)
        state.session = sessionID
        state.parentSession = json["parent_session_id"] as? String ?? ""

        var sessionState = state.openCodeSessions[sessionID] ?? OpenCodeSessionState()

        let cwd = (json["path"] as? [String: Any])?["cwd"] as? String ?? json["directory"] as? String ?? ""
        if !cwd.isEmpty {
            sessionState.project = projectName(cwd)
        }

        let timeCreated = (json["time"] as? [String: Any])?["created"] ?? json["time_created"]
        let date = seconds(timeCreated) ?? now
        // A session quiet this long with no reply being written starts its
        // next prompt as a task of its own, so what it kept to tell its rows
        // apart can go. Sessions are looked over only as a new one appears.
        if state.openCodeSessions[sessionID] == nil {
            state.openCodeSessions = state.openCodeSessions.filter { _, kept in
                !kept.writingReplyID.isEmpty
                    || date.timeIntervalSince(kept.lastActivity ?? date) < NotchAgentSupport.idleTurn
            }
        }
        let lastActivity = sessionState.lastActivity
        sessionState.lastActivity = max(lastActivity ?? date, date)

        switch role {
        case "user":
            if !id.isEmpty {
                // A prompt read again, as when its summary is saved, is no new one.
                if sessionState.seenUserMessageIDs.contains(id) { return [] }
                remember(id, in: &sessionState.seenUserMessageIDs)
                sessionState.activeUserMessageID = id
            }
            // OpenCode writes prompts of its own in the middle of a task: the
            // request that starts a compaction, the follow up after one, the
            // summary after a command's subtask. A prompt sent while it works
            // joins the running loop too, so inside a turn each is activity.
            var entries: [AgentLogEntry] = []
            // A prompt that arrives after the session went quiet is a task of
            // its own: the one before stopped without a word, as when a tool
            // call was rejected, and nothing finished. While a reply is still
            // being written, as through a long command, the prompt joins it.
            let quiet: Bool
            if let settled = sessionState.settledAt {
                quiet = date.timeIntervalSince(settled) >= openCodeSettle
            } else if sessionState.writingReplyID.isEmpty, let lastActivity {
                quiet = date.timeIntervalSince(lastActivity) >= NotchAgentSupport.idleTurn
            } else {
                quiet = false
            }
            sessionState.settledAt = nil
            sessionState.activePromptDate = date
            if sessionState.turnOpen && !quiet {
                entries.append(.turnActive(date))
            } else {
                if sessionState.turnOpen {
                    entries.append(.turnEnded(lastActivity, completed: false, duration: nil))
                }
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
            let userModel = json["model_id"] as? String
                ?? json["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["id"] as? String
                ?? json["model"] as? String
            if let userModel, !userModel.isEmpty {
                sessionState.model = native(userModel)
            }
            state.openCodeSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = true
            return entries

        case "assistant":
            let rawModel = json["model_id"] as? String
                ?? json["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["id"] as? String
                ?? json["model"] as? String
            if let rawModel, !rawModel.isEmpty {
                sessionState.model = native(rawModel)
            }
            let tokensDict = json["tokens"] as? [String: Any] ?? [:]
            let input = int(tokensDict["input"])
            let output = int(tokensDict["output"])
            let reasoning = int(tokensDict["reasoning"])
            let cacheDict = tokensDict["cache"] as? [String: Any] ?? [:]
            let cacheRead = int(cacheDict["read"])
            let cacheWrite = int(cacheDict["write"])
            let tokens = AgentTokens(input: input, cacheWrite: cacheWrite, cacheRead: cacheRead,
                                     output: output + reasoning, reasoning: reasoning)
            let billable = AgentBillable(tokens: tokens)
            let priced = AgentPricing.cost(billable, model: sessionState.model)
            let recordedCost = (json["cost"] as? NSNumber)?.doubleValue
            let reportedCostVal = recordedCost ?? 0
            // A model the list does not know costs what OpenCode recorded.
            // Local and free models record zero, which stays an estimate so
            // a price the list learns later still applies.
            let cost: Double?
            let isReported: Bool
            if let calculated = priced.cost {
                cost = calculated
                isReported = false
            } else if let recordedCost {
                cost = recordedCost
                isReported = recordedCost > 0
            } else {
                cost = nil
                isReported = false
            }

            let parentID = json["parentID"] as? String ?? ""
            let isAlreadyCompleted = (!id.isEmpty && sessionState.completedAssistantMessageIDs.contains(id))
                || (!parentID.isEmpty && sessionState.completedUserMessageIDs.contains(parentID))
            let matchesActivePrompt = parentID.isEmpty || parentID == sessionState.activeUserMessageID

            let timeCompleted = (json["time"] as? [String: Any])?["completed"]
            let completed = seconds(timeCompleted)
            let hasError = json["error"].map { !($0 is NSNull) } ?? false
            let finish = json["finish"] as? String
            if let completed { sessionState.lastActivity = max(sessionState.lastActivity ?? completed, completed) }
            // A step that starts after the last one settled is the loop going on.
            if let settled = sessionState.settledAt, date >= settled { sessionState.settledAt = nil }

            var entries: [AgentLogEntry] = []
            // OpenCode completes each reply before it answers a prompt sent
            // meanwhile. A reply to a newer prompt while an older one never
            // completed means OpenCode stopped in the middle of it, as when
            // it was killed, and the newer prompt started a task of its own.
            if !id.isEmpty, !sessionState.writingReplyID.isEmpty, sessionState.writingReplyID != id,
               sessionState.turnOpen, !parentID.isEmpty, parentID == sessionState.activeUserMessageID,
               let prompt = sessionState.activePromptDate, let started = sessionState.turnStarted, prompt > started {
                entries.append(.turnEnded(nil, completed: false, duration: nil))
                entries.append(.turnBegan(prompt))
                sessionState.turnStarted = prompt
            }
            if completed == nil && finish == nil && !hasError && !id.isEmpty {
                sessionState.writingReplyID = id
            } else if sessionState.writingReplyID == id {
                sessionState.writingReplyID = ""
            }
            if !isAlreadyCompleted && matchesActivePrompt && !sessionState.turnOpen {
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
            // A reply is saved before its answer arrives, and a shell command
            // run from the prompt, the reply that hands work to a subtask and
            // a request that failed or was stopped never hold any usage.
            if tokens.total > 0 || reportedCostVal > 0 {
                let key = "opencode:\(sessionID):\(id.isEmpty ? "\(date.timeIntervalSince1970)" : id)"
                let record = AgentUsageRecord(
                    provider: .opencode, date: date, model: sessionState.model, project: sessionState.project,
                    session: sessionID, tokens: tokens, cost: cost, savings: priced.savings,
                    reportedCost: isReported
                )
                entries.append(.usage(key: key, record: record, billable: billable))
            }

            // OpenCode's loop goes on after tool calls, after a reply that
            // still holds calls whatever its finish says, and after the
            // summary of a compaction it started on its own. Any other finish
            // stops it, as does an error or a reply that completes without a
            // finish, like a shell command's.
            let ends: Bool
            if hasError {
                ends = true
            } else if let finish {
                ends = !["tool-calls", "unknown"].contains(finish)
                    && json["tool_calls"] as? Bool != true && json["auto_compaction"] as? Bool != true
            } else {
                ends = completed != nil
            }

            if ends {
                if !isAlreadyCompleted && matchesActivePrompt && sessionState.turnOpen {
                    let endDate = completed ?? seconds(json["time_updated"]) ?? date
                    var duration: TimeInterval?
                    if let turnStarted = sessionState.turnStarted {
                        if endDate >= turnStarted {
                            duration = endDate.timeIntervalSince(turnStarted)
                        }
                    } else if endDate >= date {
                        duration = endDate.timeIntervalSince(date)
                    }
                    sessionState.turnOpen = false
                    sessionState.turnStarted = nil
                    sessionState.activeUserMessageID = ""
                    sessionState.settledAt = nil
                    entries.append(.turnEnded(endDate, completed: !hasError, duration: duration))
                }
                if !id.isEmpty { remember(id, in: &sessionState.completedAssistantMessageIDs) }
                if !parentID.isEmpty { remember(parentID, in: &sessionState.completedUserMessageIDs) }
            } else if !isAlreadyCompleted && matchesActivePrompt {
                // A step that completed hands over to the next one at once,
                // unless the loop stopped there.
                if let completed, sessionState.turnOpen {
                    sessionState.settledAt = completed
                    entries.append(.turnSettled(completed))
                } else {
                    entries.append(.turnActive(date))
                }
            }
            state.openCodeSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = sessionState.turnOpen
            return entries

        default:
            return []
        }
    }

    /// Keeps a bounded number of message ids a session has settled.
    private static func remember(_ id: String, in ids: inout Set<String>) {
        if ids.count > 100 { ids.removeFirst() }
        ids.insert(id)
    }

    /// Input counts include what came from the cache.
    static func codexTokens(_ usage: [String: Any]) -> AgentTokens {
        let input = int(usage["input_tokens"])
        let cached = min(input, int(usage["cached_input_tokens"]))
        let written = min(input - cached, int(usage["cache_write_input_tokens"]))
        return AgentTokens(input: input - cached - written, cacheWrite: written, cacheRead: cached,
                           output: int(usage["output_tokens"]), reasoning: int(usage["reasoning_output_tokens"]))
    }

    // MARK: GitHub Copilot

    /// Copilot CLI and the GitHub Copilot app share an append-only event log.
    /// Only session context, turn boundaries and cumulative model counters are
    /// decoded; prompts, replies, reasoning and tool arguments are ignored.
    static func parseCopilot(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), let type = envelope.string("type"),
              copilotEvent(type), let data = envelope.object("data") else { return [] }
        let agent = envelope.string("agentId").flatMap { $0.isEmpty ? nil : $0 }
        let root = agent == nil
        // Subagents share the root log. Their responses count as activity,
        // but their lifecycle and model changes never change the root task.
        guard root || type == "assistant.message" else { return [] }
        let date = timestamp(envelope.value("timestamp")) ?? now
        switch type {
        case "user.message", "assistant.turn_start":
            state.copilotFinalResponse = false
            state.copilotTurnID = type == "assistant.turn_start" ? data.string("turnId") : nil
            if let model = data.string("model"), !model.isEmpty { state.model = native(model) }
            let entry: AgentLogEntry = state.turnOpen ? .turnActive(date) : .turnBegan(date)
            state.turnOpen = true
            return [entry, .turnContext(model: state.model, project: state.project)]
        case "assistant.message":
            // A subagent can choose a different model; missing metadata is
            // unknown, not evidence that it used the root's selected model.
            let model = data.string("model").flatMap { $0.isEmpty ? nil : native($0) } ?? (root ? state.model : "")
            var entries = copilotActivity(data, envelope: envelope, agent: agent, model: model,
                                          date: date, state: &state)
            guard root else { return entries }
            state.model = model
            // Each tool iteration has its own turn_end. Only an iteration
            // delivering a final response can finish the person's task.
            state.copilotFinalResponse = !data.hasItems("toolRequests")
                && !["thinking", "commentary"].contains(data.string("phase") ?? "")
            if state.turnOpen {
                entries += [.turnContext(model: state.model, project: state.project), .turnActive(date)]
            }
            return entries
        case "assistant.turn_end":
            guard state.turnOpen,
                  state.copilotTurnID == nil || state.copilotTurnID == data.string("turnId") else { return [] }
            guard state.copilotFinalResponse else { return [.turnActive(date)] }
            state.turnOpen = false
            state.copilotFinalResponse = false
            return [.turnEnded(date, completed: true, duration: nil)]
        case "session.start":
            if let session = data.string("sessionId"), !session.isEmpty {
                state.session = native(session)
            }
            if let model = data.string("selectedModel"), !model.isEmpty {
                state.model = native(model)
            }
            if let context = data.object("context"),
               let path = ["gitRoot", "cwd", "repository"].compactMap({ context.string($0) }).first(where: { !$0.isEmpty }) {
                state.project = projectName(path)
            }
            return []
        case "session.context_changed":
            if let path = ["gitRoot", "cwd", "repository"].compactMap({ data.string($0) }).first(where: { !$0.isEmpty }) {
                state.project = projectName(path)
            }
            return state.turnOpen ? [.turnContext(model: state.model, project: state.project)] : []
        case "session.model_change":
            if let model = data.string("newModel"), !model.isEmpty { state.model = native(model) }
            return state.turnOpen ? [.turnContext(model: state.model, project: state.project)] : []
        case "abort":
            guard state.turnOpen else { return [] }
            state.turnOpen = false
            state.copilotFinalResponse = false
            return [.turnEnded(date, completed: false, duration: nil)]
        case "session.shutdown":
            var entries = copilotUsage(data.value("modelMetrics") as? [String: Any], event: envelope.string("id"),
                                       date: date, state: &state)
            if state.turnOpen {
                state.turnOpen = false
                entries.append(.turnEnded(date, completed: false, duration: nil))
            }
            return entries
        default:
            return []
        }
    }

    static func copilotEvent(_ type: String) -> Bool {
        ["user.message", "assistant.turn_start", "assistant.message", "assistant.turn_end",
         "session.start", "session.context_changed", "session.model_change", "session.shutdown", "abort"].contains(type)
    }

    private static func copilotActivity(_ data: AgentLogObject, envelope: AgentLogObject, agent: String?,
                                        model: String, date: Date, state: inout AgentLogState) -> [AgentLogEntry] {
        let call = data.string("apiCallId").flatMap { $0.isEmpty ? nil : $0 }
        let message = data.string("messageId").flatMap { $0.isEmpty ? nil : $0 }
            ?? envelope.string("id") ?? String(date.timeIntervalSince1970)
        // Each API call can emit several messages. Older logs lack apiCallId,
        // so they retain message-level deduplication. Namespace IDs by kind
        // and agent so independent calls cannot collide with those fallbacks.
        let request = (agent.map { "agent:\($0)" } ?? "root") + ":"
            + (call.map { "api:\($0)" } ?? "message:\(message)")
        let key = "copilot:\(state.session):\(request):activity"
        if let previous = state.copilotRequestModels[request] {
            guard previous.isEmpty, !model.isEmpty else { return [] }
            state.copilotRequestModels[request] = model
            state.copilotRequests[previous, default: 0] -= 1
            state.copilotRequests[model, default: 0] += 1
            return [.usageModel(key: key, model: model)]
        }
        state.copilotRequestModels[request] = model
        state.copilotRequests[model, default: 0] += 1
        return [.usage(key: key, record: AgentUsageRecord(
            provider: .copilot, date: date, model: model, project: state.project, session: state.session,
            tokens: AgentTokens(), cost: 0, savings: 0), billable: AgentBillable(isAggregate: true))]
    }

    private static func copilotUsage(_ metrics: [String: Any]?, event: String?, date: Date,
                                     state: inout AgentLogState) -> [AgentLogEntry] {
        guard let metrics else { return [] }
        var growth: [String: AgentTokens] = [:]
        for (model, value) in metrics {
            guard let metric = value as? [String: Any] else { continue }
            let total = copilotTokens(metric)
            growth[model] = tokenGrowth(total, after: state.copilotTotals[model])
            state.copilotTotals[model] = total
            let reported = int((metric["requests"] as? [String: Any])?["count"])
            state.copilotReportedRequests[model] = max(state.copilotReportedRequests[model, default: 0],
                                                       max(reported, total.total > 0 ? 1 : 0))
        }
        let deficits = state.copilotReportedRequests
            .map { (model: $0.key, count: max(0, $0.value - state.copilotRequests[$0.key, default: 0])) }
        let unresolved = state.copilotRequests["", default: 0]
        var missing = max(0, deficits.reduce(0) { $0 + $1.count } - unresolved)
        var requests: [String: Int] = [:]
        // Unknown responses can cover any model's deficit, but only once
        // across the whole session. Attribute only the excess that must be
        // this model; retain ambiguous requests in the unknown bucket.
        for deficit in deficits {
            let certain = max(0, deficit.count - unresolved)
            requests[deficit.model] = certain
            missing -= certain
        }
        if missing > 0 { requests["", default: 0] += missing }
        var entries: [AgentLogEntry] = []
        for model in Set(growth.keys).union(requests.keys).sorted() {
            let tokens = growth[model] ?? AgentTokens()
            let count = requests[model, default: 0]
            state.copilotRequests[model, default: 0] += count
            guard tokens.total > 0 || count > 0 else { continue }
            let billable = AgentBillable(tokens: tokens, isAggregate: true)
            let name = native(model)
            let priced = AgentPricing.cost(billable, model: name)
            let checkpoint = event.flatMap { $0.isEmpty ? nil : native($0) }
                ?? String(date.timeIntervalSince1970)
            entries.append(.usage(key: "copilot:\(state.session):\(checkpoint):\(name)", record: AgentUsageRecord(
                provider: .copilot, date: date, model: name, project: state.project, session: state.session,
                requests: count, tokens: tokens, cost: priced.cost, savings: priced.savings), billable: billable))
        }
        return entries
    }

    private static func copilotTokens(_ metric: [String: Any]) -> AgentTokens {
        let details = metric["tokenDetails"] as? [String: Any] ?? [:]
        let usage = metric["usage"] as? [String: Any] ?? [:]
        func count(_ detail: String, _ fallback: String) -> Int {
            if let value = (details[detail] as? [String: Any])?["tokenCount"] { return int(value) }
            return int(usage[fallback])
        }
        return AgentTokens(input: count("input", "inputTokens"),
                           cacheWrite: count("cache_write", "cacheWriteTokens"),
                           cacheRead: count("cache_read", "cacheReadTokens"),
                           output: count("output", "outputTokens"),
                           reasoning: int(usage["reasoningTokens"]))
    }

    private static func tokenGrowth(_ total: AgentTokens, after previous: AgentTokens?) -> AgentTokens {
        guard let previous, total.total >= previous.total else { return total }
        return AgentTokens(input: max(0, total.input - previous.input),
                           cacheWrite: max(0, total.cacheWrite - previous.cacheWrite),
                           cacheRead: max(0, total.cacheRead - previous.cacheRead),
                           output: max(0, total.output - previous.output),
                           reasoning: max(0, total.reasoning - previous.reasoning))
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
