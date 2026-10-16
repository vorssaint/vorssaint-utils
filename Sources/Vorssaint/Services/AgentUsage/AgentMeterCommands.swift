// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The assistant's own login command. Vorssaint starts it and then reads the
/// session that command saves.
struct AgentMeterCommand: Equatable {
    var executable: String
    var arguments: [String]
    var environment: [String: String]
    /// Set when the tool is not installed. Nothing is launched.
    var missing: String?
}

enum AgentMeterCommands {
    static func signIn(_ account: AgentAccount, home: URL, locate: (String) -> String?) -> AgentMeterCommand {
        command(account, home: home, locate: locate, loggingIn: true)
    }

    static func logOut(_ account: AgentAccount, home: URL, locate: (String) -> String?) -> AgentMeterCommand {
        command(account, home: home, locate: locate, loggingIn: false)
    }

    static func signedIn(claudeStatus: String) -> Bool {
        guard let data = claudeStatus.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["loggedIn"] as? Bool == true
    }

    static func signedIn(cursorStatus: String) -> Bool {
        let line = cursorStatus.lowercased()
        // `cursor-agent status` prints "Logged in …" or "✓ Login successful!".
        if line.contains("not logged") || line.contains("logged out") { return false }
        return line.contains("logged in") || line.contains("login successful")
    }

    private static func command(_ account: AgentAccount, home: URL, locate: (String) -> String?, loggingIn: Bool) -> AgentMeterCommand {
        switch account.provider {
        case .claude:
            let directory = account.slug.isEmpty ? home.appending(path: ".claude") : home.appending(path: ".claude-\(account.slug)")
            return make("claude", arguments: ["auth", loggingIn ? "login" : "logout"],
                        environment: account.slug.isEmpty ? [:] : ["CLAUDE_CONFIG_DIR": directory.path],
                        locate: locate, missing: "Claude")
        case .cursor:
            return make("cursor-agent", arguments: [loggingIn ? "login" : "logout"], environment: [:], locate: locate, missing: "Cursor")
        case .codex:
            let directory = account.slug.isEmpty ? home.appending(path: ".codex") : home.appending(path: ".codex-\(account.slug)")
            return make("codex", arguments: [loggingIn ? "login" : "logout"],
                        environment: account.slug.isEmpty ? [:] : ["CODEX_HOME": directory.path],
                        locate: locate, missing: "Codex")
        case .opencode, .copilot:
            return AgentMeterCommand(executable: "", arguments: [], environment: [:], missing: account.provider.displayName)
        }
    }

    private static func make(_ name: String, arguments: [String], environment: [String: String],
                             locate: (String) -> String?, missing: String) -> AgentMeterCommand {
        guard let executable = locate(name) else {
            return AgentMeterCommand(executable: "", arguments: [], environment: [:], missing: missing)
        }
        return AgentMeterCommand(executable: executable, arguments: arguments, environment: environment, missing: nil)
    }
}

