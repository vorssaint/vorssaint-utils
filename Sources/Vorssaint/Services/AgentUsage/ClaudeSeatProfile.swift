// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// A Claude Code profile of its own, a `CLAUDE_CONFIG_DIR`, signed in to one
/// seat of a Claude plan. Vorssaint only asks it for the seat's limits; the
/// person signs it in with Claude Code, and nothing of the sign-in is read.
struct ClaudeSeatProfile: Codable, Equatable, Identifiable {
    static let maximum = 4
    static let prefix = ".claude-"

    let id: String
    let directory: String

    static func decode(_ value: String) -> [Self] {
        guard value.utf8.count <= 16 * 1024,
              let decoded = try? JSONDecoder().decode([Self].self, from: Data(value.utf8)) else { return [] }
        var ids = Set<String>(), paths = Set<String>()
        return decoded.prefix(maximum).filter {
            UUID(uuidString: $0.id) != nil && $0.directory.hasPrefix("/")
                && ids.insert($0.id).inserted
                && paths.insert(URL(fileURLWithPath: $0.directory).resolvingSymlinksInPath().path).inserted
        }
    }

    static func encode(_ profiles: [Self]) -> String {
        (try? JSONEncoder().encode(profiles)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    var folder: URL { URL(fileURLWithPath: directory, isDirectory: true) }
    /// Where Claude Code keeps the seat's account and saved usage.
    var profileURL: URL { folder.appending(path: ".claude.json") }

    /// A private folder of the person's, never their home or the usual
    /// `~/.claude`, whose profile is a file of its own.
    var canonicalDirectory: URL? {
        guard directory.hasPrefix("/") else { return nil }
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let url = folder.resolvingSymlinksInPath()
        guard url.path != "/", url != home, url != home.appending(path: ".claude"),
              let root = try? manager.attributesOfItem(atPath: url.path),
              root[.type] as? FileAttributeType == .typeDirectory,
              (root[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let mode = root[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0,
              let profile = try? manager.attributesOfItem(atPath: url.appending(path: ".claude.json").path),
              profile[.type] as? FileAttributeType == .typeRegular,
              (profile[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { return nil }
        return url
    }

    /// The `~/.claude-<name>` folders beside the usual profile that are
    /// signed in to an account, in name order.
    static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Self] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        var paths = Set<String>()
        return folders.filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.path < $1.path }.compactMap { folder in
                let profile = Self(id: UUID().uuidString, directory: folder.path)
                guard let canonical = profile.canonicalDirectory, paths.insert(canonical.path).inserted,
                      ClaudeSeatIdentity.read(canonical.appending(path: ".claude.json")) != nil else { return nil }
                return Self(id: profile.id, directory: canonical.path)
            }
    }

    /// What a person types in Terminal to sign a new seat in, in the next
    /// free `~/.claude-seatN`.
    static func signInCommand(existing: [Self], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let taken = Set(existing.map { URL(fileURLWithPath: $0.directory).lastPathComponent })
        let number = (1...99).first { !taken.contains(prefix + "seat\($0)")
            && !FileManager.default.fileExists(atPath: home.appending(path: prefix + "seat\($0)").path) } ?? 1
        return "CLAUDE_CONFIG_DIR=~/\(prefix)seat\(number) claude auth login"
    }

    /// The command that signs this seat in again.
    var signInCommand: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = directory.hasPrefix(home + "/") ? "~" + directory.dropFirst(home.count) : directory
        return "CLAUDE_CONFIG_DIR=\(path) claude auth login"
    }
}

/// Who a seat's profile is signed in as: the account details Claude Code
/// keeps beside its sign-in, never the sign-in itself.
struct ClaudeSeatIdentity: Equatable {
    let account: String
    let organization: String?
    let email: String
    let organizationName: String?
    let organizationType: String?
    let rateLimitTier: String?

    init(account: String, organization: String?, email: String, organizationName: String? = nil,
         organizationType: String? = nil, rateLimitTier: String? = nil) {
        self.account = account
        self.organization = organization
        self.email = email
        self.organizationName = organizationName
        self.organizationType = organizationType
        self.rateLimitTier = rateLimitTier
    }

    init?(_ profile: [String: Any]) {
        guard let account = profile["oauthAccount"] as? [String: Any],
              let id = account["accountUuid"] as? String, !id.isEmpty else { return nil }
        self.init(account: id, organization: account["organizationUuid"] as? String,
                  email: account["emailAddress"] as? String ?? "",
                  organizationName: account["organizationName"] as? String,
                  organizationType: account["organizationType"] as? String,
                  rateLimitTier: account["organizationRateLimitTier"] as? String ?? account["userRateLimitTier"] as? String)
    }

    static func read(_ url: URL) -> Self? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return Self(json)
    }

    var plan: AgentPlan? { AgentPlans.claude(organizationType: organizationType, rateLimitTier: rateLimitTier) }
}

/// What the Claude app says about its accounts: the one signed in now, and
/// which of Claude Code's sessions in the app ran under which account.
enum ClaudeAppAccounts {
    static func folder(home: URL) -> URL { home.appending(path: "Library/Application Support/Claude") }

    /// The account the Claude app is signed in to, as it last recorded it.
    static func signedIn(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        guard let data = try? Data(contentsOf: folder(home: home).appending(path: "config.json"), options: .mappedIfSafe),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = json["lastKnownAccountUuid"] as? String, !account.isEmpty else { return nil }
        return account
    }

    /// The account and organization a session's folder names, from
    /// `claude-code-sessions/<account>/<organization>/local_*.json`.
    struct Owner: Equatable, Hashable {
        let account: String
        let organization: String
    }

    /// Claude Code's session ids in the app, by the account and organization
    /// each ran under. Each folder is read again only when it changes, and
    /// only the session id is kept from its files. Safe from any thread.
    final class SessionIndex {
        static let shared = SessionIndex()

        private let lock = NSLock()
        private let root: URL
        private var folders: [String: (modified: Date?, owner: Owner, sessions: Set<String>)] = [:]
        private var owners: [String: Owner] = [:]

        init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
            root = ClaudeAppAccounts.folder(home: home).appending(path: "claude-code-sessions")
        }

        /// Reads the folders of the accounts asked for that changed; the
        /// others, older accounts' and other organizations', stay unread.
        func refresh(for wanted: Set<Owner>) {
            lock.withLock {
                let manager = FileManager.default
                var seen = Set<String>()
                for owner in wanted {
                    let folder = root.appending(path: owner.account).appending(path: owner.organization)
                    let path = folder.path
                    seen.insert(path)
                    let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let known = folders[path], known.modified == modified { continue }
                    let files = (try? manager.contentsOfDirectory(atPath: path)) ?? []
                    let sessions = Set(files.filter { $0.hasPrefix("local_") && $0.hasSuffix(".json") }.compactMap { name in
                        (try? Data(contentsOf: folder.appending(path: name), options: .mappedIfSafe))
                            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
                            .flatMap { $0["cliSessionId"] as? String }
                    })
                    folders[path] = (modified, owner, sessions)
                }
                folders = folders.filter { seen.contains($0.key) }
                owners = [:]
                for entry in folders.values { for session in entry.sessions { owners[session] = entry.owner } }
            }
        }

        /// The account and organization a Claude Code session in the app ran
        /// under, by its session id or its log's path.
        func owner(of session: String) -> Owner? {
            let id = session.hasSuffix(".jsonl")
                ? ((session as NSString).lastPathComponent as NSString).deletingPathExtension : session
            return lock.withLock { owners[id] }
        }
    }
}

/// One seat as the island shows it: who it is, its limits and how its last
/// check went, and the Claude app's work under it.
struct ClaudeSeat: Equatable, Identifiable {
    let id: String
    let directory: String
    var account: String?
    var organization: String?
    var email: String
    var plan: String?
    var limits: AgentLimits?
    var checking = false
    var failure: AgentClaudeServer.Failure?
    /// The account the Claude app is signed in to now.
    var active = false
    /// When its limits were last read, by a check or a session's saved copy.
    var checked: Date?
    /// The open session's value at API prices; nil once it has closed.
    var sessionValue: Double?
    var monthValue: Double = 0

    var signInCommand: String { ClaudeSeatProfile(id: id, directory: directory).signInCommand }
    var owner: ClaudeAppAccounts.Owner? {
        guard let account, let organization else { return nil }
        return ClaudeAppAccounts.Owner(account: account, organization: organization)
    }
}

extension AgentUsageSnapshot {
    /// The seat the Claude app is signed in to, or the first one.
    var activeClaudeSeat: ClaudeSeat? { claudeSeats.first(where: \.active) ?? claudeSeats.first }

    /// The seat a Claude-app session runs under, the active one when its own
    /// is unknown; nil for sessions outside the app and without seats.
    func claudeSeat(for session: AgentLiveSession) -> ClaudeSeat? {
        guard session.provider == .claude, session.place == .app, !claudeSeats.isEmpty else { return nil }
        return claudeLiveSeats[session.id].flatMap { id in claudeSeats.first { $0.id == id } } ?? activeClaudeSeat
    }
}
