// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Where Codex keeps its login and how to read what is inside. The login is
/// one file, `auth.json`, kept as the bytes Codex wrote.
enum CodexLogin {
    static func authURL(home: URL) -> URL {
        home.appending(path: ".codex/auth.json", directoryHint: .notDirectory)
    }

    struct Identity: Equatable {
        let id: AgentAccount.ID
        let email: String
        /// The plan, which is all Codex says about where the account sits.
        let plan: String
    }

    /// Whose login an `auth.json` is, from the id token inside it. Nil for a
    /// file without one, such as an API key's.
    static func identity(_ auth: Data) -> Identity? {
        guard let tokens = object(auth)?["tokens"] as? [String: Any],
              let claims = (tokens["id_token"] as? String).flatMap(Self.claims) else { return nil }
        let account = claims["https://api.openai.com/auth"] as? [String: Any]
        guard let id = account?["chatgpt_account_id"] as? String ?? tokens["account_id"] as? String, !id.isEmpty
        else { return nil }
        return Identity(id: id, email: claims["email"] as? String ?? "",
                        plan: account?["chatgpt_plan_type"] as? String ?? "")
    }

    /// The claims of a token, unverified: they only say whose login this is,
    /// and Codex's servers are the ones that check it.
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var text = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        return Data(base64Encoded: text).flatMap(object)
    }

    /// True for a file that signs in with something other than a plan.
    static func isUnsupported(_ auth: Data) -> Bool {
        guard let json = object(auth) else { return false }
        if let mode = json["auth_mode"] as? String, mode != "chatgpt" { return true }
        return json["tokens"] as? [String: Any] == nil && json["OPENAI_API_KEY"] as? String != nil
    }

    // MARK: Limits

    /// Asks Codex's own server for a login's limits. `codexHome` is the
    /// folder holding that login's `auth.json`; nil asks for the live one.
    /// Codex refreshes the tokens itself and writes them back to that file.
    static func limits(_ executable: URL, codexHome: URL?, searchPath: String? = nil,
                       base: [String: String] = ProcessInfo.processInfo.environment,
                       now: Date = Date()) -> Result<AgentLimits, AgentCodexServer.Failure> {
        var environment = AgentCodexServer.environment(for: executable, searchPath: searchPath, base: base)
        // Without it Codex reads `~/.codex`, where the live login is.
        environment["CODEX_HOME"] = codexHome?.path
        guard let conversation = AgentCodexConversation(executable, environment: environment,
                                                        timeout: AgentCodexServer.checkTimeout) else {
            return .failure(.unreachable)
        }
        defer { conversation.end() }
        return conversation.start()
            .flatMap { _ in conversation.ask("account/read") }
            .flatMap { account -> Result<[String: Any], AgentCodexServer.Failure> in
                if let failure = AgentCodexServer.signInFailure(account) { return .failure(failure) }
                return conversation.ask("account/rateLimits/read")
            }
            .flatMap { answer -> Result<AgentLimits, AgentCodexServer.Failure> in
                guard let limits = AgentCodexServer.limits(answer, observed: now) else { return .failure(.unreachable) }
                return .success(limits)
            }
    }

    // MARK: Processes

    /// How many Codex processes run, without the servers this app started.
    static func runningProcesses() -> Int {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return 0 }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return 0 }
        let own = getpid()
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return pids.prefix(Int(filled)).reduce(0) { total, pid in
            guard pid > 0, proc_pidpath(pid, &path, UInt32(path.count)) > 0, isCodex(String(cString: path)) else { return total }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, pid_t(info.pbi_ppid) == own { return total }
            return total + 1
        }
    }

    /// The tool itself, by the name of its executable. Installed with npm it
    /// is started by a `node` script, which is not counted a second time.
    static func isCodex(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name == "codex" || name.hasPrefix("codex-aarch64-") || name.hasPrefix("codex-x86_64-")
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Codex's login on this Mac. No lock is known for `auth.json`, so a swap
/// replaces the file in one rename. Whether a running Codex reads it again
/// is not known either; the island says its sessions may need a restart.
struct CodexLoginAdapter: AgentLoginAdapter {
    let provider = AgentProvider.codex
    let home: URL
    /// Each saved login's folder is the `CODEX_HOME` its limits are read in.
    let copies: CodexCredentialCopies
    /// Asks Codex for the limits of the login in a folder, or of the live
    /// one for nil. Tests answer in its place.
    var limits: (_ codexHome: URL?) -> Result<AgentLimits, AgentCodexServer.Failure>
    var processes: () -> Int = CodexLogin.runningProcesses

    func readLive() throws -> AgentLiveLogin? {
        let url = CodexLogin.authURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let auth = try? Data(contentsOf: url) else { throw AgentLoginError.unreadable("auth.json could not be read") }
        if CodexLogin.isUnsupported(auth) { throw AgentLoginError.unsupported }
        guard let who = CodexLogin.identity(auth) else { return nil }
        return AgentLiveLogin(id: who.id, provider: .codex, email: who.email, organization: who.plan,
                              identity: Data(), credential: auth)
    }

    func withLocks<T>(_ body: () throws -> T) throws -> T { try body() }

    func activate(_ credential: Data, identity: Data) throws {
        guard CodexLogin.identity(credential) != nil else {
            throw AgentLoginError.unreadable("the saved login is not a Codex login")
        }
        try AgentLoginFiles.write(credential, to: CodexLogin.authURL(home: home))
    }

    func fetchUsage(_ account: AgentAccount, credential: Data,
                    isActive: Bool) -> (limits: Result<AgentLimits, AgentUsageFailure>, rotated: Data?) {
        let answer: Result<AgentLimits, AgentCodexServer.Failure>
        let after: Data?
        if isActive, (try? readLive())?.id == account.id {
            // In its usual home, so a refresh lands in the file Codex uses.
            answer = limits(nil)
            after = try? Data(contentsOf: CodexLogin.authURL(home: home))
        } else {
            guard let folder = copies.home(for: account.id) else {
                return (.failure(.unavailable("the login's id is not a name")), nil)
            }
            answer = limits(folder)
            after = try? copies.read(account.id)
        }
        // Codex wrote new tokens beside its answer; the old ones are spent.
        let rotated = after.flatMap { $0 != credential && CodexLogin.identity($0)?.id == account.id ? $0 : nil }
        return (answer.mapError(Self.failure), rotated)
    }

    func runningSessions() -> Int { processes() }

    private static func failure(_ failure: AgentCodexServer.Failure) -> AgentUsageFailure {
        switch failure {
        case .missing: return .toolMissing
        case .needsSignIn: return .needsLogin
        case .outdated, .unreachable, .refused: return .unavailable("codex: \(failure)")
        }
    }
}
