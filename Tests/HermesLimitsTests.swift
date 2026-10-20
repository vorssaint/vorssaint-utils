// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum HermesLimitsTests {
    static func run(_ suite: TestSuite) {
        suite.expect(AgentProvider.hermes.reportsLimits,
                     "Hermes exposes connected-account limits, independently of token usage")
        let tiles = NotchAgentSupport.tiles(cards: [.limits], providers: [.hermes])
        suite.expect(tiles.count == 1 && tiles.first?.provider == .hermes,
                     "Hermes has its own Limits card")
        parsing(suite)
        validity(suite)
        transport(suite)
        if ProcessInfo.processInfo.environment["VORSSAINT_HERMES_LIVE_CHECK"] == "1" {
            if case .success(let raw) = AgentHermesLimits.fetch(home: AgentLogRoot.hermesHome()),
               let reading = raw.current(at: Date()) {
                print("LIVE HERMES ACCOUNT: provider=\(reading.provider) plan=\(reading.plan ?? "—") fetched=\(reading.limits.observedAt)")
                for window in reading.limits.windows {
                    print("LIVE HERMES QUOTA: kind=\(window.kind.rawValue) label=\(window.scope ?? "account") used=\(window.usedPercent)% remaining=\(window.remainingFraction * 100)% reset=\(window.resetsAt?.description ?? "unknown")")
                }
                suite.expect(!reading.limits.windows.isEmpty || !reading.details.isEmpty,
                             "opt-in live check: the production CLI transport returns actual account quota")
            } else { suite.expect(false, "opt-in live check: the account quota is available") }
        }
    }

    private static func transport(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hermes-cli-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cli = folder.appending(path: "hermes")
        let json = String(decoding: document(), as: UTF8.self)
        let script = "#!/bin/sh\n[ \"$1\" = usage ] && [ \"$2\" = --json ] || exit 3\nprintf '%s' '\(json)'\n"
        try? Data(script.utf8).write(to: cli)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        suite.expect(AgentHermesLimits.executable(home: folder, environment: ["PATH": folder.path]) == cli,
                     "a GUI launch discovers Hermes on PATH without invoking a shell")
        let cancellation = BoundedProcessCancellation()
        if case .success(let reading) = AgentHermesLimits.fetch(home: folder, executable: cli, cancellation: cancellation) {
            suite.expect(reading.provider == "openai-codex", "the public CLI document reaches the limits transport")
        } else { suite.expect(false, "the valid public CLI document is accepted") }
        cancellation.cancel()
        if case .failure(.cancelled) = AgentHermesLimits.fetch(home: folder, executable: cli, cancellation: cancellation) {
            suite.expect(true, "a cancelled queued request cannot launch")
        } else { suite.expect(false, "a cancelled queued request must not return limits") }
        try? Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: cli)
        if case .failure(.timedOut) = AgentHermesLimits.fetch(home: folder, executable: cli, timeout: 0.1) {
            suite.expect(true, "a stalled quota CLI is bounded")
        } else { suite.expect(false, "a stalled quota CLI must time out") }
    }

    private static func parsing(_ suite: TestSuite) {
        let data = Data(#"{"provider":"openai-codex","plan":"Prolite","fetched_at":"2026-10-20T12:00:00.125+00:00","windows":[{"label":"Weekly","used_percent":12,"resets_at":"2026-10-27T12:00:00.500Z"}],"details":[],"unavailable_reason":null}"#.utf8)
        let reading = AgentHermesLimits.parse(data)
        suite.expect(reading?.provider == "openai-codex" && reading?.plan == "Prolite",
                     "the CLI identifies the actual connected provider and plan")
        suite.expect(reading?.limits.provider == .hermes && reading?.limits.source == .account,
                     "account limits belong to Hermes, never to the token provider's other account")
        suite.expect(reading?.limits.windows.first?.usedPercent == 12,
                     "the CLI's percentage is used, not a token-derived estimate")
        suite.expect(reading?.limits.observedAt.timeIntervalSince1970 == 1_792_497_600.125
                     && reading?.limits.windows.first?.resetsAt?.timeIntervalSince1970 == 1_793_102_400.5,
                     "fractional ISO8601 fetch and reset times are retained")
    }

    static func document(windows: String = #"[{"label":"Weekly","used_percent":12,"resets_at":"2026-10-27T12:00:00Z"}]"#,
                         details: String = "[]", unavailable: String = "null") -> Data {
        Data("""
        {"provider":"openai-codex","plan":"Prolite","fetched_at":"2026-10-20T12:00:00Z",
         "windows":\(windows),"details":\(details),"unavailable_reason":\(unavailable)}
        """.utf8)
    }

    private static func validity(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_792_497_600)
        let reading = AgentHermesLimits.parse(document())
        suite.expect(reading?.current(at: now.addingTimeInterval(599)) != nil,
                     "a recent account check remains usable")
        suite.expect(reading?.current(at: now.addingTimeInterval(600)) == nil,
                     "missed quota checks expire the reading, never become zero usage")
        suite.expect(reading?.current(at: now.addingTimeInterval(-3600)) == nil,
                     "a future-dated document is not a current reading")
        let expired = AgentHermesLimits.parse(document(windows: #"[{"label":"Weekly","used_percent":80,"resets_at":"2026-10-20T12:00:01Z"}]"#))
        suite.expect(expired?.current(at: now.addingTimeInterval(2)) == nil,
                     "after reset, unknown remote consumption is not shown as zero")
        for value in ["-1", "101", "true", "null", #""NaN""#, #""Infinity""#, "1e400"] {
            let invalid = AgentHermesLimits.parse(document(windows: "[{\"label\":\"Invalid\",\"used_percent\":\(value)}]"))
            suite.expect(invalid?.limits.windows.isEmpty != false && invalid?.current(at: now) == nil,
                         "invalid/nonfinite percentage \(value) never becomes quota")
        }
        suite.expect(AgentHermesLimits.parse(Data("{}".utf8)) == nil
                     && AgentHermesLimits.parse(Data("not json".utf8)) == nil,
                     "malformed documents are rejected")
        let unavailable = AgentHermesLimits.parse(document(unavailable: #""Unsupported provider""#))
        suite.expect(unavailable?.unavailableReason == "Unsupported provider" && unavailable?.current(at: now) == nil,
                     "explicit unavailability takes precedence over numeric windows")
        let credits = AgentHermesLimits.parse(document(windows: "[]", details: #"["Credits remaining: $4.25"]"#))
        suite.expect(credits?.current(at: now)?.details == ["Credits remaining: $4.25"]
                     && credits?.limits.windows.isEmpty == true,
                     "details-only credit balances are displayed without inventing a percentage")
        let multiple = AgentHermesLimits.parse(document(windows: #"[{"label":"Weekly","used_percent":12},{"label":"Sonnet weekly","used_percent":42},{"label":"Monthly","used_percent":0}]"#))
        suite.expect(multiple?.current(at: now)?.limits.windows.map(\.kind) == [.weekly, .other, .other],
                     "all numeric windows survive, even without a primary/session window")
        suite.expect(multiple?.limits.windows.last?.remainingFraction == 1,
                     "a genuine reported zero remains distinct from unavailable")
        suite.expect(NotchAgentSupport.focusedLimit(reading?.limits, focus: .weekly, now: now)?.usedPercent == 12,
                     "fresh Hermes account quota reaches the closed island")
        let mixed = AgentHermesLimits.parse(document(windows: #"[{"label":"Current session","used_percent":80,"resets_at":"2026-10-20T12:00:01Z"},{"label":"Weekly","used_percent":12,"resets_at":"2026-10-27T12:00:00Z"}]"#))
        suite.expect(NotchAgentSupport.focusedLimit(mixed?.limits, focus: .session, now: now.addingTimeInterval(2))?.usedPercent == 12,
                     "an expired Hermes window is excluded rather than renewed to zero")
        suite.expect(NotchAgentSupport.focusedLimit(reading?.limits, focus: .weekly, now: now.addingTimeInterval(600)) == nil,
                     "stale Hermes quota cannot remain on the closed island")
        var snapshot = AgentUsageSnapshot()
        snapshot.limits[.hermes] = mixed?.limits
        suite.expect(NotchAgentSupport.restingLimit(snapshot, focus: .session, now: now.addingTimeInterval(2))?.window.usedPercent == 12,
                     "the resting island excludes an expired Hermes window too")
        var today = AgentPeriodUsage()
        today.byProvider[.hermes] = AgentTotals(cost: 100)
        today.byProvider[.codex] = AgentTotals(cost: 2)
        today.total.cost = 102
        snapshot.periods[.today] = today
        suite.expect(snapshot.dailyBudgetCost == 2, "cumulative Hermes snapshots cannot trigger a daily-budget alert")
    }
}
