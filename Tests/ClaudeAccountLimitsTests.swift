// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClaudeAccountLimitsTests {
    static func run(_ suite: TestSuite) {
        let now = ISO8601DateFormatter().date(from: "2026-10-04T13:29:00Z")!
        let output = """
        \u{1B}[2KCurrent session
        14% 14% used
        Resets 3:30pm (Europe/Madrid)
        Current week (all models)
        61% 61% used
        Resets Oct 7 at 12am (Europe/Madrid)
        Current week (Fable)
        3% 3% used
        Resets Oct 7 at 12am (Europe/Madrid)
        What's contributing to your limits usage?
        93% of your usage came from sessions active for 8+ hours
        """
        let reading = ClaudeAccountUsageParser.limits(output, now: now)
        suite.expect(reading?.windows.first(where: { $0.kind == .session })?.usedPercent == 14
                     && reading?.windows.first(where: { $0.kind == .weekly && $0.scope == nil })?.usedPercent == 61
                     && reading?.windows.first(where: { $0.scope == "Fable" })?.usedPercent == 3,
                     "usage output keeps the session, overall week and scoped week separate from activity statistics")
        suite.expect(reading?.windows.first(where: { $0.kind == .session })?.resetsAt
                     == ISO8601DateFormatter().date(from: "2026-10-04T13:30:00Z"),
                     "account reset times honor the CLI's timezone rather than the app language")
        suite.expect(ClaudeAccountUsageParser.limits("Current session\nLoading usage data…\n" + output.components(separatedBy: "Current week")[1], now: now) == nil,
                     "incomplete output cannot invent a complete reading")
        suite.expect(ClaudeAccountUsageParser.limits(output.replacingOccurrences(of: "14% 14% used", with: "114% used"), now: now) == nil,
                     "invalid percentages fail closed instead of displaying plausible limits")
        suite.expect(ClaudeAccountUsageParser.limits(output, now: now.addingTimeInterval(120)) == nil,
                     "a just-expired session cannot roll into a fictitious reset tomorrow")
        suite.expect(ClaudeAccountUsageParser.limits(output + "\nCurrent session\nLoading usage data…", now: now) == nil,
                     "a later partial repaint cannot reuse an older account reading")
        if let reading {
            let profile = ClaudeAccountProfile(id: UUID().uuidString, name: "Personal", directory: "/nonexistent/profile")
            let state = ClaudeProfileLimitsState(profile: profile, limits: reading)
            let current = state.currentLimits(at: now.addingTimeInterval(120))
            suite.expect(current?.windows.contains(where: { $0.kind == .session }) == false
                         && current?.windows.first(where: { $0.scope == nil })?.usedPercent == 61,
                         "an expired allowance disappears without changing a still-valid weekly allowance to zero")
        }
        boundary(suite)
    }

    private static func boundary(_ suite: TestSuite) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("claude-account-contract-" + UUID().uuidString)
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: root) }
            let profiles = try ["personal", "work"].map { name -> ClaudeAccountProfile in
                let directory = root.appendingPathComponent(name)
                try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try Data("{}".utf8).write(to: directory.appendingPathComponent(".claude.json"))
                return ClaudeAccountProfile(id: UUID().uuidString, name: name.capitalized, directory: directory.path)
            }
            let cli = root.appendingPathComponent("claude")
            let script = """
            #!/bin/sh
            [ "$CLAUDE_CONFIG_DIR" = "$CLAUDE_SECURESTORAGE_CONFIG_DIR" ] || exit 1
            [ -z "${ANTHROPIC_API_KEY+x}" ] || exit 1
            case "$CLAUDE_CONFIG_DIR" in */personal) USED=14; WEEK=61; PLAN=max;; */work) USED=100; WEEK=41; PLAN=team;; *) exit 1;; esac
            if [ "$1" = auth ]; then
                printf '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"%s"}\\n' "$PLAN"
                exit 0
            fi
            /bin/stty raw -echo
            printf 'Permission Required: Accessing workspace:\\n%s\\nEnter y/n:\\n' "$PWD"
            answer="$(/bin/dd bs=1 count=2 2>/dev/null)"
            [ "$answer" = "$(printf 'y\\r')" ] || exit 1
            printf 'Current session\\n%s%% %s%% used\\n' "$USED" "$USED"
            /bin/date -u -v+1H '+Resets %I:%M%p (UTC)'
            printf 'Current week (all models)\\n%s%% %s%% used\\n' "$WEEK" "$WEEK"
            /bin/date -u -v+3d '+Resets %b %e at %I:%M%p (UTC)'
            read finish
            """
            try script.write(to: cli, atomically: true, encoding: .utf8)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
            var readings: [AgentLimits] = []
            for profile in profiles {
                let result = try ClaudeAccountUsageReader.read(profile, executable: cli,
                    workspace: root.appendingPathComponent("probe-" + profile.id), cancellation: BoundedProcessCancellation(), timeout: 5)
                readings.append(result.limits)
            }
            suite.expect(readings.map { $0.windows.first(where: { $0.kind == .session })?.usedPercent } == [14, 100]
                         && readings.map { $0.windows.first(where: { $0.kind == .weekly })?.usedPercent } == [61, 41],
                         "two real CLI conversations use separate account roots and keep their percentages distinct")
            let tiles = NotchAgentSupport.tiles(cards: [.limits], providers: [.claude, .codex], claudeProfiles: profiles)
            suite.expect(tiles.map(\.profileID) == [profiles[0].id, profiles[1].id, nil]
                         && Set(tiles.map(\.id)).count == 3 && tiles.last?.provider == .codex,
                         "the Island displays one card per Claude account while retaining the Codex card")
            let env = ClaudeAccountUsageReader.environment(directory: URL(fileURLWithPath: profiles[0].directory),
                base: ["HOME": root.path, "ANTHROPIC_API_KEY": "synthetic", "CLAUDE_CODE_OAUTH_TOKEN": "synthetic",
                       "CLAUDE_CONFIG_DIR": profiles[1].directory])
            suite.expect(env["ANTHROPIC_API_KEY"] == nil && env["CLAUDE_CODE_OAUTH_TOKEN"] == nil
                         && env["CLAUDE_CONFIG_DIR"] == profiles[0].directory
                         && env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] == profiles[0].directory,
                         "inherited credentials and the other account's route cannot override a selected profile")
            var alias = profiles[1]; alias = ClaudeAccountProfile(id: alias.id, name: alias.name, directory: profiles[0].directory)
            suite.expect(ClaudeAccountProfile.decode(ClaudeAccountProfile.encode([profiles[0], alias])).count == 1,
                         "duplicate account folders never produce two misleading cards")
            let payload: [String: Any] = [SettingsBackupSupport.formatVersionKey: 1,
                SettingsBackupSupport.settingsKey: [DefaultsKey.notchAgentsClaudeProfiles: ClaudeAccountProfile.encode(profiles)]]
            suite.expect(SettingsBackupSupport.sanitizedSettings(from: payload)?[DefaultsKey.notchAgentsClaudeProfiles] == nil,
                         "a settings import cannot authorize local account directories")
        } catch {
            suite.expect(false, "Claude account subprocess contract: \(error)")
        }
    }
}
