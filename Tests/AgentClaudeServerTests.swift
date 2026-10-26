// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

typealias AgentClaudeWeeklyFile = AgentWeeklyUsageFile

enum AgentClaudeServerTests {
    /// Extracted production methods use the real archive implementation,
    /// redirected to a temporary fixture rather than the installed app.
    enum AgentWeeklyUsageFile {
        static var url: URL?
        static func save(_ history: AgentWeeklyUsage, to url: URL?) -> Bool {
            AgentClaudeWeeklyFile.save(history, to: url)
        }
        static func load(from url: URL?) -> (history: AgentWeeklyUsage, failed: Bool) {
            AgentClaudeWeeklyFile.load(from: url)
        }
    }
    enum NotchAgentSupport {
        static let defaultLimitThreshold = 80.0
        static func limitThreshold() -> Double? { defaultLimitThreshold }
        /// Whether anything but the page's Limits card uses the limits.
        static var used = true
        static func limitsInUse(pageShown: Bool) -> Bool { used || pageShown }
    }

    class Fixture {
        let queue = DispatchQueue(label: "com.vorssaint.tests.claude-account")
        var session = 1
        var readerSession = 1
        var claudeWeeklyScope: String?
        var weeklyHistory = AgentWeeklyUsage()
        var weeklySaveFailed = false
        var claudeProfileModified: Date?
        var claudePlan: AgentPlan?
        var weeklyPublications: [AgentWeeklyUsage] = []
        func schedulePublish() { weeklyPublications.append(weeklyHistory) }
        var refreshRequests: [Bool] = []
        func refreshClaudeLimits(pageShows: Bool) { refreshRequests.append(pageShows) }
        func publish() { schedulePublish() }
        var running = true
        var paused = false
        var online = true
        var providers: [AgentProvider] = [.claude]
        var pageVisible = false
        var claudeAccountRequest: AgentClaudeServer.Request?
        var claudeAccountAttempted = Date.distantPast
        var claudeAccountFailure: AgentClaudeServer.Failure?
        var claudeAccountUnreachable = 0
        var home = FileManager.default.temporaryDirectory
        var enabled: Set<AgentProvider> = [.claude]
        var claudeOrganization: String? = "account"
        var claudeAppModified: Date?
        var claudeAppSamples: [AgentClaudeAppUsage.Sample] = []
        var claudeAccountLimits: AgentLimits?
        let store = AgentUsageStore()
        var previousLimits: [AgentProvider: AgentLimits] = [:]
        var warned: [String: (provider: AgentProvider, window: AgentLimitWindow)] = [:]
        /// When the replay is, for each event it records.
        var clock = Date.distantPast
        var events: [String] = []

        func report(_ event: AgentUsageEvent) {
            let time = ISO8601DateFormatter().string(from: clock)
            switch event {
            case .limitWarning(_, let window): events.append("warning \(window.id) \(time)")
            case .limitReset(_, let window): events.append("reset \(window.id) \(time)")
            default: events.append("other \(time)")
            }
        }
    }

