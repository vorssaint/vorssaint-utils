// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct CursorReduceResult: Equatable {
    var store: CursorSessionStore
    var notices: [CursorNoticeFacts]
    var focusID: String?
}

enum CursorSessionReducer {
    static let maxSessions = 20
    static let maxSteps = 50
    static let maxEdits = 30
    static let maxHunks = 8
    static let quietAfter: TimeInterval = 10 * 60
    static let removeAfter: TimeInterval = 60 * 60
    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    static func isCursorApp(bundleIdentifier: String?, name: String?) -> Bool {
        if bundleIdentifier == cursorBundleID { return true }
        return name == "Cursor" || name == "Cursor Nightly"
    }

    /// `holdApprovals` is false until the approval card exists. The step is
    /// still recorded, and the agent is not left looking like it is waiting.
    static func reduce(_ store: CursorSessionStore, message: CursorHookMessage, now: Date,
                       holdApprovals: Bool = false) -> CursorReduceResult {
        guard let event = CursorHookDecoder.decode(message), let id = event.sessionID, !id.isEmpty else {
            return CursorReduceResult(store: store, notices: [], focusID: nil)
        }
        var store = store
        var notices: [CursorNoticeFacts] = []
        let waitingBefore = store.sessions.filter { $0.state == .waiting }.count
        let index = ensure(&store, id: id, event: event, now: now)
        var session = store.sessions[index]
        let wasFinished = session.state.isFinished
        apply(event, to: &session, store: &store, now: now, holdApprovals: holdApprovals)
        if !wasFinished, session.state.isFinished {
            notices.append(notice(for: session, at: now))
        }
        store.sessions[index] = session
        let waitingAfter = store.sessions.filter { $0.state == .waiting }.count
        if waitingBefore < 2, waitingAfter >= 2 {
            notices.append(CursorNoticeFacts(kind: .needsYou, project: session.project, files: 0,
                                              commands: 0, failures: 0, duration: 0, waiting: waitingAfter))
        }
        return CursorReduceResult(store: store, notices: notices, focusID: id)
    }

    static func tick(_ store: CursorSessionStore, now: Date) -> CursorSessionStore {
        var store = store
        applyQuiet(&store, now: now)
        store.sessions.removeAll { session in
            guard let ended = session.endedAt else { return false }
            return now.timeIntervalSince(ended) >= removeAfter
        }
        return store
    }

    static func wake(_ store: CursorSessionStore, now: Date) -> CursorSessionStore {
        var store = store
        applyQuiet(&store, now: now)
        return store
    }

    /// Cursor leaving ends every chat. A chat that was still working stops.
    static func cursorQuit(_ store: CursorSessionStore, now: Date) -> CursorSessionStore {
        var store = store
        for index in store.sessions.indices where store.sessions[index].endedAt == nil {
            if store.sessions[index].state.isWorking {
                store.sessions[index].state = .stopped
            }
            store.sessions[index].endedAt = now
            store.sessions[index].lastEvent = now
        }
        return store
    }

    private static func ensure(_ store: inout CursorSessionStore, id: String, event: CursorDecodedHook,
                               now: Date) -> Int {
        if let index = store.sessions.firstIndex(where: { $0.id == id }) { return index }
        while store.sessions.count >= maxSessions {
            let ended = store.sessions.indices.filter { store.sessions[$0].endedAt != nil }
            let pool = ended.isEmpty ? Array(store.sessions.indices) : ended
            guard let index = pool.min(by: { store.sessions[$0].lastEvent < store.sessions[$1].lastEvent }) else { break }
            store.sessions.remove(at: index)
        }
        let root = event.roots.first
        store.sessions.append(CursorSession(
            id: id, source: event.source, remote: event.remote, background: event.background ?? false,
            mode: event.mode, root: root, project: projectName(root), model: event.model,
            cursorVersion: event.cursorVersion, generationID: event.generationID, started: now,
            lastEvent: now, endedAt: nil, state: .idle, prompt: nil, steps: [], edits: [],
            thought: nil, thoughtDurationMS: nil, reply: nil, tokens: .none, subagents: [],
            context: nil, finishReason: nil
        ))
        return store.sessions.count - 1
    }

