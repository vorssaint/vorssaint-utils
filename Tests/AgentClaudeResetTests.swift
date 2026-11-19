// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Claude's banked resets: the answers claude.ai gives, the sign-in Claude
/// Code keeps and how a request names itself.
enum AgentClaudeResetTests {
    static func run(_ suite: TestSuite) {
        answers(suite)
        signIn(suite)
        requests(suite)
    }

    private static func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    // MARK: Answers

    private static func answers(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-10-15T07:00:00Z")!
        // Shaped like a real answer, with the parts this never reads left out.
        let read = json("""
        {"five_hour":{"utilization":100,"resets_at":"2026-10-15T09:00:00+00:00"},
         "seven_day":{"utilization":41,"resets_at":"2026-10-17T23:00:00+00:00"},
         "seven_day_opus":null,
         "cedar_ember":{"eligible":true,"ineligible_reason":null,"at_limit":true,"exhausted":["five_hour"],
           "grants":[
             {"id":"late","label":"Welcome","resets_total":3,"resets_left":2,"ends_at":"2026-11-30T00:00:00Z",
              "clears":["five_hour","seven_day"],"paused":false,"usable_now":true,"use_requires_limit":true},
             {"id":"soon","resets_total":1,"resets_left":1,"ends_at":"2026-10-20T00:00:00Z","usable_now":false},
             {"id":"spent","resets_total":2,"resets_left":0,"ends_at":"2026-11-30T00:00:00Z"},
             {"id":"gone","resets_total":1,"resets_left":1,"ends_at":"2026-10-01T00:00:00Z"},
             {"id":"Not Valid!","resets_left":1}],
           "next_grant_id":"late","weekly_resets_at":null,"cooldown_until":null}}
        """)
        let summary = AgentClaudeResets.summary(read, now: now)
        suite.expect(summary?.eligible == true && summary?.grants.map(\.id) == ["soon", "late"] && summary?.available == 3
                        && summary?.nextExpiry == AgentTimestamp.parse("2026-10-20T00:00:00Z"),
                     "grants list soonest to end first, without spent, ended or malformed ones, and their resets add up")
        suite.expect(summary?.usable?.id == "late",
                     "the grant claude.ai names next is the one a use spends, when it can be used now")
        suite.expect(summary?.limits?.provider == .claude && summary?.limits?.source == .account
                        && summary?.limits?.windows.map(\.usedPercent) == [100, 41],
                     "the same answer's limits read as Claude's account limits")

        // The launch grant an account was given, as claude.ai lists it.
        let launch = AgentClaudeResets.summary(json("""
        {"cedar_ember":{"eligible":true,"ineligible_reason":null,"at_limit":false,"exhausted":[],"grants":[
          {"id":"opus55-launch-promax-20260921","label":"Claude Opus 5.5 launch: one usage-limit reset for Pro and Max",
           "resets_total":1,"resets_left":1,"starts_at":"2026-09-22T16:00:00+00:00","ends_at":"2026-10-22T16:00:00+00:00",
           "clears":["five_hour","seven_day","seven_day_overage_included"],"paused":false,"usable_now":true,
           "use_requires_limit":false,"percent_used":{"five_hour":92,"seven_day":23},"blocking":[],"arm":null}],
          "next_grant_id":"opus55-launch-promax-20260921","weekly_resets_at":"2026-10-17T23:00:00+00:00","cooldown_until":null}}
        """), now: now)
        suite.expect(launch?.available == 1 && launch?.usable?.id == "opus55-launch-promax-20260921"
                        && launch?.nextExpiry == AgentTimestamp.parse("2026-10-22T16:00:00Z"),
                     "a reset usable before any limit is offered with its grant's end")

        let saved = AgentClaudeResets.summary(json("""
        {"cedar_ember":{"eligible":true,"grants":[{"id":"kept","resets_left":1,"usable_now":false}],"next_grant_id":"kept"}}
        """), now: now)
        suite.expect(saved?.available == 1 && saved?.usable == nil,
                     "a reset kept for a limit not reached yet is counted but not offered")
        let paused = AgentClaudeResets.summary(json("""
        {"cedar_ember":{"eligible":true,"grants":[{"id":"held","resets_left":1,"usable_now":true,"paused":true}],"next_grant_id":"held"}}
        """), now: now)
        suite.expect(paused?.usable == nil, "a paused grant is never offered")
        let elsewhere = AgentClaudeResets.summary(json("""
        {"cedar_ember":{"eligible":true,"grants":[{"id":"a","resets_left":1,"usable_now":true}],"next_grant_id":"b"}}
        """), now: now)
        suite.expect(elsewhere?.nextGrant == nil && elsewhere?.usable == nil,
                     "a next grant missing from the list spends nothing")

        let outside = AgentClaudeResets.summary(json("""
        {"cedar_ember":{"eligible":false,"ineligible_reason":"tier","grants":[{"id":"x","resets_left":1,"usable_now":true}],"next_grant_id":"x"}}
        """), now: now)
        suite.expect(outside?.eligible == false && outside?.available == 0 && outside?.usable == nil,
                     "an account outside the program offers no resets whatever it lists")
        suite.expect(AgentClaudeResets.summary(json(#"{"cedar_ember":null}"#), now: now) == nil
                        && AgentClaudeResets.summary(json(#"{"five_hour":null}"#), now: now) == nil,
                     "an answer without the resets block reads as none")

        suite.expect(AgentClaudeResets.outcome(json(#"{"result":"reset","resets_left":1}"#)) == .reset
                        && AgentClaudeResets.outcome(json(#"{"result":"already_used"}"#)) == .alreadyUsed
                        && AgentClaudeResets.outcome(json(#"{"result":"not_limited"}"#)) == .notLimited
                        && AgentClaudeResets.outcome(json(#"{"result":"cooldown"}"#)) == .cooldown
                        && AgentClaudeResets.outcome(json(#"{"result":"something_new"}"#)) == nil,
                     "a use's outcome is read in claude.ai's words, and an unknown one is no outcome")
    }

    // MARK: Sign-in

    private static func signIn(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let stored = Data(#"""
        {"mcpOAuth":{},"claudeAiOauth":{"accessToken":"token","refreshToken":"never-read","expiresAt":1792003600000,
         "scopes":["user:inference","user:profile"],"subscriptionType":"max"}}
        """#.utf8)
        let credentials = AgentClaudeResets.credentials(stored)
        suite.expect(credentials?.token == "token" && credentials?.expiresAt == Date(timeIntervalSince1970: 1_792_003_600)
                        && credentials?.readsUsage == true && credentials?.current(at: now) == true,
                     "Claude Code's stored sign-in gives its access token and when it expires")
        suite.expect(credentials?.current(at: now.addingTimeInterval(3_570)) == false,
                     "a token within a minute of expiring is renewed by Claude Code first")
        let inference = AgentClaudeResets.credentials(Data(#"{"claudeAiOauth":{"accessToken":"t","scopes":["user:inference"]}}"#.utf8))
        suite.expect(inference?.readsUsage == false, "a token made for inference alone cannot read the plan's usage")
        suite.expect(AgentClaudeResets.credentials(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil
                        && AgentClaudeResets.credentials(Data("not json".utf8)) == nil,
                     "an empty or unreadable sign-in is no sign-in")
    }

    // MARK: Requests

    private static func requests(_ suite: TestSuite) {
        suite.expect(AgentClaudeResets.version("2.1.286 (Claude Code)\n") == "2.1.286"
                        && AgentClaudeResets.version("Claude Code") == nil && AgentClaudeResets.version("") == nil,
                     "the version is the first word of `claude --version`, or none")
        suite.expect(AgentClaudeResets.userAgent(version: "2.1.286")
                        == "claude-cli/2.1.286 (external, cli, client-app/Vorssaint)",
                     "requests name Claude Code, whose sign-in they carry, and Vorssaint as the app asking")
        suite.expect(AgentClaudeResets.valid(grant: "grant_1-a") && !AgentClaudeResets.valid(grant: "../x")
                        && !AgentClaudeResets.valid(grant: String(repeating: "a", count: 41))
                        && AgentClaudeResets.valid(request: UUID().uuidString) && !AgentClaudeResets.valid(request: "a b"),
                     "grant and request names keep to the characters claude.ai uses")
        let now = Date(timeIntervalSince1970: 0)
        suite.expect(AgentClaudeResets.busyUntil(retryAfter: "167", now: now) == now.addingTimeInterval(167)
                        && AgentClaudeResets.busyUntil(retryAfter: "5", now: now) == now.addingTimeInterval(120)
                        && AgentClaudeResets.busyUntil(retryAfter: "86400", now: now) == now.addingTimeInterval(1_800)
                        && AgentClaudeResets.busyUntil(retryAfter: nil, now: now) == now.addingTimeInterval(300),
                     "a request to wait is kept within two minutes and half an hour")
    }
}