    static func run(_ suite: TestSuite) {
        accountSelection(suite)
        signedOutSelection(suite)
        alerts(suite)
        checks(suite)
        preview(suite)
        discovery(suite)
        let now = AgentTimestamp.parse("2026-10-15T07:00:00Z")!
        func result(_ used: Any = 62, resets: Any = "2026-10-15T10:39:59.973389+00:00") -> [String: Any] {
            ["rate_limits_available": true, "rate_limits": [
                "five_hour": ["utilization": used, "resets_at": resets],
                "seven_day": ["utilization": 9, "resets_at": "2026-10-17T22:59:59.973411+00:00"],
                "seven_day_opus": ["utilization": 70, "resets_at": "2026-10-17T22:59:59Z"],
                "seven_day_sonnet": NSNull()]]
        }
        let limits = AgentClaudeServer.limits(result(), observed: now)
        suite.expect(limits?.source == .account && limits?.observedAt == now
                        && limits?.windows.map(\.usedPercent) == [62, 9, 70]
                        && limits?.windows.map(\.id) == ["claude.fh", "claude.sd", "claude.so"]
                        && limits?.windows.last?.scope == "Opus"
                        && limits?.windows.first?.resetsAt == AgentTimestamp.parse("2026-10-15T10:39:59.973389Z")
                        && limits?.windows.first?.estimatedResetsAt == nil,
                     "structured CLI usage preserves account-wide percentages, model windows and exact resets")
        suite.expect(AgentClaudeServer.limits(["rate_limits_available": false], observed: now) == nil
                        && AgentClaudeServer.limits(["rate_limits_available": true, "rate_limits": NSNull()], observed: now) == nil,
                     "unsupported or unavailable accounts never produce invented limits")
        for used: Any in [true, "62", NSNull()] {
            suite.expect(AgentClaudeServer.limits(result(used), observed: now)?.windows.map(\.kind) == [.weekly, .weekly],
                         "invalid percentages cannot replace a known session limit")
        }
        suite.expect(AgentClaudeServer.limits(result(-1), observed: now)?.windows.first?.usedPercent == 0
                        && AgentClaudeServer.limits(result(101), observed: now)?.windows.first?.usedPercent == 100,
                     "account percentages outside 0 to 100 are clamped as the Claude app history is")
        let idle = AgentClaudeServer.limits(result(0, resets: NSNull()), observed: now)
        suite.expect(idle?.windows.first.map { $0.kind == .session && $0.usedPercent == 0 && $0.resetsAt == nil } == true
                        && AgentClaudeServer.limits(result(0, resets: "2026-10-15T06:00:00Z"), observed: now)?
                            .windows.map(\.kind) == [.weekly, .weekly]
                        && AgentClaudeServer.current(idle, now: now.addingTimeInterval(4 * 3_600))?.windows.first?.kind == .session
                        && AgentClaudeServer.current(idle, now: now.addingTimeInterval(5 * 3_600))?.windows.first?.kind == .weekly,
                     "an idle session without a renewal keeps its row for as long as the Claude app history would")
        suite.expect(AgentClaudeServer.interval(after: nil, pageVisible: true) == 60
                        && AgentClaudeServer.interval(after: nil, pageVisible: false) == 300
                        && AgentClaudeServer.interval(after: .unreachable, pageVisible: true) == 300
                        && [AgentClaudeServer.Failure.missing, .needsSignIn, .outdated].allSatisfy {
                            AgentClaudeServer.interval(after: $0, pageVisible: true) == 1_800 },
                     "Claude Code is asked every minute only while the AI page shows, and rarely after a failure only the person can fix")
        suite.expect([0, 1, 2, 3, 4, 9].map { AgentClaudeServer.interval(after: .unreachable, repeated: $0, pageVisible: true) }
                        == [300, 300, 600, 1_200, 1_800, 1_800],
                     "Claude Code that keeps failing to answer is asked half as often each time, down to every half hour")
        suite.expect(AgentClaudeServer.current(limits, now: AgentTimestamp.parse("2026-10-15T11:00:00Z")!)?
            .windows.map(\.kind) == [.weekly, .weekly]
            && AgentClaudeServer.current(limits, now: AgentTimestamp.parse("2026-10-18T00:00:00Z")!) == nil,
                     "passed renewals expire independently without claiming zero remote usage")
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorssaint-claude-server-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // `--setting-sources ""` leaves out the person's user settings,
            // so their opt-outs come along by name, and only those.
            let settings = folder.appending(path: ".claude/settings.json")
            try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["env": ["DISABLE_TELEMETRY": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": 1,
                                                                "ANTHROPIC_BASE_URL": "https://example.invalid",
                                                                "HTTPS_PROXY": "http://proxy.invalid:8080", "NO_PROXY": "localhost",
                                                                "NODE_EXTRA_CA_CERTS": "/etc/proxy.pem"]]).write(to: settings)
            let child = AgentClaudeServer.environment(["PATH": "/usr/bin", "CLAUDECODE": "1", "DISABLE_ERROR_REPORTING": "1",
                                                       "HTTP_PROXY": "http://other.invalid"], home: folder)
            try FileManager.default.removeItem(at: settings)
            suite.expect(child == ["PATH": "/usr/bin", "DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1",
                                   "DISABLE_ERROR_REPORTING": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
                                   "HTTP_PROXY": "http://other.invalid", "HTTPS_PROXY": "http://proxy.invalid:8080",
                                   "NO_PROXY": "localhost", "NODE_EXTRA_CA_CERTS": "/etc/proxy.pem"]
                            && AgentClaudeServer.environment(["PATH": "/usr/bin"], home: folder)
                                == ["PATH": "/usr/bin", "DISABLE_AUTOUPDATER": "1"],
                         "a check keeps the person's Claude Code opt-outs and proxy, never updates it and turns nothing else off")
            let tool = folder.appending(path: "claude")
            try Data(standIn.utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
            func run(_ mode: String, timeout: TimeInterval = 2) -> Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure> {
                AgentClaudeServer.Request().run(tool, home: folder,
                    environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "STAND_IN": mode, "CLAUDECODE": "nested"],
                    timeout: timeout)
            }
            let summary = try? run("ok").get()
            suite.expect(summary?.limits.windows.map(\.usedPercent) == [100, 9],
                         "a CLI conversation initializes and asks get_usage without a user prompt, hooks, tools or MCP")
            suite.expect(run("old") == .failure(.outdated) && run("unsupported") == .failure(.outdated)
                            && run("signedOut") == .failure(.needsSignIn) && run("unavailable") == .failure(.unreachable),
                         "old CLIs, signed-out accounts and temporary failures retain distinct outcomes")
            // After a failed fetch Claude Code answers from the copy it saved,
            // which is no new reading; one saved as it exits is.
            let saved = folder.appending(path: ".claude.json")
            func save(fetched: Date) throws {
                try JSONSerialization.data(withJSONObject: ["cachedUsageUtilization":
                    ["fetchedAtMs": fetched.timeIntervalSince1970 * 1_000, "utilization": [:] as [String: Any]]]).write(to: saved)
            }
            try save(fetched: Date().addingTimeInterval(-30 * 60))
            let seeded = run("ok")
            let checked = Date()
            let exited = try? run("saves").get()
            let recent = Date().addingTimeInterval(-5)
            try save(fetched: recent)
            let reused = try? run("ok").get()
            try? FileManager.default.removeItem(at: saved)
            suite.expect(seeded == .failure(.unreachable)
                            && (exited?.limits.observedAt).map { $0 > checked.addingTimeInterval(-1) && $0 <= Date() } == true
                            && abs((reused?.limits.observedAt ?? .distantPast).timeIntervalSince(recent)) < 0.01,
                         "an answer from Claude Code's saved copy keeps its own time and an old copy is a failure")
            let began = Date()
            suite.expect(run("silent", timeout: 0.15) == .failure(.unreachable)
                            && run("exit") == .failure(.unreachable) && Date().timeIntervalSince(began) < 2,
                         "a silent or exited CLI cannot block the caller past its bounded deadline")
            let request = AgentClaudeServer.Request()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { request.cancel() }
            let cancelling = Date()
            let cancelled = request.run(tool, home: folder, environment: ["PATH": "/usr/bin:/bin", "STAND_IN": "silent"], timeout: 10)
            suite.expect(cancelled == .failure(.unreachable) && Date().timeIntervalSince(cancelling) < 4,
                         "pause or disable closes an active CLI request rather than waiting for its full timeout")
            let missing = AgentClaudeServer.executable(home: folder, searchPath: nil)
            suite.expect(missing != tool, "CLI discovery never guesses an executable from a project folder")
            // Run the production service's source selection against an older
            // desktop sample, including after expiry and a failed refresh.
            let desktop = AgentClaudeAppUsage.historyURL(home: folder)
            try FileManager.default.createDirectory(at: desktop.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["version": 2, "samples": [["t": now.addingTimeInterval(-60).timeIntervalSince1970 * 1000,
                "org": "account", "u": ["fh": 34, "sd": 8]]]]).write(to: desktop)
            let host = Host()
            host.home = folder
            host.claudeAccountLimits = limits
            host.readClaudeApp(now: now)
            suite.expect(host.store.limits[.claude] == limits,
                         "periodic desktop reads cannot overwrite a newer account reading")
            host.readClaudeApp(now: now.addingTimeInterval(60))
            suite.expect(host.store.limits[.claude]?.observedAt == now,
                         "a failed refresh leaves the last account observation time unchanged")
            // The app saves after the last check: its latest possible renewal
            // must not trade places with the exact one, or the warning repeats.
            try JSONSerialization.data(withJSONObject: ["version": 2, "samples": [["t": now.addingTimeInterval(120).timeIntervalSince1970 * 1000,
                "org": "account", "u": ["fh": 90, "sd": 8]]]]).write(to: desktop)
            host.claudeAppModified = nil
            host.readClaudeApp(now: now.addingTimeInterval(150))
            let kept = host.store.limits[.claude]?.source == .account
            host.readClaudeApp(now: now.addingTimeInterval(AgentClaudeAppUsage.freshness + 60))
            suite.expect(kept && host.store.limits[.claude]?.source == .claudeApp,
                         "a recent account reading keeps its place when the Claude app saves a newer one")
            host.claudeAccountLimits = nil
            host.readClaudeApp(now: now)
            suite.expect(host.store.limits[.claude]?.source == .claudeApp,
                         "desktop history remains a fallback when the CLI is unavailable")
            host.enabled = []
            host.readClaudeApp(now: now)
            suite.expect(host.store.limits[.claude] == nil && host.claudeAccountLimits == nil,
                         "turning Claude off clears its account and desktop readings")
        } catch { suite.expect(false, "Claude CLI fixture: \(error)") }
    }

    /// The production reading and alert methods, replayed tick by tick over
    /// what the account and the Claude app report.
    private static func accountSelection(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = folder.appendingPathComponent(".claude.json")
        let host = Host(), now = Date()
        host.home = folder
        host.claudeOrganization = "same-organization"
        host.claudeAccountFailure = .unreachable
        host.claudeAppSamples = [.init(date: now, organization: "same-organization", used: ["sd": 40])]
        let scope = AgentWeeklyAccount.scope(identifier: "account-a", organization: "same-organization")!
        host.claudeWeeklyScope = scope
        let reading = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                             usedPercent: 30, resetsAt: now.addingTimeInterval(604_800))
        ], observedAt: now, source: .account, accountScope: scope)
        host.weeklyHistory.record(reading, now: now)
        func writeAccount(_ identifier: String, modified: Date) throws {
            try JSONSerialization.data(withJSONObject: ["oauthAccount": [
                "accountUuid": identifier, "organizationUuid": "same-organization", "organizationType": "claude_pro"
            ]]).write(to: profile)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: profile.path)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeAccount("account-a", modified: now)
            host.readClaudePlan()
            host.readClaudeApp(now: now)
            let plan = host.claudePlan, desktop = host.store.limits[.claude]
            suite.expect(host.weeklyPublications.isEmpty && desktop?.source == .claudeApp,
                         "unchanged Claude identity uses its desktop fallback without a redundant history publication")
            try writeAccount("account-b", modified: now.addingTimeInterval(1))
            host.readClaudePlan()
            host.readClaudeApp(now: now)
            suite.expect(host.claudePlan == plan && host.store.limits[.claude] == desktop,
                         "switching individuals in the same organization and plan can leave all displayed limits unchanged")
            suite.expect(host.weeklyPublications.count == 1
                         && host.weeklyPublications.last?.current(.claude) == nil
                         && host.weeklyHistory.cycles.count == 1,
                         "an identity-only Claude change publishes the new selection without exposing or deleting the old account history")
            host.readClaudePlan()
            suite.expect(host.weeklyPublications.count == 1, "an unchanged account file does not publish again")
            try FileManager.default.removeItem(at: profile)
            host.readClaudePlan()
            suite.expect(host.weeklyPublications.count == 2 && host.claudeWeeklyScope == nil,
                         "losing the Claude account file also publishes removal of its selected history")
        } catch { suite.expect(false, "Claude account-selection fixture: \(error)") }
    }

    private static func signedOutSelection(_ suite: TestSuite) {
        let host = Host(), now = Date()
        let scope = AgentWeeklyAccount.scope(identifier: "signed-out", organization: "account")!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        host.home = folder
        AgentWeeklyUsageFile.url = folder.appendingPathComponent("weekly.json")
        defer { AgentWeeklyUsageFile.url = nil }
        let profile = folder.appendingPathComponent(".claude.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: ["oauthAccount": [
            "accountUuid": "signed-out", "organizationUuid": "account", "organizationType": "claude_pro"
        ]]).write(to: profile)
        host.readClaudePlan()
        suite.expect(host.claudeWeeklyScope == scope, "the sign-out fixture starts with cached Claude identity metadata")
        let reading = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                             usedPercent: 35, resetsAt: now.addingTimeInterval(604_800))
        ], observedAt: now, source: .account, accountScope: scope)
        host.weeklyHistory.record(reading, now: now)
        suite.expect(AgentWeeklyUsageFile.save(host.weeklyHistory, to: AgentWeeklyUsageFile.url),
                     "the relaunch fixture starts with a valid private weekly archive")
        host.claudeAccountLimits = reading
        host.store.setLimits(reading)
        host.noteClaudeCheck(.unreachable)
        host.queue.sync {}
        suite.expect(host.weeklyHistory.current(.claude)?.latest?.usedPercent == 35,
                     "an inconclusive Claude check preserves its selected weekly observations")
        host.noteClaudeCheck(.needsSignIn)
        host.queue.sync {}
        suite.expect(host.weeklyHistory.current(.claude) == nil && host.weeklyHistory.cycles.count == 1
                     && host.weeklyPublications.last?.current(.claude) == nil && !host.weeklyPublications.isEmpty,
                     "a definitive Claude sign-out publishes an unselected history without deleting cycles")
        signedOutRelaunch(suite, folder: folder, reading: reading)
        host.readClaudeApp(now: now)
        for limits in host.store.limits.values { host.weeklyHistory.record(limits, now: now) }
        suite.expect(host.claudeAccountLimits == nil && host.weeklyHistory.current(.claude) == nil,
                     "a later publish cannot resurrect the signed-out account from its cached limits")
        host.readClaudePlan()
        suite.expect(host.weeklyHistory.current(.claude) == nil,
                     "an unchanged cached Claude profile cannot restore a revoked account selection")
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(2)], ofItemAtPath: profile.path)
        host.readClaudePlan()
        suite.expect(host.weeklyHistory.current(.claude) == nil,
                     "touching cached metadata cannot restore a signed-out Claude account")
        host.noteClaudeCheck(nil)
        let later = now
        let renewed = AgentLimits(provider: .claude, windows: reading.windows, observedAt: later,
                                  source: .account, accountScope: scope)
        host.queue.sync {
            host.acceptClaudeAccount(AgentClaudeServer.Summary(limits: renewed, organization: "account", accountScope: scope),
                                     session: host.session - 1)
        }
        suite.expect(host.weeklyHistory.current(.claude) == nil && host.claudeAccountLimits == nil,
                     "a response from an old reader session cannot restore signed-out Claude observations")
        host.queue.sync {
            host.acceptClaudeAccount(AgentClaudeServer.Summary(limits: renewed, organization: "account", accountScope: "different"),
                                     session: host.session)
        }
        suite.expect(host.weeklyHistory.current(.claude) == nil && host.claudeAccountLimits == nil,
                     "a response for another Claude identity cannot restore signed-out observations")
        host.queue.sync {
            host.acceptClaudeAccount(AgentClaudeServer.Summary(limits: renewed, organization: "account", accountScope: scope),
                                     session: host.session)
        }
        for limits in host.store.limits.values { host.weeklyHistory.record(limits, now: later) }
        suite.expect(host.weeklyHistory.current(.claude)?.latest?.usedPercent == 35
                     && host.weeklyHistory.current(.claude)?.samples.count == 1,
                     "a successful cached reading reselects Claude history without inventing a duplicate observation")
    }

    private static func signedOutRelaunch(_ suite: TestSuite, folder: URL, reading: AgentLimits) {
        let loaded = AgentWeeklyUsageFile.load(from: AgentWeeklyUsageFile.url)
        suite.expect(!loaded.failed && loaded.history.cycles.count == 1 && loaded.history.current(.claude) == nil,
                     "Claude sign-out is committed to the private archive before process exit")
        for failure in [AgentClaudeServer.Failure.missing, .outdated, .unreachable] {
            let relaunched = Host()
            relaunched.home = folder
            relaunched.weeklyHistory = AgentWeeklyUsageFile.load(from: AgentWeeklyUsageFile.url).history
            relaunched.weeklyHistory.selectAccount(nil, provider: .claude)
            relaunched.readClaudePlan()
            relaunched.noteClaudeCheck(failure)
            relaunched.queue.sync {}
            let cached = AgentLimits(provider: .claude, windows: reading.windows,
                                 observedAt: reading.observedAt.addingTimeInterval(1), source: .account,
                                 accountScope: reading.accountScope)
            let recorded = relaunched.weeklyHistory.record(cached, now: cached.observedAt)
            suite.expect(!recorded && relaunched.weeklyHistory.current(.claude) == nil
                         && relaunched.weeklyHistory.cycles.first?.samples.count == 1,
                         "relaunch with cached OAuth and an inconclusive check cannot restore revoked Claude history")
        }
        var expired = loaded.history
        expired.prune(now: reading.observedAt.addingTimeInterval(92 * 86_400))
        let roundTrip = try? JSONEncoder().encode(expired)
        let expiredReload = roundTrip.flatMap { try? JSONDecoder().decode(AgentWeeklyUsage.self, from: $0) }
        suite.expect(expiredReload?.cycles.isEmpty == true && expiredReload?.claudeAccountInvalidated == true,
                     "pruning the final Claude observation retains only its non-identifying sign-out marker")
        let unidentified = Host()
        unidentified.home = folder.appendingPathComponent("without-identity")
        unidentified.weeklyHistory = loaded.history
        unidentified.queue.sync {
            unidentified.acceptClaudeAccount(AgentClaudeServer.Summary(limits: reading, organization: nil, accountScope: nil),
                                              session: unidentified.session)
        }
        unidentified.weeklyHistory.selectAccount(reading.accountScope, provider: .claude)
        suite.expect(unidentified.weeklyHistory.current(.claude) == nil
                     && unidentified.weeklyHistory.claudeAccountInvalidated == true,
                     "an unidentified successful response cannot lift invalidation or allow cached identity to select history")
        let recovered = Host()
        recovered.home = folder
        recovered.weeklyHistory = loaded.history
        recovered.readClaudePlan()
        for (session, scope) in [(recovered.session - 1, reading.accountScope), (recovered.session, "different")] {
            recovered.queue.sync {
                recovered.acceptClaudeAccount(AgentClaudeServer.Summary(limits: reading, organization: "account", accountScope: scope),
                                              session: session)
            }
        }
        suite.expect(AgentWeeklyUsageFile.load(from: AgentWeeklyUsageFile.url).history.current(.claude) == nil,
                     "old-session and different-identity successes cannot lift persisted Claude invalidation")
        recovered.queue.sync {
            recovered.acceptClaudeAccount(AgentClaudeServer.Summary(limits: reading, organization: "account",
                                                                    accountScope: reading.accountScope), session: recovered.session)
        }
        let restored = AgentWeeklyUsageFile.load(from: AgentWeeklyUsageFile.url)
        suite.expect(!restored.failed && restored.history.current(.claude)?.samples.count == 1,
                     "identified success with the same timestamp durably restores selection without duplicating samples")
        let nextLaunch = Host()
        nextLaunch.home = folder
        nextLaunch.weeklyHistory = restored.history
        nextLaunch.weeklyHistory.selectAccount(nil, provider: .claude)
        nextLaunch.readClaudePlan()
        suite.expect(nextLaunch.weeklyHistory.current(.claude)?.samples.count == 1,
                     "a subsequent launch can select cached metadata after the validated recovery was saved")
        let savedURL = AgentWeeklyUsageFile.url
        let corrupt = folder.appendingPathComponent("corrupt-weekly.json")
        let bytes = Data("{broken".utf8)
        try? bytes.write(to: corrupt)
        AgentWeeklyUsageFile.url = corrupt
        defer { AgentWeeklyUsageFile.url = savedURL }
        nextLaunch.noteClaudeCheck(.needsSignIn)
        nextLaunch.queue.sync {}
        suite.expect(nextLaunch.weeklySaveFailed && nextLaunch.weeklyHistory.current(.claude) == nil
                     && nextLaunch.weeklyHistory.cycles.count == 1 && (try? Data(contentsOf: corrupt)) == bytes,
                     "failed sign-out persistence leaves memory invalidated, reports failure, and preserves a corrupt archive")
    }

    private static func alerts(_ suite: TestSuite) {
        let at = { (time: String) in AgentTimestamp.parse(time)! }
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorssaint-claude-alerts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let desktop = AgentClaudeAppUsage.historyURL(home: folder)
        func host() -> Host {
            let host = Host()
            host.home = folder
            host.store.reportsTransitions = true
            return host
        }
        func account(_ used: Double, resets: String, at observed: String) -> AgentLimits {
            AgentLimits(provider: .claude, windows: [AgentLimitWindow(id: "claude.fh", kind: .session, minutes: 300, scope: nil,
                                                                       usedPercent: used, resetsAt: at(resets))],
                        observedAt: at(observed), source: .account)
        }
        // One tick: what the Claude app saved and Claude Code answered so far.
        func tick(_ host: Host, _ time: String, app samples: [(String, [String: Any])]? = nil,
                  account reading: AgentLimits? = nil) throws {
            if let samples {
                try JSONSerialization.data(withJSONObject: ["version": 2, "samples": samples.map { sample, used in
                    ["t": at(sample).timeIntervalSince1970 * 1_000, "org": "account", "u": used] }]).write(to: desktop)
                host.claudeAppModified = nil
            }
            if let reading { host.claudeAccountLimits = reading }
            host.clock = at(time)
            host.readClaudeApp(now: at(time))
            host.checkLimits()
            host.reportRenewals(now: at(time))
        }
        do {
            try FileManager.default.createDirectory(at: desktop.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The session began at 02:40 and renews at 07:40. The Claude app's
            // readings place its start no later than 02:47, so the latest it
            // can renew is 07:47.
            let opened: [(String, [String: Any])] = [("2026-10-15T02:35:00Z", ["fh": 0]), ("2026-10-15T02:47:00Z", ["fh": 4])]
            let handover = host()
            try tick(handover, "2026-10-15T06:50:30Z", app: opened,
                     account: account(70, resets: "2026-10-15T07:40:00Z", at: "2026-10-15T06:50:00Z"))
            try tick(handover, "2026-10-15T07:00:30Z", account: account(92, resets: "2026-10-15T07:40:00Z", at: "2026-10-15T07:00:00Z"))
            // Claude Code stops answering, and half an hour on the app's reading takes over.
            try tick(handover, "2026-10-15T07:31:30Z", app: opened + [("2026-10-15T07:31:00Z", ["fh": 95])])
            try tick(handover, "2026-10-15T07:40:30Z")
            // Another Mac spent most of the next session before this one looked again.
            try tick(handover, "2026-10-15T07:50:30Z", account: account(85, resets: "2026-10-15T12:50:00Z", at: "2026-10-15T07:50:00Z"))
            suite.expect(handover.events == ["warning claude.fh 2026-10-15T07:00:30Z", "reset claude.fh 2026-10-15T07:40:30Z",
                                             "warning claude.fh 2026-10-15T07:50:30Z"],
                         "the Claude app taking over a warned session warns no more, renews at the account's time and warns after a real renewal")
            // At launch the app's reading is the baseline; the account answers
            // with the exact renewal, then the app takes over again.
            let launched = host()
            try tick(launched, "2026-10-15T07:01:30Z", app: opened + [("2026-10-15T07:01:00Z", ["fh": 92])])
            try tick(launched, "2026-10-15T07:02:30Z", account: account(92, resets: "2026-10-15T07:40:00Z", at: "2026-10-15T07:02:00Z"))
            try tick(launched, "2026-10-15T07:33:00Z", app: opened + [("2026-10-15T07:01:00Z", ["fh": 92]),
                                                                       ("2026-10-15T07:32:00Z", ["fh": 96])])
            suite.expect(launched.events.isEmpty,
                         "a session past the threshold at launch stays quiet whichever source reads it")
            // #3114's banked history: two weeks renew on Saturday, then a reset
            // used on Wednesday empties the warned week, which keeps its
            // Saturday renewal. The drop is the news, once.
            let weeks: [(String, [String: Any])] = [
                ("2026-09-19T11:56:00Z", ["sd": 100]), ("2026-09-19T12:01:00Z", ["sd": 0]),
                ("2026-09-26T11:56:00Z", ["sd": 100]), ("2026-09-26T12:01:00Z", ["sd": 0]),
                ("2026-10-01T08:48:00Z", ["sd": 100]), ("2026-10-01T08:53:00Z", ["sd": 0]),
                ("2026-10-01T10:00:00Z", ["fh": 5, "sd": 4])]
            let banked = host()
            for count in 4...weeks.count {
                try tick(banked, ISO8601DateFormatter().string(from: at(weeks[count - 1].0).addingTimeInterval(30)),
                         app: Array(weeks.prefix(count)))
            }
            for time in ["2026-10-02T12:00:00Z", "2026-10-03T11:59:00Z", "2026-10-03T12:00:30Z", "2026-10-03T13:00:00Z"] {
                try tick(banked, time)
            }
            suite.expect(banked.events == ["warning claude.sd 2026-10-01T08:48:30Z", "reset claude.sd 2026-10-01T08:53:30Z"],
                         "a reset used mid-week renews a warned week at the drop, not again at the renewal it kept")
            // A session began on another device at 01:30 while the Mac slept.
            // The Claude app's readings place its end no later than 10:00, and
            // Claude Code answers only after the next session began at 06:30.
            let slept = host()
            let night: [(String, [String: Any])] = [("2026-10-15T01:00:00Z", ["fh": 0])]
            try tick(slept, "2026-10-15T01:00:30Z", app: night)
            try tick(slept, "2026-10-15T05:00:30Z", app: night + [("2026-10-15T05:00:00Z", ["fh": 85])])
            try tick(slept, "2026-10-15T07:00:30Z", account: account(90, resets: "2026-10-15T11:30:00Z", at: "2026-10-15T07:00:00Z"))
            for time in ["2026-10-15T10:00:30Z", "2026-10-15T11:30:30Z"] { try tick(slept, time) }
            suite.expect(slept.events == ["warning claude.fh 2026-10-15T05:00:30Z", "warning claude.fh 2026-10-15T07:00:30Z",
                                          "reset claude.fh 2026-10-15T11:30:30Z"],
                         "a session that began after the last reading warns, and the one before it does not renew over it")
        } catch { suite.expect(false, "Claude alert fixture: \(error)") }
    }

    /// The production schedule for Claude Code's checks, run without one.
    private static func checks(_ suite: TestSuite) {
        defer { NotchAgentSupport.used = true }
        let host = Host()
        var now = Date(timeIntervalSince1970: 2_000_000)
        func wait() -> TimeInterval {
            (1...180).map { TimeInterval($0) * 60 }.first { host.claudeLimitsDue(at: now + $0, pageShows: false) } ?? -1
        }
        // A setup that never answers, such as one whose proxy Claude Code cannot see.
        var waits: [TimeInterval] = []
        for _ in 0..<5 {
            host.claudeAccountAttempted = now
            host.noteClaudeCheck(.unreachable)
            waits.append(wait())
            now += waits.last ?? 0
        }
        suite.expect(waits == [300, 600, 1_200, 1_800, 1_800],
                     "Claude Code that never answers is asked less and less often, down to every half hour")
        // Another check fails as the network goes.
        host.claudeAccountAttempted = now
        host.noteClaudeCheck(.unreachable)
        host.networkChanged(online: false)
        let offline = !host.claudeLimitsDue(at: now + 86_400, pageShows: true)
        host.networkChanged(online: true)
        suite.expect(offline && wait() == 300, "nothing asks Claude Code while the Mac is offline, and back online the wait starts over")
        for _ in 0..<3 { host.noteClaudeCheck(.unreachable) }
        host.noteClaudeCheck(nil)
        host.noteClaudeCheck(.unreachable)
        suite.expect(wait() == 300, "an answer starts the wait over")
        host.noteClaudeCheck(nil)
        NotchAgentSupport.used = false
        let unused = !host.claudeLimitsDue(at: now + 86_400, pageShows: false)
        let shown = host.claudeLimitsDue(at: now + 86_400, pageShows: true)
        host.pageVisible = true
        suite.expect(unused && shown && host.claudeLimitsDue(at: now + 86_400, pageShows: false),
                     "Claude Code is not asked while nothing shows or alerts on the limits, and the page's Limits card counts")
    }

    private static func preview(_ suite: TestSuite) {
        let host = Host()
        host.pageDidAppear(preview: true)
        host.queue.sync {}
        suite.expect(host.refreshRequests.isEmpty && !host.pageVisible && host.weeklyPublications.count == 1,
                     "Settings preview reads local state without triggering a Claude account refresh")
        host.pageDidAppear()
        host.queue.sync {}
        suite.expect(host.refreshRequests == [true] && host.pageVisible,
                     "the actual AI page still requests its regular Claude account refresh")
        host.pageDidAppear(preview: true)
        host.queue.sync {}
        suite.expect(host.refreshRequests == [true] && host.pageVisible && host.weeklyPublications.count == 3,
                     "a concurrent Settings preview neither adds a request nor deactivates the real AI page")
        host.pageDidDisappear()
        host.running = false
        host.pageDidAppear(preview: true)
        host.queue.sync {}
        suite.expect(host.refreshRequests == [true] && !host.pageVisible && host.weeklyPublications.count == 3,
                     "a preview cannot start a stopped account service")
    }

    /// Where people install Claude Code, each in a home of its own, with
    /// stand-ins that only exit.
    private static func discovery(_ suite: TestSuite) {
        func home() throws -> URL {
            let home = FileManager.default.temporaryDirectory.appending(path: "vorssaint-claude-install-\(UUID())")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            return home
        }
        func make(_ relative: String, in home: URL, _ script: String = "#!/bin/sh\nexit 0\n") throws {
            let file = home.appending(path: relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(script.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        // Only what is in the home: the Mac running the tests may have its own Claude Code.
        func found(_ home: URL) -> [String] {
            AgentClaudeServer.candidates(home: home).map(\.path)
                .filter { $0.hasPrefix(home.path + "/") && FileManager.default.isExecutableFile(atPath: $0) }
                .map { String($0.dropFirst(home.path.count + 1)) }
        }
        let layouts = [".volta/bin/claude", "Library/Application Support/fnm/aliases/default/bin/claude",
                       ".local/share/fnm/node-versions/v22.3.0/installation/bin/claude",
                       ".nvm/versions/node/v22.3.0/bin/claude", ".asdf/installs/nodejs/22.3.0/bin/claude",
                       ".local/share/mise/installs/node/22.3.0/bin/claude", ".bun/bin/claude", "Library/pnpm/claude",
                       ".npm-global/bin/claude"]
        var homes: [URL] = []
        defer { homes.forEach { try? FileManager.default.removeItem(at: $0) } }
        do {
            var missed: [String] = []
            for layout in layouts {
                let home = try home()
                homes.append(home)
                try make(layout, in: home)
                if found(home) != [layout] { missed.append(layout) }
            }
            suite.expect(missed.isEmpty, "Claude Code is found where version managers, Bun and pnpm keep it: missed \(missed)")
            let several = try home()
            homes.append(several)
            for version in ["v9.11.2", "v22.3.0", "v20.11.0"] { try make(".nvm/versions/node/\(version)/bin/claude", in: several) }
            // The Claude app's own copy has no sign-in of its own to check with.
            let bundled = "Library/Application Support/Claude/claude-code/2.1.299/4fa9694b7975"
            try make(bundled + "/claude.app/Contents/MacOS/claude", in: several)
            try make(bundled + "/.verified", in: several, "")
            let ordered = found(several)
            try make(".local/bin/claude", in: several)
            suite.expect(ordered == [".nvm/versions/node/v22.3.0/bin/claude", ".nvm/versions/node/v20.11.0/bin/claude",
                                     ".nvm/versions/node/v9.11.2/bin/claude"]
                            && found(several).first == ".local/bin/claude",
                         "the newest Node's Claude Code comes first, the person's own install before it, and never the Claude app's copy")
            // ~/.claude/local runs on Node, which may live only in a version manager.
            let local = try home()
            homes.append(local)
            try make(".claude/local/claude", in: local, "#!/usr/bin/env node\n")
            try make(".nvm/versions/node/v22.3.0/bin/node", in: local, "#!/bin/sh\nshift\nexec /bin/sh \"$HOME/stand-in\" \"$@\"\n")
            try Data(standIn.utf8).write(to: local.appending(path: "stand-in"))
            // Only the stand-in in this home ever runs, never a Claude Code of the Mac's.
            let tool = AgentClaudeServer.executable(home: local).flatMap { $0.path.hasPrefix(local.path + "/") ? $0 : nil }
            // Without Homebrew's folders, which may hold a Node of the Mac's.
            let path = AgentClaudeServer.searchPath(after: "/usr/bin:/bin", home: local)
            let answer = tool.map { tool in
                AgentClaudeServer.Request().run(tool, home: local,
                    environment: ["PATH": path, "HOME": local.path, "STAND_IN": "ok"], timeout: 5)
            }
            suite.expect(tool?.path.hasSuffix("/.claude/local/claude") == true
                            && (try? answer?.get())?.limits.windows.isEmpty == false && path.hasPrefix("/usr/bin:/bin:"),
                         "a Claude Code in ~/.claude/local runs on the Node a version manager keeps, after the system's tools")
        } catch { suite.expect(false, "Claude Code install fixture: \(error)") }
        let failures: [AgentClaudeServer.Failure] = [.missing, .needsSignIn, .outdated, .unreachable]
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            Set(failures.map { FeatureStrings.notchAgents(language).claudeCode($0) }).count == failures.count
        }, "Settings says in every language why Claude Code could not check")
    }

    private static let standIn = #"""
    #!/bin/sh
    [ -z "$CLAUDECODE" ] && [ "$DISABLE_AUTOUPDATER" = 1 ] || exit 2
    [ "$1" = "--print" ] && [ "$2" = "--input-format" ] && [ "$3" = "stream-json" ] || exit 2
    flags="$*"
    case "$flags" in *'--no-session-persistence --tools  --strict-mcp-config --mcp-config {"mcpServers":{}} --setting-sources  --settings {"disableAllHooks":true}'*) ;; *) exit 2 ;; esac
    [ "$STAND_IN" = exit ] && exit 0
    while IFS= read -r line; do
      [ "$STAND_IN" = silent ] && continue
      case "$line" in
        *'"subtype":"initialize"'*)
          printf '%s\n' '{"type":"system","subtype":"status"}' '{"type":"control_response","response":{"subtype":"success","request_id":"initialize","response":{}}}' ;;
        *'"subtype":"get_usage"'*)
          case "$line" in *'"skip_behaviors":true'*) ;; *) exit 3 ;; esac
          case "$STAND_IN" in
            old) printf '%s\n' '{"type":"control_response","response":{"subtype":"error","request_id":"usage","error":"get_usage is not supported in this context"}}' ;;
            unsupported) printf '%s\n' '{"type":"control_response","response":{"subtype":"error","request_id":"usage","error":"Unsupported control request subtype: get_usage"}}' ;;
            signedOut) printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":false,"rate_limits":null}}}' ;;
            unavailable) printf '%s\n' '{"type":"control_response","response":{"subtype":"error","request_id":"usage","error":"temporary failure"}}' ;;
            *) printf '%s\n' 'not json' '{"type":"control_response","response":{"subtype":"success","request_id":"other","response":{}}}' \
              '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":100,"resets_at":"2099-10-15T10:40:00Z"},"seven_day":{"utilization":9,"resets_at":"2099-10-17T23:00:00Z"}}}}}' ;;
          esac ;;
        *) exit 4 ;;
      esac
    done
    # Saves what it fetched on its way out.
    [ "$STAND_IN" = saves ] && printf '{"cachedUsageUtilization":{"fetchedAtMs":%s000}}\n' "$(date +%s)" > "$HOME/.claude.json"
    """#
}
