// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentMeterSessionTests {
    static func run(_ suite: TestSuite) {
        discovery(suite)
        phases(suite)
        cursorLog(suite)
        cursorProject(suite)
        cursorUsage(suite)
        meterDetail(suite)
        meterSignIn(suite)
        commands(suite)
        quota(suite)
        attention(suite)
    }

    private static func meterDetail(_ suite: TestSuite) {
        let now = Date()
        let live = [AgentLiveSession(id: "1", provider: .cursor, started: now.addingTimeInterval(-30),
                                     lastActivity: now, model: "", project: "demo-app", tokens: AgentTokens(), cost: 0)]
        let limits = AgentLimits(provider: .cursor, windows: [
            AgentLimitWindow(id: "plan", kind: .weekly, minutes: nil, scope: nil, usedPercent: 45,
                             resetsAt: now.addingTimeInterval(3_600))
        ], observedAt: now, source: .account)
        let text = NotchAgentSupport.meterDetail(provider: .cursor, live: live, waiting: true,
                                                 reason: "Ship it?", limits: limits, now: now)
        let strings = FeatureStrings.notchAgents(.enUS)
        suite.expect(text.contains("Cursor") && text.contains(strings.waitingReason("Ship it?"))
                        && text.contains("demo-app") && text.contains("used") && text.contains("resets"),
                     "hover text carries state, reason, project, plan use and reset")
        suite.expect(NotchAgentSupport.meterDetail(provider: .claude, live: [], waiting: true, reason: nil)
                        .contains(strings.waitingForYou),
                     "waiting without a reason still says so")
    }

    private static func meterSignIn(_ suite: TestSuite) {
        suite.expect(AgentMeterAccounts.requiresSignIn(.cursor) && AgentMeterAccounts.requiresSignIn(.claude)
                        && !AgentMeterAccounts.requiresSignIn(.opencode),
                     "the meter trio needs a session; local tools do not")
        suite.expect(AgentMeterAccounts.showsInUI(.opencode, signedIn: [])
                        && !AgentMeterAccounts.showsInUI(.cursor, signedIn: []),
                     "rings and live UI hide unsigned meter assistants")
    }

    private static func discovery(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "vorss-agent-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let work = home.appending(path: ".claude-work/projects")
        let empty = home.appending(path: ".codex-empty")
        let transcript = home.appending(path: ".cursor/projects/demo/agent-transcripts/abc/abc.jsonl")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: transcript.path, contents: Data("{}\n".utf8))

        let roots = AgentLogRoot.all(home: home)
        let claudeWork = roots.filter { $0.account == AgentAccount(provider: .claude, slug: "work") }
        suite.expect(claudeWork.count == 1 && claudeWork[0].url.path == work.path,
                     "a .claude-work folder with projects is its own Claude account")
        suite.expect(!roots.contains { $0.account.slug == "empty" },
                     "an extra Codex folder without sessions is not an account")
        suite.expect(roots.contains { $0.provider == .cursor && $0.account.slug.isEmpty },
                     "Cursor transcripts are a discovered root")
        let found = AgentLogReader.discover(roots.filter { $0.provider == .cursor }, since: .distantPast)
        suite.expect(found.map(\.path) == [transcript.path] && found.first?.provider == .cursor,
                     "discovery returns the Cursor transcript and not the rest of the project tree")
    }

    private static func phases(_ suite: TestSuite) {
        var phase = AgentMeterPhase()
        phase.apply(.tool("Bash"))
        suite.expect(phase.phase == .working, "an ordinary tool is working")
        phase.apply(.tool("AskUserQuestion"))
        suite.expect(phase.phase == .waiting, "Claude's question waits")
        phase.apply(.toolResult)
        suite.expect(phase.phase == .working, "an answer returns to working")
        phase.apply(.tool("AskQuestion"))
        suite.expect(phase.phase == .waiting, "Cursor's question waits")
        phase.apply(.turnEnded(success: true))
        suite.expect(phase.phase == .idle, "a finished turn is idle")
        phase.apply(.codexStarted)
        suite.expect(phase.phase == .working, "Codex works from the start of a task")
        phase.apply(.codexFinished)
        suite.expect(phase.phase == .idle, "Codex finishing is idle and never waiting")
    }

    private static func cursorLog(_ suite: TestSuite) {
        var state = AgentLogState()
        var waiting = false
        var settled = false
        var reason: String?
        let user = Data(#"{"role":"user","message":{"content":[{"type":"text","text":"hi"}]}}"#.utf8)
        let ask = Data(#"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"AskQuestion","input":{"title":"Ship it?"}}]}}"#.utf8)
        let ended = Data(#"{"type":"turn_ended","status":"success"}"#.utf8)
        let began = AgentLogParser.parseCursor(user, state: &state, waiting: &waiting, settled: &settled,
                                               reason: &reason, now: Date())
        suite.expect(began.contains { if case .turnBegan = $0 { return true }; return false }
                        && !waiting && !settled && reason == nil,
                     "a user line opens a turn and is not waiting")
        _ = AgentLogParser.parseCursor(ask, state: &state, waiting: &waiting, settled: &settled,
                                       reason: &reason, now: Date())
        suite.expect(waiting && state.turnOpen && !settled && reason == "Ship it?",
                     "AskQuestion waits while the turn is open and keeps its title")
        _ = AgentLogParser.parseCursor(ended, state: &state, waiting: &waiting, settled: &settled,
                                       reason: &reason, now: Date())
        suite.expect(waiting && state.turnOpen && !settled && reason == "Ship it?",
                     "a question stays up while it waits for a reply")
        let reply = Data(#"{"role":"user","message":{"content":[{"type":"text","text":"go"}]}}"#.utf8)
        _ = AgentLogParser.parseCursor(reply, state: &state, waiting: &waiting, settled: &settled,
                                       reason: &reason, now: Date())
        suite.expect(!waiting && state.turnOpen && !settled && reason == nil,
                     "the person's reply is work again")

        var done = AgentLogState()
        var doneWaiting = false
        var doneSettled = false
        var doneReason: String?
        let answer = Data(#"{"role":"assistant","message":{"content":[{"type":"text","text":"done"}]}}"#.utf8)
        _ = AgentLogParser.parseCursor(user, state: &done, waiting: &doneWaiting, settled: &doneSettled,
                                       reason: &doneReason, now: Date())
        _ = AgentLogParser.parseCursor(answer, state: &done, waiting: &doneWaiting, settled: &doneSettled,
                                       reason: &doneReason, now: Date())
        let finished = AgentLogParser.parseCursor(ended, state: &done, waiting: &doneWaiting, settled: &doneSettled,
                                                  reason: &doneReason, now: Date())
        let stopped = finished.contains { if case .turnEnded(_, false, _) = $0 { return true }; return false }
        suite.expect(!doneWaiting && !done.turnOpen && stopped, "a delivered reply stops the timer")
    }

    private static func cursorProject(_ suite: TestSuite) {
        let path = "/Users/a/.cursor/projects/demo-app/agent-transcripts/abc/abc.jsonl"
        suite.expect(AgentCursorPath.project(in: path) == "demo-app",
                     "the project is the folder above agent-transcripts")
    }

    private static func cursorUsage(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-10-06T12:00:00.000Z")!
        let json = Data("""
        {"billingCycleStart":"2026-09-20T00:00:00.000Z","billingCycleEnd":"2026-10-20T00:00:00.000Z",\
        "membershipType":"pro","individualUsage":{"plan":{"used":4500,"limit":10000,"totalPercentUsed":45.2,\
        "autoPercentUsed":40,"apiPercentUsed":50},"onDemand":{"used":200,"limit":1000}}}
        """.utf8)
        let reading = AgentCursorAccountUsage.reading(from: json, now: now)
        suite.expect(reading?.limits.provider == .cursor && reading?.limits.source == .account
                        && reading?.planName == "Pro",
                     "Cursor's usage summary becomes an account reading with the plan name")
        suite.expect(reading?.limits.windows.count == 2
                        && abs((reading?.limits.windows.first?.usedPercent ?? 0) - 45.2) < 0.01
                        && reading?.limits.windows.first?.resetsAt == AgentTimestamp.parse("2026-10-20T00:00:00.000Z"),
                     "the plan window carries the used percent and billing-cycle end")
        suite.expect(AgentCursorAccountUsage.reading(from: Data("{}".utf8), now: now) == nil,
                     "an empty summary is not a reading")

        // sub = auth0|user_abc, exp far in the future
        let header = Data(#"{"alg":"none"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        let payloadJSON = #"{"sub":"auth0|user_abc","exp":4102444800}"#
        var payload = Data(payloadJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        while payload.last == "=" { payload.removeLast() }
        let token = "\(header).\(payload).sig"
        let session = AgentCursorAccountUsage.Session(accessToken: token, userID: "user_abc",
                                                      expiresAt: Date(timeIntervalSince1970: 4_102_444_800))
        suite.expect(session.isUsable && session.cookieHeader.contains("user_abc%3A%3A"),
                     "the app session builds the cookie Cursor's API expects")
    }

    private static func commands(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/a")
        let found: (String) -> String? = { "/bin/\($0)" }
        let claude = AgentMeterCommands.signIn(AgentAccount(provider: .claude, slug: "work"), home: home, locate: found)
        suite.expect(claude.arguments == ["auth", "login"]
                        && claude.environment["CLAUDE_CONFIG_DIR"] == "/Users/a/.claude-work",
                     "a second Claude login uses its own config directory")
        let primary = AgentMeterCommands.signIn(AgentAccount(provider: .claude), home: home, locate: found)
        suite.expect(primary.environment.isEmpty, "the main Claude login sets no extra environment")
        let cursor = AgentMeterCommands.signIn(AgentAccount(provider: .cursor), home: home, locate: { _ in nil })
        suite.expect(cursor.missing == "Cursor" && cursor.executable.isEmpty, "a missing tool launches nothing")
        suite.expect(AgentMeterCommands.signedIn(claudeStatus: #"{"loggedIn":true}"#), "Claude status JSON says logged in")
        suite.expect(AgentMeterCommands.signedIn(cursorStatus: "Logged in"), "Cursor status text says logged in")
        suite.expect(AgentMeterCommands.signedIn(cursorStatus: "✓ Login successful!\nLogged in (unable to fetch user details)"),
                     "cursor-agent's success line counts as signed in")
        suite.expect(!AgentMeterCommands.signedIn(cursorStatus: "Not logged in"),
                     "a logged-out Cursor status stays unsigned")
    }

    private static func quota(_ suite: TestSuite) {
        let first = AgentMeterReading(usedPercent: 40, resetsAt: nil, observedAt: Date(), stale: false)
        let failed = AgentMeterQuota.reduce(previous: first, incoming: nil, signedIn: true)
        suite.expect(failed?.usedPercent == 40 && failed?.stale == true,
                     "a failed check keeps the last percentage and marks it stale")
        suite.expect(AgentMeterQuota.reduce(previous: first, incoming: nil, signedIn: false) == nil,
                     "logout drops the reading")
        let later = AgentMeterReading(usedPercent: 10, resetsAt: nil, observedAt: Date(), stale: false)
        suite.expect(AgentMeterQuota.reduce(previous: first, incoming: later, signedIn: false) == nil,
                     "a response after logout is ignored")
    }

    private static func attention(_ suite: TestSuite) {
        let now = Date()
        let silent = AgentMeterAttention.crossings(previous: [:], current: ["a": 90], resets: [:], fired: [], now: now, announce: false)
        suite.expect(silent.isEmpty, "the first reading is quiet")
        let eighty = AgentMeterAttention.crossings(previous: ["a": 70], current: ["a": 85], resets: [:], fired: [], now: now, announce: true)
        suite.expect(eighty == ["a@80"], "crossing 80 alerts once")
        let again = AgentMeterAttention.crossings(previous: ["a": 85], current: ["a": 90], resets: [:], fired: eighty, now: now, announce: true)
        suite.expect(again.isEmpty, "staying above 80 does not alert again")
        let full = AgentMeterAttention.crossings(previous: ["a": 90], current: ["a": 100], resets: [:], fired: eighty, now: now, announce: true)
        suite.expect(full == ["a@100"], "crossing 100 alerts separately")
    }
}
