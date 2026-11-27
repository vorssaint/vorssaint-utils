// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

@MainActor
enum LidLogoWorkingCueTests {
    static func run(_ suite: TestSuite) {
        preferences(suite)
        let now = Date()
        let silenceLimit = NotchAgentSupport.idleTurn
        let old = session(.codex, last: now.addingTimeInterval(-silenceLimit))
        let codex = session(.codex, last: now.addingTimeInterval(-5))
        let claude = session(.claude, last: now)
        suite.expect(LidLogoWorkingCue.expiration(for: [old, claude], enabledProviders: [.codex], now: now) == nil,
                     "disabled providers and stale sessions do not keep the logo breathing")
        suite.expect(LidLogoWorkingCue.expiration(for: [codex, claude], enabledProviders: [.codex, .claude], now: now)
                        == now.addingTimeInterval(silenceLimit),
                     "the newest activity keeps the logo breathing as long as any enabled agent is working")
        suite.expect(LidLogoWorkingCue.expiration(for: [codex], enabledProviders: [.codex, .claude], now: now)
                        == codex.lastActivity.addingTimeInterval(silenceLimit),
                     "the logo can continue when one of two working agents finishes")

        var attempts = 0
        var stops = 0
        var result = LidLogoWorkingCue.StartResult.busy
        let cue = LidLogoWorkingCue(startBreath: {
            attempts += 1
            return result
        }, stopBreath: { stops += 1 }, startupDelay: 0.05, cycleDuration: 0.3,
           busyRetryDelay: 0.05, unavailableRetryDelay: 0.45)
        let active = Date().addingTimeInterval(10)
        cue.update(expires: active)
        suite.expect(attempts == 0, "an active turn does not immediately start a breath")
        cue.update(expires: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        suite.expect(attempts == 0, "a turn that finishes during startup causes no fade")
        stops = 0

        cue.update(expires: active)
        suite.expect(waitUntil { attempts == 1 }, "an active turn attempts a breath after startup")
        result = .started
        suite.expect(waitUntil { attempts == 2 }, "breathing resumes when completion releases the controller")
        cue.update(expires: Date().addingTimeInterval(0.04))
        suite.expect(waitUntil { stops == 1 } && attempts == 2,
                     "activity expiring mid-cycle immediately stops the working breath")
        RunLoop.current.run(until: Date().addingTimeInterval(0.34))
        suite.expect(attempts == 2 && stops == 1, "expired work leaves no repeating animation")

        result = .unavailable
        cue.update(expires: active)
        suite.expect(waitUntil { attempts == 3 }, "working activity checks for a usable logo")
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        suite.expect(attempts == 3, "an unavailable logo uses a longer retry interval")
        result = .started
        suite.expect(waitUntil { attempts == 4 }, "the longer retry resumes the cue when hardware becomes usable")
        cue.stop()
    }

    private static func preferences(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.working-lid-cue." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        defaults.set(true, forKey: AppFeature.notchAgents.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(!NotchAgentSupport.breathesLidLogo(in: defaults)
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsBreatheLidLogo] as? Bool == false,
                     "working lid breathing is opt-in")
        defaults.set(true, forKey: DefaultsKey.notchAgentsBreatheLidLogo)
        defaults.set(false, forKey: DefaultsKey.notchAgentsFinishAlert)
        defaults.set(false, forKey: DefaultsKey.notchAgentsLiveActivity)
        suite.expect(NotchAgentSupport.breathesLidLogo(in: defaults)
                        && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsBreatheLidLogo),
                     "working lid breathing is independent of alerts and the strip and is portable")
        defaults.set(false, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(!NotchAgentSupport.breathesLidLogo(in: defaults),
                     "disabling Agents disables working lid breathing")
    }

    private static func session(_ provider: AgentProvider, last: Date) -> AgentLiveSession {
        AgentLiveSession(id: provider.rawValue, provider: provider, started: last, lastActivity: last,
                         model: "", project: "", tokens: AgentTokens(), cost: 0)
    }

    private static func waitUntil(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return predicate()
    }
}
