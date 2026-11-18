// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Antigravity's account-wide quota pools through its own CLI (`agy`).
/// Antigravity handles authentication itself; no prompt reaches a model and
/// nothing besides the parsed window usage and renewal time is retained.
enum AgentAntigravityServer {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, outdated, unreachable
    }

    static let timeout: TimeInterval = 25
    static let versionTimeout: TimeInterval = 5
    static let printTimeout = "20s"
    static let minimumVersion = (1, 1, 11)
    /// While the AI page is on screen a reading this old is asked again.
    static let freshness: TimeInterval = 60
    /// Otherwise Antigravity starts at most this often.
    static let backgroundFreshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 5 * 60
    /// Only the person can install, update or sign in to Antigravity.
    static let settledRetry: TimeInterval = 30 * 60
    private static let maxOutputBytes = 256 * 1024

    /// How long after the last check Antigravity is asked again. Each check
    /// in a row without an answer doubles the wait, up to settledRetry, so a
    /// broken or outdated CLI is rarely started.
    static func interval(after failure: Failure?, repeated: Int = 1, pageVisible: Bool) -> TimeInterval {
        switch failure {
        case nil: return pageVisible ? freshness : backgroundFreshness
        case .unreachable?: return min(settledRetry, retryAfter * Double(1 << min(3, max(0, repeated - 1))))
        case .missing?, .needsSignIn?, .outdated?: return settledRetry
        }
    }

    static func candidates(home: URL, searchPath: String? = nil) -> [URL] {
        var folders: [String] = [
            home.appending(path: ".local/bin").path,
            home.appending(path: ".antigravity/bin").path,
            // The Antigravity app installs its own copy here, which may be
            // older than the standalone CLI, so it comes after it.
            home.appending(path: ".gemini/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        folders += (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        folders += AgentClaudeServer.toolFolders(home: home)
        return folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "agy") }
    }

    static func executable(home: URL, searchPath: String? = nil) -> URL? {
        candidates(home: home, searchPath: searchPath).first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func environment(_ base: [String: String], executable: URL, home: URL) -> [String: String] {
        var env = AgentCodexServer.environment(for: executable, searchPath: nil, base: base)
        env["PATH"] = AgentClaudeServer.searchPath(after: env["PATH"] ?? "", home: home)
        return env
    }

    static func parseVersion(_ output: String) -> (Int, Int, Int)? {
        for rawToken in output.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }) {
            let trimmed = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let core = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmed
            let parts = core.split(separator: ".").map(String.init)
            guard parts.count >= 3,
                  let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { continue }
            return (major, minor, patch)
        }
        return nil
    }

    static func supportsUsageCommand(_ versionOutput: Data) -> Bool {
        guard let text = String(data: versionOutput, encoding: .utf8),
              let version = parseVersion(text) else { return false }
        return version >= minimumVersion
    }

    static func limits(_ json: [String: Any], observed: Date) -> AgentLimits? {
        if let status = json["status"] as? String, status.uppercased() != "SUCCESS" { return nil }
        guard let command = json["command"] as? [String: Any],
              let data = command["data"] as? [String: Any],
              let groups = data["groups"] as? [[String: Any]] else { return nil }

        var primary: [AgentLimitWindow] = []
        var scoped: [AgentLimitWindow] = []
        for group in groups {
            let groupName = (group["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let scope = windowScope(for: groupName)
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                if bucket["disabled"] as? Bool == true { continue }
                guard let remaining = bucket["remaining_fraction"] as? NSNumber,
                      CFGetTypeID(remaining) != CFBooleanGetTypeID(), remaining.doubleValue.isFinite else { continue }
                let resets = bucket["reset_time"].flatMap { $0 is NSNull ? nil : $0 }
                let end = (resets as? String).flatMap(AgentTimestamp.parse)
                guard resets == nil || end.map({ $0 > observed }) == true else { continue }

                let windowName = bucket["window"] as? String ?? ""
                let (kind, minutes) = windowSpec(windowName)
                let rawID = (bucket["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let identifier = rawID?.isEmpty == false ? rawID! : "\(scope ?? "main").\(windowName)"
                let usedPercent = min(100, max(0, (1 - remaining.doubleValue) * 100))
                let window = AgentLimitWindow(
                    id: "antigravity.\(identifier)", kind: kind, minutes: minutes, scope: scope,
                    usedPercent: usedPercent, resetsAt: end
                )
                if scope == nil { primary.append(window) } else { scoped.append(window) }
            }
        }
        let windows = primary + scoped
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .antigravity, windows: windows, observedAt: observed, source: .account)
    }

    /// Expires each window without inventing zero usage after a reset.
    static func current(_ reading: AgentLimits?, now: Date) -> AgentLimits? {
        guard var reading else { return nil }
        let age = now.timeIntervalSince(reading.observedAt)
        reading.windows.removeAll { window in
            if let resets = window.resetsAt { return resets <= now }
            return age >= (window.kind == .session ? TimeInterval(window.minutes ?? 300) * 60 : 86_400)
        }
        return reading.windows.isEmpty ? nil : reading
    }

    static func parseUsageResult(_ output: Data, status: Int32, observed: Date) -> Result<AgentLimits, Failure> {
        let rawText = String(data: output, encoding: .utf8) ?? ""
        if let json = decodeObject(output) {
            if let statusText = json["status"] as? String, statusText.uppercased() != "SUCCESS" {
                return .failure(classifyFailure(message: errorText(from: json) ?? rawText))
            }
            if status != 0 {
                return .failure(classifyFailure(message: errorText(from: json) ?? rawText))
            }
            guard let reading = limits(json, observed: observed) else { return .failure(.unreachable) }
            return .success(reading)
        }
        guard status == 0 else { return .failure(classifyFailure(message: rawText)) }
        return .failure(.unreachable)
    }

    private static func windowScope(for groupName: String) -> String? {
        let lower = groupName.lowercased()
        if lower.isEmpty || lower == "gemini models" { return nil }
        if lower.contains("claude") && lower.contains("gpt") { return "Claude/GPT" }
        if lower.hasSuffix(" models") {
            let trimmed = String(groupName.dropLast(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return groupName
    }

    private static func windowSpec(_ window: String) -> (AgentLimitWindow.Kind, Int?) {
        let lower = window.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lower {
        case "5h": return (.session, 300)
        case "weekly", "7d": return (.weekly, 10_080)
        default:
            if lower.hasSuffix("h"), let hours = Int(lower.dropLast()), hours > 0 {
                let minutes = hours * 60
                return (AgentLogParser.kind(minutes: minutes), minutes)
            }
            if lower.hasSuffix("d"), let days = Int(lower.dropLast()), days > 0 {
                let minutes = days * 1440
                return (AgentLogParser.kind(minutes: minutes), minutes)
            }
            return (.other, nil)
        }
    }

    private static func decodeObject(_ data: Data) -> [String: Any]? {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return object }
        // stderr shares the pipe, and agy can log lines that hold braces
        // before its result. The result is one JSON line, so take the last
        // line that parses as an object instead of slicing between braces.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let object = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any]
            else { continue }
            return object
        }
        return nil
    }

    private static func errorText(from json: [String: Any]) -> String? {
        for key in ["error", "message", "detail"] {
            if let text = json[key] as? String, !text.isEmpty { return text }
            if let nested = json[key] as? [String: Any],
               let text = nested["message"] as? String ?? nested["error"] as? String { return text }
        }
        if let command = json["command"] as? [String: Any],
           let error = command["error"] as? String ?? command["message"] as? String { return error }
        return nil
    }

    private static func classifyFailure(message: String) -> Failure {
        let lower = message.lowercased()
        let tokens = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if lower.contains("sign in") || lower.contains("signed out") || lower.contains("login")
            || lower.contains("logged out") || lower.contains("not authenticated")
            || lower.contains("unauthenticated") || lower.contains("unauthorized")
            || lower.contains("authentication") || lower.contains("credential")
            || tokens.contains("auth") || tokens.contains("oauth") {
            return .needsSignIn
        }
        if lower.contains("unknown command") || lower.contains("unknown option")
            || lower.contains("unrecognized") || lower.contains("unsupported") {
            return .outdated
        }
        return .unreachable
    }

    /// A cancellable, short-lived `agy` invocation; pause/disable cancels it too.
    final class Request {
        private let lock = NSLock()
        private var cancelled = false
        private var activeCancellation: BoundedProcessCancellation?

        func cancel() {
            let active = lock.withLock { () -> BoundedProcessCancellation? in
                cancelled = true
                return activeCancellation
            }
            active?.cancel()
        }

        private var isCancelled: Bool { lock.withLock { cancelled } }

        func run(_ executable: URL, home: URL,
                 environment: [String: String]? = nil,
                 timeout: TimeInterval = AgentAntigravityServer.timeout,
                 versionTimeout: TimeInterval = AgentAntigravityServer.versionTimeout,
                 now: @escaping () -> Date = Date.init) -> Result<AgentLimits, Failure> {
            guard !isCancelled else { return .failure(.unreachable) }
            let env = AgentAntigravityServer.environment(environment ?? ProcessInfo.processInfo.environment,
                                                         executable: executable, home: home)
            guard let version = exec(executable.path, ["--version"], timeout: versionTimeout,
                                     maxOutputBytes: 4096, environment: env),
                  !isCancelled else { return .failure(.unreachable) }
            guard !version.timedOut, version.status == 0 else { return .failure(.unreachable) }
            guard AgentAntigravityServer.supportsUsageCommand(version.output) else { return .failure(.outdated) }

            guard let result = exec(executable.path,
                                    ["-p", "/usage", "--output-format", "json",
                                     "--print-timeout", AgentAntigravityServer.printTimeout],
                                    timeout: timeout,
                                    maxOutputBytes: AgentAntigravityServer.maxOutputBytes,
                                    environment: env),
                  !isCancelled, !result.timedOut else { return .failure(.unreachable) }
            return AgentAntigravityServer.parseUsageResult(result.output, status: result.status, observed: now())
        }

        private func exec(_ path: String, _ arguments: [String], timeout: TimeInterval,
                          maxOutputBytes: Int, environment: [String: String]) -> BoundedProcessRunner.Result? {
            let token = BoundedProcessCancellation()
            let accepted = lock.withLock { () -> Bool in
                guard !cancelled else { return false }
                activeCancellation = token
                return true
            }
            guard accepted else { return nil }
            defer { lock.withLock { if activeCancellation === token { activeCancellation = nil } } }
            return BoundedProcessRunner.run(path, arguments, timeout: timeout, maxOutputBytes: maxOutputBytes,
                                            environment: environment, cancellation: token)
        }
    }
}
