// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

struct CodexAccountProfile: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    let directory: String

    static func decode(_ value: String) -> [Self] {
        guard value.utf8.count <= 64 * 1024,
              let decoded = try? JSONDecoder().decode([Self].self, from: Data(value.utf8)) else { return [] }
        var ids = Set<String>(), paths = Set<String>()
        return decoded.prefix(8).filter {
            UUID(uuidString: $0.id) != nil && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name.count <= 40 && $0.directory.hasPrefix("/")
                && ids.insert($0.id).inserted
                && paths.insert(URL(fileURLWithPath: $0.directory).resolvingSymlinksInPath().path).inserted
        }
    }

    static func encode(_ profiles: [Self]) -> String {
        (try? JSONEncoder().encode(profiles)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Inspect only metadata. Codex, not Vorssaint, opens the credential store.
    /// A config-only home is valid too: Codex may use its own Keychain backend.
    var canonicalDirectory: URL? {
        guard directory.hasPrefix("/") else { return nil }
        let manager = FileManager.default
        let url = URL(fileURLWithPath: directory, isDirectory: true).resolvingSymlinksInPath()
        guard url.path != "/", url != manager.homeDirectoryForCurrentUser.resolvingSymlinksInPath(),
              let root = try? manager.attributesOfItem(atPath: url.path),
              root[.type] as? FileAttributeType == .typeDirectory,
              (root[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let mode = root[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else { return nil }
        let auth = url.appendingPathComponent("auth.json")
        if let metadata = try? manager.attributesOfItem(atPath: auth.path) {
            // Symlinks and hard links would collapse two apparently distinct homes.
            guard metadata[.type] as? FileAttributeType == .typeRegular,
                  (metadata[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let permissions = metadata[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0,
                  (metadata[.referenceCount] as? NSNumber)?.intValue == 1 else { return nil }
            return url
        }
        guard let config = try? manager.attributesOfItem(atPath: url.appendingPathComponent("config.toml").path),
              config[.type] as? FileAttributeType == .typeRegular else { return nil }
        return url
    }

    static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Self] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        var paths = Set<String>()
        return folders.filter { $0.lastPathComponent == ".codex" || $0.lastPathComponent.hasPrefix(".codex-") }
            .sorted { $0.path < $1.path }.compactMap { folder in
                let suffix = String(folder.lastPathComponent.dropFirst(".codex-".count).prefix(40))
                let profile = Self(id: UUID().uuidString, name: suffix.isEmpty ? "Default" : suffix.capitalized,
                                   directory: folder.path)
                guard let canonical = profile.canonicalDirectory, paths.insert(canonical.path).inserted else { return nil }
                return Self(id: profile.id, name: profile.name, directory: canonical.path)
            }
    }
}

enum CodexAccountUsageError: Error, Equatable {
    case invalidProfile, missingCLI, unavailable, cancelled
}

enum CodexAccountUsageReader {
    static let refreshInterval: TimeInterval = 5 * 60

    static func executable(apps: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        AgentCodexServer.candidates(apps: apps, home: home).first {
            let url = $0.resolvingSymlinksInPath()
            guard ["codex", "codex.js"].contains(url.lastPathComponent),
                  FileManager.default.isExecutableFile(atPath: url.path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o022 == 0,
                  let owner = attributes[.ownerAccountID] as? NSNumber,
                  owner.uint32Value == 0 || owner.uint32Value == getuid() else { return false }
            return true
        }
    }

    static func environment(directory: URL, executable: URL,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        // Neither inherited credentials nor a shared SQLite home may retarget a check.
        let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                       "http_proxy", "https_proxy", "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR",
                       "NODE_EXTRA_CA_CERTS", "DO_NOT_TRACK", "DISABLE_TELEMETRY"]
        var result = AgentCodexServer.environment(for: executable, searchPath: nil,
                                                  base: base.filter { allowed.contains($0.key) })
        result["CODEX_HOME"] = directory.path
        result["LANG"] = "en_US.UTF-8"
        return result
    }

    /// Only status RPCs are sent. Older Codex versions can report limits even
    /// when they do not support banked resets; do not require a reset summary.
    static func read(_ profile: CodexAccountProfile, executable: URL, cancellation: BoundedProcessCancellation,
                     timeout: TimeInterval = AgentCodexServer.checkTimeout) throws -> (limits: AgentLimits, plan: String?) {
        guard let directory = profile.canonicalDirectory else { throw CodexAccountUsageError.invalidProfile }
        guard !cancellation.isCancelled else { throw CodexAccountUsageError.cancelled }
        guard let conversation = AgentCodexConversation(executable,
            environment: environment(directory: directory, executable: executable), timeout: timeout, cancellation: cancellation)
        else { throw cancellation.isCancelled ? CodexAccountUsageError.cancelled : .unavailable }
        defer { conversation.end() }
        do {
            try conversation.start().get()
            let account = try conversation.ask("account/read", ["refreshToken": false]).get()
            if let failure = AgentCodexServer.signInFailure(account) { throw failure }
            let result = try conversation.ask("account/rateLimits/read").get()
            guard let limits = AgentCodexServer.limits(result, observed: Date()) else { throw CodexAccountUsageError.unavailable }
            let plan = ((account["account"] as? [String: Any])?["planType"] as? String).flatMap {
                ["free", "go", "plus", "pro", "team", "business", "enterprise", "edu"].contains($0)
                    ? AgentPlans.codex(planType: $0)?.name : nil
            }
            guard !cancellation.isCancelled else { throw CodexAccountUsageError.cancelled }
            return (limits, plan)
        } catch {
            if cancellation.isCancelled { throw CodexAccountUsageError.cancelled }
            throw error
        }
    }
}
