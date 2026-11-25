// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// A Claude Code configuration directory, already set up by its owner.
/// An empty path keeps Claude's usual login: explicitly setting its default
/// directory would select a different Keychain entry and .claude.json file.
struct ClaudeAccountProfile: Equatable, Identifiable {
    var directory = ""
    var id: String { directory }
    var isDefault: Bool { directory.isEmpty }

    struct Identity: Equatable {
        let account: String?
        let email: String?
        let organization: String?
    }

    struct Reading {
        var identity: Identity?
        var plan: AgentPlan?
        var usageFetched: Date?
    }

    static func selected(in defaults: UserDefaults = .standard) -> Self {
        Self(directory: defaults.string(forKey: DefaultsKey.notchAgentsClaudeProfile) ?? "")
    }

    func configurationURL(home: URL) -> URL {
        isDefault ? home.appending(path: ".claude", directoryHint: .isDirectory)
            : URL(fileURLWithPath: directory, isDirectory: true)
    }

    func profileURL(home: URL) -> URL {
        (isDefault ? home : configurationURL(home: home)).appending(path: ".claude.json")
    }

    /// Never silently fall back to the default account if a chosen folder
    /// disappears. Only metadata is inspected; credentials belong to Claude.
    func isAvailable(home: URL) -> Bool {
        guard !isDefault else { return true }
        guard directory.hasPrefix("/"), directory.utf8.count <= 4_096 else { return false }
        let folder = configurationURL(home: home)
        guard folder.path != "/", folder.resolvingSymlinksInPath() != home.resolvingSymlinksInPath(),
              let metadata = try? FileManager.default.attributesOfItem(atPath: folder.path),
              metadata[.type] as? FileAttributeType == .typeDirectory,
              (metadata[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = metadata[.posixPermissions] as? NSNumber, permissions.intValue & 0o022 == 0,
              let profile = try? FileManager.default.attributesOfItem(atPath: profileURL(home: home).path),
              profile[.type] as? FileAttributeType == .typeRegular,
              (profile[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (profile[.referenceCount] as? NSNumber)?.intValue == 1 else { return false }
        return true
    }

    func logURLs(home: URL) -> [URL] {
        guard isAvailable(home: home) else { return [] }
        let folders = isDefault ? [home.appending(path: ".claude"), home.appending(path: ".config/claude")]
            : [configurationURL(home: home)]
        return folders.map { $0.appending(path: "projects", directoryHint: .isDirectory) }
    }

    /// Only account metadata and the usage timestamp survive decoding, in
    /// memory. No email, account identifier or token enters the usage archive.
    func read(home: URL) -> Reading {
        guard isAvailable(home: home),
              let size = try? profileURL(home: home).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4 << 20,
              let data = try? Data(contentsOf: profileURL(home: home)), data.count <= 4 << 20,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return Reading() }
        let account = json["oauthAccount"] as? [String: Any]
        let identity = account.map {
            Identity(account: Self.text($0["accountUuid"]), email: Self.text($0["emailAddress"]),
                     organization: Self.text($0["organizationUuid"]))
        }
        let plan = account.flatMap {
            AgentPlans.claude(organizationType: $0["organizationType"] as? String,
                             rateLimitTier: $0["organizationRateLimitTier"] as? String ?? $0["userRateLimitTier"] as? String)
        }
        let fetched = (json["cachedUsageUtilization"] as? [String: Any])?["fetchedAtMs"] as? NSNumber
        let date = fetched.flatMap { value -> Date? in
            guard CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite, value.doubleValue > 0 else { return nil }
            return Date(timeIntervalSince1970: value.doubleValue / 1_000)
        }
        return Reading(identity: identity, plan: plan, usageFetched: date)
    }

    func name(defaultName: String) -> String {
        guard !isDefault else { return defaultName }
        let name = URL(fileURLWithPath: directory).lastPathComponent
        return String((name.hasPrefix(".claude-") ? String(name.dropFirst(8)) : name).prefix(80))
    }

    /// Common profile locations only; arbitrary folders are chosen explicitly.
    static func discover(home: URL) -> [Self] {
        // URL enumeration can resolve a symlink in the home path. Preserve
        // its spelling: Claude keys its sign-in to the config directory.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        let candidates = names.filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .map { home.appending(path: $0, directoryHint: .isDirectory) }
            + [home.appending(path: ".config/claude")]
        return candidates.sorted { $0.path < $1.path }.prefix(32).map { Self(directory: $0.path) }
            .filter { $0.isAvailable(home: home) }
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let clean = value.components(separatedBy: .controlCharacters).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(254))
    }
}
