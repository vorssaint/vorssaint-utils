// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClaudeAccountLimitsTests {
    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent("claude-accounts-" + UUID().uuidString)
        defer { try? manager.removeItem(at: home) }
        do {
            try manager.createDirectory(at: home, withIntermediateDirectories: true)
            suite.expect(ClaudeAccountProfile.discover(home: home, defaultName: "Default").isEmpty,
                         "No Claude account cards without a profile")
            try Data("{}".utf8).write(to: home.appending(path: ".claude.json"))
            suite.expect(ClaudeAccountProfile.discover(home: home, defaultName: "Default").isEmpty,
                         "The usual ~/.claude alone keeps the provider's own card")
            for name in [".claude-work", ".claude-nik"] {
                let folder = home.appending(path: name)
                try manager.createDirectory(at: folder.appending(path: "projects"), withIntermediateDirectories: true)
                try Data("{}".utf8).write(to: folder.appending(path: ".claude.json"))
            }
            // A plugin's data folder is no profile.
            try manager.createDirectory(at: home.appending(path: ".claude-mem/projects"), withIntermediateDirectories: true)

            let profiles = ClaudeAccountProfile.discover(home: home, defaultName: "Default")
            suite.expect(profiles.map(\.name) == ["Default", "Nik", "Work"], "Each Claude profile gets a named card")
            suite.expect(profiles.allSatisfy { $0.provider == .claude }, "Claude profiles are marked as Claude")
            suite.expect(ClaudeAccountProfile.configHome(profiles[0], home: home) == home
                && ClaudeAccountProfile.configHome(profiles[2], home: home).lastPathComponent == ".claude-work",
                         "The usual profile reads ~/.claude.json, others their own folder's")
            suite.expect(CodexAccountProfile.decode(CodexAccountProfile.encode(profiles)).isEmpty,
                         "Claude profiles are never restored from saved Codex homes")

            let roots = AgentLogRoot.all(home: home).filter { $0.provider == .claude }.map(\.url.lastPathComponent)
            let parents = AgentLogRoot.all(home: home).filter { $0.provider == .claude }
                .map { $0.url.deletingLastPathComponent().lastPathComponent }
            suite.expect(roots.allSatisfy { $0 == "projects" } && parents.contains(".claude-work")
                && parents.contains(".claude-nik") && !parents.contains(".claude-mem"),
                         "Spend reads every Claude profile's logs")

            let tiles = NotchAgentSupport.tiles(cards: [.limits], providers: [.claude], claudeAccounts: profiles.map(\.id))
            suite.expect(tiles.map(\.accountID) == profiles.map(\.id), "Each Claude profile has a limits card")

            // Spend is measured against what the shown accounts cost together.
            try Data(#"{"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#.utf8)
                .write(to: home.appending(path: ".claude-work/.claude.json"))
            try Data(#"{"oauthAccount":{"organizationType":"claude_pro"}}"#.utf8).write(to: home.appending(path: ".claude.json"))
            let plans = profiles.compactMap { ClaudeAccountProfile.plan($0, home: home) }
            suite.expect(plans.map(\.monthlyPrice) == [20, 100], "Each Claude profile's plan is read from its own .claude.json")
            let combined = ClaudeAccountProfile.combined(plans + [AgentPlan(name: "Team", monthlyPrice: nil)])
            suite.expect(combined?.monthlyPrice == 120 && combined?.name.contains(" + ") == true,
                         "Claude plans combine at the sum of their known prices")
            suite.expect(ClaudeAccountProfile.combined([AgentPlan(name: "Team", monthlyPrice: nil)]) == nil,
                         "Plans without a known price give no multiple")

            hiding(suite, profiles: profiles)
        } catch { suite.expect(false, "Claude account contract: \(error)") }
        strings(suite)
    }

    private static func hiding(_ suite: TestSuite, profiles: [CodexAccountProfile]) {
        let domain = "com.vorssaint.tests.claude-accounts." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: domain) else { return suite.expect(false, "Claude account defaults") }
        defer { defaults.removePersistentDomain(forName: domain) }
        let service = CodexProfileLimitsService(defaults: defaults, reader: { _, _, _ in .failure(.unavailable) },
                                                claudeProfiles: { profiles })
        service.synchronize()
        suite.expect(service.states.map(\.id) == profiles.map(\.id), "Every Claude profile shows while none is hidden")

        ClaudeAccountProfile.setHidden(true, id: ClaudeAccountProfile.defaultID, in: defaults)
        service.synchronize()
        suite.expect(service.states.map(\.id) == profiles.dropFirst().map(\.id), "A hidden Claude profile loses its card")

        ClaudeAccountProfile.setHidden(false, id: ClaudeAccountProfile.defaultID, in: defaults)
        service.synchronize()
        suite.expect(service.states.map(\.id) == profiles.map(\.id), "Turning a Claude profile back on restores its card")

        let payload: [String: Any] = [SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchAgentsHiddenClaudeProfiles: ClaudeAccountProfile.defaultID]]
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsHiddenClaudeProfiles)
                        && SettingsBackupSupport.sanitizedSettings(from: payload)?[DefaultsKey.notchAgentsHiddenClaudeProfiles] == nil,
                     "Hidden Claude profiles, folders on this Mac, stay out of settings backups")
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.claudeAccounts(language)
            suite.expect(!text.title.isEmpty && text.explanation.contains("~/.claude-work"),
                         "Claude account settings are translated for \(language.rawValue)")
        }
    }
}
