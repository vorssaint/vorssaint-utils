// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Reads the session logs Gemini CLI appends under `~/.gemini/tmp`. A
/// message is written again whole when its tool calls finish, so usage is
/// keyed by message. Only the session, model, times and token counts are
/// decoded; prompts, replies, thoughts and tool calls are not.
///
/// Nothing marks a turn's end. `turnOpen` holds whether the work goes on:
/// it opens with a prompt and closes at a reply or notice that may have been
/// the turn's last, which only what follows it can tell.
struct GeminiReader: AgentHarnessReader {
    var provider: AgentProvider { .gemini }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let record = AgentLogObject(line) else { return [] }
        // The first line describes the session. Later `$set`, `$patch` and
        // `$rewindTo` lines edit what was written and hold no new response.
        guard let type = record.string("type") else {
            if let session = record.string("sessionId"), !session.isEmpty {
                state.session = AgentLogParser.native(session)
            }
            return []
        }
        guard let id = record.string("id"), !id.isEmpty else { return [] }
        let date = AgentLogParser.timestamp(record.value("timestamp")) ?? now
        switch type {
        case "user":
            // Tool results go back to the model as user messages too.
            if AgentLogParser.contains(line, #""functionResponse":"#) {
                state.turnOpen = true
                return [.turnActive(date)]
            }
            // The context a session opens with, or a hook adds, is no prompt.
            if AgentLogParser.contains(line, #""content":[{"text":"<session_context>"#)
                || AgentLogParser.contains(line, #""content":[{"text":"<hook_context>"#) { return [] }
            // A compressed history is written again, prompts included, while
            // its turn goes on; only a prompt after the last reply opens one.
            let entry: AgentLogEntry = state.turnOpen ? .turnActive(date) : .turnBegan(date)
            state.turnOpen = true
            return [entry, .turnContext(model: state.model, project: state.project)]
        case "gemini":
            if let model = record.string("model"), !model.isEmpty { state.model = AgentLogParser.native(model) }
            var entries: [AgentLogEntry] = []
            if let tokens = record.object("tokens").map(Self.tokens), tokens.total > 0 {
                let billable = AgentBillable(tokens: tokens)
                let priced = AgentPricing.cost(billable, model: state.model)
                entries.append(.usage(key: "gemini:\(state.session):\(AgentLogParser.native(id))", record: AgentUsageRecord(
                    provider: .gemini, date: date, model: state.model, project: state.project, session: state.session,
                    tokens: tokens, cost: priced.cost, savings: priced.savings), billable: billable))
            }
            // Finished tool calls are added to the reply that asked for
            // them, which keeps its own time; the work goes on now.
            if record.hasItems("toolCalls") {
                state.turnOpen = true
                return entries + [.turnContext(model: state.model, project: state.project), .turnActive(nil)]
            }
            // A reply copied into a rewritten history, as compression does,
            // has no token counts and names no model; the turn goes on.
            guard record.object("tokens") != nil || record.has("model") else { return entries }
            entries.append(.turnContext(model: state.model, project: state.project))
            // Tool calls are written only once they finish. A reply without
            // text asked for them; one with text, or an empty one, which
            // keeps its parts, may have been the turn's last.
            if !record.hasText("content"), record.string("content") != nil {
                state.turnOpen = true
                entries.append(.turnActive(date))
            } else {
                state.turnOpen = false
                entries.append(.turnSettled(date))
            }
            return entries
        case "info", "warning", "error":
            // A cancelled or failed request ends its turn this way; a notice
            // the turn goes on after, like a compressed history, is followed
            // by more work at once.
            guard state.turnOpen else { return [] }
            // Binary content a tool returned goes to the model as an info
            // message holding parts rather than a notice's text.
            if record.hasItems("content") { return [.turnActive(date)] }
            state.turnOpen = false
            return [.turnSettled(date)]
        default:
            return []
        }
    }

    /// The prompt counts include what came from the cache, and thinking
    /// bills as output. Tool-use prompts are counted apart and bill as input.
    static func tokens(_ usage: AgentLogObject) -> AgentTokens {
        let prompt = AgentLogParser.int(usage.value("input"))
        let cached = min(prompt, AgentLogParser.int(usage.value("cached")))
        let thoughts = AgentLogParser.int(usage.value("thoughts"))
        return AgentTokens(input: prompt - cached + AgentLogParser.int(usage.value("tool")), cacheRead: cached,
                           output: AgentLogParser.int(usage.value("output")) + thoughts, reasoning: thoughts)
    }

    /// A subagent's log sits in a folder named after the session that
    /// started it, inside that session's `chats`, which can itself be the
    /// name of a project.
    static func isSubagent(_ path: String) -> Bool {
        let folder = (path as NSString).deletingLastPathComponent as NSString
        return folder.lastPathComponent != "chats" && (folder.deletingLastPathComponent as NSString).lastPathComponent == "chats"
    }

    /// The session a subagent's log works for.
    static func parentSession(of path: String) -> String {
        AgentLogParser.native(((path as NSString).deletingLastPathComponent as NSString).lastPathComponent)
    }

    /// Gemini CLI keeps the folder a session worked in beside its logs, not
    /// in them: each project's folder holds its full path in `.project_root`.
    func initialState(forLog path: String) -> AgentLogState {
        var state = AgentLogState()
        guard let chats = path.range(of: "/chats/", options: .backwards) else { return state }
        // Without O_NONBLOCK a FIFO in its place would block the open.
        let descriptor = open(String(path[..<chats.lowerBound]) + "/.project_root", O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return state }
        defer { close(descriptor) }
        var info = stat()
        var buffer = [UInt8](repeating: 0, count: 4096)
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return state }
        let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
        guard count > 0 else { return state }
        let owner = String(decoding: buffer[..<count], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if owner.hasPrefix("/") { state.project = AgentLogParser.projectName(owner) }
        return state
    }
}