    private static func apply(_ event: CursorDecodedHook, to session: inout CursorSession,
                              store: inout CursorSessionStore, now: Date, holdApprovals: Bool) {
        session.lastEvent = now
        if event.remote { session.remote = true }
        if let background = event.background { session.background = background }
        if let mode = event.mode, !mode.isEmpty { session.mode = mode }
        if let model = event.model, !model.isEmpty { session.model = model }
        if let version = event.cursorVersion, !version.isEmpty { session.cursorVersion = version }
        if let root = event.roots.first, !root.isEmpty {
            session.root = root
            session.project = projectName(root)
        }
        if let generation = event.generationID, generation != session.generationID {
            session.generationID = generation
            session.thought = nil
            session.thoughtDurationMS = nil
            session.reply = nil
            session.tokens = .none
        }
        switch event.hook {
        case "sessionEnd":
            if let duration = event.sessionDurationMS {
                session.started = now.addingTimeInterval(-TimeInterval(duration) / 1000)
            }
            if let reason = event.reason { session.finishReason = reason }
            if !session.state.isFinished {
                session.state = reasonState(event.reason)
            }
            session.endedAt = now
        case "beforeSubmitPrompt":
            session.prompt = event.prompt
            session.state = .sent
            session.endedAt = nil
        case "afterAgentThought":
            session.thought = event.text
            session.thoughtDurationMS = event.thoughtDurationMS
            session.state = .thinking
            session.endedAt = nil
        case "afterAgentResponse":
            session.reply = event.text
            if !event.tokens.isEmpty { session.tokens = event.tokens }
            if session.state.isWorking || session.state == .idle || session.state == .sent {
                session.state = .idle
            }
        case "preToolUse":
            let label = stepLabel(tool: event.toolName, path: event.path, query: event.query, command: event.command)
            addStep(label, id: event.toolUseID, status: .running, sandbox: false, truncated: event.truncated,
                    to: &session, store: &store)
            session.state = holdApprovals ? .waiting : activity(for: label)
            session.endedAt = nil
        case "postToolUse":
            finishStep(id: event.toolUseID, tool: event.toolName, status: .done, output: nil,
                       duration: event.durationMS, sandbox: false, session: &session, store: &store,
                       path: event.path, query: event.query, command: event.command)
        case "postToolUseFailure":
            let status: CursorStepStatus = event.interrupted ? .stopped
                : event.failureType == "permission_denied" ? .denied : .failed
            finishStep(id: event.toolUseID, tool: event.toolName, status: status, output: nil,
                       duration: event.durationMS, sandbox: false, session: &session, store: &store,
                       path: event.path, query: event.query, command: event.command)
        case "beforeShellExecution":
            addStep(.run(event.command ?? ""), id: event.toolUseID, status: .running,
                    sandbox: event.sandbox ?? false, truncated: false, to: &session, store: &store)
            session.state = holdApprovals ? .waiting : .running
            session.endedAt = nil
        case "afterShellExecution":
            finishShell(event, session: &session, store: &store)
        case "beforeMCPExecution":
            let server = event.server ?? ""
            let tool = event.toolName ?? event.command ?? ""
            addStep(.mcp(server: server, tool: tool), id: event.toolUseID, status: .running,
                    sandbox: false, truncated: false, to: &session, store: &store)
            session.state = holdApprovals ? .waiting : .running
            session.endedAt = nil
        case "afterMCPExecution":
            finishStep(id: event.toolUseID, tool: nil, status: .done, output: nil, duration: event.durationMS,
                       sandbox: false, session: &session, store: &store, path: nil, query: nil, command: nil,
                       prefer: .mcp(server: event.server ?? "", tool: event.toolName ?? ""))
        case "afterFileEdit":
            absorbEdits(event, session: &session)
            if session.state != .waiting { session.state = .editing }
        case "subagentStart":
            let child = event.childConversationID ?? event.conversationID ?? store.nextStepID()
            let task = event.task ?? ""
            if let index = session.subagents.firstIndex(where: { $0.id == child }) {
                session.subagents[index].task = task.isEmpty ? session.subagents[index].task : task
                session.subagents[index].type = event.subagentType ?? session.subagents[index].type
                session.subagents[index].status = "running"
            } else {
                session.subagents.append(CursorSubagent(id: child, type: event.subagentType ?? "", task: task,
                                                        status: "running", summary: nil, files: []))
            }
            addStep(.subagent(task), id: event.toolUseID ?? child, status: .running, sandbox: false,
                    truncated: false, to: &session, store: &store)
            session.state = .subagent
            session.endedAt = nil
        case "subagentStop":
            let child = event.childConversationID ?? event.conversationID
            if let child, let index = session.subagents.firstIndex(where: { $0.id == child }) {
                session.subagents[index].status = event.status ?? "done"
                session.subagents[index].summary = event.summary ?? session.subagents[index].summary
                if !event.modifiedFiles.isEmpty { session.subagents[index].files = event.modifiedFiles }
            }
            finishStep(id: event.toolUseID ?? child, tool: nil, status: .done, output: nil, duration: nil,
                       sandbox: false, session: &session, store: &store, path: nil, query: nil, command: nil)
            if !session.subagents.contains(where: { $0.status == "running" }) {
                session.state = .thinking
            }
        case "preCompact":
            session.context = CursorContextMeter(percent: event.contextPercent, tokens: event.contextTokens,
                                                  window: event.contextWindow)
        case "stop":
            session.finishReason = event.status
            session.state = stopState(event.status)
            session.endedAt = now
        default:
            break
        }
    }

