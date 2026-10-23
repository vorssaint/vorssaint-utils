// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum ClaudeSeatTests {
    static func run(_ suite: TestSuite) {
        strings(suite)
        profiles(suite)
        checks(suite)
        sessions(suite)
        layout(suite)
        resting(suite)
    }

    private static let now = AgentTimestamp.parse("2026-10-23T09:00:00Z")!

    private static func limits(_ used: Double, resets: String? = "2026-10-23T11:30:00Z",
                               observed: Date = now) -> AgentLimits {
        AgentLimits(provider: .claude, windows: [AgentLimitWindow(
            id: "claude.fh", kind: .session, minutes: 300, scope: nil, usedPercent: used,
            resetsAt: resets.flatMap(AgentTimestamp.parse))], observedAt: observed, source: .account)
    }

    private static func seat(_ id: String, account: String, used: Double?, active: Bool = false) -> ClaudeSeat {
        ClaudeSeat(id: id, directory: "/tmp/.claude-\(id)", account: account, organization: "org",
                   email: "\(id)@example.com", plan: "Team", limits: used.map { limits($0) }, active: active)
    }

    private static func strings(_ suite: TestSuite) {
        let english = Mirror(reflecting: FeatureStrings.claudeSeats(.enUS)).children.count
        for language in AppLanguage.allCases {
            let text = Mirror(reflecting: FeatureStrings.claudeSeats(language)).children.compactMap { $0.value as? String }
            suite.expect(text.count == english && text.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "every Claude seat string is written in \(language.rawValue)")
            suite.expect(FeatureStrings.claudeSeats(language).checked("x").contains("x"),
                         "the check time shows in \(language.rawValue)")
        }
        let informal: [AppLanguage: String] = [
            .ru: #"(?i)\b(выбери|войди|обнови|попробуй|ты|тебе|тебя|твой|твоя)\b"#,
            .uk: #"(?i)\b(вибери|увійди|онови|спробуй|ти|тобі|тебе|твій|твоя)\b"#]
        for (language, pattern) in informal {
            let text = Mirror(reflecting: FeatureStrings.claudeSeats(language)).children.compactMap { $0.value as? String }
            suite.expect(text.allSatisfy { $0.range(of: pattern, options: .regularExpression) == nil },
                         "Claude seat text uses the formal register in \(language.rawValue)")
        }
    }

    private static func profiles(_ suite: TestSuite) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("claude-seats-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            func folder(_ name: String, account: String?) throws {
                let directory = root.appendingPathComponent(name)
                try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var profile: [String: Any] = ["numStartups": 3]
                if let account {
                    profile["oauthAccount"] = ["accountUuid": account, "organizationUuid": "org",
                                               "emailAddress": "\(account)@example.com", "organizationType": "claude_team"]
                }
                try JSONSerialization.data(withJSONObject: profile).write(to: directory.appendingPathComponent(".claude.json"))
            }
            try folder(".claude-seat2", account: "b")
            try folder(".claude-seat1", account: "a")
            try folder(".claude-signedout", account: nil)
            try folder(".codex-work", account: "c")
            try folder(".claude", account: "usual")
            let found = ClaudeSeatProfile.discover(home: root)
            suite.expect(found.map { URL(fileURLWithPath: $0.directory).lastPathComponent } == [".claude-seat1", ".claude-seat2"],
                         "only signed-in .claude-* folders are found as seats, in name order, never the usual profile")
            let identity = ClaudeSeatIdentity.read(root.appendingPathComponent(".claude-seat1/.claude.json"))
            suite.expect(identity?.account == "a" && identity?.organization == "org" && identity?.email == "a@example.com"
                            && identity?.plan?.name == "Team",
                         "a seat's account, organization, email and plan come from its profile")
            let encoded = ClaudeSeatProfile.encode(found)
            suite.expect(ClaudeSeatProfile.decode(encoded) == found
                            && ClaudeSeatProfile.decode(ClaudeSeatProfile.encode(found + found)) == found
                            && ClaudeSeatProfile.decode("[{\"id\":\"x\",\"directory\":\"/tmp\"}]").isEmpty
                            && ClaudeSeatProfile.decode("nonsense").isEmpty,
                         "saved seats round-trip once each, and malformed entries are dropped")
            suite.expect(ClaudeSeatProfile.signInCommand(existing: found, home: root)
                            == "CLAUDE_CONFIG_DIR=~/.claude-seat3 claude auth login",
                         "a new seat signs in to the next free folder")
            try manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.appendingPathComponent(".claude-seat2").path)
            suite.expect(ClaudeSeatProfile(id: UUID().uuidString, directory: root.appendingPathComponent(".claude-seat2").path)
                            .canonicalDirectory == nil,
                         "a folder others can write to is never a seat")
        } catch { suite.expect(false, "Claude seat profiles: \(error)") }
    }

    private static func checks(_ suite: TestSuite) {
        let folder = URL(fileURLWithPath: "/tmp/.claude-seat1")
        let location = AgentClaudeServer.Location.seat(folder)
        let environment = AgentClaudeServer.environment(["CLAUDE_CONFIG_DIR": "/elsewhere", "CLAUDECODE": "1"],
                                                        location: location)
        suite.expect(environment["CLAUDE_CONFIG_DIR"] == folder.path && environment["CLAUDECODE"] == nil
                        && location.profile.path == "/tmp/.claude-seat1/.claude.json"
                        && location.settings.path == "/tmp/.claude-seat1/settings.json",
                     "a seat's check runs Claude Code on the seat's own folder, profile and settings")
        let usual = AgentClaudeServer.environment(["CLAUDE_CONFIG_DIR": "/elsewhere"],
                                                  home: URL(fileURLWithPath: "/tmp/home"))
        suite.expect(usual["CLAUDE_CONFIG_DIR"] == nil, "the usual check never inherits another profile's folder")

        let profile: [String: Any] = [
            "oauthAccount": ["accountUuid": "a", "organizationUuid": "org"],
            "cachedUsageUtilization": ["accountUuid": "a", "fetchedAtMs": now.timeIntervalSince1970 * 1_000 - 30_000,
                                       "utilization": ["five_hour": ["utilization": 64, "resets_at": "2026-10-23T11:30:00Z"],
                                                       "seven_day": NSNull()]]]
        let cache = AgentClaudeServer.cache(profile, now: now)
        suite.expect(cache?.limits.windows.map(\.usedPercent) == [64] && cache?.organization == "org",
                     "a seat's saved usage reads its session and skips the weeks a Team seat lacks")
        var other = profile
        other["oauthAccount"] = ["accountUuid": "b", "organizationUuid": "org"]
        suite.expect(AgentClaudeServer.cache(other, now: now) == nil,
                     "saved usage of another account than the one signed in is never shown")
    }

    private static func sessions(_ suite: TestSuite) {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent("claude-app-" + UUID().uuidString)
        defer { try? manager.removeItem(at: home) }
        do {
            let app = ClaudeAppAccounts.folder(home: home)
            func session(account: String, organization: String, id: String) throws {
                let folder = app.appending(path: "claude-code-sessions/\(account)/\(organization)")
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: ["cliSessionId": id, "title": "x"])
                    .write(to: folder.appending(path: "local_\(UUID().uuidString).json"))
            }
            try session(account: "a", organization: "org", id: "s1")
            try session(account: "b", organization: "org", id: "s2")
            try session(account: "b", organization: "personal", id: "s3")
            try JSONSerialization.data(withJSONObject: ["lastKnownAccountUuid": "b", "other": 1])
                .write(to: app.appending(path: "config.json"))
            let index = ClaudeAppAccounts.SessionIndex(home: home)
            index.refresh(for: [ClaudeAppAccounts.Owner(account: "a", organization: "org"),
                                ClaudeAppAccounts.Owner(account: "b", organization: "org")])
            suite.expect(index.owner(of: "s1")?.account == "a" && index.owner(of: "/logs/p/s2.jsonl")?.account == "b"
                            && index.owner(of: "s3") == nil,
                         "the app's sessions map to the seat they ran under, by id or log path, and only for the plan's organization")
            suite.expect(ClaudeAppAccounts.signedIn(home: home) == "b", "the Claude app's account comes from its config")
        } catch { suite.expect(false, "Claude app sessions: \(error)") }

        var snapshot = AgentUsageSnapshot()
        snapshot.claudeSeats = [seat("one", account: "a", used: 64), seat("two", account: "b", used: 96, active: true)]
        let app = AgentLiveSession(id: "/p/s1.jsonl", provider: .claude, started: now, lastActivity: now, model: "",
                                   project: "", tokens: AgentTokens(), cost: 0, place: .app)
        let unknown = AgentLiveSession(id: "/p/s9.jsonl", provider: .claude, started: now, lastActivity: now, model: "",
                                       project: "", tokens: AgentTokens(), cost: 0, place: .app)
        let terminal = AgentLiveSession(id: "/p/t.jsonl", provider: .claude, started: now, lastActivity: now, model: "",
                                        project: "", tokens: AgentTokens(), cost: 0, place: .terminal)
        snapshot.claudeLiveSeats = [app.id: "one"]
        suite.expect(snapshot.claudeSeat(for: app)?.id == "one" && snapshot.claudeSeat(for: unknown)?.id == "two"
                        && snapshot.claudeSeat(for: terminal) == nil && snapshot.activeClaudeSeat?.id == "two",
                     "an app session shows its own seat, an unknown one the active seat, and a terminal one none")
        snapshot.limits[.claude] = limits(10)
        snapshot.live = [app]
        suite.expect(NotchAgentSupport.workingLimits(snapshot, provider: .claude)?.windows.first?.usedPercent == 64,
                     "the working ring shows the seat the app session runs under")
        snapshot.live = [terminal]
        suite.expect(NotchAgentSupport.workingLimits(snapshot, provider: .claude)?.windows.first?.usedPercent == 96,
                     "a terminal session reads Claude's one reading, the active seat's")
        snapshot.live = [app]
        suite.expect(NotchAgentSupport.stripReading(snapshot, readout: .limit, display: .used, now: now) == "64%"
                        && NotchAgentSupport.stripReading(snapshot, readout: .elapsed, display: .used, now: now) == "0:00",
                     "the strip's reading follows the same seat as its ring, and elapsed time stays time")
    }

    private static func layout(_ suite: TestSuite) {
        let cards = NotchAgentSupport.orderedCards("", claudeSeats: true).filter { !$0.retired }
        suite.expect(Array(cards.prefix(6)) == [.limits, .spend, .projects, .trend, .resets, .activity]
                        && NotchAgentSupport.orderedCards("", claudeSeats: false).prefix(3) == [.limits, .spend, .trend]
                        && NotchAgentSupport.orderedCards("trend,spend", claudeSeats: true).prefix(2) == [.trend, .spend],
                     "with seats a new page pairs Spending with Codex, Projects with Trend and Resets with Activity, and a saved order is kept")
        let tiles = NotchAgentSupport.tiles(cards: [.limits, .trend, .spend, .projects, .resets, .activity],
                                            providers: [.claude, .codex], claudeUsesAPI: true, claudeSeats: 2)
        let rows = NotchAgentSupport.rows(tiles, width: 600)
        suite.expect(rows.map { $0.map(\.card) } == [[.limits], [.limits, .trend], [.spend, .projects], [.resets, .activity]]
                        && rows[0].first?.claudeSeats == true && rows[0].first?.seatsShowAPI == true
                        && rows[0].first?.seatCount == 2 && !tiles.contains(where: \.claudeAPI)
                        && rows[1].first?.provider == .codex && Set(tiles.map(\.id)).count == tiles.count,
                     "seats take the first row with the API key's figures in its header, Codex pairs with Trend and Resets with Activity")
        suite.expect(NotchAgentSupport.height(of: rows[0], width: 600) == NotchAgentSupport.seatsBaseHeight + NotchAgentSupport.seatRowHeight
                        && NotchAgentSupport.height(of: rows[0], width: 360)
                            == NotchAgentSupport.stackedSeatsBaseHeight + 2 * NotchAgentSupport.stackedSeatHeight
                                + NotchAgentSupport.stackedAPILineHeight
                        && NotchAgentSupport.height(of: rows[1], width: 600) == NotchAgentSupport.sessionCardHeight
                        && NotchAgentSupport.height(of: rows[3], width: 600) == NotchAgentSupport.pairedActivityHeight
                        && rows[3].allSatisfy { !$0.fullWidth }
                        && NotchAgentSupport.rows(tiles, width: 360).allSatisfy { $0.count == 1 },
                     "the seats' row and its pairs have room for what they show, and a narrow page stacks every card")
        suite.expect(NotchAgentSupport.seatColumns(3, width: 504) == 3 && NotchAgentSupport.seatColumns(3, width: 420) == 2
                        && NotchAgentSupport.seatColumns(3, width: 360) == 1 && NotchAgentSupport.seatColumns(1, width: 600) == 1
                        && NotchAgentSupport.seatColumns(4, width: 504) == 2
                        && NotchAgentSupport.seatsCardHeight(3, width: 504, api: true)
                            == NotchAgentSupport.seatsCardHeight(2, width: 504, api: true)
                        && NotchAgentSupport.seatsCardHeight(3, width: 420, api: true)
                            == NotchAgentSupport.seatsBaseHeight + 2 * NotchAgentSupport.seatRowHeight,
                     "three seats share one row where they fit and go two and one where they do not")
        suite.expect(NotchAgentSupport.tiles(cards: [.limits], providers: [.claude], claudeUsesAPI: false, claudeSeats: 2)
                        .map(\.seatsShowAPI) == [false],
                     "the API key's figures show only when an API key pays for Claude Code")
        let without = NotchAgentSupport.tiles(cards: [.limits, .trend, .spend], providers: [.claude, .codex],
                                              claudeUsesAPI: true)
        suite.expect(without.first?.splitsBilling == true && without.first(where: { $0.card == .trend })?.fullWidth == true
                        && NotchAgentSupport.tiles(cards: [.activity], providers: [.claude]).first?.fullWidth == true
                        && NotchAgentSupport.tiles(cards: [.limits], providers: [.codex], claudeSeats: 2).allSatisfy { !$0.claudeSeats },
                     "without seats, or without Claude, the page is today's")
    }

    private static func resting(_ suite: TestSuite) {
        var snapshot = AgentUsageSnapshot()
        snapshot.claudeSeats = [seat("one", account: "a", used: 64, active: true), seat("two", account: "b", used: 96),
                                seat("three", account: "c", used: nil)]
        snapshot.limits[.claude] = limits(64)
        snapshot.limits[.codex] = AgentLimits(provider: .codex, windows: [AgentLimitWindow(
            id: "codex.primary", kind: .session, minutes: 300, scope: nil, usedPercent: 20, resetsAt: nil)],
            observedAt: now, source: .account)
        let cycle = NotchAgentSupport.restingSequence(snapshot, layout: .cycle, providers: AgentProvider.allCases,
                                                      hidden: [], focus: .session, now: now)
        suite.expect(cycle.map(\.id) == ["claude.two", "claude.one", "codex"]
                        && cycle.first?.email == "two@example.com" && cycle.first?.window.usedPercent == 96,
                     "Rotate shows each seat in turn, the most spent first, and Codex after them")
        let single = NotchAgentSupport.restingSequence(snapshot, layout: .single, providers: AgentProvider.allCases,
                                                       hidden: [], focus: .session, now: now)
        suite.expect(single.map(\.id) == ["claude.one"] && single.first?.seat == "one",
                     "Single shows the seat the Claude app is signed in to")
        let hidden = NotchAgentSupport.restingSequence(snapshot, layout: .cycle, providers: AgentProvider.allCases,
                                                       hidden: [.claude], focus: .session, now: now)
        suite.expect(hidden.map(\.id) == ["codex"], "leaving Claude out at rest leaves out every seat")
        let speech = NotchAgentSupport.restingSpeech(Array(cycle.prefix(1)), used: true,
                                                     text: FeatureStrings.notchAgents(.enUS), locale: Locale(identifier: "en_US"),
                                                     now: now)
        suite.expect(speech.hasPrefix("Claude · two@example.com:"), "VoiceOver names the seat a meter belongs to")
    }
}
