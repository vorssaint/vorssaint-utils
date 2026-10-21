// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// A Codex home of its own, a `CODEX_HOME`, whose account gets a limits card.
struct CodexAccountProfile: Codable, Equatable, Identifiable {
    static let maximum = 8

    let id: String
    var name: String
    let directory: String

    static func decode(_ value: String) -> [Self] {
        guard value.utf8.count <= 64 * 1024,
              let decoded = try? JSONDecoder().decode([Self].self, from: Data(value.utf8)) else { return [] }
        var ids = Set<String>(), paths = Set<String>()
        return decoded.prefix(maximum).filter {
            UUID(uuidString: $0.id) != nil && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name.count <= 40 && $0.directory.hasPrefix("/")
                && ids.insert($0.id).inserted
                && paths.insert(URL(fileURLWithPath: $0.directory).resolvingSymlinksInPath().path).inserted
        }
    }

    static func encode(_ profiles: [Self]) -> String {
        (try? JSONEncoder().encode(profiles)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Only metadata is looked at: Codex, not Vorssaint, opens the sign-in.
    /// A home with only a config is valid too, since Codex can keep its
    /// sign-in in the Keychain.
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
            // A symbolic or hard link would make two homes one account.
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

    /// `~/.codex` and the `~/.codex-<name>` homes beside it. The usual one is
    /// named `defaultName`, so it can have a card beside the others.
    static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser, defaultName: String) -> [Self] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        var paths = Set<String>()
        return folders.filter { $0.lastPathComponent == ".codex" || $0.lastPathComponent.hasPrefix(".codex-") }
            .sorted { $0.path < $1.path }.compactMap { folder in
                let profile = Self(id: UUID().uuidString, name: name(for: folder, defaultName: defaultName),
                                   directory: folder.path)
                guard let canonical = profile.canonicalDirectory, paths.insert(canonical.path).inserted else { return nil }
                return Self(id: profile.id, name: profile.name, directory: canonical.path)
            }
    }

    /// `.codex-work` is Work; the usual `.codex` takes `defaultName`.
    static func name(for folder: URL, defaultName: String) -> String {
        let folder = folder.lastPathComponent
        let name = folder.hasPrefix(".codex-") ? String(folder.dropFirst(".codex-".count))
            : String(folder.drop { $0 == "." })
        return name.isEmpty || folder == ".codex" ? defaultName : String(name.capitalized.prefix(40))
    }
}

/// What stopped an account check.
enum CodexAccountUsageError: Error, Equatable {
    /// The folder is no longer a private Codex home.
    case invalidProfile
    /// Neither the Codex app nor its command-line tool is on this Mac.
    case missingCLI
    /// Signed out, or signed in with a key, which has no plan limits.
    case needsSignIn
    /// A Codex from before its limits could be read from outside it.
    case outdated
    /// No usable answer: it stopped, ran out of time or refused.
    case unavailable
    /// The page closed for good, the Mac locked or Codex was turned off.
    case cancelled
}

struct CodexAccountReading: Equatable {
    let limits: AgentLimits
    let plan: String?
}

/// Asks the account behind one Codex home for its plan and limits through
/// the same server and tool as the Resets card.
enum CodexAccountUsageReader {
    /// A reading this recent still stands.
    static let refreshInterval: TimeInterval = 5 * 60
    /// After a window renews, the next reading comes sooner.
    static let renewedInterval: TimeInterval = 60
    static let retryAfter: TimeInterval = 5 * 60
    /// Only the person can install, update or sign in to Codex, or fix a folder.
    static let settledRetry: TimeInterval = 30 * 60

    /// How long after the last check the account is asked again.
    static func interval(after failure: CodexAccountUsageError?, renewed: Bool) -> TimeInterval {
        switch failure {
        case nil: return renewed ? renewedInterval : refreshInterval
        case .unavailable?, .cancelled?: return retryAfter
        case .invalidProfile?, .missingCLI?, .needsSignIn?, .outdated?: return settledRetry
        }
    }

    static func environment(directory: URL, executable: URL, searchPath: String?,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        // Neither a sign-in, a provider nor a shared state folder Vorssaint
        // was opened with may point a check at another account.
        let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                       "http_proxy", "https_proxy", "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR",
                       "NODE_EXTRA_CA_CERTS", "DO_NOT_TRACK", "DISABLE_TELEMETRY"]
        var result = AgentCodexServer.environment(for: executable, searchPath: searchPath,
                                                  base: base.filter { allowed.contains($0.key) })
        result["CODEX_HOME"] = directory.path
        result["LANG"] = "en_US.UTF-8"
        return result
    }

    /// Asks only for the account and its limits, never refreshing its
    /// sign-in on purpose and never using a reset. A Codex from before resets
    /// still reports limits, so none are required.
    static func read(_ profile: CodexAccountProfile, executable: URL, searchPath: String?,
                     cancellation: BoundedProcessCancellation,
                     timeout: TimeInterval = AgentCodexServer.checkTimeout) -> Result<CodexAccountReading, CodexAccountUsageError> {
        guard let directory = profile.canonicalDirectory else { return .failure(.invalidProfile) }
        guard !cancellation.isCancelled,
              let conversation = AgentCodexConversation(executable,
                  environment: environment(directory: directory, executable: executable, searchPath: searchPath),
                  timeout: timeout, cancellation: cancellation)
        else { return .failure(cancellation.isCancelled ? .cancelled : .unavailable) }
        defer { conversation.end() }
        let reading = conversation.start()
            .flatMap { _ in conversation.ask("account/read", ["refreshToken": false]) }
            .mapError(failure)
            .flatMap { account -> Result<CodexAccountReading, CodexAccountUsageError> in
                if AgentCodexServer.signInFailure(account) != nil { return .failure(.needsSignIn) }
                return conversation.ask("account/rateLimits/read").mapError(failure).flatMap { result in
                    guard let limits = AgentCodexServer.limits(result, observed: Date()) else { return .failure(.unavailable) }
                    return .success(CodexAccountReading(limits: limits, plan: plan(account)))
                }
            }
        return cancellation.isCancelled ? .failure(.cancelled) : reading
    }

    private static func failure(_ failure: AgentCodexServer.Failure) -> CodexAccountUsageError {
        switch failure {
        case .missing: return .missingCLI
        case .needsSignIn: return .needsSignIn
        case .outdated: return .outdated
        case .unreachable, .refused: return .unavailable
        }
    }

    private static func plan(_ account: [String: Any]) -> String? {
        ((account["account"] as? [String: Any])?["planType"] as? String).flatMap {
            ["free", "go", "plus", "pro", "team", "business", "enterprise", "edu"].contains($0)
                ? AgentPlans.codex(planType: $0)?.name : nil
        }
    }
}
