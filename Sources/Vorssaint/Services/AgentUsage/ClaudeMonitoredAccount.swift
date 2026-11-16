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

    /// The legacy config location belongs to the default login only when
    /// it has no profile of its own. Removing an explicit account must not
    /// quietly move that account's history back into the default card.
    func logURLs(home: URL) -> [URL] {
        profile.logURLs(home: home).filter { url in
            !profile.isDefault || url.deletingLastPathComponent() == profile.configurationURL(home: home)
                || !FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appending(path: ".claude.json").path)
        }
    }

    static func logScopes(_ accounts: [Self], home: URL) -> [String: String] {
        var scopes: [String: String] = [:]
        for account in accounts {
            let scope = AgentLogRoot.canonical(account.profile.configurationURL(home: home)).path
            for url in account.logURLs(home: home) { scopes[AgentLogRoot.canonical(url).path + "/"] = scope }
        }
        return scopes
    }

    static func decode(_ value: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Self] {
        guard value.utf8.count <= 64 * 1024,
              let decoded = try? JSONDecoder().decode([Self].self, from: Data(value.utf8)) else { return [] }
        var paths = Set<String>()
        var roots: [String] = []
        return Array(decoded.filter { account in
            guard (account.directory.isEmpty || account.directory.hasPrefix("/")), account.directory.utf8.count <= 4_096,
                  account.name.count <= 40, !account.directory.contains("\0") else { return false }
            let primary = account.profile.configurationURL(home: home).appending(path: "projects")
            let claimed = Set(([primary] + account.logURLs(home: home)).map { $0.resolvingSymlinksInPath().path })
            guard !claimed.contains(where: { path in
                roots.contains { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }
            }), paths.insert(account.profile.configurationURL(home: home).resolvingSymlinksInPath().path).inserted else { return false }
            roots.append(contentsOf: claimed)
            return true
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
