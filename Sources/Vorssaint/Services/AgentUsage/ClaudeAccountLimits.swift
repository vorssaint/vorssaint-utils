// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Claude Code profiles. People who use several Claude accounts on one Mac
/// give each its own `CLAUDE_CONFIG_DIR`, such as `~/.claude-work`, which
/// holds that account's sign-in (`.claude.json`), logs (`projects/`) and live
/// sessions (`sessions/`).
///
/// Once there is at least one such folder, `~/.claude` and every profile get
/// a Limits card of their own. The cards reuse the Codex account cards: each
/// profile is a `CodexAccountProfile` with `provider == .claude`, checked by
/// `CodexProfileLimitsService`. Profiles are found on disk, never saved.
enum ClaudeAccountProfile {
    /// The usual `~/.claude`, whose `.claude.json` sits in the home folder.
    static let defaultID = "claude.default"
    private static let prefix = ".claude-"

    /// The `.claude-<name>` folders in `home` that hold a `.claude.json`.
    /// Other folders with the prefix, such as a plugin's data, are left out.
    static func folders(home: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        return names.filter { name in
            name.hasPrefix(prefix) && name.count > prefix.count
                && isConfig(home.appending(path: name).appending(path: ".claude.json"))
        }.sorted()
    }

    /// Every profile, the usual one first. Empty while `~/.claude` is the
    /// only one, so a single-account setup keeps the provider's own card.
    static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                         defaultName: String) -> [CodexAccountProfile] {
        let folders = folders(home: home)
        guard !folders.isEmpty else { return [] }

        var profiles: [CodexAccountProfile] = []
        if isConfig(home.appending(path: ".claude.json")) {
            profiles.append(CodexAccountProfile(id: defaultID, name: defaultName,
                                                directory: home.appending(path: ".claude").path, provider: .claude))
        }
        for folder in folders {
            // `.claude-work` is shown as "Work".
            let suffix = String(folder.dropFirst(prefix.count))
            profiles.append(CodexAccountProfile(id: "claude." + suffix, name: String(suffix.capitalized.prefix(40)),
                                                directory: home.appending(path: folder).path, provider: .claude))
        }
        return profiles
    }

    /// The ids of the profiles the person turned off in Settings.
    static func hiddenIDs(in defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.string(forKey: DefaultsKey.notchAgentsHiddenClaudeProfiles) ?? "")
            .split(separator: ",").map(String.init))
    }

    static func setHidden(_ hidden: Bool, id: String, in defaults: UserDefaults = .standard) {
        var ids = hiddenIDs(in: defaults)
        if hidden { ids.insert(id) } else { ids.remove(id) }
        defaults.set(ids.sorted().joined(separator: ","), forKey: DefaultsKey.notchAgentsHiddenClaudeProfiles)
    }

    /// The folder that holds the profile's `.claude.json`: the home folder
    /// for the usual profile, the profile's own folder for the others.
    static func configHome(_ profile: CodexAccountProfile, home: URL) -> URL {
        profile.id == defaultID ? home : URL(fileURLWithPath: profile.directory, isDirectory: true)
    }

    /// A regular file owned by the person running Vorssaint.
    static func isConfig(_ url: URL) -> Bool {
        guard let metadata = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return metadata[.type] as? FileAttributeType == .typeRegular
            && (metadata[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
    }

    /// Asks Claude Code for the profile's limits with the same request as the
    /// provider's Limits card (`AgentClaudeServer`), with `CLAUDE_CONFIG_DIR`
    /// pointing at the profile. Claude Code refreshes its own sign-in.
    ///
    /// A check that is cancelled still runs until `AgentClaudeServer.timeout`;
    /// the service ignores its answer.
    static func read(_ profile: CodexAccountProfile, searchPath: String?,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Result<CodexAccountReading, CodexAccountUsageError> {
        guard let executable = AgentClaudeServer.executable(
            home: home, searchPath: searchPath ?? ProcessInfo.processInfo.environment["PATH"]) else { return .failure(.missingCLI) }
        let config = configHome(profile, home: home)
        guard isConfig(config.appending(path: ".claude.json")) else { return .failure(.invalidProfile) }

        var environment = AgentCodexServer.environment(for: executable, searchPath: nil)
        environment["PATH"] = AgentClaudeServer.searchPath(after: environment["PATH"] ?? "", home: home)
        if profile.id == defaultID {
            environment.removeValue(forKey: "CLAUDE_CONFIG_DIR")
        } else {
            environment["CLAUDE_CONFIG_DIR"] = config.path
        }

        switch AgentClaudeServer.Request().run(executable, home: config, environment: environment) {
        case .success(let summary): return .success(CodexAccountReading(limits: summary.limits, plan: plan(profile, home: home)?.name))
        case .failure(.missing): return .failure(.missingCLI)
        case .failure(.needsSignIn): return .failure(.needsSignIn)
        case .failure(.outdated): return .failure(.outdated)
        case .failure(.unreachable): return .failure(.unavailable)
        }
    }

    /// The plan in the profile's `.claude.json`, read as the provider card reads it.
    static func plan(_ profile: CodexAccountProfile, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AgentPlan? {
        let config = configHome(profile, home: home)
        guard let data = try? Data(contentsOf: config.appending(path: ".claude.json"), options: .mappedIfSafe),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any] else { return nil }
        return AgentPlans.claude(organizationType: account["organizationType"] as? String,
                                 rateLimitTier: account["organizationRateLimitTier"] as? String
                                    ?? account["userRateLimitTier"] as? String)
    }

    /// The plans of several profiles as one, for value against what they cost
    /// together: "Max 5× + Pro" at the sum of their known monthly prices. Nil
    /// when no plan has a known price.
    static func combined(_ plans: [AgentPlan]) -> AgentPlan? {
        let priced = plans.compactMap(\.monthlyPrice)
        guard !priced.isEmpty else { return nil }
        return AgentPlan(name: plans.map(\.name).joined(separator: " + "), monthlyPrice: priced.reduce(0, +))
    }
}
