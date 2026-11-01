// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the same account-wide data as /usage through Claude Code's structured
/// control protocol. Claude handles authentication itself, including refreshing
/// its sign-in. No user message, model request, MCP server or tool is run, and
/// no hook but those an organization manages, which our `disableAllHooks`
/// cannot turn off.
enum AgentClaudeServer {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, outdated, unreachable
    }
    struct Summary: Equatable {
        let limits: AgentLimits
        let organization: String?
    }
    static let timeout: TimeInterval = 25
    /// While the AI page is on screen a reading this old is asked again.
    static let freshness: TimeInterval = 60
    /// Otherwise Claude Code starts at most this often, as the Codex check does.
    static let backgroundFreshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 5 * 60
    /// Only the person can install, update or sign in to Claude Code.
    static let settledRetry: TimeInterval = 30 * 60
    /// Claude Code answers from the copy it saved, without asking the
    /// account, while that copy is younger than this.
    static let reuse: TimeInterval = 60
    /// The opt-outs a person may keep in Claude Code's user settings, which
    /// `--setting-sources ""` leaves out of a check.
    static let optOuts = ["DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"]
    /// The proxy and certificates a network may need, which can be kept
    /// there too.
    static let networkSettings = ["HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS"]

    /// How long after the last check Claude Code is asked again. Each check
    /// in a row without an answer doubles the wait, up to the one for what
    /// only the person can fix, so a setup that never answers, as a Claude
    /// Code too old for the check's options, is rarely started.
    static func interval(after failure: Failure?, repeated: Int = 1, pageVisible: Bool) -> TimeInterval {
        switch failure {
        case nil: return pageVisible ? freshness : backgroundFreshness
        case .unreachable?: return min(settledRetry, retryAfter * Double(1 << min(3, max(0, repeated - 1))))
        case .missing?, .needsSignIn?, .outdated?: return settledRetry
        }
    }

    /// Where Claude Code can be: where its installer, Homebrew and npm put
    /// it, along the app's PATH, then where Node version managers, Bun and
    /// pnpm keep global tools. The Claude app's own copy is left out: it has
    /// no sign-in of its own to check with.
    static func candidates(home: URL, searchPath: String? = nil) -> [URL] {
        // One list per line: Swift 6.0.3 cannot type-check them as one sum in time.
        var folders: [String] = [home.appending(path: ".local/bin").path,
                                 home.appending(path: ".claude/local").path, "/opt/homebrew/bin", "/usr/local/bin"]
        folders += (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        folders += toolFolders(home: home)
        return folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "claude") }
    }

    /// The folders that keep npm's global tools beside the Node that runs
    /// them, each manager's newest Node first, and Volta's, Bun's and pnpm's
    /// own. A Claude Code that needs Node finds it on this list too.
    static func toolFolders(home: URL) -> [String] {
        let path = { (relative: String) -> String in home.appending(path: relative).path }
        let fnm: [String] = ["Library/Application Support/fnm", ".local/share/fnm", ".fnm"].map(path)
        // One list per line, as above.
        var folders: [String] = [path(".volta/bin")]
        folders += fnm.map { $0 + "/aliases/default/bin" }
        folders += newest(in: path(".nvm/versions/node")).map { $0 + "/bin" }
        folders += fnm.flatMap { root in newest(in: root + "/node-versions").map { $0 + "/installation/bin" } }
        folders += newest(in: path(".asdf/installs/nodejs")).map { $0 + "/bin" }
        folders += newest(in: path(".local/share/mise/installs/node")).map { $0 + "/bin" }
        folders += [path(".bun/bin"), path("Library/pnpm"), path(".local/share/pnpm"), path(".npm-global/bin")]
        return folders
    }

    /// The folders in `folder` named for a version, as `v22.11.0` or
    /// `22.11.0`, newest first.
    private static func newest(in folder: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.compactMap { name -> (version: [Int], path: String)? in
            let parts = (name.hasPrefix("v") ? String(name.dropFirst()) : name).split(separator: ".").map { Int($0) }
            guard !parts.isEmpty, !parts.contains(nil) else { return nil }
            return (parts.compactMap { $0 }, folder + "/" + name)
        }
        .sorted { $1.version.lexicographicallyPrecedes($0.version) }
        .map(\.path)
    }

    /// The PATH a check gives Claude Code: `path`, the one the app gives
    /// Codex, then the version managers' folders. A Claude Code that runs on
    /// Node, as one in `~/.claude/local` does, finds one there, while the
    /// tools the system has still come from the system.
    static func searchPath(after path: String, home: URL) -> String {
        ([path] + toolFolders(home: home)).joined(separator: ":")
    }

    static func executable(home: URL, searchPath: String? = nil) -> URL? {
        candidates(home: home, searchPath: searchPath).first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func organization(home: URL) -> String? {
        profile(home: home).organization
    }

    /// The organization Claude Code signs in to, and when it last fetched
    /// the account's usage. After a failed fetch, get_usage answers from
    /// that saved copy, up to an hour old, with nothing to say so.
    static func profile(home: URL) -> (organization: String?, usageFetched: Date?) {
        guard let data = try? Data(contentsOf: home.appending(path: ".claude.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (nil, nil) }
        let organization = (json["oauthAccount"] as? [String: Any])?["organizationUuid"] as? String
        guard let number = (json["cachedUsageUtilization"] as? [String: Any])?["fetchedAtMs"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue > 0 else { return (organization, nil) }
        return (organization, Date(timeIntervalSince1970: number.doubleValue / 1_000))
    }

    /// The app's environment for a check: Claude Code never updates itself
    /// from one, and the opt-outs and the proxy the person keeps in its user
    /// settings apply as in their own sessions. Nothing else is turned off.
    static func environment(_ base: [String: String], home: URL) -> [String: String] {
        var environment = base
        environment.removeValue(forKey: "CLAUDECODE")
        environment["DISABLE_AUTOUPDATER"] = "1"
        guard let data = try? Data(contentsOf: home.appending(path: ".claude/settings.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let settings = json["env"] as? [String: Any] else { return environment }
        // Claude Code lets its settings override the environment, and reads
        // a number or a switch there as text.
        for key in optOuts + networkSettings {
            switch settings[key] {
            case let text as String: environment[key] = text
            case let number as NSNumber:
                environment[key] = CFGetTypeID(number) == CFBooleanGetTypeID()
                    ? (number.boolValue ? "true" : "false") : number.stringValue
            default: break
            }
        }
        return environment
    }

    static func limits(_ result: [String: Any], observed: Date) -> AgentLimits? {
        guard result["rate_limits_available"] as? Bool == true,
              let limits = result["rate_limits"] as? [String: Any] else { return nil }
        let windows: [AgentLimitWindow] = [
            ("five_hour", AgentLimitWindow.Kind.session, 300, nil as String?),
            ("seven_day", .weekly, 10_080, nil),
            ("seven_day_opus", .weekly, 10_080, "Opus"),
            ("seven_day_sonnet", .weekly, 10_080, "Sonnet")].compactMap { key, kind, minutes, scope in
                guard let window = limits[key] as? [String: Any],
                      let percent = window["utilization"] as? NSNumber,
                      CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite else { return nil }
                // An idle window has no renewal yet and keeps its percentage,
                // as in the Claude app's history; one that renewed before the
                // reading says nothing about the window now.
                let resets = window["resets_at"].flatMap { $0 is NSNull ? nil : $0 }
                let end = (resets as? String).flatMap(AgentTimestamp.parse)
                guard resets == nil || end.map({ $0 > observed }) == true else { return nil }
                let id = ["five_hour": "fh", "seven_day": "sd", "seven_day_opus": "so", "seven_day_sonnet": "sn"][key]!
                return AgentLimitWindow(id: "claude.\(id)", kind: kind, minutes: minutes, scope: scope,
                                        usedPercent: min(100, max(0, percent.doubleValue)), resetsAt: end)
            }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: windows, observedAt: observed, source: .account)
    }

    /// Expires each window without inventing zero usage after a reset. Remote
    /// work may already have spent part of the next window before we ask again.
    /// A window without a renewal lasts as it would in the Claude app's
    /// history: a session's length, or a day.
    static func current(_ reading: AgentLimits?, now: Date) -> AgentLimits? {
        guard var reading else { return nil }
        let age = now.timeIntervalSince(reading.observedAt)
        reading.windows.removeAll { window in
            if let resets = window.resetsAt { return resets <= now }
            return age >= (window.kind == .session ? TimeInterval(window.minutes ?? 300) * 60 : 86_400)
        }
        return reading.windows.isEmpty ? nil : reading
    }

    /// A cancellable, short-lived CLI invocation; pause/disable closes it too.
    final class Request {
        private let lock = NSLock()
        private var cancelled = false
        private var conversation: AgentCLIConversation?

        func cancel() {
            let active = lock.withLock { () -> AgentCLIConversation? in
                cancelled = true
                return conversation
            }
            active?.end()
        }

        func run(_ executable: URL, home: URL, environment: [String: String],
                 timeout: TimeInterval = AgentClaudeServer.timeout) -> Result<Summary, Failure> {
            guard !lock.withLock({ cancelled }) else { return .failure(.unreachable) }
            let started = Date()
            let organization = AgentClaudeServer.organization(home: home)
            let environment = AgentClaudeServer.environment(environment, home: home)
            let arguments = ["--print", "--input-format", "stream-json", "--output-format", "stream-json",
                "--verbose", "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config",
                "{\"mcpServers\":{}}", "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}"]
            guard let channel = AgentCLIConversation(executable, arguments: arguments,
                                                     environment: environment, timeout: timeout) else { return .failure(.unreachable) }
            let accepted = lock.withLock { () -> Bool in
                guard !cancelled else { return false }
                conversation = channel
                return true
            }
            defer {
                channel.end()
                lock.withLock { conversation = nil }
            }
            guard accepted else { return .failure(.unreachable) }
            switch ask(channel, id: "initialize", request: ["subtype": "initialize"]) {
            case .failure(let failure): return .failure(failure)
            case .success: break
            }
            return ask(channel, id: "usage", request: ["subtype": "get_usage", "skip_behaviors": true])
                .flatMap { result in
                    guard !self.lock.withLock({ self.cancelled }) else { return .failure(.unreachable) }
                    guard result["rate_limits_available"] as? Bool == true else { return .failure(.needsSignIn) }
                    // The saved copy is read once Claude Code has exited, so
                    // what it fetched for this answer is on disk.
                    channel.end()
                    channel.waitForExit(timeout: 3)
                    let saved = AgentClaudeServer.profile(home: home)
                    guard !self.lock.withLock({ self.cancelled }),
                          organization == saved.organization else { return .failure(.unreachable) }
                    // A copy saved before this check began was answered in place
                    // of the account, which was not reached.
                    if let fetched = saved.usageFetched, started.timeIntervalSince(fetched) > AgentClaudeServer.reuse {
                        return .failure(.unreachable)
                    }
                    guard let reading = AgentClaudeServer.limits(result, observed: min(Date(), saved.usageFetched ?? Date()))
                    else { return .failure(.unreachable) }
                    return .success(Summary(limits: reading, organization: organization))
                }
        }

        private func ask(_ channel: AgentCLIConversation, id: String,
                         request: [String: Any]) -> Result<[String: Any], Failure> {
            guard channel.send(["type": "control_request", "request_id": id, "request": request]) else { return .failure(.unreachable) }
            while let message = channel.next() {
                guard message["type"] as? String == "control_response",
                      let response = message["response"] as? [String: Any], response["request_id"] as? String == id else { continue }
                guard response["subtype"] as? String == "success" else {
                    let error = (response["error"] as? String ?? "").lowercased()
                    // A CLI from before the request answers "Unsupported control request subtype".
                    if error.contains("supported") || error.contains("unknown") { return .failure(.outdated) }
                    if error.contains("auth") || error.contains("login") || error.contains("sign in") { return .failure(.needsSignIn) }
                    return .failure(.unreachable)
                }
                return .success(response["response"] as? [String: Any] ?? [:])
            }
            return .failure(.unreachable)
        }
    }
}
