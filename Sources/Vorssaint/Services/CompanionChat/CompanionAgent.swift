// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Which AI answers in the companion's chat. Each answers one question at a
/// time through the command-line tool already installed and signed in on this
/// Mac, read-only, using the account's subscription before any API key.
enum CompanionAgent: String, CaseIterable, Identifiable {
    case claude, cursor, chatgpt
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .chatgpt: return "ChatGPT (Codex)"
        }
    }

    var tool: String {
        switch self {
        case .claude: return "claude"
        case .cursor: return "cursor-agent"
        case .chatgpt: return "codex"
        }
    }

    /// The saved choice, or until one is made the first tool installed on this
    /// Mac, so a new install works without opening Settings. A choice saved by
    /// an earlier version that no longer exists falls back the same way.
    static var current: CompanionAgent {
        CompanionAgent(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.companionChatAgent) ?? "") ?? detected
    }

    static var detected: CompanionAgent {
        [.claude, .chatgpt, .cursor].first { $0.executable() != nil } ?? .claude
    }

    /// Cursor is only offered when it's on this Mac, as its app or its command.
    var isPresent: Bool {
        guard self == .cursor else { return true }
        return executable() != nil
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") != nil
    }

    /// The AIs to list: those present here, plus the one currently chosen so
    /// the choice never disappears from its own menu.
    static func listed(chosen: CompanionAgent = .current) -> [CompanionAgent] {
        allCases.filter { $0.isPresent || $0 == chosen }
    }

    /// True once a test question has passed for this tool on this Mac. It is
    /// only asked again when a question later fails or Check now is pressed.
    var isVerified: Bool {
        let verified = UserDefaults.standard.dictionary(forKey: DefaultsKey.companionChatVerified) as? [String: Double] ?? [:]
        return CompanionSetupSupport.isVerified(verified, tool: tool)
    }

    /// Looks in the usual install folders; the app's own PATH is minimal.
    func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let folders = [home.appending(path: ".local/bin").path, home.appending(path: ".claude/local").path,
                       home.appending(path: ".npm-global/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        // Cursor ships the same CLI as `agent`; Codex also ships inside the ChatGPT app.
        let names = self == .cursor ? [tool, "agent"] : [tool]
        var paths = folders.flatMap { folder in names.map { folder + "/" + $0 } }
        if self == .chatgpt { paths.append("/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex") }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Read-only, no tools, nothing saved by the tool itself.
    func arguments(prompt: String, outputFile: String? = nil) -> [String] {
        switch self {
        case .claude: return ["-p", "--no-session-persistence", "--tools", "", "--", prompt]
        case .cursor: return ["-p", "--trust", "--mode", "ask", "--output-format", "text", "--", prompt]
        case .chatgpt:
            // `-o` keeps just the final answer, without Codex's banner and log.
            let out = outputFile.map { ["-o", $0] } ?? []
            return ["exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral", "--color", "never"] + out + ["--", prompt]
        }
    }

    /// Earlier turns are folded into the prompt, since each call is stateless.
    static func prompt(history: [CompanionMessage], question: String) -> String {
        let recent = history.suffix(8).map { ($0.isUser ? "User: " : "Assistant: ") + $0.text }
        guard !recent.isEmpty else { return question }
        return "Conversation so far:\n" + recent.joined(separator: "\n") + "\n\nUser: " + question
    }

    private func environment(for path: String, allowAPIKey: Bool, _ context: CompanionContext) -> [String: String] {
        var environment = CompanionSetupSupport.environment(context.environment, tool: tool, allowAPIKey: allowAPIKey)
        environment["PATH"] = [URL(fileURLWithPath: path).deletingLastPathComponent().path,
                               "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].joined(separator: ":")
        return environment
    }

    /// An empty folder of its own: the tools run read-only, but a trusted or
    /// sandboxed workspace should still be nothing, not the whole disk.
    static func workFolder(_ context: CompanionContext) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-companion", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])) != nil else { return nil }
        return folder
    }

    private func attempt(_ path: String, _ prompt: String, allowAPIKey: Bool, timeout: TimeInterval,
                         cancellation: BoundedProcessCancellation, _ context: CompanionContext) -> BoundedProcessRunner.Result {
        let environment = environment(for: path, allowAPIKey: allowAPIKey, context)
        guard self == .chatgpt else {
            return BoundedProcessRunner.run(path, arguments(prompt: prompt), timeout: timeout, maxOutputBytes: 1 << 20,
                                            environment: environment, cancellation: cancellation,
                                            currentDirectory: Self.workFolder(context))
        }
        // Codex reads extra input from stdin when it is open, so it is closed
        // here, and only its final message is kept.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        let result = BoundedProcessRunner.run("/bin/sh", ["-c", "exec \"$0\" \"$@\" </dev/null", path]
            + arguments(prompt: prompt, outputFile: file.path), timeout: timeout, maxOutputBytes: 1 << 20,
            environment: environment, cancellation: cancellation, currentDirectory: Self.workFolder(context))
        guard result.status == 0, !result.timedOut, let answer = try? Data(contentsOf: file), !answer.isEmpty else { return result }
        return BoundedProcessRunner.Result(status: 0, output: answer, timedOut: false)
    }

    /// Subscription sign-in first; an API key in the environment is only the fallback.
    private func result(_ path: String, _ prompt: String, timeout: TimeInterval,
                        cancellation: BoundedProcessCancellation, _ context: CompanionContext) -> BoundedProcessRunner.Result {
        let first = attempt(path, prompt, allowAPIKey: false, timeout: timeout, cancellation: cancellation, context)
        guard first.status != 0, !first.timedOut, !cancellation.isCancelled,
              CompanionSetupSupport.hasAPIKey(context.environment, tool: tool) else { return first }
        return attempt(path, prompt, allowAPIKey: true, timeout: timeout, cancellation: cancellation, context)
    }

    func ask(_ prompt: String, cancellation: BoundedProcessCancellation,
             context: CompanionContext = CompanionContext()) throws -> String {
        guard let path = executable(home: context.home) else { throw CompanionFailure.missing }
        let result = result(path, prompt, timeout: 120, cancellation: cancellation, context)
        guard !result.timedOut, !cancellation.isCancelled else { throw CompanionFailure.uncertain }
        guard result.status == 0 else { throw CompanionFailure.unavailable }
        let text = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CompanionFailure.malformed }
        return text
    }

    /// The cheap half of the check: is the tool there, and is it signed in.
    /// Used to notice a login or install finishing in Terminal.
    func isReadyToCheck(cancellation: BoundedProcessCancellation, context: CompanionContext = CompanionContext()) -> Bool {
        guard let path = executable(home: context.home) else { return false }
        let status = BoundedProcessRunner.run(path, CompanionSetupSupport.statusArguments(for: tool), timeout: 20,
            maxOutputBytes: 1 << 16, environment: environment(for: path, allowAPIKey: true, context), cancellation: cancellation)
        return CompanionSetupSupport.isSignedIn(tool: tool, status: status.status,
                                                output: String(decoding: status.output, as: UTF8.self))
    }

    /// First-use check: installed, signed in, and a one-word question answered.
    /// Works with a subscription login, so no API key is needed.
    /// Always sends the test question; callers only ask the first time, on
    /// Check now, or after a question failed. `onSignedIn` fires once the
    /// sign-in is confirmed, before the slower test question.
    func checkHealth(cancellation: BoundedProcessCancellation, context: CompanionContext = CompanionContext(),
                     onSignedIn: (() -> Void)? = nil) -> CompanionHealth {
        guard let path = executable(home: context.home) else { return .notInstalled }
        let status = BoundedProcessRunner.run(path, CompanionSetupSupport.statusArguments(for: tool), timeout: 20,
            maxOutputBytes: 1 << 16, environment: environment(for: path, allowAPIKey: true, context), cancellation: cancellation)
        let said = String(decoding: status.output, as: UTF8.self)
        let hasKey = CompanionSetupSupport.hasAPIKey(context.environment, tool: tool)
        // An API key counts as being signed in when no subscription login exists.
        if !CompanionSetupSupport.isSignedIn(tool: tool, status: status.status, output: said), !hasKey {
            return .notSignedIn
        }
        var verified = context.defaults.dictionary(forKey: DefaultsKey.companionChatVerified) as? [String: Double] ?? [:]
        onSignedIn?()
        let answer = result(path, CompanionSetupSupport.testQuestion, timeout: 90, cancellation: cancellation, context)
        // a stopped check says nothing about the tool, so it must not change the record
        guard !cancellation.isCancelled else { return .noAnswer(blocked: false, reason: "") }
        let text = String(decoding: answer.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.timedOut, answer.status == 0, !text.isEmpty {
            verified[tool] = Date().timeIntervalSince1970
            context.defaults.set(verified, forKey: DefaultsKey.companionChatVerified)
            return .ready
        }
        verified[tool] = nil
        context.defaults.set(verified, forKey: DefaultsKey.companionChatVerified)
        let detail = text.isEmpty ? String(decoding: answer.output, as: UTF8.self) : text
        return .noAnswer(blocked: CompanionSetupSupport.looksBlocked(detail), reason: CompanionSetupSupport.reason(from: detail))
    }
}
