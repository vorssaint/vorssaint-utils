// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Command Code's plan limits, read from answers kept in Tests/Fixtures/commandcode.
enum CommandCodeLimitsTests {
    private static func fixture(_ name: String) -> String {
        (try? String(contentsOfFile: "Tests/Fixtures/commandcode/\(name)", encoding: .utf8)) ?? ""
    }

    private static let observed = Date(timeIntervalSince1970: 1_794_000_000)

    private static func reply(_ body: String, status: Int = 200) -> AgentCommandCodeAccount.Reply {
        .init(status: status, body: Data(body.utf8))
    }

    /// Answers in order; records what was asked.
    private final class Server {
        var answers: [AgentCommandCodeAccount.Reply?]
        var asked: [URLRequest] = []
        init(_ answers: [AgentCommandCodeAccount.Reply?]) { self.answers = answers }
        func fetch(_ request: URLRequest) -> AgentCommandCodeAccount.Reply? {
            asked.append(request)
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }

    private static func good() -> [AgentCommandCodeAccount.Reply?] {
        [reply(fixture("whoami.json")), reply(fixture("credits.json")),
         reply(fixture("subscription.json")), reply(fixture("summary.json"))]
    }

    static func run(_ suite: TestSuite) {
        key(suite)
        asks(suite)
        windows(suite)
        failures(suite)
        plans(suite)
    }

