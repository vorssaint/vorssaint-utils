// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CursorRuleDecision: Equatable {
    /// Answer at once and let the tool run, with no permission JSON.
    case pass
    case allow
    case deny
    /// Hand the prompt back to Cursor.
    case ask
    /// Keep the hook open for the person.
    case hold
}

enum CursorApprovalRules {
    static let ruleCap = 50

    static func tokens(_ command: String) -> [String] {
        command.split { $0.isWhitespace }.map(String.init)
    }

    /// Deny wins. The longest matching token prefix wins. A risky command
    /// still asks, even when an allow rule matches.
    static func decision(command: String, allow: [String], deny: [String]) -> CursorRuleDecision {
        let tokens = tokens(command)
        guard !tokens.isEmpty else { return .hold }
        let denied = best(tokens, in: deny)
        let allowed = best(tokens, in: allow)
        if let denied, denied >= (allowed ?? 0) { return .deny }
        if allowed != nil {
            return isRisky(command) ? .hold : .allow
        }
        return .hold
    }

    static func isRisky(_ command: String) -> Bool {
        let tokens = tokens(command)
        if tokens.contains("rm"), tokens.contains(where: { $0 == "-rf" || $0 == "-fr" || $0.hasPrefix("-") && $0.contains("r") && $0.contains("f") }) {
            return true
        }
        if tokens.first == "git", tokens.contains("push"),
           tokens.contains(where: { $0 == "--force" || $0 == "-f" || $0 == "--force-with-lease" }) {
            return true
        }
        let folded = command.lowercased()
        if folded.contains("curl"), folded.contains("|"), folded.contains("sh") { return true }
        return false
    }

    static func lines(_ stored: String) -> [String] {
        stored.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func stored(_ rules: [String]) -> String {
        rules.prefix(ruleCap).joined(separator: "\n")
    }

    private static func best(_ tokens: [String], in rules: [String]) -> Int? {
        rules.map { prefixLength(tokens, rule: CursorApprovalRules.tokens($0)) }.filter { $0 > 0 }.max()
    }

    private static func prefixLength(_ tokens: [String], rule: [String]) -> Int {
        guard !rule.isEmpty, rule.count <= tokens.count else { return 0 }
        for (index, token) in rule.enumerated() where token != tokens[index] { return 0 }
        return rule.count
    }
}

enum CursorProtectedPaths {
    /// A glob matches the relative path and the basename. `*` and `?` are
    /// wildcards. An empty list means every edit is covered.
    static func includes(_ path: String, globs: [String]) -> Bool {
        let patterns = globs.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !patterns.isEmpty else { return true }
        let base = URL(fileURLWithPath: path).lastPathComponent
        return patterns.contains { pattern in
            matches(path, pattern) || matches(base, pattern)
        }
    }

    static func matches(_ text: String, _ pattern: String) -> Bool {
        match(Array(text), pattern: Array(pattern))
    }

    private static func match(_ text: [Character], pattern: [Character]) -> Bool {
        var textIndex = 0
        var patternIndex = 0
        var star = -1
        var mark = 0
        while textIndex < text.count {
            if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                star = patternIndex
                patternIndex += 1
                mark = textIndex
            } else if patternIndex < pattern.count,
                      pattern[patternIndex] == "?" || pattern[patternIndex] == text[textIndex] {
                textIndex += 1
                patternIndex += 1
            } else if star >= 0 {
                patternIndex = star + 1
                mark += 1
                textIndex = mark
            } else {
                return false
            }
        }
        while patternIndex < pattern.count, pattern[patternIndex] == "*" { patternIndex += 1 }
        return patternIndex == pattern.count
    }
}

enum CursorApprovalGate {
    static func decide(hook: String, command: String, path: String, server: String, tool: String,
                       approvals: Bool, edits: Bool, allow: [String], deny: [String],
                       protected: [String]) -> CursorRuleDecision {
        switch hook {
        case "beforeShellExecution", "beforeMCPExecution":
            guard approvals else { return .pass }
            let subject = hook == "beforeMCPExecution" && command.isEmpty
                ? [server, tool].filter { !$0.isEmpty }.joined(separator: " ")
                : command
            return CursorApprovalRules.decision(command: subject, allow: allow, deny: deny)
        case "preToolUse":
            guard edits, CursorProtectedPaths.includes(path, globs: protected) else { return .pass }
            return .hold
        default:
            return .pass
        }
    }
}

enum CursorFollowUp {
    enum Action: Equatable {
        case send(String)
        case hold
        case ignore
    }

