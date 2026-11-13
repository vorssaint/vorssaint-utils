// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClaudeAccountProfileTests {
    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appending(path: "vorssaint-claude-profiles-\(UUID())")
        defer { try? manager.removeItem(at: home) }
        do {
            try manager.createDirectory(at: home, withIntermediateDirectories: true)
            let personal = ClaudeAccountProfile()
            let work = ClaudeAccountProfile(directory: home.appending(path: ".claude-work account").path)
            for (profile, name, used) in [(personal, "personal", 91), (work, "work", 12)] {
                let folder = profile.configurationURL(home: home)
                try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try saveAccount(name, to: profile.profileURL(home: home))
                try Data(String(used).utf8).write(to: folder.appending(path: "test-usage"))
                let log = folder.appending(path: "projects/project/session.jsonl")
                try manager.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
                // The same session/message ids in separate accounts must not
                // make one account's counts survive a switch to the other.
                let line = #"{"type":"assistant","timestamp":\#(Date().timeIntervalSince1970),"sessionId":"session","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":\#(used),"output_tokens":1}}}"#
                try Data((line + "\n").utf8).write(to: log)
            }
            suite.expect(personal.profileURL(home: home) == home.appending(path: ".claude.json")
                            && work.profileURL(home: home) == work.configurationURL(home: home).appending(path: ".claude.json")
                            && personal.read(home: home).identity?.email == "personal@example.invalid"
                            && work.read(home: home).identity?.email == "work@example.invalid",
                         "default and explicit Claude profiles read their own account metadata")
            let discovered = ClaudeAccountProfile.discover(home: home)
            suite.expect(discovered == [work],
                         "profile discovery preserves the work folder: \(discovered.map(\.directory)); expected \(work.directory)")
            let defaultRoots = AgentLogRoot.all(home: home)
            let workRoots = AgentLogRoot.all(home: home, claudeProfile: work)
            suite.expect(workRoots.filter { $0.provider == .claude }.map(\.url)
                            == work.logURLs(home: home).map(AgentLogRoot.canonical)
                            && workRoots.filter { $0.provider != .claude } == defaultRoots.filter { $0.provider != .claude },
                         "the selected Claude profile replaces only Claude's log roots")
            let host = AgentUsageReadTests.Host()
            host.home = home
            host.start(session: 1, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation())
            let saved = AgentUsageArchive.Contents(providers: [.claude], store: host.store.saved,
                                                   cursors: host.cursors.values.map(\.saved))
            suite.expect(host.snapshot.usage(.today).total.tokens.input == 91, "the default profile starts with its own history")
            host.start(session: 2, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation(), claudeProfile: work)
            let watchedFolder = AgentLogRoot.canonical(work.configurationURL(home: home)).path + "/"
            suite.expect(host.snapshot.usage(.today).total.tokens.input == 12 && host.store.records.count == 1
                            && host.watchedRoots.allSatisfy { $0.provider != .claude || $0.url.path.hasPrefix(watchedFolder) },
                         "switching profiles replaces history and watches: tokens \(host.snapshot.usage(.today).total.tokens.input), records \(host.store.records.count), roots \(host.watchedRoots.map { $0.url.path }), profile \(work.directory)")
            let resumed = AgentUsageArchive.resume(saved, logs: Set(host.cursors.keys), since: Date().addingTimeInterval(-86_400))
            suite.expect(resumed.store.records.isEmpty && resumed.cursors.isEmpty,
                         "a previous profile's cached history cannot enter the new profile on relaunch")
            host.start(session: 3, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation())
            suite.expect(host.snapshot.usage(.today).total.tokens.input == 91, "choosing the default account again restores its own history")

            try environment(suite, home: home, work: work)
            try conversations(suite, home: home, work: work)
            try sourceChanges(suite, home: home, work: work)
            try boundaries(suite, home: home, work: work)
        } catch { suite.expect(false, "Claude account profiles: \(error)") }
        for language in AppLanguage.allCases {
            let text = FeatureStrings.claudeAccount(language)
            suite.expect([text.title, text.defaultAccount, text.chooseFolder, text.explanation, text.invalidFolder,
                          text.unknownAccount, text.noLimits, text.signInHelp].allSatisfy { !$0.isEmpty },
                         "Claude account selection is localized in \(language.rawValue)")
        }
        let payload: [String: Any] = [SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchAgentsClaudeProfile: "/private/account"]]
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchAgentsClaudeProfile] as? String == ""
                        && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsClaudeProfile)
                        && SettingsBackupSupport.sanitizedSettings(from: payload)?[DefaultsKey.notchAgentsClaudeProfile] == nil,
                     "the default remains unchanged and account folders never travel in settings backups")
        let tiles = NotchAgentSupport.tiles(cards: [.limits], providers: [.claude, .codex], claudeAccount: "work")
        suite.expect(tiles.first?.accountID == "work" && tiles.last?.accountID == nil
                        && NotchAgentSupport.height(of: tiles) == NotchAgentSupport.accountCardHeight,
                     "a selected Claude account has room for its identity, refresh and failure state")
    }

    private static func saveAccount(_ name: String, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid": name, "emailAddress": "\(name)@example.invalid",
            "organizationUuid": "same-organization", "organizationType": "claude_max"]]).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func environment(_ suite: TestSuite, home: URL, work: ClaudeAccountProfile) throws {
        try JSONSerialization.data(withJSONObject: ["env": ["HTTPS_PROXY": "https://work-proxy.invalid",
            "DISABLE_TELEMETRY": "1", "CLAUDE_CONFIG_DIR": "/another-account", "ANTHROPIC_API_KEY": "unused-test-value"]])
            .write(to: work.configurationURL(home: home).appending(path: "settings.json"))
        let base = ["PATH": "/usr/bin:/bin", "HOME": home.path, "CLAUDE_CONFIG_DIR": "/wrong-account",
                    "CLAUDE_CONFIG_PATH": "/wrong-profile", "CLAUDE_CODE_OAUTH_TOKEN": "unused-test-value",
                    "ANTHROPIC_API_KEY": "unused-test-value", "ANTHROPIC_AUTH_TOKEN": "unused-test-value",
                    "ANTHROPIC_BASE_URL": "https://wrong.invalid", "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDECODE": "nested"]
        let selected = AgentClaudeServer.environment(base, home: home, profile: work)
        let ordinary = AgentClaudeServer.environment(base, home: home)
        suite.expect(selected["CLAUDE_CONFIG_DIR"] == work.directory && ordinary["CLAUDE_CONFIG_DIR"] == nil
                        && selected["HTTPS_PROXY"] == "https://work-proxy.invalid" && selected["DISABLE_TELEMETRY"] == "1"
                        && selected["PATH"] == base["PATH"] && selected["HOME"] == home.path,
                     "the selected login and its network settings replace inherited configuration without changing HOME")
        let overrides = ["CLAUDE_CONFIG_PATH", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
                         "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDECODE"]
        let isolated = [selected, ordinary].allSatisfy { env in overrides.allSatisfy { env[$0] == nil } }
        suite.expect(isolated, "an inherited personal token or provider cannot override either selected account")
    }

    private static func conversations(_ suite: TestSuite, home: URL, work: ClaudeAccountProfile) throws {
        let tool = home.appending(path: "test-claude")
        try Data(standIn.utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let base = ["PATH": "/usr/bin:/bin", "HOME": home.path, "CLAUDE_CONFIG_DIR": "/wrong-account"]
        let personal = try AgentClaudeServer.Request().run(tool, home: home, environment: base, timeout: 3).get()
        let selected = try AgentClaudeServer.Request().run(tool, home: home, environment: base, profile: work, timeout: 3).get()
        suite.expect(personal.identity?.account == "personal" && personal.limits.windows.first?.usedPercent == 91
                        && selected.identity?.account == "work" && selected.limits.windows.first?.usedPercent == 12,
                     "the real transport asks each profile for its own allowance without a login or model request")
        let changed = AgentClaudeServer.Request().run(tool, home: home,
            environment: base.merging(["SWITCH_ACCOUNT": "1"], uniquingKeysWith: { _, new in new }), profile: work, timeout: 3)
        suite.expect(changed == .failure(.unreachable),
                     "a delayed answer is rejected after the account changes, even inside the same organization")
        try saveAccount("work", to: work.profileURL(home: home))
        let marker = home.appending(path: "test-started")
        try FileManager.default.removeItem(at: marker)
        let missing = ClaudeAccountProfile(directory: home.appending(path: "removed-profile").path)
        let answer = AgentClaudeServer.Request().run(tool, home: home, environment: base, profile: missing, timeout: 3)
        suite.expect(answer == .failure(.needsSignIn) && !FileManager.default.fileExists(atPath: marker.path),
                     "a missing profile never starts Claude with the default account")
        let cancelled = AgentClaudeServer.Request()
        cancelled.cancel()
        suite.expect(cancelled.run(tool, home: home, environment: base, profile: work, timeout: 3) == .failure(.unreachable)
                        && !FileManager.default.fileExists(atPath: marker.path),
                     "a cancelled profile request cannot start later with a stale selection")
    }

    private static func sourceChanges(_ suite: TestSuite, home: URL, work: ClaudeAccountProfile) throws {
        let now = Date()
        let host = AgentClaudeServerTests.Host()
        host.home = home
        host.readerClaudeProfile = work
        host.readClaudePlan()
        let reading = AgentLimits(provider: .claude, windows: [AgentLimitWindow(id: "claude.fh", kind: .session,
            minutes: 300, scope: nil, usedPercent: 12, resetsAt: now.addingTimeInterval(3_600))], observedAt: now, source: .account)
        host.claudeAccountLimits = reading
        host.readClaudeApp(now: now)
        suite.expect(host.store.limits[.claude] == reading, "a selected profile displays its own account reading")
        let desktop = AgentClaudeAppUsage.historyURL(home: home)
        try FileManager.default.createDirectory(at: desktop.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 2, "samples": [["t": now.timeIntervalSince1970 * 1_000,
            "org": "same-organization", "u": ["fh": 91, "sd": 80]]]]).write(to: desktop)
        host.claudeAccountLimits = nil
        host.readClaudeApp(now: now)
        suite.expect(host.store.limits[.claude] == nil && host.claudeAppSamples.isEmpty,
                     "an unavailable work account never borrows the personal desktop reading, even in the same organization")
        host.claudeAccountLimits = reading
        host.store.setLimits(reading)
        host.previousLimits[.claude] = reading
        host.warned["claude.fh"] = (.claude, reading.windows[0])
        try saveAccount("replacement", to: work.profileURL(home: home))
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(1)],
                                              ofItemAtPath: work.profileURL(home: home).path)
        host.readClaudePlan()
        suite.expect(host.claudeIdentity?.account == "replacement" && host.store.limits[.claude] == nil
                        && host.claudeAccountLimits == nil && host.previousLimits[.claude] == nil && host.warned.isEmpty,
                     "an identity change clears the former account's allowance and alerts before accepting new readings")
    }

    private static func boundaries(_ suite: TestSuite, home: URL, work: ClaudeAccountProfile) throws {
        let manager = FileManager.default
        suite.expect(!ClaudeAccountProfile(directory: "/").isAvailable(home: home)
                        && !ClaudeAccountProfile(directory: home.path).isAvailable(home: home)
                        && !ClaudeAccountProfile(directory: "relative/profile").isAvailable(home: home),
                     "root, home and relative paths cannot become account folders")
        try manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: work.directory)
        suite.expect(!work.isAvailable(home: home) && work.read(home: home).identity == nil && work.logURLs(home: home).isEmpty,
                     "an unsafe profile yields neither account metadata nor logs")
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: work.directory)
        let saved = work.profileURL(home: home)
        try manager.removeItem(at: saved)
        try manager.createSymbolicLink(at: saved, withDestinationURL: ClaudeAccountProfile().profileURL(home: home))
        suite.expect(!work.isAvailable(home: home), "a linked default profile cannot masquerade as an independent account")
        try manager.removeItem(at: saved)
        try manager.linkItem(at: ClaudeAccountProfile().profileURL(home: home), to: saved)
        suite.expect(!work.isAvailable(home: home), "hard-linked account metadata cannot identify an independent profile")
    }

    private static let standIn = #"""
    #!/bin/sh
    [ -z "$CLAUDECODE" ] && [ "$DISABLE_AUTOUPDATER" = 1 ] || exit 2
    [ "$1" = --print ] && [ "$2" = --input-format ] && [ "$3" = stream-json ] || exit 2
    profile="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    printf started > "$HOME/test-started"
    while IFS= read -r line; do
      case "$line" in
        *'"subtype":"initialize"'*)
          printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"initialize","response":{}}}' ;;
        *'"subtype":"get_usage"'*)
          case "$line" in *'"skip_behaviors":true'*) ;; *) exit 3 ;; esac
          [ "$SWITCH_ACCOUNT" = 1 ] && printf '%s' '{"oauthAccount":{"accountUuid":"another","emailAddress":"another@example.invalid","organizationUuid":"same-organization"}}' > "$profile/.claude.json"
          used=$(cat "$profile/test-usage")
          printf '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":%s,"resets_at":"2099-10-28T15:00:00Z"}}}}}\n' "$used" ;;
        *) exit 4 ;;
      esac
    done
    """#
}