    private static func finishShell(_ event: CursorDecodedHook, session: inout CursorSession,
                                    store: inout CursorSessionStore) {
        let command = event.command ?? ""
        if let index = session.steps.lastIndex(where: { step in
            guard case .run(let existing) = step.label else { return false }
            return step.status == .running && (command.isEmpty || existing == command)
        }) {
            session.steps[index].status = .done
            session.steps[index].output = event.output
            session.steps[index].durationMS = event.durationMS
            session.steps[index].sandbox = event.sandbox ?? session.steps[index].sandbox
            session.steps[index].truncated = event.truncated
        } else {
            append(CursorStep(id: event.toolUseID ?? store.nextStepID(), label: .run(command), status: .done,
                              output: event.output, durationMS: event.durationMS,
                              sandbox: event.sandbox ?? false, truncated: event.truncated), to: &session)
        }
    }

    private static func addStep(_ label: CursorStepLabel, id: String?, status: CursorStepStatus, sandbox: Bool,
                                truncated: Bool, to session: inout CursorSession, store: inout CursorSessionStore) {
        if let id, let index = session.steps.firstIndex(where: { $0.id == id }) {
            session.steps[index].label = label
            session.steps[index].status = status
            session.steps[index].sandbox = sandbox
            return
        }
        append(CursorStep(id: id ?? store.nextStepID(), label: label, status: status, output: nil,
                          durationMS: nil, sandbox: sandbox, truncated: truncated), to: &session)
    }

    private static func finishStep(id: String?, tool: String?, status: CursorStepStatus, output: String?,
                                   duration: Int?, sandbox: Bool, session: inout CursorSession,
                                   store: inout CursorSessionStore, path: String?, query: String?,
                                   command: String?, prefer: CursorStepLabel? = nil) {
        if let id, let index = session.steps.firstIndex(where: { $0.id == id }) {
            session.steps[index].status = status
            session.steps[index].durationMS = duration ?? session.steps[index].durationMS
            if output != nil { session.steps[index].output = output }
            return
        }
        if let index = session.steps.lastIndex(where: { $0.status == .running && matches($0.label, tool: tool, prefer: prefer) }) {
            session.steps[index].status = status
            session.steps[index].durationMS = duration ?? session.steps[index].durationMS
            return
        }
        let label = prefer ?? stepLabel(tool: tool, path: path, query: query, command: command)
        append(CursorStep(id: id ?? store.nextStepID(), label: label, status: status, output: output,
                          durationMS: duration, sandbox: sandbox, truncated: false), to: &session)
    }