    static func decide(status: String?, loopCount: Int, queued: String?, holdSeconds: Int,
                       queueOnAbort: Bool) -> Action {
        guard loopCount <= 0, status != "error" else { return .ignore }
        let allowed = status == "completed" || (status == "aborted" && queueOnAbort)
        guard allowed else { return .ignore }
        if let queued, !queued.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .send(queued)
        }
        return holdSeconds > 0 ? .hold : .ignore
    }
}

enum CursorPromptLink {
    static let limit = 10_000

    static func encodedCount(_ text: String) -> Int {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return 21 + encoded.count
    }

    static func fits(_ text: String) -> Bool {
        encodedCount(text) <= limit
    }

    static func url(text: String) -> URL? {
        guard fits(text), !text.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "cursor://anysphere.cursor-deeplink/prompt?text=\(encoded)")
    }
}

enum CursorRepoList {
    static func remember(_ path: String, existing: [String], limit: Int = 20) -> [String] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existing }
        var next = existing.filter { $0 != trimmed }
        next.insert(trimmed, at: 0)
        if next.count > limit { next = Array(next.prefix(limit)) }
        return next
    }
}

enum CursorHookDecider {
    /// Nil means the socket should keep the hook open.
    static func reply(_ message: CursorHookMessage, queues: [String: String],
                      defaults: UserDefaults = .standard) -> CursorHookReply? {
        if CursorHookInstaller.isProbe(message) { return .empty }
        switch message.hook {
        case "sessionStart":
            return .empty
        case "stop":
            return stopReply(message, queues: queues, defaults: defaults)
        case "beforeShellExecution", "beforeMCPExecution", "preToolUse":
            return approvalReply(message, defaults: defaults)
        default:
            return .empty
        }
    }

    private static func approvalReply(_ message: CursorHookMessage, defaults: UserDefaults) -> CursorHookReply? {
        let fields = CursorHookDecoder.decode(message)
        let gate = CursorApprovalGate.decide(
            hook: message.hook,
            command: fields?.command ?? "",
            path: fields?.path ?? "",
            server: fields?.server ?? "",
            tool: fields?.toolName ?? "",
            approvals: defaults.bool(forKey: DefaultsKey.notchCursorApprovals),
            edits: defaults.bool(forKey: DefaultsKey.notchCursorApproveEdits),
            allow: CursorApprovalRules.lines(defaults.string(forKey: DefaultsKey.notchCursorAllowRules) ?? ""),
            deny: CursorApprovalRules.lines(defaults.string(forKey: DefaultsKey.notchCursorDenyRules) ?? ""),
            protected: CursorApprovalRules.lines(defaults.string(forKey: DefaultsKey.notchCursorProtectedPaths) ?? "")
        )
        switch gate {
        case .pass: return .empty
        case .allow: return CursorHookReplies.allow()
        case .deny: return CursorHookReplies.deny()
        case .ask: return CursorHookReplies.ask()
        case .hold: return nil
        }
    }

    private static func stopReply(_ message: CursorHookMessage, queues: [String: String],
                                  defaults: UserDefaults) -> CursorHookReply? {
        let fields = CursorHookDecoder.decode(message)
        let id = fields?.conversationID ?? ""
        let hold = defaults.integer(forKey: DefaultsKey.notchCursorHoldForReply)
        let action = CursorFollowUp.decide(
            status: fields?.status,
            loopCount: fields?.loopCount ?? 0,
            queued: queues[id],
            holdSeconds: [30, 60, 120].contains(hold) ? hold : 0,
            queueOnAbort: defaults.bool(forKey: DefaultsKey.notchCursorQueueOnAbort)
        )
        switch action {
        case .send(let text): return CursorHookReplies.followUp(text)
        case .hold: return nil
        case .ignore: return .empty
        }
    }

}

enum CursorHookReplies {
    static func allow() -> CursorHookReply {
        CursorHookReply(stdout: #"{"permission":"allow"}"#, exitCode: 0)
    }

    static func ask() -> CursorHookReply {
        CursorHookReply(stdout: #"{"permission":"ask"}"#, exitCode: 0)
    }

    static func deny() -> CursorHookReply {
        CursorHookReply(stdout: CursorHookProtocol.deniedStdout(), exitCode: 0)
    }

    static func followUp(_ message: String) -> CursorHookReply {
        let object = ["followup_message": message]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return .empty }
        return CursorHookReply(stdout: text, exitCode: 0)
    }

    static func context(_ note: String) -> CursorHookReply {
        let object = ["additional_context": note]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return .empty }
        return CursorHookReply(stdout: text, exitCode: 0)
    }

    /// What to print when the person cannot see a prompt.
    static func deferral(hook: String) -> CursorHookReply {
        hook == "preToolUse" ? .empty : ask()
    }
}
