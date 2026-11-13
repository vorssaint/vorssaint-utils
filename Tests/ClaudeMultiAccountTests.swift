// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClaudeMultiAccountTests {
    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appending(path: "vorssaint-multiple-claude-\(UUID())")
        defer { try? manager.removeItem(at: home) }
        do {
            let accounts = [ClaudeMonitoredAccount(directory: "", name: "Personal"),
                            ClaudeMonitoredAccount(directory: home.appending(path: ".claude-work").path, name: "Work")]
            for (index, account) in accounts.enumerated() {
                let profile = account.profile
                let projects = profile.configurationURL(home: home).appending(path: "projects/project")
                try manager.createDirectory(at: projects, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid": account.name]])
                    .write(to: profile.profileURL(home: home))
                let log = projects.appending(path: "same-session.jsonl")
                let line = #"{"type":"assistant","timestamp":\#(Date().timeIntervalSince1970),"sessionId":"same-session","requestId":"same-request","message":{"id":"same-message","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":\#(10 + index * 10),"output_tokens":1}}}"#
                try Data((line + "\n").utf8).write(to: log)
            }
            let host = AgentUsageReadTests.Host()
            host.home = home
            host.start(session: 1, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation(),
                       claudeProfile: accounts[0].profile, claudeAccounts: accounts)
            let now = Date()
            let individual = accounts.map { host.store.claudeSnapshot(roots: $0.profile.logURLs(home: home), now: now) }
            suite.expect(host.snapshot.usage(.today).total.tokens.total == 32 && host.store.records.count == 2,
                         "simultaneous Claude profiles with identical response ids both contribute to combined usage")
            suite.expect(individual.map { $0.usage(.today).total.tokens.total } == [11, 21],
                         "account selection projects only that profile's tokens, costs, models and projects")
            let roots = AgentLogRoot.all(home: home, additionalClaudeProfiles: [accounts[1].profile, accounts[1].profile])
            suite.expect(roots.filter { $0.provider == .claude }.count == 3,
                         "configured roots include both default locations and each additional profile once")
            let restored = AgentUsageStore(saved: host.store.saved)
            suite.expect(restored.claudeSnapshot(roots: accounts[1].profile.logURLs(home: home), now: now)
                .usage(.today).total.tokens.total == 21,
                         "account attribution survives a usage cache round trip without storing account identities")
            let resumed = AgentUsageArchive.resume(.init(providers: [.claude], store: host.store.saved,
                cursors: host.cursors.values.map(\.saved)),
                logs: Set(host.cursors.keys.filter { $0.hasPrefix(AgentLogRoot.canonical(accounts[1].profile.configurationURL(home: home)).path + "/") }), since: .distantPast)
            suite.expect(resumed.store.snapshot(plans: [:], providers: [.claude], now: now).usage(.today).total.tokens.total == 21,
                         "removing a profile drops its archived counters without losing the other account")
            let personalRoot = AgentLogRoot.canonical(accounts[0].profile.logURLs(home: home)[0])
            let workRoot = AgentLogRoot.canonical(accounts[1].profile.logURLs(home: home)[0])
            let personalFile = personalRoot.appending(path: "project/same-session.jsonl").path
            let workFile = workRoot.appending(path: "project/same-session.jsonl").path
            for file in [personalFile, workFile] {
                host.store.apply([.turnBegan(now)], file: file, provider: .claude, tracksTurns: true, modified: now)
            }
            _ = host.store.closeEndedTurns(.init(ended: ["same-session"], listed: true), root: personalRoot)
            suite.expect(host.store.live.map(\.id) == [workFile],
                         "an ended personal process cannot end the work profile's identically named live session")
            suite.expect(host.store.claudeSnapshot(roots: [personalRoot], now: now).live.isEmpty
                            && host.store.claudeSnapshot(roots: [workRoot], now: now).live.count == 1,
                         "live sessions remain separate even when usage summaries are cached")
            let legacy = ClaudeMonitoredAccount(directory: home.appending(path: ".config/claude").path, name: "Legacy")
            try manager.createDirectory(at: legacy.profile.configurationURL(home: home), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid": "legacy"]])
                .write(to: legacy.profile.profileURL(home: home))
            let legacyProjects = legacy.profile.configurationURL(home: home).appending(path: "projects/project")
            try manager.createDirectory(at: legacyProjects, withIntermediateDirectories: true)
            try manager.copyItem(at: URL(fileURLWithPath: personalFile), to: legacyProjects.appending(path: "same-session.jsonl"))
            let all = accounts + [legacy]
            let combined = AgentUsageReadTests.Host()
            combined.home = home
            combined.start(session: 2, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation(),
                           claudeProfile: all[0].profile, claudeAccounts: all)
            let totals = all.map { combined.store.claudeSnapshot(roots: $0.logURLs(home: home), now: Date()).usage(.today).total.tokens.total }
            suite.expect(totals == [11, 21, 11] && combined.snapshot.usage(.today).total.tokens.total == 43,
                         "an explicit legacy-location login owns its logs separately from the default, even with identical message ids")
            let removed = AgentUsageReadTests.Host()
            removed.home = home
            removed.start(session: 3, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation(),
                          claudeProfile: accounts[0].profile, claudeAccounts: accounts)
            suite.expect(removed.snapshot.usage(.today).total.tokens.total == 32,
                         "removing a legacy-location account does not transfer its history to the default login")
            // A profile can keep its own metadata while sharing another profile's log tree.
            try manager.removeItem(at: legacy.profile.profileURL(home: home))
            let alias = ClaudeMonitoredAccount(directory: home.appending(path: ".claude-alias").path)
            try manager.createDirectory(at: alias.profile.configurationURL(home: home), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid": "alias"]])
                .write(to: alias.profile.profileURL(home: home))
            try manager.createSymbolicLink(at: alias.profile.configurationURL(home: home).appending(path: "projects"),
                                           withDestinationURL: legacyProjects.deletingLastPathComponent())
            suite.expect(ClaudeMonitoredAccount.decode(ClaudeMonitoredAccount.encode([accounts[0], alias]), home: home).count == 1,
                         "a profile sharing the default legacy log tree is rejected even with separate account metadata")
            preferences(suite, home: home, accounts: accounts)
            lifecycle(suite, accounts: accounts)
        } catch { suite.expect(false, "multiple Claude fixtures run: \(error)") }
    }

    private static func preferences(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount]) {
        let domain = "claude-multiple-\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(accounts[1].directory, forKey: DefaultsKey.notchAgentsClaudeProfile)
        defaults.set("", forKey: DefaultsKey.notchAgentsClaudeAccounts)
        suite.expect(ClaudeMonitoredAccount.configured(in: defaults).map(\.directory) == [accounts[1].directory],
                     "the previous single-account selection migrates without changing the login")
        let encoded = ClaudeMonitoredAccount.encode(accounts)
        suite.expect(ClaudeMonitoredAccount.decode(encoded, home: home) == accounts,
                     "account names and exact config-directory spelling survive persistence")
        let duplicate = ClaudeMonitoredAccount(directory: home.appending(path: ".claude").path)
        suite.expect(ClaudeMonitoredAccount.decode(ClaudeMonitoredAccount.encode(accounts + [duplicate]), home: home) == accounts,
                     "two profiles sharing a projects directory cannot be added twice")
        suite.expect(ClaudeMonitoredAccount.decode(ClaudeMonitoredAccount.encode([
            .init(directory: "relative"), .init(directory: "/valid", name: String(repeating: "x", count: 41))])).isEmpty,
                     "invalid profile paths and oversized labels are rejected")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsClaudeAccounts),
                     "machine-specific profile paths and custom account names stay out of settings backups")
        let tiles = NotchAgentSupport.tiles(cards: [.limits, .spend], providers: [.claude, .codex],
                                           codexAccounts: ["codex"], claudeAccounts: accounts.map(\.id))
        suite.expect(tiles.filter { $0.provider == .claude }.map(\.accountID) == accounts.map { Optional($0.id) }
                        && Set(tiles.map(\.id)).count == tiles.count,
                     "simultaneous default and work Claude cards have distinct identities beside Codex")
        suite.expect(NotchAgentSupport.pageProviders(enabled: [.claude, .codex], seen: [.codex], codexAccounts: [],
            claudeAccounts: accounts, filter: accounts[1].id) == [.claude]
                && NotchAgentSupport.claudeAccountIDs(accounts, filter: accounts[1].id) == [accounts[1].id]
                && NotchAgentSupport.pageProviders(enabled: [.codex], seen: [.codex], codexAccounts: [],
                    claudeAccounts: accounts, filter: accounts[1].id) == [.codex],
                     "card rendering and height use the same filter and ignore Claude selection when Claude is off")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.claudeAccount(language)
            suite.expect(!text.accountsTitle.isEmpty && !text.allAccounts.isEmpty && !text.multipleExplanation.isEmpty,
                         "multiple Claude accounts have labels and help in \(language)")
        }
    }

    private static func wait(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    private static func lifecycle(_ suite: TestSuite, accounts: [ClaudeMonitoredAccount]) {
        let domain = "com.vorssaint.tests.multiple-claude.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        defaults.set(ClaudeMonitoredAccount.encode(accounts), forKey: DefaultsKey.notchAgentsClaudeAccounts)
        let lock = NSLock()
        var calls = 0
        var identity = "work"
        var fail = false
        let service = ClaudeProfileLimitsService(defaults: defaults) { _, _ in
            let (name, failure) = lock.withLock { calls += 1; return (identity, fail) }
            let account = ClaudeAccountProfile.Identity(account: name, email: nil, organization: "shared")
            let limits = AgentLimits(provider: .claude, windows: [.init(id: "claude.fh", kind: .session,
                minutes: 300, scope: nil, usedPercent: 24, resetsAt: Date().addingTimeInterval(300))], observedAt: Date(), source: .account)
            return .init(metadata: .init(identity: account), result: failure ? .failure(.unreachable)
                : .success(.init(limits: limits, identity: account)))
        }
        defer { service.pause() }
        service.pageDidAppear(preview: true)
        suite.expect(service.timer == nil && lock.withLock { calls } == 0,
                     "a settings preview never starts an additional account request")
        service.pageDidAppear()
        wait { service.states.first?.limits != nil }
        suite.expect(service.states.count == 1 && service.states[0].id == accounts[1].id
                        && service.states[0].limits?.windows.first?.usedPercent == 24,
                     "the additional-account reader checks the work account while the primary keeps its existing reader")
        service.refresh()
        suite.expect(lock.withLock { calls } == 1, "reopening or refreshing does not bypass account polling cadence")
        var renamed = accounts
        renamed[1].name = "Company"
        defaults.set(ClaudeMonitoredAccount.encode(renamed), forKey: DefaultsKey.notchAgentsClaudeAccounts)
        service.synchronize()
        suite.expect(service.states[0].account.name == "Company" && service.states[0].limits != nil,
                     "renaming an account preserves its limits and retry timer")
        lock.withLock { identity = "replacement"; fail = true }
        service.refresh(force: true)
        wait { service.states.first?.failure != nil }
        suite.expect(service.states[0].limits == nil && service.states[0].identity?.account == "replacement",
                     "a failed check after login replacement cannot retain the previous user's allowance")
        service.setOnline(false)
        service.refresh(force: true)
        suite.expect(lock.withLock { calls } == 2 && service.states.allSatisfy { !$0.checking },
                     "offline accounts do not start requests even on a manual refresh")
        service.pageDidDisappear()
        suite.expect(service.timer == nil, "the additional-account timer stops when the AI page leaves")
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let late = ClaudeProfileLimitsService(defaults: defaults) { _, _ in
            entered.signal()
            _ = release.wait(timeout: .now() + 3)
            return .init(metadata: .init(), result: .failure(.outdated))
        }
        late.pageDidAppear()
        suite.expect(entered.wait(timeout: .now() + 2) == .success, "the removal fixture starts a pending check")
        defaults.set(ClaudeMonitoredAccount.encode([accounts[0]]), forKey: DefaultsKey.notchAgentsClaudeAccounts)
        late.synchronize()
        release.signal()
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        suite.expect(late.states.isEmpty && late.timer == nil,
                     "removing a checking profile rejects its late result and stops the last additional-account timer")
        late.pause()
        defaults.set(false, forKey: DefaultsKey.notchAgentsClaude)
        service.synchronize()
        service.refresh(force: true)
        suite.expect(lock.withLock { calls } == 2, "turning Claude off prevents additional-account requests")
    }
}
