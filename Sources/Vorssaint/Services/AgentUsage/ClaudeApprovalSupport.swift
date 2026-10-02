// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One AskUserQuestion question, as Claude Code sends it.
struct ClaudeApprovalQuestion: Equatable {
    struct Option: Equatable {
        let label: String
        let description: String?

        /// Claude marks its pick by ending the label with "(Recommended)".
        var isRecommended: Bool { label.hasSuffix("(Recommended)") }
        /// The label without that marker; the answer still sends `label`.
        var title: String {
            isRecommended ? String(label.dropLast("(Recommended)".count)).trimmingCharacters(in: .whitespaces) : label
        }
    }
    let text: String
    let header: String?
    let options: [Option]
    let multiSelect: Bool
}

/// What the card asks: a tool to allow, questions to answer, or a plan to approve.
enum ClaudeApprovalKind: Equatable {
    case tool
    case questions([ClaudeApprovalQuestion])
    case plan(String)
}

/// One Claude Code or Codex PermissionRequest, reduced to what the notch card
/// shows and what the reply and the transcript watch need.
struct ClaudeApprovalRequest: Equatable {
    /// Assigned by the service per connection, so an answer reaches the request
    /// the card showed and never one that replaced it a moment later.
    var id = 0
    var agent = AgentProvider.claude
    var kind = ClaudeApprovalKind.tool
    let cwd: String
    let toolName: String
    let toolInput: NSDictionary
    let summary: String
    let transcriptPath: String?
    /// The `addRules` suggestions only. Claude Code also suggests session-wide
    /// updates such as switching to accept-edits mode, which is broader than
    /// what "Always" promises, so those are never sent.
    let alwaysRules: NSArray?

    var canAlways: Bool { alwaysRules != nil }
    var project: String { AgentLogParser.projectName(cwd) }
}

enum ClaudeApprovalDecision: Equatable {
    case allow, deny, always
    /// AskUserQuestion: question text to the chosen label(s).
    case answers([String: String])
    /// ExitPlanMode: approve and switch the session to accept-edits.
    case allowAcceptingEdits
}

enum ClaudeHookStatus: Equatable { case notInstalled, installed, otherCopy, unreadable }

struct ClaudeSettingsDiffLine: Equatable {
    enum Kind { case same, added, removed }
    let kind: Kind
    let text: String
}

