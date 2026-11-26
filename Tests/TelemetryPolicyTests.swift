// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TelemetryPolicyTests {
    static func run(_ suite: TestSuite) {
        let suiteName = "com.vorssaint.tests.telemetry-policy.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            suite.expect(false, "isolated defaults suite can be created")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        suite.expect(Defaults.registeredDefaults[DefaultsKey.telemetryRefused] as? Bool == false,
                     "telemetryRefused defaults to false in registeredDefaults")
        suite.expect(!SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.telemetryRefused),
                     "telemetryRefused is portable across settings backups")
        suite.expect(!TelemetryPolicy.isRefused(in: defaults),
                     "telemetry is not refused by default on a fresh defaults suite")

        // Pre-onboarding launch gating: automatic update checks must never start
        // before the user finishes first-run onboarding, giving them the first
        // screen to refuse all telemetry before any network request fires.
        suite.expect(!TelemetryPolicy.shouldStartAutomaticUpdateChecksAtLaunch(in: defaults),
                     "automatic update checks stay paused until onboarding completes")
        defaults.set(true, forKey: DefaultsKey.hasOnboarded)
        suite.expect(TelemetryPolicy.shouldStartAutomaticUpdateChecksAtLaunch(in: defaults),
                     "automatic update checks may start once onboarding completes without refusal")

        // Enable every optional lookup / background collection / learning key first.
        defaults.set(true, forKey: DefaultsKey.autoCheckUpdates)
        defaults.set(AppUpdatesSupport.CheckFrequency.daily.rawValue,
                     forKey: DefaultsKey.appUpdatesCheckFrequency)
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchLyricsEnabled)
        defaults.set(true, forKey: DefaultsKey.notchLyricsOnline)
        defaults.set(true, forKey: DefaultsKey.notchBrowserCovers)
        defaults.set(true, forKey: DefaultsKey.notchAgentsPriceUpdates)
        defaults.set("entry:1", forKey: DefaultsKey.commandBarUsage)
        defaults.set("digest:entry", forKey: DefaultsKey.commandBarQueryHabits)
        defaults.set("secret-key", forKey: DefaultsKey.commandBarQueryHabitKey)

        // Ensure notchLyrics feature is available so onlineEnabled returns true pre-refusal.
        defaults.set(true, forKey: AppFeature.notchLyrics.availabilityKey)

        suite.expect(NotchLyricsSupport.onlineEnabled(in: defaults),
                     "online lyrics lookup is enabled before telemetry refusal")
        suite.expect(NotchBrowserArtworkSupport.isEnabled(in: defaults),
                     "browser cover lookup is enabled before telemetry refusal")
        suite.expect(NotchAgentSupport.updatesPrices(in: defaults),
                     "remote AI price updates are enabled before telemetry refusal")

        // Click "I refuse all telemetry".
        TelemetryPolicy.applyRefusal(to: defaults)

        suite.expect(TelemetryPolicy.isRefused(in: defaults),
                     "applyRefusal persists telemetryRefused = true")
        suite.expect(!TelemetryPolicy.shouldStartAutomaticUpdateChecksAtLaunch(in: defaults),
                     "automatic update checks are blocked at launch after refusal")
        suite.expect(!TelemetryPolicy.allowsAutomaticUpdateChecks(in: defaults)
                     && !TelemetryPolicy.allowsBackgroundDataCollection(in: defaults)
                     && !TelemetryPolicy.allowsUsageLearning(in: defaults)
                     && !TelemetryPolicy.allowsFeedbackDiagnostics(in: defaults)
                     && !TelemetryPolicy.allowsHomebrewAnalytics(in: defaults)
                     && !TelemetryPolicy.allowsOnlineMetadataLookups(in: defaults)
                     && !TelemetryPolicy.allowsRemotePriceUpdates(in: defaults),
                     "every policy gate returns false once telemetry is refused")

        suite.expect(defaults.bool(forKey: DefaultsKey.autoCheckUpdates) == false,
                     "refusal switches autoCheckUpdates off")
        suite.expect(defaults.string(forKey: DefaultsKey.appUpdatesCheckFrequency) == AppUpdatesSupport.CheckFrequency.off.rawValue,
                     "refusal switches scheduled app update checks off")
        suite.expect(defaults.bool(forKey: DefaultsKey.notchLyricsOnline) == false
                     && defaults.bool(forKey: DefaultsKey.notchBrowserCovers) == false
                     && defaults.bool(forKey: DefaultsKey.notchAgentsPriceUpdates) == false,
                     "refusal switches online lyrics, browser covers and remote AI price updates off")
        suite.expect(defaults.object(forKey: DefaultsKey.commandBarUsage) == nil
                     && defaults.object(forKey: DefaultsKey.commandBarQueryHabits) == nil
                     && defaults.object(forKey: DefaultsKey.commandBarQueryHabitKey) == nil,
                     "refusal wipes stored Command Bar usage counts, query habits and habit key")

        // Even if individual feature flags are flipped back on while telemetryRefused is true,
        // the policy boundary still blocks them.
        defaults.set(true, forKey: DefaultsKey.notchLyricsOnline)
        defaults.set(true, forKey: DefaultsKey.notchBrowserCovers)
        defaults.set(true, forKey: DefaultsKey.notchAgentsPriceUpdates)
        suite.expect(!NotchLyricsSupport.onlineEnabled(in: defaults),
                     "telemetry refusal still blocks online lyrics even if its flag is true")
        suite.expect(!NotchBrowserArtworkSupport.isEnabled(in: defaults),
                     "telemetry refusal still blocks browser covers even if its flag is true")
        suite.expect(!NotchAgentSupport.updatesPrices(in: defaults),
                     "telemetry refusal still blocks remote price updates even if its flag is true")

        // Subprocess opt-out environments for Homebrew, Codex and Claude Code.
        let brewEnv = TelemetryPolicy.brewEnvironment(["PATH": "/usr/bin"], in: defaults)
        suite.expect(brewEnv["HOMEBREW_NO_ANALYTICS"] == "1" && brewEnv["DO_NOT_TRACK"] == "1",
                     "Homebrew environment enforces HOMEBREW_NO_ANALYTICS and DO_NOT_TRACK when refused")
        let codexExec = URL(fileURLWithPath: "/usr/local/bin/codex")
        let codexEnv = AgentCodexServer.environment(for: codexExec, searchPath: nil,
                                                    base: ["PATH": "/usr/bin"], telemetryRefused: true)
        suite.expect(codexEnv["DO_NOT_TRACK"] == "1" && codexEnv["DISABLE_TELEMETRY"] == "1",
                     "Codex environment enforces DO_NOT_TRACK and DISABLE_TELEMETRY when refused")
        let codexProfileEnv = CodexAccountUsageReader.environment(
            directory: URL(fileURLWithPath: "/tmp/codex-home"),
            executable: codexExec,
            searchPath: nil,
            base: ["HOME": "/tmp"],
            telemetryRefused: true)
        suite.expect(codexProfileEnv["DO_NOT_TRACK"] == "1" && codexProfileEnv["DISABLE_TELEMETRY"] == "1",
                     "Codex profile environment enforces DO_NOT_TRACK and DISABLE_TELEMETRY when refused")
        let claudeEnv = AgentClaudeServer.environment(["HOME": "/tmp"],
                                                      home: URL(fileURLWithPath: "/tmp/nonexistent-home"),
                                                      telemetryRefused: true)
        suite.expect(claudeEnv["DISABLE_TELEMETRY"] == "1"
                     && claudeEnv["DISABLE_ERROR_REPORTING"] == "1"
                     && claudeEnv["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] == "1"
                     && claudeEnv["DO_NOT_TRACK"] == "1",
                     "Claude Code environment enforces all telemetry opt-out variables when refused")

        // Un-refusing restores policy permission without silently re-enabling opt-ins.
        TelemetryPolicy.setRefused(false, in: defaults)
        suite.expect(!TelemetryPolicy.isRefused(in: defaults),
                     "setRefused(false) clears the refusal flag")
        suite.expect(defaults.bool(forKey: DefaultsKey.autoCheckUpdates) == false,
                     "clearing refusal does not silently re-enable autoCheckUpdates")

        // Exact English first-screen button label and non-empty translations across all 15 languages.
        suite.expect(TelemetryPolicyStrings.enUS.refuseButton == "I refuse all telemetry",
                     "English first-screen button uses the exact requested label")
        for language in AppLanguage.allCases {
            let localized = TelemetryPolicyStrings.localized(language)
            suite.expect(!localized.refuseButton.isEmpty && !localized.refusedBadge.isEmpty,
                         "telemetry strings exist for \(language.rawValue)")
        }
    }
}
