// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reading a saved login's limits: Anthropic's answers and the token
/// refresh before them, Codex's own server, and how often each is asked.
enum AgentAccountUsageTests {
    private static let now = AgentAccountTests.now

    static func run(_ suite: TestSuite) {
        parsing(suite)
        claudeCopies(suite)
        claudeLive(suite)
        codexRotation(suite)
        codexServer(suite)
        polling(suite)
    }

    /// Answers requests in turn from memory and keeps what was asked.
    private final class Wire {
        var answers: [AgentHTTPResponse]
        private(set) var requests: [URLRequest] = []
        var onRequest: (() -> Void)?

        init(_ answers: [AgentHTTPResponse]) { self.answers = answers }

        func send(_ request: URLRequest) -> AgentHTTPResponse? {
            requests.append(request)
            onRequest?()
            return answers.isEmpty ? nil : answers.removeFirst()
        }

        var bearers: [String?] { requests.map { $0.value(forHTTPHeaderField: "Authorization") } }
    }

    private static var usageAnswer: AgentHTTPResponse {
        AgentHTTPResponse(status: 200, body: AgentAccountTests.fixture("agent-accounts-claude-usage.json"))
    }
    private static let tokenAnswer = AgentHTTPResponse(status: 200, body: Data(
        #"{"access_token":"at-new","refresh_token":"rt-new","expires_in":3600,"scope":"user:inference user:profile user:sessions"}"#.utf8))

    private static func oauth(_ credential: Data?) -> [String: Any] {
        AgentAccountTests.json(credential)["claudeAiOauth"] as? [String: Any] ?? [:]
    }

    // MARK: Claude

    private static func parsing(_ suite: TestSuite) {
        let limits = ClaudeCodeLogin.limits(usage: AgentAccountTests.fixture("agent-accounts-claude-usage.json"), now: now)
        let windows = limits?.windows ?? []
        suite.expect(limits?.provider == .claude && limits?.source == .account && limits?.observedAt == now
                        && windows.map(\.id) == ["claude.fh", "claude.sd", "claude.sd.opus", "claude.sd.sonnet"]
                        && windows.map(\.kind) == [.session, .weekly, .weekly, .weekly]
                        && windows.map(\.scope) == [nil, nil, "Opus", "Sonnet"],
                     "the answer reads as a session, a week, and a week for each model that has one of its own")
        suite.expect(windows.map(\.usedPercent) == [42.5, 91, 100, 12.25]
                        && windows.first?.resetsAt == Date(timeIntervalSince1970: 1_791_817_200)
                        && windows.last?.resetsAt == nil && AgentAutoSwap.binding(limits) == 100,
                     "use is kept within a hundred percent, renewals read with or without fractions of a second, and extra usage is left out")
        suite.expect(ClaudeCodeLogin.limits(usage: Data("[]".utf8), now: now) == nil
                        && ClaudeCodeLogin.limits(usage: Data(#"{"five_hour":null,"usage":{"percent":40}}"#.utf8), now: now) == nil,
                     "an answer that is not the object expected, or names no window known here, is no reading rather than an unused login")

        let soon = AgentAccountTests.claudeCredential("a", expires: now.addingTimeInterval(299))
        let later = AgentAccountTests.claudeCredential("a", expires: now.addingTimeInterval(301))
        suite.expect(ClaudeCodeLogin.isExpired(soon, now: now) && !ClaudeCodeLogin.isExpired(later, now: now)
                        && !ClaudeCodeLogin.isExpired(Data(#"{"claudeAiOauth":{"accessToken":"at"}}"#.utf8), now: now)
                        && ClaudeCodeLogin.tokens(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil,
                     "a token counts as expired five minutes before its end, and one without an end never does")
    }

    /// Two saved logins with B the live one, so A is read from its copy.
    private static func world() -> AgentAccountTests.ClaudeWorld {
        let world = AgentAccountTests.ClaudeWorld()
        world.signIn("a")
        world.save()
        world.signIn("b")
        world.save()
        return world
    }

    private static func claudeCopies(_ suite: TestSuite) {
        let world = world()
        guard let account = world.store.account("acct-a/org-a"), let copy = try? world.store.credential(for: account.id) else {
            suite.expect(false, "the saved login and its copy are there")
            return
        }
        let live = world.live
        func fetch(_ credential: Data, _ answers: [AgentHTTPResponse], active: Bool = false)
            -> (limits: Result<AgentLimits, AgentUsageFailure>, rotated: Data?, wire: Wire) {
            let wire = Wire(answers)
            world.adapter.transport = wire.send
            let answer = world.adapter.fetchUsage(account, credential: credential, isActive: active)
            return (answer.limits, answer.rotated, wire)
        }
        func failure(_ result: Result<AgentLimits, AgentUsageFailure>) -> AgentUsageFailure? {
            if case .failure(let failure) = result { return failure }
            return nil
        }

        let plain = fetch(copy, [usageAnswer])
        let request = plain.wire.requests.first
        suite.expect((try? plain.limits.get())?.windows.count == 4 && plain.rotated == nil && plain.wire.requests.count == 1
                        && request?.url == ClaudeCodeLogin.usageURL && plain.wire.bearers == ["Bearer at-a"]
                        && request?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20"
                        && request?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Vorssaint/") == true,
                     "a copy whose token still holds is read with one request, as that login")

        let expired = AgentAccountTests.claudeCredential("a", expires: now.addingTimeInterval(60), extra: ["mcpOAuth": ["server": "kept"]])
        let refreshed = fetch(expired, [tokenAnswer, usageAnswer])
        let body = AgentAccountTests.json(refreshed.wire.requests.first?.httpBody) as? [String: String]
        suite.expect(refreshed.wire.requests.map(\.url) == [ClaudeCodeLogin.tokenURL, ClaudeCodeLogin.usageURL]
                        && refreshed.wire.requests.first?.httpMethod == "POST"
                        && body == ["grant_type": "refresh_token", "refresh_token": "rt-a", "client_id": ClaudeCodeLogin.clientID]
                        && refreshed.wire.bearers.last == "Bearer at-new",
                     "an expired copy is refreshed first, and its limits are asked with the new token")
        let tokens = oauth(refreshed.rotated)
        suite.expect((try? refreshed.limits.get()) != nil && tokens["accessToken"] as? String == "at-new"
                        && tokens["refreshToken"] as? String == "rt-new"
                        && (tokens["expiresAt"] as? NSNumber)?.int64Value == Int64((now.timeIntervalSince1970 + 3_600) * 1_000)
                        && (tokens["scopes"] as? [String])?.count == 3 && tokens["subscriptionType"] as? String == "max"
                        && AgentAccountTests.json(refreshed.rotated)["mcpOAuth"] != nil,
                     "the new tokens come back to be stored, with everything else of the credential kept")

        let dead = fetch(expired, [AgentHTTPResponse(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"Refresh token not found"}"#.utf8))])
        suite.expect(failure(dead.limits) == .needsLogin && dead.rotated == nil && dead.wire.requests.count == 1,
                     "a refresh token the provider no longer knows means the login needs a new sign-in")

        let limited = fetch(expired, [tokenAnswer, AgentHTTPResponse(status: 429, retryAfter: 120, body: Data())])
        suite.expect(failure(limited.limits) == .rateLimited(retryAfter: 120) && oauth(limited.rotated)["refreshToken"] as? String == "rt-new",
                     "a refusal after a refresh still hands back the new tokens, since the old ones are spent")

        let revoked = fetch(copy, [AgentHTTPResponse(status: 401, body: Data()), tokenAnswer, usageAnswer])
        suite.expect((try? revoked.limits.get()) != nil && revoked.wire.bearers == ["Bearer at-a", nil, "Bearer at-new"]
                        && oauth(revoked.rotated)["accessToken"] as? String == "at-new",
                     "a copy's token refused before its time is refreshed once and asked again")
        let silent = fetch(copy, [])
        let broken = fetch(copy, [AgentHTTPResponse(status: 500, body: Data())])
        suite.expect(failure(silent.limits) == .unavailable("usage did not answer") && failure(broken.limits) == .unavailable("usage answered 500")
                        && silent.rotated == nil,
                     "no answer and an error are failures to try again later")

        // Asked as the live login, though the live login is B by now.
        let stale = fetch(copy, [usageAnswer], active: true)
        suite.expect(stale.wire.bearers == ["Bearer at-a"] && stale.rotated == nil && world.live == live,
                     "the live login's tokens are only taken for the login they belong to, and reading a copy never touches the live login")
        suite.expect(!FileManager.default.fileExists(atPath: ClaudeLocks.refresh(home: world.home).url.path),
                     "reading a copy takes none of Claude Code's locks")
    }

    private static func claudeLive(_ suite: TestSuite) {
        let world = AgentAccountTests.ClaudeWorld()
        let expired = AgentAccountTests.claudeCredential("a", expires: now.addingTimeInterval(-60))
        world.signIn("a", credential: expired)
        guard let account = world.save() else {
            suite.expect(false, "the live login is saved")
            return
        }
        let lock = ClaudeLocks.refresh(home: world.home).url

        // The live login, rotated since it was saved and still valid.
        let rotatedLive = AgentAccountTests.claudeCredential("a2")
        world.live = String(decoding: rotatedLive, as: UTF8.self)
        var wire = Wire([usageAnswer])
        world.adapter.transport = wire.send
        let fresh = world.adapter.fetchUsage(account, credential: expired, isActive: true)
        suite.expect((try? fresh.limits.get()) != nil && wire.bearers == ["Bearer at-a2"] && fresh.rotated == rotatedLive,
                     "the live login is read with the tokens Claude Code has now, which come back for its copy")

        // Expired, and nobody else refreshes it.
        world.live = String(decoding: expired, as: UTF8.self)
        wire = Wire([tokenAnswer, usageAnswer])
        var held: [Bool] = []
        wire.onRequest = { held.append(FileManager.default.fileExists(atPath: lock.path)) }
        world.adapter.transport = wire.send
        let refreshed = world.adapter.fetchUsage(account, credential: expired, isActive: true)
        suite.expect((try? refreshed.limits.get()) != nil && held == [true, false] && AgentAccountTests.access(world.live) == "at-new"
                        && refreshed.rotated == world.live.map { Data($0.utf8) }
                        && !FileManager.default.fileExists(atPath: ClaudeCodeLogin.credentialsFileURL(home: world.home).path),
                     "the live login is refreshed holding Claude Code's refresh lock, written back, and its limits asked after the lock is released")

        // Expired when first looked at; a session refreshes it before the lock is ours.
        world.live = String(decoding: expired, as: UTF8.self)
        wire = Wire([usageAnswer])
        world.adapter.transport = wire.send
        world.secrets.afterRead = {
            world.secrets.afterRead = nil
            world.live = String(decoding: rotatedLive, as: UTF8.self)
        }
        let raced = world.adapter.fetchUsage(account, credential: expired, isActive: true)
        suite.expect((try? raced.limits.get()) != nil && wire.requests.map(\.url) == [ClaudeCodeLogin.usageURL]
                        && wire.bearers == ["Bearer at-a2"] && raced.rotated == rotatedLive,
                     "the live login is read again once the lock is held, and a refresh Claude Code did meanwhile is not repeated")

        world.live = String(decoding: expired, as: UTF8.self)
        try? FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        wire = Wire([tokenAnswer, usageAnswer])
        world.adapter.transport = wire.send
        let busy = world.adapter.fetchUsage(account, credential: expired, isActive: true)
        var waited = false
        if case .failure(.unavailable) = busy.limits { waited = true }
        suite.expect(waited && wire.requests.isEmpty && busy.rotated == nil && world.live == String(decoding: expired, as: UTF8.self),
                     "while Claude Code holds its refresh lock, nothing is asked and nothing is written")
    }

    // MARK: Codex

    private static func codexRotation(_ suite: TestSuite) {
        let home = AgentAccountTests.temporaryFolder("codex-usage")
        defer { try? FileManager.default.removeItem(at: home) }
        let live = CodexLogin.authURL(home: home)
        try? FileManager.default.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
        let copies = CodexCredentialCopies(directory: home.appending(path: "copies"))
        let store = AgentAccountStore(directory: home.appending(path: "store"), copies: [.codex: copies])
        var adapter = CodexLoginAdapter(home: home, copies: copies, limits: { _ in .failure(.missing) }, processes: { 0 })
        let first = AgentAccountTests.codexAuth(account: "c0de-1", email: "one@example.com")
        let second = AgentAccountTests.codexAuth(account: "c0de-2", email: "two@example.com")
        for auth in [first, second] {
            try? auth.write(to: live)
            _ = (try? adapter.readLive()).flatMap { try? store.capture($0, now: now) }
        }
        guard let saved = store.account("c0de-1"), let current = store.account("c0de-2") else {
            suite.expect(false, "both Codex logins are saved")
            return
        }

        // Codex writes new tokens into whichever home it was pointed at.
        let limits = AgentLimits(provider: .codex, windows: [], observedAt: now, source: .account)
        let rotatedCopy = AgentAccountTests.codexAuth(account: "c0de-1", email: "one@example.com", refresh: "rt-2")
        let rotatedLive = AgentAccountTests.codexAuth(account: "c0de-2", email: "two@example.com", refresh: "rt-2")
        var asked: [URL?] = []
        adapter.limits = { folder in
            asked.append(folder)
            if let folder { try? rotatedCopy.write(to: folder.appending(path: "auth.json")) } else { try? rotatedLive.write(to: live) }
            return .success(limits)
        }
        let copy = adapter.fetchUsage(saved, credential: first, isActive: false)
        suite.expect(asked == [copies.home(for: "c0de-1")] && (try? copy.limits.get()) == limits && copy.rotated == rotatedCopy
                        && (try? Data(contentsOf: live)) == second,
                     "a saved Codex login is read in its own home, and the auth.json Codex rotated there comes back to be stored")
        try? store.storeCredential(rotatedCopy, for: "c0de-1", now: now.addingTimeInterval(60))
        suite.expect((try? store.credential(for: "c0de-1")) == rotatedCopy && store.account("c0de-1")?.savedAt == now.addingTimeInterval(60),
                     "storing rotated tokens keeps the copy current")

        asked = []
        let active = adapter.fetchUsage(current, credential: second, isActive: true)
        suite.expect(asked == [nil] && active.rotated == rotatedLive && (try? copies.read("c0de-2")) == second,
                     "the live Codex login is read in Codex's usual home, so its refresh lands in the file Codex uses")

        func failure(_ answer: AgentCodexServer.Failure) -> AgentUsageFailure? {
            adapter.limits = { _ in .failure(answer) }
            if case .failure(let failure) = adapter.fetchUsage(saved, credential: rotatedCopy, isActive: false).limits { return failure }
            return nil
        }
        suite.expect(failure(.needsSignIn) == .needsLogin && failure(.missing) == .toolMissing
                        && failure(.unreachable) == .unavailable("codex: unreachable"),
                     "a copy Codex calls signed out needs a new login, and a Mac without Codex says so")
    }

    /// Answers like Codex's server, with limits that tell whether it was
    /// pointed at a home of its own, where it leaves a mark.
    private static let standIn = #"""
        #!/bin/sh
        [ "$3" = "app-server" ] || exit 2
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*) printf '%s\n' '{"id":1,"result":{}}' ;;
            *'"method":"account/read"'*)
              if [ "$STAND_IN" = "signedOut" ]; then printf '%s\n' '{"id":2,"result":{"account":null}}'
              else printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"pro"}}}'; fi ;;
            *'"method":"account/rateLimits/read"'*)
              used=7
              if [ -n "$CODEX_HOME" ]; then used=42; : > "$CODEX_HOME/asked"; fi
              printf '%s\n' "{\"id\":3,\"result\":{\"rateLimitsByLimitId\":{\"codex\":{\"primary\":{\"usedPercent\":$used,\"windowDurationMins\":300}}}}}" ;;
          esac
        done
        """#

    private static func codexServer(_ suite: TestSuite) {
        let folder = AgentAccountTests.temporaryFolder("codex-server")
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = folder.appending(path: "codex")
        let home = folder.appending(path: "login")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: server.path, contents: Data(standIn.utf8),
                                             attributes: [.posixPermissions: 0o755]) else {
            suite.expect(false, "the stand-in server is written")
            return
        }
        let base = ["PATH": "/usr/bin:/bin", "CODEX_HOME": "/somewhere/else"]
        let saved = CodexLogin.limits(server, codexHome: home, base: base, now: now)
        suite.expect((try? saved.get())?.windows.map(\.usedPercent) == [42] && (try? saved.get())?.source == .account
                        && FileManager.default.fileExists(atPath: home.appending(path: "asked").path),
                     "Codex's server is started in a saved login's own home to read that login's limits")
        let live = CodexLogin.limits(server, codexHome: nil, base: base, now: now)
        suite.expect((try? live.get())?.windows.map(\.usedPercent) == [7],
                     "for the live login it runs in Codex's usual home, whatever the app was started with")
        var signedOut = base
        signedOut["STAND_IN"] = "signedOut"
        suite.expect(CodexLogin.limits(server, codexHome: home, base: signedOut, now: now) == .failure(.needsSignIn),
                     "a home without a plan's login is told as needing a sign-in")
    }

    // MARK: Polling

    private static func polling(_ suite: TestSuite) {
        var polling = AgentAccountPolling()
        func due(_ pace: AgentAccountPolling.Pace, after minutes: Double, appeared: Bool = false) -> Bool {
            polling.isDue("a", pace: pace, appeared: appeared, now: now.addingTimeInterval(minutes * 60))
        }
        suite.expect(due(.idle, after: 0), "a login never asked is asked at once")
        polling.succeeded("a", now: now)
        suite.expect(!due(.active, after: 4.9) && due(.active, after: 5) && !due(.urgent, after: 1.9) && due(.urgent, after: 2)
                        && !due(.idle, after: 9.9) && due(.idle, after: 10) && !due(.candidate, after: 4.9) && due(.candidate, after: 5),
                     "the login in use is asked every five minutes, every two near the threshold, and the others every ten or five")
        suite.expect(!due(.idle, after: 2.9, appeared: true) && due(.idle, after: 3, appeared: true)
                        && !due(.urgent, after: 1.9, appeared: true),
                     "opening the page asks again after three minutes, and nothing asks one login twice within two")

        suite.expect((1...7).map(AgentAccountPolling.backoff) == [60, 120, 240, 480, 600, 600, 600],
                     "failures wait one minute, then twice as long each time, up to ten")
        polling.failed("a", .unavailable("x"), now: now)
        suite.expect(!due(.urgent, after: 0.9, appeared: true) && !due(.urgent, after: 1) && due(.urgent, after: 2), "a failure is tried again once both its wait and the two minutes are over")
        polling.failed("a", .unavailable("x"), now: now)
        polling.failed("a", .unavailable("x"), now: now)
        suite.expect(!due(.urgent, after: 3.9, appeared: true) && due(.idle, after: 4), "repeated failures wait longer, whatever the page does")
        polling.succeeded("a", now: now)
        polling.failed("a", .unavailable("x"), now: now)
        suite.expect(due(.idle, after: 2), "a success in between starts the waits over")

        suite.expect(AgentAccountPolling.hold(retryAfter: nil) == 20 * 60 && AgentAccountPolling.hold(retryAfter: 120) == 20 * 60
                        && AgentAccountPolling.hold(retryAfter: 600) == 25 * 60 && AgentAccountPolling.hold(retryAfter: 7_200) == 135 * 60,
                     "a login asked too often rests fifteen minutes past what the provider named, and twenty at least")
        polling.failed("a", .rateLimited(retryAfter: 600), now: now)
        suite.expect(!due(.urgent, after: 24.9, appeared: true) && due(.urgent, after: 25), "nothing asks a login during that rest")
        polling.forget("a")
        suite.expect(due(.idle, after: 0), "a login saved again is asked at once")

        func limits(_ used: Double) -> AgentLimits {
            AgentLimits(provider: .claude, windows: [AgentLimitWindow(id: "claude.fh", kind: .session, minutes: 300, scope: nil,
                                                                      usedPercent: used, resetsAt: nil)],
                        observedAt: now, source: .account)
        }
        suite.expect(AgentAccountPolling.isNear(limits(75), threshold: 90) && !AgentAccountPolling.isNear(limits(74.9), threshold: 90)
                        && !AgentAccountPolling.isNear(nil, threshold: 90),
                     "a login within fifteen points of the threshold is watched more closely")
    }
}