enum ClaudeApprovalSupport {
    /// Claude Code waits up to the hook timeout (120 s) and the relay up to
    /// 115 s; releasing first keeps Claude Code's own prompt in charge.
    static let pendingSeconds: TimeInterval = 110
    static let hookTimeout = 120
    static let denyMessage = "Denied in Vorssaint"
    static let keepPlanningMessage = "Not approved in Vorssaint. Keep planning."
    /// `sun_path` holds 104 bytes including the terminator.
    static let socketPathLimit = 103

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchAgentSupport.isEnabled(in: defaults)
            && AppFeature.notchAgentApprovals.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchAgentApprovalsEnabled)
    }

    static func socketPath(container: URL) -> String? {
        let path = container.appendingPathComponent("claude.sock").path
        return path.utf8.count <= socketPathLimit ? path : nil
    }

    static func settingsURL(for agent: AgentProvider) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(agent == .codex ? ".codex/hooks.json" : ".claude/settings.json")
    }

    /// The name the settings and the card use; product names stay untranslated.
    static func productName(_ agent: AgentProvider) -> String {
        agent == .codex ? "Codex" : "Claude Code"
    }

    // MARK: Payload and reply

    /// Claude Code's AskUserQuestion and ExitPlanMode become their own cards;
    /// one that cannot be read is nil, so it goes back to the terminal rather
    /// than showing raw JSON. Codex documents neither, and may omit the tool.
    static func parseRequest(_ data: Data, agent: AgentProvider = .claude) -> ClaudeApprovalRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["hook_event_name"] as? String == "PermissionRequest"
        else { return nil }
        let tool = object["tool_name"] as? String ?? ""
        guard agent == .codex || !tool.isEmpty else { return nil }
        let input = object["tool_input"] as? [String: Any] ?? [:]
        var kind = ClaudeApprovalKind.tool
        if agent == .claude, tool == "AskUserQuestion" {
            guard let questions = parseQuestions(input["questions"]) else { return nil }
            kind = .questions(questions)
        } else if agent == .claude, tool == "ExitPlanMode" {
            guard let plan = input["plan"] as? String, planTitle(plan) != nil else { return nil }
            kind = .plan(plan)
        }
        let rules = agent == .codex ? [] : (object["permission_suggestions"] as? [Any] ?? []).filter {
            guard let update = $0 as? [String: Any] else { return false }
            return update["type"] as? String == "addRules" && !(update["rules"] as? [Any] ?? []).isEmpty
        }
        return ClaudeApprovalRequest(
            agent: agent,
            kind: kind,
            cwd: object["cwd"] as? String ?? "",
            toolName: tool,
            toolInput: input as NSDictionary,
            summary: summary(tool: tool, input: input),
            // Codex rollouts are not Claude transcripts, so nothing watches them.
            transcriptPath: agent == .codex ? nil : object["transcript_path"] as? String,
            alwaysRules: rules.isEmpty ? nil : rules as NSArray)
    }

    /// One to four questions, each with a text and at least one option.
    /// Options arrive as `{label, description}`; plain strings are accepted too.
    static func parseQuestions(_ raw: Any?) -> [ClaudeApprovalQuestion]? {
        guard let items = raw as? [[String: Any]], (1...4).contains(items.count) else { return nil }
        let questions = items.compactMap { item -> ClaudeApprovalQuestion? in
            guard let text = item["question"] as? String, !text.isEmpty else { return nil }
            let options = (item["options"] as? [Any] ?? []).compactMap { option -> ClaudeApprovalQuestion.Option? in
                if let label = option as? String { return label.isEmpty ? nil : .init(label: label, description: nil) }
                guard let option = option as? [String: Any], let label = option["label"] as? String, !label.isEmpty
                else { return nil }
                return .init(label: label, description: option["description"] as? String)
            }
            guard !options.isEmpty else { return nil }
            return ClaudeApprovalQuestion(text: text, header: item["header"] as? String, options: options,
                                          multiSelect: item["multiSelect"] as? Bool ?? false)
        }
        return questions.count == items.count ? questions : nil
    }

    /// Question text to its answer: the chosen labels in option order, then
    /// the typed "Other" text, joined with ", " as Claude Code's own picker
    /// does. nil while any question is still blank.
    static func answers(for questions: [ClaudeApprovalQuestion], chosen: [Set<Int>],
                        other: [String]) -> [String: String]? {
        var answers: [String: String] = [:]
        for (index, question) in questions.enumerated() {
            var labels = question.options.indices
                .filter { chosen.indices.contains(index) && chosen[index].contains($0) }
                .map { question.options[$0].label }
            let typed = other.indices.contains(index) ? other[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if !typed.isEmpty { labels.append(typed) }
            guard !labels.isEmpty else { return nil }
            answers[question.text] = labels.joined(separator: ", ")
        }
        return answers
    }

    /// The plan's first `#` heading, else its first line; nil for a blank plan.
    static func planTitle(_ plan: String) -> String? {
        let lines = plan.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        let line = lines.first { $0.hasPrefix("# ") } ?? first
        let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? first : title
    }

    /// Whether this answer fits this card; anything else is ignored.
    static func accepts(_ decision: ClaudeApprovalDecision, for request: ClaudeApprovalRequest) -> Bool {
        switch (decision, request.kind) {
        case (.always, _): return request.canAlways
        case (.answers(let answers), .questions(let questions)): return answers.count == questions.count
        case (.answers, _): return false
        case (.allowAcceptingEdits, .plan): return true
        case (.allowAcceptingEdits, _): return false
        default: return true
        }
    }

    static func summary(tool: String, input: [String: Any]) -> String {
        if let command = input["command"] as? String { return command }
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String { return path }
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return tool }
        return String(decoding: data, as: UTF8.self)
    }

    static func reply(_ decision: ClaudeApprovalDecision, for request: ClaudeApprovalRequest) -> Data {
        var verdict: [String: Any]
        switch decision {
        case .allow: verdict = ["behavior": "allow"]
        case .deny:
            if case .plan = request.kind {
                verdict = ["behavior": "deny", "message": keepPlanningMessage]
            } else {
                verdict = ["behavior": "deny", "message": denyMessage]
            }
        case .always:
            verdict = ["behavior": "allow"]
            if let rules = request.alwaysRules { verdict["updatedPermissions"] = rules }
        case .answers(let answers):
            // Claude Code validates updatedInput against the whole schema, so
            // the questions go back with the answers.
            var input = request.toolInput as? [String: Any] ?? [:]
            input["answers"] = answers
            verdict = ["behavior": "allow", "updatedInput": input]
        case .allowAcceptingEdits:
            verdict = ["behavior": "allow", "updatedPermissions": [
                ["type": "setMode", "mode": "acceptEdits", "destination": "session"]]]
        }
        let output: [String: Any] = ["hookSpecificOutput": [
            "hookEventName": "PermissionRequest", "decision": verdict]]
        return (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
    }

    // MARK: Transcript

    /// Claude Code shows its own prompt alongside the hook and keeps the hook
    /// running after the user answers there, so the transcript is the only
    /// sign the request is settled. `toolUseID` follows the latest tool_use
    /// matching the request; its tool_result settles it. `counting` is false
    /// for lines written before the request arrived, which only find the id.
    static func scanTranscript(_ lines: [Substring], for request: ClaudeApprovalRequest,
                               toolUseID: inout String?, counting: Bool) -> Bool {
        for line in lines where line.contains("tool_") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]]
            else { continue }
            for block in content {
                switch block["type"] as? String {
                case "tool_use":
                    if block["name"] as? String == request.toolName,
                       (block["input"] as? NSDictionary ?? [:]) == request.toolInput {
                        toolUseID = block["id"] as? String
                    }
                case "tool_result":
                    guard let id = toolUseID, block["tool_use_id"] as? String == id else { continue }
                    if counting { return true }
                    toolUseID = nil
                default: continue
                }
            }
        }
        return false
    }

    // MARK: settings.json and hooks.json

    static func hookCommand(executable: String, socket: String, agent: AgentProvider = .claude) -> String {
        let argument = agent == .codex ? ClaudeApprovalRelay.codexArgument : ClaudeApprovalRelay.argument
        return "\(shellQuoted(executable)) \(argument) \(shellQuoted(socket))"
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func isVorssaintHook(_ command: String) -> Bool {
        command.contains(ClaudeApprovalRelay.argument) || command.contains(ClaudeApprovalRelay.codexArgument)
    }

    private static func permissionCommands(in settings: [String: Any]) -> [String] {
        let groups = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    static func installedCommand(in settings: [String: Any]) -> String? {
        permissionCommands(in: settings).first(where: isVorssaintHook)
    }

    static func foreignPermissionHooks(in settings: [String: Any]) -> [String] {
        permissionCommands(in: settings).filter { !isVorssaintHook($0) }
    }

    /// nil for a missing file, which installs into an empty object.
    static func parseSettings(_ data: Data?) -> [String: Any]? {
        guard let data, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x09 || $0 == 0x0D })
        else { return [:] }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func status(of data: Data?, command: String) -> ClaudeHookStatus {
        guard let settings = parseSettings(data) else { return .unreadable }
        switch installedCommand(in: settings) {
        case nil: return .notInstalled
        case command: return .installed
        default: return .otherCopy
        }
    }

    /// Any earlier Vorssaint entry (another build, a moved app) is removed
    /// first, so installing again is also the migration.
    static func installing(_ settings: [String: Any], command: String) -> [String: Any] {
        var settings = uninstalling(settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var groups = hooks["PermissionRequest"] as? [Any] ?? []
        groups.append(["hooks": [["type": "command", "command": command, "timeout": hookTimeout]]])
        hooks["PermissionRequest"] = groups
        settings["hooks"] = hooks
        return settings
    }

    static func uninstalling(_ settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any],
              let groups = hooks["PermissionRequest"] as? [Any]
        else { return settings }
        let kept: [Any] = groups.compactMap { item in
            guard var group = item as? [String: Any], let entries = group["hooks"] as? [Any] else { return item }
            let others = entries.filter { !isVorssaintHook(($0 as? [String: Any])?["command"] as? String ?? "") }
            guard others.count != entries.count else { return item }
            guard !others.isEmpty else { return nil }
            group["hooks"] = others
            return group
        }
        var settings = settings
        hooks["PermissionRequest"] = kept.isEmpty ? nil : kept
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    static func render(_ settings: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }

    /// ponytail: O(n·m) line LCS, fine for a settings file; Myers if it ever isn't.
    static func diff(_ old: String, _ new: String) -> [ClaudeSettingsDiffLine] {
        let a = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let b = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var lines: [ClaudeSettingsDiffLine] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                lines.append(.init(kind: .same, text: a[i])); i += 1; j += 1
            } else if j < b.count, i == a.count || lengths[i][j + 1] >= lengths[i + 1][j] {
                lines.append(.init(kind: .added, text: b[j])); j += 1
            } else {
                lines.append(.init(kind: .removed, text: a[i])); i += 1
            }
        }
        return lines
    }

    static func backupName(file: String = "settings.json", date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return file + ".bak-" + formatter.string(from: date)
    }
}
