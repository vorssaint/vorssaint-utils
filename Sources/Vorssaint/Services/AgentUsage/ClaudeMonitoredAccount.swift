// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A named, existing Claude login. The first supplies the resting island's
/// limits and alerts; all accounts contribute usage and have their own cards.
struct ClaudeMonitoredAccount: Codable, Equatable, Identifiable {
    static let maximum = 8
    var directory: String
    var name: String = ""
    var id: String { directory }
    var profile: ClaudeAccountProfile { ClaudeAccountProfile(directory: directory) }

    func label(defaultName: String) -> String {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? profile.name(defaultName: defaultName) : label
    }

    enum FolderIssue: Equatable { case duplicate, invalid }

    /// Discovery and validation may touch slow home directories or volumes.
    static func adding(_ profiles: @escaping () -> [ClaudeAccountProfile], to accounts: [Self], home: URL,
                       ignoringKnown: Bool = false,
                       completion: @escaping ((accounts: [Self], issue: FolderIssue?)) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var profiles = profiles()
            if ignoringKnown {
                var known = Set(accounts.map { $0.profile.configurationURL(home: home).resolvingSymlinksInPath().path })
                profiles = profiles.filter { known.insert($0.configurationURL(home: home).resolvingSymlinksInPath().path).inserted }
            }
            let result = adding(profiles, to: accounts, home: home)
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func adding(_ profiles: [ClaudeAccountProfile], to accounts: [Self], home: URL)
        -> (accounts: [Self], issue: FolderIssue?) {
        var updated = accounts
        var paths = Set(accounts.map { $0.profile.configurationURL(home: home).resolvingSymlinksInPath().path })
        var issue: FolderIssue?
        for var profile in profiles {
            let folder = profile.configurationURL(home: home)
            let path = folder.resolvingSymlinksInPath().path
            if paths.contains(path) {
                if issue == nil { issue = .duplicate }
                continue
            }
            if folder.standardizedFileURL == home.appending(path: ".claude", directoryHint: .isDirectory).standardizedFileURL,
               !FileManager.default.fileExists(atPath: profile.profileURL(home: home).path) {
                profile = ClaudeAccountProfile()
            }
            guard profile.isAvailable(home: home), updated.count < maximum else { issue = .invalid; continue }
            paths.insert(path)
            updated.append(Self(directory: profile.directory))
        }
        return (updated, issue)
    }

    /// The legacy config location belongs to the default login only when
    /// it has no profile of its own. Removing an explicit account must not
    /// quietly move that account's history back into the default card.
    func logURLs(home: URL) -> [URL] {
        profile.logURLs(home: home).filter { url in
            !profile.isDefault || url.deletingLastPathComponent() == profile.configurationURL(home: home)
                || !FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appending(path: ".claude.json").path)
        }
    }

    /// Only history owned by this account, after earlier accounts claim theirs.
    func logURLs(home: URL, scopes: [String: String]) -> [URL] {
        let scope = AgentLogRoot.canonical(profile.configurationURL(home: home)).path
        return logURLs(home: home).filter { scopes[AgentLogRoot.canonical($0).path + "/"] == scope }
    }

    /// Earlier subtrees stay with their owner when this account owns an ancestor.
    func excludedLogURLs(home: URL, scopes: [String: String]) -> [URL] {
        let scope = AgentLogRoot.canonical(profile.configurationURL(home: home)).path
        let roots = logURLs(home: home, scopes: scopes).map { AgentLogRoot.canonical($0).path + "/" }
        return scopes.filter { entry in entry.value != scope && roots.contains { entry.key.hasPrefix($0) } }
            .keys.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func logRoot(for path: String, scopes: [String: String]) -> String? {
        guard let root = scopes.keys.filter({ path.hasPrefix($0) }).max(by: { $0.count < $1.count }) else { return nil }
        return scopes[root]
    }

    /// Response namespaces use only source roots, independent of login order.
    /// Default and legacy history share ids; a nested account remains distinct
    /// from its ancestor's other projects, even when ids happen to coincide.
    static func recordScopes(_ accounts: [Self], home: URL) -> [String: String] {
        var scopes: [String: String] = [:]
        for account in accounts {
            let roots = account.logURLs(home: home).map { AgentLogRoot.canonical($0).path + "/" }
            let shared = Set(roots.compactMap { scopes[$0] })
            let group = Set(roots).union(scopes.keys.filter { shared.contains(scopes[$0]!) })
            guard let source = group.sorted().first else { continue }
            for root in group { scopes[root] = source }
        }
        return scopes
    }

    static func logScopes(_ accounts: [Self], home: URL) -> [String: String] {
        var scopes: [String: String] = [:]
        for account in accounts {
            let scope = AgentLogRoot.canonical(account.profile.configurationURL(home: home)).path
            for url in account.logURLs(home: home) {
                let root = AgentLogRoot.canonical(url).path + "/"
                // Keep a later ancestor to discover its other project folders.
                // An earlier ancestor already covers a later subtree in full.
                guard !scopes.keys.contains(where: { root.hasPrefix($0) }) else { continue }
                scopes[root] = scope
            }
        }
        return scopes
    }

    static func decode(_ value: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Self] {
        guard value.utf8.count <= 64 * 1024,
              let decoded = try? JSONDecoder().decode([Self].self, from: Data(value.utf8)) else { return [] }
        var paths = Set<String>()
        return Array(decoded.filter { account in
            guard (account.directory.isEmpty || account.directory.hasPrefix("/")), account.directory.utf8.count <= 4_096,
                  account.name.count <= 40, !account.directory.contains("\0") else { return false }
            return paths.insert(account.profile.configurationURL(home: home).resolvingSymlinksInPath().path).inserted
        }.prefix(maximum))
    }

    static func encode(_ accounts: [Self]) -> String {
        (try? JSONEncoder().encode(accounts)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func configured(in defaults: UserDefaults = .standard) -> [Self] {
        let accounts = decode(defaults.string(forKey: DefaultsKey.notchAgentsClaudeAccounts) ?? "")
        // Migrate the previous selector without changing which account runs.
        return accounts.isEmpty ? [Self(directory: ClaudeAccountProfile.selected(in: defaults).directory)] : accounts
    }
}
