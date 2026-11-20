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
    /// The agent paused to ask the user a question or awaits tool approval.
    case turnNeedsApproval(Date?)
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
    /// Antigravity named the workspace in the person's message, which
    /// outranks the folder a command runs in.
    var namedWorkspace = false
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

    // MARK: Antigravity

    static func parseAntigravity(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        if contains(line, "background task with task id:") || contains(line, #""status":"RUNNING""#) {
            updateRunningTasks(from: line, state: &state, started: true)
        }
        if contains(line, "finished with result:") || contains(line, "finished with exit code") || contains(line, "Task id ") {
            updateRunningTasks(from: line, state: &state, started: false)
        }
        let response = contains(line, #""type":"PLANNER_RESPONSE""#)
        guard response || contains(line, #""type":"USER_INPUT""#) else {
            return state.turnOpen && contains(line, #""type":""#) ? [.turnActive(nil)] : []
        }
        guard let json = object(line), let type = json["type"] as? String else { return [] }
        let date = timestamp(json["created_at"]) ?? now

        switch type {
        case "USER_INPUT":
            var entries: [AgentLogEntry] = []
            if state.turnOpen {
                entries.append(.turnEnded(date, completed: false, duration: nil))
            }
            state.turnOpen = true
            state.runningCommands.removeAll()
            if let content = json["content"] as? String {
                if let model = antigravityModel(content) { state.model = model }
                if let workspace = antigravityWorkspace(content) {
                    state.project = workspace
                    state.namedWorkspace = true
                }
                if state.session.isEmpty, let session = antigravitySession(content) { state.session = session }
                if content.contains("antigravity-cli") { state.parentSession = "antigravity-cli" }
            }
            if state.project.isEmpty && (state.session.contains("antigravity-cli") || state.parentSession.contains("antigravity-cli")) {
                state.project = "agy"
            }
            entries.append(.turnBegan(date))
            if !state.model.isEmpty || !state.project.isEmpty {
                entries.append(.turnContext(model: state.model, project: state.project))
            }
            return entries

        case "PLANNER_RESPONSE":
            if let model = json["model"] as? String, !model.isEmpty {
                state.model = native(model)
            } else if state.model.isEmpty {
                state.model = "gemini-3.8-flash"
            }
            let toolCalls = json["tool_calls"] as? [[String: Any]] ?? []
            if !state.namedWorkspace {
                for tool in toolCalls {
                    guard let cwd = (tool["args"] as? [String: Any])?["Cwd"] as? String else { continue }
                    let folder = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if !folder.isEmpty {
                        if let inferred = inferProject(fromPath: folder) {
                            state.project = inferred
                        } else if !folder.contains("/.ai/") && !folder.hasPrefix("~/.ai") && !folder.contains("/.gemini/") {
                            state.project = projectName(folder)
                        }
                    }
                }
                if state.project.isEmpty {
                    for tool in toolCalls {
                        let args = (tool["args"] as? [String: Any]) ?? [:]
                        for key in ["Path", "AbsolutePath", "FilePath", "path", "filePath", "absolutePath", "file_path", "target_path", "source_path", "file"] {
                            if let val = args[key] as? String, let inferred = inferProject(fromPath: val) {
                                state.project = inferred
                                break
                            }
                        }
                        if !state.project.isEmpty { break }
                        for key in ["CommandLine", "command", "cmd"] {
                            if let val = args[key] as? String, let inferred = inferProject(fromCommand: val) {
                                state.project = inferred
                                break
                            }
                        }
                        if !state.project.isEmpty { break }
                    }
                }
            }
            if state.project.isEmpty && (state.session.contains("antigravity-cli") || state.parentSession.contains("antigravity-cli")) {
                state.project = "agy"
            }

            let input = int(json["input_tokens"])
            let cacheWrite = int(json["cache_write_input_tokens"]) + int(json["cache_creation_input_tokens"])
            let cacheRead = int(json["cache_read_tokens"]) + int(json["cache_read_input_tokens"])
            let output = int(json["output_tokens"])
            let reasoning = int(json["thinking_tokens"]) + int(json["reasoning_tokens"])
            let tokens = AgentTokens(input: input, cacheWrite: cacheWrite, cacheRead: cacheRead, output: output, reasoning: reasoning)
            let billable = AgentBillable(tokens: tokens)
            let priced: (cost: Double?, savings: Double) = tokens.total > 0
                ? AgentPricing.cost(billable, model: state.model)
                : (nil, 0)

            let step = json["step_index"] as? Int ?? 0
            let record = AgentUsageRecord(
                provider: .agy, date: date, model: state.model, project: state.project,
                session: state.session, tokens: tokens, cost: priced.cost, savings: priced.savings
            )
            var entries: [AgentLogEntry] = []
            if !state.turnOpen {
                state.turnOpen = true
                entries.append(.turnBegan(date))
            }
            if !state.model.isEmpty || !state.project.isEmpty {
                entries.append(.turnContext(model: state.model, project: state.project))
            }
            entries.append(.usage(key: "antigravity:\(state.session):\(step)", record: record, billable: billable))

            let status = json["status"] as? String
            let needsApproval = status == "WAITING_FOR_USER" || toolCalls.contains { tool in
                let name = ((tool["name"] as? String) ?? (tool["tool_name"] as? String) ?? "").lowercased()
                return name == "ask_question" || name == "confirm" || name.contains("ask_user")
            }

            if status == "ERROR" {
                state.turnOpen = false
                state.runningCommands.removeAll()
                entries.append(.turnEnded(date, completed: false, duration: nil))
            } else if toolCalls.isEmpty && (status == "DONE" || status == nil) {
                if !state.runningCommands.isEmpty {
                    entries.append(.turnActive(date))
                } else {
                    state.turnOpen = false
                    entries.append(.turnEnded(date, completed: true, duration: nil))
                }
            } else if needsApproval {
                entries.append(.turnNeedsApproval(date))
            } else {
                entries.append(.turnActive(date))
            }
            return entries

        default:
            return []
        }
    }

    private static func updateRunningTasks(from line: Data, state: inout AgentLogState, started: Bool) {
        guard let text = String(data: line, encoding: .utf8) else { return }
        if started {
            guard contains(line, #""type":"GENERIC""#) || contains(line, "background task with task id:") else { return }
            if let startRange = text.range(of: "background task with task id:") {
                let tail = text[startRange.upperBound...].trimmingCharacters(in: .whitespaces)
                let id = tail.prefix(while: { !$0.isWhitespace && $0 != "\\" && $0 != "\"" })
                if !id.isEmpty {
                    state.runningCommands.insert(String(id))
                }
            } else if text.contains(#""status":"RUNNING""#) {
                if let stepRange = text.range(of: #""step_index":"#) {
                    let tail = text[stepRange.upperBound...]
                    let step = tail.prefix(while: { $0.isNumber })
                    state.runningCommands.insert("step-\(step)")
                } else {
                    state.runningCommands.insert("running-task")
                }
            }
        } else {
            if let finishRange = text.range(of: "Task id \"") {
                let tail = text[finishRange.upperBound...]
                let id = tail.prefix(while: { $0 != "\"" })
                if !id.isEmpty {
                    let idStr = String(id)
                    state.runningCommands = state.runningCommands.filter {
                        $0 != idStr && !$0.hasSuffix("/" + idStr) && !idStr.hasSuffix("/" + $0)
                    }
                }
            } else if text.contains("finished with result:") || text.contains("finished with exit code") {
                if let idRange = text.range(of: "task-") {
                    let sub = text[idRange.lowerBound...]
                    let id = sub.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" })
                    let idStr = String(id)
                    state.runningCommands = state.runningCommands.filter {
                        $0 != idStr && !$0.hasSuffix("/" + idStr) && !idStr.hasSuffix("/" + $0)
                    }
                }
                state.runningCommands.remove("running-task")
            }
        }
    }

    static func isIgnoredPath(_ rawPath: String) -> Bool {
        var path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\r\n"))
        if path.hasPrefix("file://") { path = String(path.dropFirst(7)) }
        guard !path.isEmpty && path != "/" else { return true }
        if let range = path.range(of: "/.claude/worktrees/") { path = String(path[..<range.lowerBound]) }

        let expanded = (path as NSString).expandingTildeInPath
        let ignoredSubstrings = ["/.ai/", "/.gemini/", "/.config/", "/Library/", "/.claude/", "/tmp/", "/private/"]
        if ignoredSubstrings.contains(where: { path.contains($0) || expanded.contains($0) }) {
            return true
        }
        let ignoredPrefixes = ["~/.ai/", ".ai/", "~/.gemini/", ".gemini/", "~/.config/", ".config/",
                               "~/.claude/", ".claude/", "/Library/", "Library/", "/tmp/", "tmp/",
                               "/private/", "private/"]
        if ignoredPrefixes.contains(where: { path.hasPrefix($0) || expanded.hasPrefix($0) }) {
            return true
        }
        let exactMatches = ["~/.ai", ".ai", "~/.gemini", ".gemini", "~/.config", ".config",
                            "~/.claude", ".claude", "/Library", "Library", "/tmp", "tmp",
                            "/private", "private"]
        if exactMatches.contains(where: { path == $0 || expanded == $0 }) {
            return true
        }
        return false
    }

    static func inferProject(fromPath rawPath: String) -> String? {
        if isIgnoredPath(rawPath) { return nil }

        var path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\r\n"))
        if path.hasPrefix("file://") { path = String(path.dropFirst(7)) }
        guard !path.isEmpty && path != "/" else { return nil }
        if let range = path.range(of: "/.claude/worktrees/") { path = String(path[..<range.lowerBound]) }

        let expandedPath = (path as NSString).expandingTildeInPath
        let expanded = (expandedPath as NSString).isAbsolutePath
            ? expandedPath
            : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expandedPath)

        let fm = FileManager.default
        var isDir: ObjCBool = false
        var dir = fm.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue
            ? expanded : (expanded as NSString).deletingLastPathComponent

        while !dir.isEmpty && dir != "/" {
            if isIgnoredPath(dir) { break }
            if fm.fileExists(atPath: (dir as NSString).appendingPathComponent(".git"))
                || fm.fileExists(atPath: (dir as NSString).appendingPathComponent("_ai"))
                || fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) {
                return native((dir as NSString).lastPathComponent)
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }

        let parts = path.split(separator: "/").map(String.init)
        let rootFolders: Set<String> = [
            "projects", "Projects", "Repositories", "repositories", "workspace", "Workspace",
            "Developer", "developer", "Development", "development"
        ]
        for (i, part) in parts.enumerated().reversed() {
            if rootFolders.contains(part), i + 1 < parts.count {
                let name = parts[i + 1]
                if !name.isEmpty && !name.hasPrefix(".") && !rootFolders.contains(name) {
                    return native(name)
                }
            }
        }

        let subdirs: Set<String> = ["src", "Sources", "lib", "_ai"]
        for (i, part) in parts.enumerated() {
            if subdirs.contains(part), i > 0 {
                let name = parts[i - 1]
                if !name.isEmpty && !name.hasPrefix(".") && name != "Users" && !rootFolders.contains(name) {
                    return native(name)
                }
            }
        }

        return nil
    }

    static func inferProject(fromCommand cmd: String) -> String? {
        let clean = cmd.replacingOccurrences(of: "\\n", with: "\n")
        for line in clean.split(whereSeparator: \.isNewline) {
            let str = String(line)
            for marker in ["cd ", "-C ", "--package-path "] {
                if let range = str.range(of: marker) {
                    let tail = str[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    let token = tail.prefix(while: { !$0.isWhitespace && $0 != "&" && $0 != ";" && $0 != "|" && $0 != "\"" && $0 != "'" })
                    if !token.isEmpty, let project = inferProject(fromPath: String(token)) {
                        return project
                    }
                }
            }
            for prefix in ["/Users/", "/home/", "~/"] {
                if let pRange = str.range(of: prefix) {
                    let sub = str[pRange.lowerBound...]
                    let token = sub.prefix(while: { !$0.isWhitespace && $0 != "&" && $0 != ";" && $0 != "|" && $0 != "\"" && $0 != "'" })
                    if !token.isEmpty, let project = inferProject(fromPath: String(token)) {
                        return project
                    }
                }
            }
        }
        return nil
    }

    /// The model the person picked, from the settings change Antigravity
    /// adds to their message, or explicit model identifiers in their prompt.
    private static func antigravityModel(_ content: String) -> String? {
        if let change = content.range(of: "<USER_SETTINGS_CHANGE>"),
           let range = content[change.upperBound...].range(of: "Model Selection`") {
            let tail = content[range.upperBound...]
            if let toRange = tail.range(of: " to ") {
                let afterTo = tail[toRange.upperBound...]
                var endIndex = afterTo.endIndex
                for candidate in [". No need", ".</USER_SETTINGS_CHANGE>", "</USER_SETTINGS_CHANGE>", ".\n", "\n"] {
                    if let found = afterTo.range(of: candidate), found.lowerBound < endIndex { endIndex = found.lowerBound }
                }
                let model = String(afterTo[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !model.isEmpty { return model }
            }
        }
        if content.contains("Gemini 4 Argon") || content.contains("gemini-4-argon") {
            return "gemini-4-argon"
        }
        if content.contains("Claude Sonnet 5.5") || content.contains("claude-sonnet-5") {
            return "claude-sonnet-5-5"
        }
        if content.contains("Claude Opus 5.5") || content.contains("claude-opus-5") {
            return "claude-opus-5-5"
        }
        if content.contains("Claude Haiku 5.5") || content.contains("claude-haiku-5") {
            return "claude-haiku-5-5"
        }
        if content.contains("Gemini 3.8 Flash") || content.contains("gemini-3.8-flash") {
            return "gemini-3.8-flash"
        }
        if content.contains("Gemini 3.7 Flash") || content.contains("gemini-3.7-flash") {
            return "gemini-3.7-flash"
        }
        if content.contains("Gemini 2.5 Pro") || content.contains("gemini-2.5-pro") {
            return "gemini-2.5-pro"
        }
        if content.contains("Gemini 1.5 Pro") || content.contains("gemini-1.5-pro") {
            return "gemini-1.5-pro"
        }
        return nil
    }

    private static func antigravityWorkspace(_ content: String) -> String? {
        if let range = content.range(of: "[URI] -> [CorpusName]:\n") {
            let tail = content[range.upperBound...]
            if let lineEnd = tail.firstIndex(of: "\n"),
               let arrow = tail[..<lineEnd].range(of: " -> ") {
                let name = projectName(String(tail[..<arrow.lowerBound]))
                if !name.isEmpty { return name }
            }
        }
        if let range = content.range(of: "Active Workspaces:") {
            let tail = content[range.upperBound...]
            if let dashRange = tail.range(of: "- ") {
                let sub = tail[dashRange.upperBound...]
                let line = sub.firstIndex(of: "\n").map { sub[..<$0] } ?? sub
                let path = line.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let name = projectName(path)
                if !name.isEmpty { return name }
            }
        }
        if let range = content.range(of: "Command Working Directory: ") {
            let tail = content[range.upperBound...]
            let line = tail.firstIndex(of: "\n").map { tail[..<$0] } ?? tail
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let name = projectName(path)
            if !name.isEmpty { return name }
        }
        if let range = content.range(of: "CWD: ") {
            let tail = content[range.upperBound...]
            let line = tail.firstIndex(of: "\n").map { tail[..<$0] } ?? tail
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let name = projectName(path)
            if !name.isEmpty { return name }
        }
        if let range = content.range(of: "Active Document: ") {
            let tail = content[range.upperBound...]
            let line = tail.firstIndex(of: "\n").map { tail[..<$0] } ?? tail
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let name = projectName(path)
            if !name.isEmpty { return name }
        }
        return nil
    }

    private static func antigravitySession(_ content: String) -> String? {
        guard let range = content.range(of: "Conversation ID: ") else { return nil }
        let session = content[range.upperBound...].prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" })
        return session.isEmpty ? nil : String(session)
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