enum AgentMeterLocator {
    /// GUI apps inherit a short PATH, so the login tools are also sought in
    /// the places a Terminal login would already have.
    static func locate(_ name: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let extras = [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        for directory in path.split(separator: ":").map(String.init) + extras {
            let candidate = URL(fileURLWithPath: directory).appending(path: name).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

enum AgentMeterLogin {
    static func run(_ command: AgentMeterCommand) {
        guard command.missing == nil, !command.executable.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        var environment = ProcessInfo.processInfo.environment
        command.environment.forEach { environment[$0.key] = $0.value }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// Percentages kept after a usage check. A failed check leaves the last good
/// reading and marks it stale. Logout drops it.
struct AgentMeterReading: Equatable {
    var usedPercent: Double
    var resetsAt: Date?
    var observedAt: Date
    var stale: Bool
}

/// Claude, Codex and Cursor keep their session on disk only after sign-in.
enum AgentMeterAccounts {
    static let meterProviders: Set<AgentProvider> = [.claude, .codex, .cursor]

    static func requiresSignIn(_ provider: AgentProvider) -> Bool {
        meterProviders.contains(provider)
    }

    /// OpenCode and Copilot stay visible from local logs; the meter trio needs a session.
    static func showsInUI(_ provider: AgentProvider, signedIn: Set<AgentProvider>) -> Bool {
        !requiresSignIn(provider) || signedIn.contains(provider)
    }

    static func discovered(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentAccount] {
        var result: [AgentAccount] = []
        for root in AgentLogRoot.all(home: home) where meterProviders.contains(root.provider) {
            if !root.account.slug.isEmpty && !root.exists { continue }
            if result.contains(where: { $0.id == root.account.id }) { continue }
            result.append(root.account)
        }
        return result
    }

    /// Accounts to check: every discovered folder plus the default account for each meter provider.
    static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentAccount] {
        var result = discovered(home: home)
        for provider in meterProviders {
            let primary = AgentAccount(provider: provider)
            if !result.contains(where: { $0.id == primary.id }) { result.append(primary) }
        }
        return result
    }

    static func refresh(enabled: Set<AgentProvider>, home: URL = FileManager.default.homeDirectoryForCurrentUser)
        -> (signedIn: Set<AgentProvider>, needSignIn: [AgentAccount]) {
        var signedIn = Set<AgentProvider>()
        var needSignIn: [AgentAccount] = []
        var status: [String: Bool?] = [:]
        for account in candidates(home: home) where enabled.contains(account.provider) {
            status[account.id] = AgentMeterStatus.isSignedIn(account, home: home)
        }
        for account in candidates(home: home) where enabled.contains(account.provider) {
            guard requiresSignIn(account.provider) else { continue }
            if status[account.id] == true { signedIn.insert(account.provider) }
        }
        for account in candidates(home: home) where enabled.contains(account.provider) {
            guard requiresSignIn(account.provider), !signedIn.contains(account.provider) else { continue }
            guard status[account.id] == false else { continue }
            if !needSignIn.contains(where: { $0.id == account.id }) { needSignIn.append(account) }
        }
        for provider in meterProviders where enabled.contains(provider) && !signedIn.contains(provider) {
            guard !needSignIn.contains(where: { $0.provider == provider }) else { continue }
            let primary = AgentAccount(provider: provider)
            if status[primary.id] == false { needSignIn.append(primary) }
        }
        return (signedIn, needSignIn)
    }

    static func signIn(_ account: AgentAccount, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let command = AgentMeterCommands.signIn(account, home: home, locate: { AgentMeterLocator.locate($0, home: home) })
        AgentMeterLogin.run(command)
    }
}

enum AgentMeterQuota {
    static func reduce(previous: AgentMeterReading?, incoming: AgentMeterReading?, signedIn: Bool) -> AgentMeterReading? {
        guard signedIn else { return nil }
        guard let incoming else {
            guard var previous else { return nil }
            previous.stale = true
            return previous
        }
        var next = incoming
        next.stale = false
        return next
    }

    /// The window nearest a full plan, which is the number a ring draws.
    static func headline(_ windows: [AgentLimitWindow]) -> AgentLimitWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }
}

enum AgentMeterStatus {
    /// True when the assistant's own session is present, false when it is not,
    /// nil when the tool itself is not installed.
    static func isSignedIn(_ account: AgentAccount, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool? {
        let login = AgentMeterCommands.signIn(account, home: home, locate: { AgentMeterLocator.locate($0, home: home) })
        if login.missing != nil { return nil }
        switch account.provider {
        case .codex:
            let directory = account.slug.isEmpty ? home.appending(path: ".codex") : home.appending(path: ".codex-\(account.slug)")
            return FileManager.default.fileExists(atPath: directory.appending(path: "auth.json").path)
        case .claude:
            return AgentMeterCommands.signedIn(claudeStatus: capture(login.executable, ["auth", "status"], login.environment))
        case .cursor:
            return AgentMeterCommands.signedIn(cursorStatus: capture(login.executable, ["status"], [:]))
        case .opencode, .copilot:
            return false
        }
    }

    private static func capture(_ executable: String, _ arguments: [String], _ extra: [String: String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        extra.forEach { environment[$0] = $1 }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

enum AgentMeterAttention {
    /// Ids that newly crossed 80 or 100. An id already fired stays quiet until
    /// its reset time has passed. `announce` is false for the first reading.
    static func crossings(previous: [String: Double], current: [String: Double], resets: [String: Date],
                          fired: Set<String>, now: Date, announce: Bool) -> Set<String> {
        guard announce else { return [] }
        var hits = Set<String>()
        for (id, used) in current {
            let before = previous[id] ?? 0
            for threshold in [80.0, 100.0] where before < threshold && used >= threshold {
                let key = "\(id)@\(Int(threshold))"
                if let reset = resets[id], reset <= now { hits.insert(key); continue }
                if !fired.contains(key) { hits.insert(key) }
            }
        }
        return hits
    }
}
