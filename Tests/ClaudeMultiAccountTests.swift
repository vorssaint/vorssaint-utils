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
            let sharedLegacy = [accounts[0], alias]
            let legacyScopes = ClaudeMonitoredAccount.logScopes(sharedLegacy, home: home)
            suite.expect(ClaudeMonitoredAccount.decode(ClaudeMonitoredAccount.encode(sharedLegacy), home: home) == sharedLegacy
                            && alias.logURLs(home: home, scopes: legacyScopes).isEmpty,
                         "a profile sharing the default legacy log tree keeps its login without claiming that history")
            preferences(suite, home: home, accounts: accounts)
            try folderFeedback(suite, home: home, accounts: accounts)
            backgroundFolders(suite, home: home, accounts: accounts)
            try liveLimits(suite, home: home, accounts: accounts)
            spendPlans(suite, home: home, accounts: accounts)
            try sourceAliases(suite, home: home, accounts: accounts)
            try sharedHistory(suite, home: home, accounts: accounts)
            try nestedHistory(suite, home: home, accounts: accounts)
            try archiveKeys(suite, home: home)
            lifecycle(suite, accounts: accounts)
        } catch { suite.expect(false, "multiple Claude fixtures run: \(error)") }
    }

    private static func folderFeedback(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount]) throws {
        let defaultFolder = ClaudeAccountProfile(directory: home.appending(path: ".claude").path)
        let duplicate = ClaudeMonitoredAccount.adding([defaultFolder], to: accounts, home: home)
        suite.expect(duplicate.accounts == accounts && duplicate.issue == .duplicate,
                     "choosing the listed default folder reports a duplicate instead of an invalid profile")
        let alias = home.appending(path: ".claude-folder-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: accounts[1].profile.configurationURL(home: home))
        let linked = ClaudeMonitoredAccount.adding([ClaudeAccountProfile(directory: alias.path)], to: accounts, home: home)
        suite.expect(linked.accounts == accounts && linked.issue == .duplicate,
                     "a second path to a listed configuration reports the same duplicate message")
        let invalid = ClaudeAccountProfile(directory: home.appending(path: "missing-profile").path)
        let rejected = ClaudeMonitoredAccount.adding([invalid], to: accounts, home: home)
        suite.expect(rejected.accounts == accounts && rejected.issue == .invalid,
                     "an unusable folder still reports the invalid-folder message")
        let added = ClaudeMonitoredAccount.adding([accounts[1].profile], to: [accounts[0]], home: home)
        suite.expect(added.accounts.map(\.directory) == accounts.map(\.directory) && added.issue == nil,
                     "a valid additional account is accepted without an alert")
        let mixed = ClaudeMonitoredAccount.adding([defaultFolder, accounts[1].profile, invalid], to: [accounts[0]], home: home)
        suite.expect(mixed.accounts.map(\.directory) == accounts.map(\.directory) && mixed.issue == .invalid,
                     "mixed folder selections add valid accounts and retain feedback about unusable folders")
    }

    private static func backgroundFolders(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount]) {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        var completed = false
        var offMain = false
        ClaudeMonitoredAccount.adding({
            offMain = !Thread.isMainThread
            entered.signal()
            _ = release.wait(timeout: .now() + 3)
            return [accounts[1].profile]
        }, to: [accounts[0]], home: home) { result in
            suite.expect(offMain && Thread.isMainThread && result.accounts == accounts && result.issue == nil,
                         "selected-folder validation returns valid accounts on the main thread")
            completed = true
        }
        let started = entered.wait(timeout: .now() + 2) == .success
        suite.expect(started && !completed, "slow folder discovery leaves the main thread free before validation completes")
        release.signal()
        wait { completed }
        suite.expect(completed, "background selected-folder validation completes")
        completed = false
        offMain = false
        let known = Set(accounts.map { $0.profile.configurationURL(home: home).resolvingSymlinksInPath().path })
        ClaudeMonitoredAccount.adding({
            offMain = !Thread.isMainThread
            return [ClaudeAccountProfile()] + ClaudeAccountProfile.discover(home: home).filter {
                known.contains($0.configurationURL(home: home).resolvingSymlinksInPath().path)
            }
        }, to: accounts, home: home, ignoringKnown: true) { result in
            suite.expect(offMain && Thread.isMainThread && result.accounts == accounts && result.issue == nil,
                         "background account discovery ignores already configured logins without a duplicate alert")
            completed = true
        }
        wait { completed }
        suite.expect(completed, "background account discovery completes")
    }

    private static func liveLimits(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount]) throws {
        let now = Date()
        let scopes = accounts.map { AgentLogRoot.canonical($0.profile.configurationURL(home: home)).path }
        try session("work", account: accounts[1], home: home)
        let registries = AgentSessionRegistry.read(accounts: accounts, home: home)
        func limits(_ used: Double) -> AgentLimits {
            AgentLimits(provider: .claude, windows: [.init(id: "session", kind: .session, minutes: 300, scope: nil,
                usedPercent: used, resetsAt: now.addingTimeInterval(300))], observedAt: now, source: .account)
        }
        let personal = limits(10), work = limits(75)
        let state = ClaudeProfileLimitsState(account: accounts[1], limits: work)
        let store = AgentUsageStore()
        store.apply([.turnBegan(now.addingTimeInterval(-120))], file: scopes[1] + "/projects/work.jsonl",
            provider: .claude, tracksTurns: true, accountScope: scopes[1], modified: now, now: now)
        store.updateLimits(personal)
        store.closeEndedTurns(accounts: registries)
        var snapshot = store.snapshot(plans: [:], providers: [.claude], now: now)
        snapshot.claudeLimits = ClaudeProfileLimitsState.readings(primary: accounts[0], limits: personal,
            additional: [state], home: home)
        suite.expect(snapshot.live.first?.claudeProfile == scopes[1]
                        && NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining, now: now)
                            == AgentFormat.percent(0.25)
                        && NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .used, now: now)
                            == AgentFormat.percent(0.75),
                     "a Work-only live session uses Work's limits even with Personal listed first")
        suite.expect(NotchAgentSupport.restingLimit(snapshot, focus: .mostUsed, now: now)?.window.usedPercent == 10,
                     "the resting island keeps using the first Claude account's limits")
        suite.expect(NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining,
                        now: now.addingTimeInterval(300)) == AgentFormat.clock(420),
                     "a secondary live allowance expires at its reset and falls back to elapsed time")
        var partial = work
        partial.windows.append(.init(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                                     usedPercent: 60, resetsAt: now.addingTimeInterval(600)))
        snapshot.claudeLimits[scopes[1]] = partial
        suite.expect(NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining, focus: .session,
                        now: now.addingTimeInterval(300)) == AgentFormat.percent(0.4),
                     "a still-current weekly allowance remains available after the session window expires")
        suite.expect(NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining,
                        now: now.addingTimeInterval(600)) == AgentFormat.clock(720),
                     "elapsed time replaces the allowance once every reported window has expired")
        snapshot.claudeLimits[scopes[1]] = work
        snapshot.claudeLimits = ClaudeProfileLimitsState.readings(primary: accounts[0], limits: personal,
            additional: [.init(account: accounts[1])], home: home)
        suite.expect(NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining, now: now)
                        == AgentFormat.clock(120),
                     "a Work session without its own limits shows elapsed time instead of Personal's allowance")
        snapshot.claudeLimits = ClaudeProfileLimitsState.readings(primary: accounts[0], limits: personal,
            additional: [state], home: home)
        snapshot.live[0].claudeProfile = nil
        suite.expect(NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining, now: now)
                        == AgentFormat.clock(120),
                     "a session with unknown account ownership shows elapsed time despite available Claude limits")
        snapshot.live[0].claudeProfile = scopes[0]
        suite.expect(NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining, now: now)
                        == AgentFormat.percent(0.9),
                     "a Personal session still uses Personal's own limits")
        let resumed = AgentUsageStore()
        resumed.apply([.turnActive(now)], file: scopes[1] + "/projects/resumed.jsonl", provider: .claude,
            tracksTurns: true, accountScope: scopes[1], modified: now, now: now)
        try session("resumed", account: accounts[1], home: home)
        resumed.closeEndedTurns(accounts: AgentSessionRegistry.read(accounts: accounts, home: home))
        suite.expect(resumed.snapshot(plans: [:], providers: [.claude], now: now)
                        .live.first?.claudeProfile == scopes[1],
                     "sessions first seen through activity retain their Claude account too")
        var saved = store.saved
        let privateIdentity = "account-ownership-is-not-archived"
        saved.turns[0].claudeProfile = privateIdentity
        let data = AgentUsageArchive.encode(.init(providers: [.claude], store: saved, cursors: []), build: "ownership")
        guard let archive = AgentUsageArchive.decode(data, build: "ownership") else {
            suite.expect(false, "Claude ownership fixture round-trips through the binary archive")
            return
        }
        suite.expect(data.range(of: Data(privateIdentity.utf8)) == nil && archive.store.turns.first?.claudeProfile == nil,
                     "Claude account identity is not persisted in the binary archive")
        let restored = AgentUsageStore(saved: archive.store)
        restored.closeEndedTurns(accounts: registries)
        suite.expect(restored.snapshot(plans: [:], providers: [.claude], now: now)
                        .live.first?.claudeProfile == scopes[1],
                     "live sessions restored from the usage archive regain their account from a running login registry")
    }

    private static func spendPlans(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount]) {
        let now = Date()
        let pro = AgentPlan(name: "Pro", monthlyPrice: 20)
        let store = AgentUsageStore()
        for account in accounts {
            let root = account.profile.configurationURL(home: home).appending(path: "projects")
            let record = AgentUsageRecord(provider: .claude, date: now, model: "claude-opus-5-5", project: "app",
                session: "session", tokens: AgentTokens(output: 1), cost: 100, savings: 0)
            store.apply([.usage(key: "response", record: record, billable: AgentBillable(tokens: record.tokens))],
                file: root.appending(path: "session.jsonl").path, provider: .claude, tracksTurns: false,
                accountScope: account.id, modified: now, now: now)
        }
        let combined = store.snapshot(plans: [.claude: AgentPlans.combined([pro, pro])!], providers: [.claude], now: now)
        suite.expect(combined.usage(.month).total.cost == 200 && combined.planMultiple(for: .claude) == 5,
                     "two accounts with $100 each and $20 plans show a combined 5x multiple")
        for account in accounts {
            let selected = store.claudeSnapshot(roots: account.profile.logURLs(home: home), now: now, plan: pro)
            suite.expect(selected.plans[.claude] == pro && selected.planMultiple(for: .claude) == 5,
                         "selecting \(account.name) keeps its own plan and $100 / $20 multiple")
        }
        let maxPlan = AgentPlan(name: "Max", monthlyPrice: 100)
        let selected = store.claudeSnapshot(roots: accounts[1].profile.logURLs(home: home), now: now, plan: maxPlan)
        suite.expect(selected.planMultiple(for: .claude) == 1
                        && AgentPlans.combined([pro, maxPlan])?.monthlyPrice == 120,
                     "different account plans and changed plans use their own prices even with cached usage")
        for unknown in [nil, AgentPlan(name: "New plan", monthlyPrice: nil)] as [AgentPlan?] {
            var plans: [AgentProvider: AgentPlan] = [:]
            plans[.claude] = AgentPlans.combined([pro, unknown])
            let incomplete = store.snapshot(plans: plans, providers: [.claude], now: now)
            suite.expect(incomplete.planMultiple(for: .claude) == nil,
                         "the combined Claude multiple is hidden if any account's plan or price is unknown")
        }
        let unpriced = store.claudeSnapshot(roots: accounts[1].profile.logURLs(home: home), now: now)
        suite.expect(unpriced.planMultiple(for: .claude) == nil,
                     "a selected account without a known plan does not reuse a cached account's price")
    }

    private static func sourceAliases(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount]) throws {
        let root = accounts[0].profile.configurationURL(home: home).appending(path: "projects")
        let alias = home.appending(path: "personal-history")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let now = Date()
        let record = AgentUsageRecord(provider: .claude, date: now, model: "claude-opus-5-5", project: "app",
            session: "aliased", tokens: AgentTokens(output: 7), cost: 2, savings: 0)
        let store = AgentUsageStore()
        // The file may have gone since it was read; its parent still resolves.
        store.apply([.turnBegan(now), .usage(key: "aliased", record: record, billable: .init(tokens: record.tokens))],
            file: alias.appending(path: "missing.jsonl").path, provider: .claude, tracksTurns: true,
            modified: now, now: now)
        let restored = AgentUsageStore(saved: store.saved)
        let personal = restored.claudeSnapshot(roots: [root], now: now)
        let viaAlias = restored.claudeSnapshot(roots: [alias], now: now)
        let work = restored.claudeSnapshot(roots: accounts[1].profile.logURLs(home: home), now: now)
        let combined = restored.snapshot(plans: [:], providers: [.claude], now: now)
        suite.expect(personal.usage(.month).total.tokens.total == 7 && personal.usage(.month).total.cost == 2
                        && personal.live.count == 1 && personal == viaAlias
                        && combined.usage(.month).total == personal.usage(.month).total
                        && work.usage(.month).total.tokens.total == 0 && work.live.isEmpty,
                     "source aliases preserve Personal's tokens, spend and live turns after restoring cached usage")
    }

    private static func sharedHistory(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount]) throws {
        let manager = FileManager.default
        let personal = accounts[0], work = accounts[1]
        let personalRoot = personal.profile.configurationURL(home: home).appending(path: "projects")
        let workRoot = work.profile.configurationURL(home: home).appending(path: "projects")
        try manager.removeItem(at: workRoot)
        try manager.createSymbolicLink(at: workRoot, withDestinationURL: personalRoot)
        let duplicate = ClaudeMonitoredAccount(directory: home.appending(path: ".claude-work-alias").path)
        try manager.createSymbolicLink(at: duplicate.profile.configurationURL(home: home),
                                       withDestinationURL: work.profile.configurationURL(home: home))
        let decoded = ClaudeMonitoredAccount.decode(ClaudeMonitoredAccount.encode(accounts + [work, duplicate]), home: home)
        suite.expect(decoded == accounts,
                     "separate Claude logins sharing a symlinked projects folder survive decoding, but duplicate config directories do not")
        suite.expect(personal.profile.read(home: home).identity?.account == "Personal"
                        && work.profile.read(home: home).identity?.account == "Work",
                     "shared session history preserves each login's own account metadata")
        let scopes = ClaudeMonitoredAccount.logScopes(decoded, home: home)
        suite.expect(scopes[AgentLogRoot.canonical(personalRoot).path + "/"]
                        == AgentLogRoot.canonical(personal.profile.configurationURL(home: home)).path
                        && work.logURLs(home: home, scopes: scopes).isEmpty,
                     "the first Claude account alone owns the shared log root")
        let host = AgentUsageReadTests.Host()
        host.home = home
        host.start(session: 4, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation(),
                   claudeProfile: personal.profile, claudeAccounts: decoded)
        let now = Date()
        let totals = accounts.map {
            host.store.claudeSnapshot(roots: $0.logURLs(home: home, scopes: scopes), now: now).usage(.today).total
        }
        suite.expect(host.snapshot.usage(.today).total.tokens.total == 11
                        && totals.map { $0.tokens.total } == [11, 0]
                        && totals[0].cost == host.snapshot.usage(.today).total.cost && totals[1].cost == 0,
                     "shared logs contribute tokens and API value to the first account and combined usage only once")
        try sharedSessions(suite, home: home, accounts: accounts, host: host, now: now)
        let cached = AgentUsageArchive.Contents(providers: [.claude], store: host.store.saved,
            cursors: host.cursors.values.map(\.saved))
        let resumed = AgentUsageArchive.resume(cached, logs: Set(host.cursors.keys), since: now.addingTimeInterval(-86_400))
        let personalUsage = resumed.store.claudeSnapshot(roots: personal.logURLs(home: home, scopes: scopes), now: now)
        suite.expect(personal.id.isEmpty && personalUsage.usage(.month).total.tokens.total == 11
                        && resumed.store.snapshot(plans: [:], providers: [.claude], now: now).usage(.month).total
                            == personalUsage.usage(.month).total,
                     "a relaunch keeps shared cached history in All accounts and Personal despite Personal's empty account id")
        let reordered = [work, personal]
        let reorderedScopes = ClaudeMonitoredAccount.logScopes(reordered, home: home)
        let legacyRoot = AgentLogRoot.canonical(home.appending(path: ".config/claude/projects"))
        suite.expect(reorderedScopes[AgentLogRoot.canonical(personalRoot).path + "/"]
                        == AgentLogRoot.canonical(work.profile.configurationURL(home: home)).path
                        && personal.logURLs(home: home, scopes: reorderedScopes).map { AgentLogRoot.canonical($0) } == [legacyRoot],
                     "reordering transfers shared history to the earlier login while the later login keeps its separate legacy root")
        let roots = AgentLogRoot.all(home: home, claudeProfile: work.profile, additionalClaudeProfiles: [personal.profile])
        suite.expect(roots.filter { $0.provider == .claude }.map(\.url) == [AgentLogRoot.canonical(personalRoot), legacyRoot],
                     "log discovery monitors each owned Claude history root once")
    }

    private static func session(_ id: String, account: ClaudeMonitoredAccount, home: URL,
                                pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        let folder = account.profile.configurationURL(home: home).appending(path: "sessions")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["pid": Int(pid), "sessionId": id, "pidDomain": "darwin"])
            .write(to: folder.appending(path: "\(pid).json"))
    }

    private static func sharedSessions(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount],
                                       host: AgentUsageReadTests.Host, now: Date) throws {
        let manager = FileManager.default
        let personalSessions = accounts[0].profile.configurationURL(home: home).appending(path: "sessions")
        try manager.createDirectory(at: personalSessions, withIntermediateDirectories: true)
        try session("same-session", account: accounts[1], home: home)
        let file = AgentLogRoot.canonical(accounts[0].profile.configurationURL(home: home).appending(path: "projects"))
            .appending(path: "project/same-session.jsonl").path
        host.store.apply([.turnBegan(now.addingTimeInterval(-120))], file: file, provider: .claude,
                         tracksTurns: true, modified: now, now: now)
        host.store = AgentUsageStore(saved: host.store.saved)
        host.closeEndedTurns(atLaunch: true)
        var snapshot = host.store.snapshot(plans: [:], providers: [.claude], now: now)
        let work = AgentLogRoot.canonical(accounts[1].profile.configurationURL(home: home)).path
        suite.expect(snapshot.live.count == 1 && snapshot.live.first?.claudeProfile == work,
                     "startup retains a Work turn in shared history when Personal's readable sessions registry is empty")
        let personalLimits = AgentLimits(provider: .claude, windows: [.init(id: "session", kind: .session,
            minutes: 300, scope: nil, usedPercent: 10, resetsAt: now.addingTimeInterval(300))], observedAt: now, source: .account)
        let workLimits = AgentLimits(provider: .claude, windows: [.init(id: "session", kind: .session,
            minutes: 300, scope: nil, usedPercent: 75, resetsAt: now.addingTimeInterval(300))], observedAt: now, source: .account)
        snapshot.claudeLimits = ClaudeProfileLimitsState.readings(primary: accounts[0], limits: personalLimits,
            additional: [.init(account: accounts[1], limits: workLimits)], home: home)
        suite.expect(NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining, now: now)
                        == AgentFormat.percent(0.25),
                     "a Work process in Personal's shared history displays Work's allowance")
        try session("same-session", account: accounts[0], home: home)
        suite.expect(host.closeEndedTurns(), "an ownership change requests a fresh live snapshot")
        snapshot.live = host.store.live
        suite.expect(snapshot.live.first?.claudeProfile == nil
                        && NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .remaining, now: now)
                            == AgentFormat.clock(120),
                     "two logins registering the same shared session make its allowance ambiguous and show elapsed time")
        try manager.removeItem(at: personalSessions.appending(path: "\(ProcessInfo.processInfo.processIdentifier).json"))
        let unrelated = ClaudeMonitoredAccount(directory: home.appending(path: ".claude-unrelated").path)
        try manager.createDirectory(at: unrelated.profile.configurationURL(home: home).appending(path: "projects"),
                                    withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: unrelated.profile.profileURL(home: home))
        try session("unrelated-only", account: unrelated, home: home)
        let missing = URL(fileURLWithPath: file).deletingLastPathComponent().appending(path: "unrelated-only.jsonl").path
        host.store.apply([.turnBegan(now)], file: missing, provider: .claude, tracksTurns: true, modified: now, now: now)
        host.readerClaudeAccounts = accounts + [unrelated]
        host.closeEndedTurns(atLaunch: true)
        suite.expect(host.store.live.map(\.id) == [file] && host.store.live.first?.claudeProfile == work,
                     "a registry for an unrelated root cannot preserve or claim a missing shared-history session")
        host.readerClaudeAccounts = accounts
        let incomplete = personalSessions.appending(path: "1.json")
        try Data("{".utf8).write(to: incomplete)
        host.closeEndedTurns()
        suite.expect(host.store.live.count == 1 && host.store.live.first?.claudeProfile == nil,
                     "an incomplete account registry preserves a running shared session without guessing its allowance")
        try manager.removeItem(at: incomplete)
    }

    private static func nestedHistory(_ suite: TestSuite, home: URL, accounts: [ClaudeMonitoredAccount]) throws {
        let manager = FileManager.default
        let personalRoot = accounts[0].profile.configurationURL(home: home).appending(path: "projects")
        let team = personalRoot.appending(path: "team")
        try manager.createDirectory(at: team, withIntermediateDirectories: true)
        let workRoot = accounts[1].profile.configurationURL(home: home).appending(path: "projects")
        try manager.removeItem(at: workRoot)
        try manager.createSymbolicLink(at: workRoot, withDestinationURL: team)
        let now = Date()
        let line = #"{"type":"assistant","timestamp":\#(now.timeIntervalSince1970),"sessionId":"team","requestId":"same-request","message":{"id":"same-message","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":20,"output_tokens":1}}}"#
        let teamLog = team.appending(path: "team.jsonl")
        try Data((line + "\n").utf8).write(to: teamLog)
        let ordered = [accounts[1], accounts[0]]
        let scopes = ClaudeMonitoredAccount.logScopes(ordered, home: home)
        let host = AgentUsageReadTests.Host()
        host.home = home
        host.start(session: 5, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation(),
                   claudeProfile: ordered[0].profile, claudeAccounts: ordered)
        let totals = ordered.map { account in
            host.store.claudeSnapshot(roots: account.logURLs(home: home, scopes: scopes),
                excluding: account.excludedLogURLs(home: home, scopes: scopes), now: now).usage(.today).total
        }
        suite.expect(host.cursors[teamLog.path] != nil
                        && host.cursors[personalRoot.appending(path: "project/same-session.jsonl").path] != nil
                        && host.snapshot.usage(.today).total.tokens.total == 32
                        && totals.map { $0.tokens.total } == [21, 11],
                     "a first account's shared subtree cannot hide the later account's other projects or count the overlap twice")
        let restored = AgentUsageStore(saved: host.store.saved)
        let selected = restored.claudeSnapshot(roots: accounts[0].logURLs(home: home, scopes: scopes),
            excluding: accounts[0].excludedLogURLs(home: home, scopes: scopes), now: now)
        suite.expect(selected.usage(.today).total == totals[1]
                        && totals.reduce(0) { $0 + $1.cost } == host.snapshot.usage(.today).total.cost,
                     "nested history keeps account costs and archived attribution consistent with the combined totals")
        let reordered = ClaudeMonitoredAccount.recordScopes(accounts, home: home)
        suite.expect(ClaudeMonitoredAccount.logRoot(for: teamLog.path, scopes: reordered)
                        == ClaudeMonitoredAccount.logRoot(for: teamLog.path,
                            scopes: ClaudeMonitoredAccount.recordScopes(ordered, home: home)),
                     "reordering overlapping accounts preserves their response deduplication scope")
    }

    private static func archiveKeys(_ suite: TestSuite, home: URL) throws {
        let manager = FileManager.default
        let home = home.appending(path: "archive-privacy")
        let account = ClaudeMonitoredAccount(directory: home.appending(path: "private-configuration").path)
        let history = home.appending(path: "external-history/project")
        try manager.createDirectory(at: account.profile.configurationURL(home: home), withIntermediateDirectories: true)
        try manager.createDirectory(at: history, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: account.profile.profileURL(home: home))
        try manager.createSymbolicLink(at: account.profile.configurationURL(home: home).appending(path: "projects"),
                                       withDestinationURL: history.deletingLastPathComponent())
        let now = Date()
        let line = #"{"type":"assistant","timestamp":\#(now.timeIntervalSince1970),"sessionId":"private-session","message":{"id":"private-message","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":7,"output_tokens":1}}}"#
        let file = history.appending(path: "private-session.jsonl")
        try Data((line + "\n").utf8).write(to: file)
        let host = AgentUsageReadTests.Host()
        host.home = home
        host.start(session: 6, providers: [.claude], cancellation: AgentUsageReadTests.Cancellation(),
                   claudeProfile: account.profile, claudeAccounts: [account])
        let data = AgentUsageArchive.encode(.init(providers: [.claude], store: host.store.saved,
            cursors: host.cursors.values.map(\.saved)), build: "private-keys")
        guard let decoded = AgentUsageArchive.decode(data, build: "private-keys") else {
            suite.expect(false, "private record-key fixture round-trips through the usage archive")
            return
        }
        let configuration = account.profile.configurationURL(home: home).path
        suite.expect(decoded.store.records.count == 1
                        && decoded.store.records.allSatisfy { !$0.key.contains(configuration) && !$0.key.contains(home.path) }
                        && data.range(of: Data(configuration.utf8)) == nil,
                     "serialized response keys and the archive contain no configuration-directory path when history lives elsewhere")
        host.store = AgentUsageStore(saved: decoded.store)
        host.cursors.removeAll()
        host.read(file.path, provider: .claude)
        suite.expect(host.store.records.count == 1 && host.store.records.first?.tokens.total == 8,
                     "private response keys still deduplicate a full log reread after restoring the archive")
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
                     "two profiles resolving to the same configuration directory cannot be added twice")
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
            suite.expect(!text.accountsTitle.isEmpty && !text.allAccounts.isEmpty && !text.multipleExplanation.isEmpty
                            && !text.duplicateFolder.isEmpty && text.duplicateFolder != text.invalidFolder,
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

        let third = ClaudeMonitoredAccount(directory: accounts[1].directory + "-queued", name: "Queued")
        defaults.set(ClaudeMonitoredAccount.encode(accounts + [third]), forKey: DefaultsKey.notchAgentsClaudeAccounts)
        let queuedEntered = DispatchSemaphore(value: 0), queuedRelease = DispatchSemaphore(value: 0)
        let queued = ClaudeProfileLimitsService(defaults: defaults) { profile, _ in
            if profile.id == accounts[1].id {
                queuedEntered.signal()
                _ = queuedRelease.wait(timeout: .now() + 3)
                return .init(metadata: .init(), result: .failure(.outdated))
            }
            let limits = AgentLimits(provider: .claude, windows: [.init(id: "claude.fh", kind: .session,
                minutes: 300, scope: nil, usedPercent: 42, resetsAt: Date().addingTimeInterval(300))], observedAt: Date(), source: .account)
            return .init(metadata: .init(), result: .success(.init(limits: limits, identity: nil)))
        }
        defer { queuedRelease.signal(); queued.pause() }
        queued.synchronize()
        queued.refresh(force: true)
        suite.expect(queuedEntered.wait(timeout: .now() + 2) == .success
                        && queued.states.map(\.id) == [accounts[1].id, third.id]
                        && queued.states.allSatisfy(\.checking) && queued.timer == nil,
                     "a manual limits check starts the second Claude account and queues the third while the AI page is closed")
        defaults.set(ClaudeMonitoredAccount.encode([accounts[0], third]), forKey: DefaultsKey.notchAgentsClaudeAccounts)
        queued.synchronize()
        queuedRelease.signal()
        wait { queued.states.first?.limits != nil }
        suite.expect(queued.states.count == 1 && queued.states.first?.id == third.id
                        && queued.states.first?.limits?.windows.first?.usedPercent == 42
                        && queued.states.first?.checking == false && queued.timer == nil,
                     "removing a running Claude account advances the queued manual check while the AI page stays closed")

        defaults.set(false, forKey: DefaultsKey.notchAgentsClaude)
        service.synchronize()
        service.refresh(force: true)
        suite.expect(lock.withLock { calls } == 2, "turning Claude off prevents additional-account requests")
    }
}