    private static func key(_ suite: TestSuite) {
        suite.run("Command Code key") {
            let auth = Data(fixture("auth.json").utf8)
            if case .success(let key) = AgentCommandCodeAccount.apiKey(authFile: auth, installed: true) {
                suite.expect(key == "user_testkey0123456789abcdef", "reads apiKey")
            } else { suite.expect(false, "good key not read") }
            suite.expect(AgentCommandCodeAccount.apiKey(authFile: nil, installed: false) == .failure(.notFound),
                         "nothing of Command Code is not found")
            let signedOut: [(Data?, Bool)] = [
                (nil, true), (Data("{}".utf8), false), (Data("{not json".utf8), false),
                (Data(#"{"apiKey":"  "}"#.utf8), false),
                (Data(#"{"apiKey":"user_\ntest"}"#.utf8), false),
            ]
            for (file, installed) in signedOut {
                suite.expect(AgentCommandCodeAccount.apiKey(authFile: file, installed: installed) == .failure(.signedOut),
                             "no usable key is signed out")
            }
        }
    }

    private static func asks(_ suite: TestSuite) {
        suite.run("Command Code requests") {
            let server = Server(good())
            let result = AgentCommandCodeAccount.check(key: "user_testkey0123456789abcdef", now: observed,
                                                       fetch: server.fetch)
            suite.expect(server.asked.map { $0.url?.absoluteString ?? "" } == [
                "https://api.commandcode.ai/alpha/whoami?limits=1",
                "https://api.commandcode.ai/alpha/billing/credits",
                "https://api.commandcode.ai/alpha/billing/subscriptions",
                "https://api.commandcode.ai/alpha/usage/summary?since=2026-10-22T09%3A31%3A07.000Z",
            ], "four asks, in order, to Command Code only")
            for request in server.asked {
                suite.expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user_testkey0123456789abcdef",
                             "the key goes as a bearer")
                suite.expect(request.httpMethod == "GET", "read only")
            }
            if case .success = result {} else { suite.expect(false, "good answers give limits") }

            // An organisation goes into the other asks; an id that could change the address does not.
            let org = fixture("whoami.json").replacingOccurrences(of: #""org":null"#, with: #""org":{"id":"org_1-a"}"#)
            let withOrg = Server([reply(org)] + Array(good().dropFirst()))
            _ = AgentCommandCodeAccount.check(key: "k", now: observed, fetch: withOrg.fetch)
            suite.expect(withOrg.asked[1].url?.absoluteString == "https://api.commandcode.ai/alpha/billing/credits?orgId=org_1-a",
                         "organisation in the credits ask")
            let evil = fixture("whoami.json").replacingOccurrences(of: #""org":null"#, with: #""org":{"id":"x&y=/z"}"#)
            let withEvil = Server([reply(evil)] + Array(good().dropFirst()))
            _ = AgentCommandCodeAccount.check(key: "k", now: observed, fetch: withEvil.fetch)
            suite.expect(withEvil.asked[1].url?.absoluteString == "https://api.commandcode.ai/alpha/billing/credits",
                         "an unsafe organisation id is dropped")
        }
    }

    private static func windows(_ suite: TestSuite) {
        suite.run("Command Code windows") {
            let server = Server(good())
            guard case .success(let summary) = AgentCommandCodeAccount.check(key: "k", now: observed, fetch: server.fetch) else {
                suite.expect(false, "no summary"); return
            }
            suite.expect(summary.plan == "Go", "plan from the subscription")
            let limits = summary.limits
            suite.expect(limits.provider == .commandcode && limits.source == .account, "an account reading")
            let five = limits.windows.first { $0.kind == .session }
            suite.expectClose(five?.usedPercent ?? -1, 100.0 / 3.0, "5-hour used")
            suite.expect(five?.minutes == 300, "5-hour length")
            suite.expect(five?.resetsAt == Date(timeIntervalSince1970: 1_794_003_600), "5-hour reset")
            let week = limits.windows.first { $0.kind == .weekly }
            suite.expectClose(week?.usedPercent ?? -1, 25, "weekly used")
            suite.expect(week?.resetsAt == Date(timeIntervalSince1970: 1_794_203_150.49), "weekly reset")
            // 2.5 left and 7.5 spent: a pool of 10, three quarters used, until the period ends.
            let month = limits.windows.first { $0.kind == .other }
            suite.expectClose(month?.usedPercent ?? -1, 75, "monthly credits used")
            suite.expect(month?.scope == "Credits", "monthly credits are named")
            suite.expect(limits.windows.count == 3, "three windows")

            // Plan and spend are best effort: the limits show without them.
            let bare = Server([reply(fixture("whoami.json")), reply(fixture("credits.json")),
                               reply("", status: 500), reply("", status: 500)])
            guard case .success(let partial) = AgentCommandCodeAccount.check(key: "k", now: observed, fetch: bare.fetch) else {
                suite.expect(false, "limits need neither plan nor spend"); return
            }
            suite.expect(partial.plan == nil && partial.limits.windows.count == 2, "no plan, no month bar")
            suite.expect(!(bare.asked[3].url?.absoluteString.contains("since") ?? true), "no period, no start")

            // A window with no cap is no window; a reset of 0 is no reset.
            let credits = #"{"credits":{"monthlyCredits":1},"windowLimits":{"fiveHour":{"used":2,"cap":4,"resetAt":0},"weekly":{"used":1,"cap":0}}}"#
            let odd = Server([reply(fixture("whoami.json")), reply(credits), reply("", status: 500), reply("", status: 500)])
            if case .success(let s) = AgentCommandCodeAccount.check(key: "k", now: observed, fetch: odd.fetch) {
                suite.expect(s.limits.windows.count == 1 && s.limits.windows[0].usedPercent == 50
                             && s.limits.windows[0].resetsAt == nil, "uncapped dropped, zero reset unknown")
            } else { suite.expect(false, "one capped window is enough") }

            // A plan that is not running has no month bar.
            let canceled = fixture("subscription.json").replacingOccurrences(of: #""status":"active""#, with: #""status":"canceled""#)
            let stopped = Server([reply(fixture("whoami.json")), reply(fixture("credits.json")),
                                  reply(canceled), reply(fixture("summary.json"))])
            if case .success(let s) = AgentCommandCodeAccount.check(key: "k", now: observed, fetch: stopped.fetch) {
                suite.expect(!s.limits.windows.contains { $0.kind == .other } && s.plan == "Go", "no month bar when canceled")
            } else { suite.expect(false, "canceled plan still shows limits") }
        }
    }

    private static func failures(_ suite: TestSuite) {
        suite.run("Command Code failures") {
            func check(_ answers: [AgentCommandCodeAccount.Reply?]) -> Result<AgentCommandCodeAccount.Summary, AgentCommandCodeAccount.Failure> {
                AgentCommandCodeAccount.check(key: "k", now: observed, fetch: Server(answers).fetch)
            }
            func failure(_ result: Result<AgentCommandCodeAccount.Summary, AgentCommandCodeAccount.Failure>) -> AgentCommandCodeAccount.Failure? {
                if case .failure(let failure) = result { return failure }
                return nil
            }
            suite.expect(failure(check([reply("", status: 401)])) == .refused, "401 is refused")
            suite.expect(failure(check([reply(fixture("whoami.json")), reply("", status: 403)])) == .refused, "403 is refused")
            suite.expect(failure(check([reply(fixture("whoami.json")), reply("", status: 429)])) == .busy, "429 is busy")
            suite.expect(failure(check([nil])) == .offline, "no answer is offline")
            suite.expect(failure(check([reply(fixture("whoami.json")), reply("<html>")])) == .unreadable, "not JSON is unreadable")
            let empty = #"{"credits":{"monthlyCredits":0},"windowLimits":{"fiveHour":{"used":0,"cap":0,"resetAt":0}}}"#
            suite.expect(failure(check([reply(fixture("whoami.json")), reply(empty), reply("", status: 500), reply("", status: 500)])) == .unreadable,
                         "no limits is unreadable")
            suite.expect(AgentCommandCodeAccount.minimumGap == 300, "asks at most every five minutes")
        }
    }

    private static func plans(_ suite: TestSuite) {
        suite.run("Command Code plan names") {
            let names: [(String, String)] = [
                ("individual-go-v1", "Go"), ("individual-goat", "GOAT"), ("individual-pro-v1", "Pro"),
                ("individual_provider", "Provider"), ("individual-max", "Max"), ("individual-ultra-v2", "Ultra"),
                ("teams-pro", "Teams Pro"),
            ]
            for (id, name) in names {
                suite.expect(AgentCommandCodeAccount.planName(id) == name, "\(id) is \(name)")
            }
            suite.expect(AgentCommandCodeAccount.planName("free") == nil && AgentCommandCodeAccount.planName("") == nil,
                         "an unknown plan has no name")
        }
    }
}