    private static func matches(_ label: CursorStepLabel, tool: String?, prefer: CursorStepLabel?) -> Bool {
        if let prefer {
            switch (label, prefer) {
            case (.mcp, .mcp): return true
            default: break
            }
        }
        guard let tool else { return false }
        switch (label, tool) {
        case (.read, "Read"), (.search, "Grep"), (.search, "Glob"), (.search, "WebSearch"), (.search, "WebFetch"),
             (.edit, "Write"), (.edit, "Edit"), (.delete, "Delete"), (.run, "Shell"), (.run, "Bash"),
             (.subagent, "Task"):
            return true
        default:
            return false
        }
    }

    private static func append(_ step: CursorStep, to session: inout CursorSession) {
        session.steps.append(step)
        if session.steps.count > maxSteps {
            session.steps.removeFirst(session.steps.count - maxSteps)
        }
    }

    private static func absorbEdits(_ event: CursorDecodedHook, session: inout CursorSession) {
        let grouped = Dictionary(grouping: event.edits, by: { $0.path ?? event.path ?? "" })
        for (path, hunks) in grouped {
            let file = path.isEmpty ? "file" : path
            let converted = hunks.prefix(maxHunks).map {
                CursorEditHunk(oldText: $0.oldText, newText: $0.newText, truncated: $0.truncated || event.truncated)
            }
            let counts = converted.reduce((added: 0, removed: 0)) { partial, hunk in
                let diff = CursorLineDiff.counts(old: hunk.oldText, new: hunk.newText)
                return (partial.added + diff.added, partial.removed + diff.removed)
            }
            if let index = session.edits.firstIndex(where: { $0.path == file }) {
                session.edits[index].hunks = Array(converted)
                session.edits[index].added = counts.added
                session.edits[index].removed = counts.removed
            } else {
                session.edits.append(CursorEdit(id: file, path: file, hunks: Array(converted),
                                                added: counts.added, removed: counts.removed))
            }
        }
        if session.edits.count > maxEdits {
            session.edits.removeFirst(session.edits.count - maxEdits)
        }
    }

    private static func stepLabel(tool: String?, path: String?, query: String?, command: String?) -> CursorStepLabel {
        let file = fileName(path)
        switch tool {
        case "Read": return .read(file)
        case "Grep", "Glob", "WebSearch", "WebFetch": return .search(query ?? file)
        case "Write", "Edit": return .edit(file)
        case "Delete": return .delete(file)
        case "Shell", "Bash": return .run(command ?? "")
        case "Task": return .subagent(query ?? "")
        default:
            if let command, !command.isEmpty { return .run(command) }
            return .tool(tool ?? "tool")
        }
    }

    private static func activity(for label: CursorStepLabel) -> CursorLiveState {
        switch label {
        case .read: return .reading
        case .search: return .searching
        case .edit, .delete: return .editing
        case .run, .mcp: return .running
        case .subagent: return .subagent
        case .tool: return .running
        }
    }

    private static func stopState(_ status: String?) -> CursorLiveState {
        switch status {
        case "error": return .failed
        case "aborted": return .stopped
        default: return .done
        }
    }

    private static func reasonState(_ reason: String?) -> CursorLiveState {
        switch reason {
        case "error": return .failed
        case "aborted": return .stopped
        default: return .done
        }
    }

    private static func notice(for session: CursorSession, at now: Date) -> CursorNoticeFacts {
        CursorNoticeFacts(
            kind: session.state == .failed ? .failed : session.state == .stopped ? .stopped : .finished,
            project: session.project, files: session.fileCount, commands: session.commandCount,
            failures: session.failureCount, duration: now.timeIntervalSince(session.started), waiting: 0
        )
    }

    private static func applyQuiet(_ store: inout CursorSessionStore, now: Date) {
        for index in store.sessions.indices where store.sessions[index].state.isWorking {
            if now.timeIntervalSince(store.sessions[index].lastEvent) >= quietAfter {
                store.sessions[index].state = .quiet
            }
        }
    }

    static func projectName(_ root: String?) -> String {
        guard let root, !root.isEmpty else { return "Cursor" }
        let name = URL(fileURLWithPath: root).lastPathComponent
        return name.isEmpty ? "Cursor" : name
    }

    static func fileName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "file" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }
}
