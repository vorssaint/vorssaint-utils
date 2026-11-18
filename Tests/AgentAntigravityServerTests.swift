// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentAntigravityServerTests {
    enum NotchAgentSupport {
        static let defaultLimitThreshold = 80.0
        static func limitThreshold() -> Double? { defaultLimitThreshold }
        static var used = true
        static func limitsInUse(pageShown: Bool) -> Bool { used || pageShown }
    }

    class Fixture {
        var running = true
        var paused = false
        var online = true
        var providers: [AgentProvider] = [.antigravity]
        var pageVisible = false
        var antigravityAccountRequest: AgentAntigravityServer.Request?
        var antigravityAccountAttempted = Date.distantPast
        var antigravityAccountFailure: AgentAntigravityServer.Failure?
        var antigravityAccountUnreachable = 0
        var claudeAccountUnreachable = 0
        var antigravityAccountLimits: AgentLimits?
        var home = FileManager.default.temporaryDirectory
        var enabled: Set<AgentProvider> = [.antigravity]
        let store = AgentUsageStore()
        var previousLimits: [AgentProvider: AgentLimits] = [:]
        var warned: [String: (provider: AgentProvider, window: AgentLimitWindow)] = [:]
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
        parsing(suite)
        checks(suite)
        alerts(suite)
        processRunner(suite)
        discovery(suite)
    }

    private static func parsing(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-11-15T10:00:00Z")!
        let sample: [String: Any] = [
            "status": "SUCCESS",
            "command": [
                "name": "usage",
                "data": [
                    "groups": [
                        [
                            "name": "Claude and GPT models",
                            "buckets": [
                                [
                                    "id": "3p-weekly",
                                    "window": "weekly",
                                    "remaining_fraction": 0,
                                    "reset_time": "2026-11-19T13:49:36Z"
                                ],
                                [
                                    "id": "3p-5h",
                                    "window": "5h",
                                    "disabled": true,
                                    "remaining_fraction": 1
                                ]
                            ]
                        ],
                        [
                            "name": "Gemini Models",
                            "buckets": [
                                [
                                    "id": "gemini-weekly",
                                    "window": "weekly",
                                    "remaining_fraction": 0.98,
                                    "reset_time": "2026-11-21T06:26:21Z"
                                ],
                                [
                                    "id": "gemini-5h",
                                    "window": "5h",
                                    "remaining_fraction": 0.95,
                                    "reset_time": "2026-11-15T11:46:12Z"
                                ]
                            ]
                        ],
                        [
                            "name": "Gemini 4 Argon",
                            "buckets": [
                                [
                                    "id": "gemini-argon-wtu-weekly",
                                    "window": "weekly",
                                    "remaining_fraction": 1,
                                    "reset_time": "2026-11-22T06:47:37Z"
                                ],
                                [
                                    "id": "expired-bucket",
                                    "window": "weekly",
                                    "remaining_fraction": 0.5,
                                    "reset_time": "2026-11-15T09:00:00Z"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let limits = AgentAntigravityServer.limits(sample, observed: now)
        suite.expect(limits?.provider == .antigravity && limits?.source == .account && limits?.observedAt == now,
                     "parsed Antigravity limits carry account source and observation time")
        suite.expect(limits?.windows.map(\.id) == [
            "antigravity.gemini-weekly",
            "antigravity.gemini-5h",
            "antigravity.3p-weekly",
            "antigravity.gemini-argon-wtu-weekly"
        ], "primary Gemini pool sorts first, disabled buckets and expired windows are excluded")
        suite.expect(limits?.windows.prefix(2).allSatisfy { $0.scope == nil } == true
                        && limits?.windows[2].scope == "Claude/GPT"
                        && limits?.windows[3].scope == "Gemini 4 Argon",
                     "primary pool leaves scope nil for limit focus while secondary pools keep distinct scopes")
        suite.expectClose(limits?.windows[0].usedPercent ?? -1, 2.0,
                          "remaining_fraction maps to usedPercent", tol: 0.0001)
        suite.expectClose(limits?.windows[1].usedPercent ?? -1, 5.0,
                          "session remaining_fraction maps to usedPercent", tol: 0.0001)
        suite.expect(limits?.windows[2].usedPercent == 100 && limits?.windows[3].usedPercent == 0,
                     "zero and full remaining fractions clamp cleanly to 100 and 0 percent used")

        let afterSession = AgentTimestamp.parse("2026-11-15T12:00:00Z")!
        suite.expect(AgentAntigravityServer.current(limits, now: afterSession)?.windows.contains(where: { $0.id == "antigravity.gemini-5h" }) == false
                        && AgentAntigravityServer.current(limits, now: AgentTimestamp.parse("2026-11-23T00:00:00Z")!) == nil,
                     "expired Antigravity windows drop independently without inventing zero usage")

        suite.expect(AgentAntigravityServer.parseVersion("1.5.9\n").map { $0 == (1, 5, 9) } == true
                        && AgentAntigravityServer.parseVersion("agy v1.1.11-beta.1").map { $0 == (1, 1, 11) } == true
                        && !AgentAntigravityServer.supportsUsageCommand(Data("1.1.10\n".utf8))
                        && !AgentAntigravityServer.supportsUsageCommand(Data("unknown".utf8))
                        && AgentAntigravityServer.supportsUsageCommand(Data("1.1.11\n".utf8))
                        && AgentAntigravityServer.supportsUsageCommand(Data("1.5.9\n".utf8)),
                     "version gating requires agy >= 1.1.11 before issuing /usage")

        suite.expect(AgentAntigravityServer.interval(after: nil, pageVisible: true) == 60
                        && AgentAntigravityServer.interval(after: nil, pageVisible: false) == 300
                        && [0, 1, 2, 3, 4, 9].map { AgentAntigravityServer.interval(after: .unreachable, repeated: $0, pageVisible: true) }
                            == [300, 300, 600, 1_200, 1_800, 1_800]
                        && [AgentAntigravityServer.Failure.missing, .needsSignIn, .outdated].allSatisfy {
                            AgentAntigravityServer.interval(after: $0, pageVisible: true) == 1_800 },
                     "Antigravity polling matches the minute visible, five-minute background, and exponential failure schedule")

        // stderr shares the pipe: agy's Go log lines, some with braces, can
        // come before the one-line JSON result.
        let result = #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","window":"5h","remaining_fraction":0.5,"reset_time":"2026-11-15T11:46:12Z"}]}]}}}"#
        let noisy = "I1115 16:18:16.873900 51 server.go:2543] Starting language server {pid: 10517}\n"
            + "E1115 16:18:16.874020 51 server.go:2457] crash reporter: {dir: unset}\n" + result + "\n"
        let parsed = AgentAntigravityServer.parseUsageResult(Data(noisy.utf8), status: 0, observed: now)
        suite.expect((try? parsed.get().windows.map(\.id)) == ["antigravity.gemini-5h"],
                     "log lines with braces before the JSON result do not hide the usage reading")
    }

    private static func checks(_ suite: TestSuite) {
        defer { NotchAgentSupport.used = true }
        let host = Host()
        var now = Date(timeIntervalSince1970: 2_000_000)
        func wait() -> TimeInterval {
            (1...180).map { TimeInterval($0) * 60 }.first { host.antigravityLimitsDue(at: now + $0, pageShows: false) } ?? -1
        }
        var waits: [TimeInterval] = []
        for _ in 0..<5 {
            host.antigravityAccountAttempted = now
            host.noteAntigravityCheck(.unreachable)
            waits.append(wait())
            now += waits.last ?? 0
        }
        suite.expect(waits == [300, 600, 1_200, 1_800, 1_800],
                     "failing Antigravity CLI checks back off down to half an hour")

        host.antigravityAccountAttempted = now
        host.noteAntigravityCheck(.unreachable)
        host.networkChanged(online: false)
        let offline = !host.antigravityLimitsDue(at: now + 86_400, pageShows: true)
        host.networkChanged(online: true)
        suite.expect(offline && wait() == 300,
                     "Antigravity CLI is not polled offline and resets backoff when back online")

        NotchAgentSupport.used = false
        let unused = !host.antigravityLimitsDue(at: now + 86_400, pageShows: false)
        let shown = host.antigravityLimitsDue(at: now + 86_400, pageShows: true)
        host.pageVisible = true
        suite.expect(unused && shown && host.antigravityLimitsDue(at: now + 86_400, pageShows: false),
                     "Antigravity CLI runs only when limits are shown or alerted on")
    }

    private static func alerts(_ suite: TestSuite) {
        let host = Host()
        host.store.reportsTransitions = true
        let t0 = AgentTimestamp.parse("2026-11-15T09:00:00Z")!
        let t1 = AgentTimestamp.parse("2026-11-15T10:00:00Z")!
        let r5h = "2026-11-15T13:00:00Z"
        let r7d = "2026-11-21T06:26:21Z"
        func reading(sessionUsed: Double, at observed: Date) -> AgentLimits {
            AgentLimits(
                provider: .antigravity,
                windows: [
                    AgentLimitWindow(id: "antigravity.gemini-5h", kind: .session, minutes: 300, scope: nil,
                                     usedPercent: sessionUsed, resetsAt: AgentTimestamp.parse(r5h)),
                    AgentLimitWindow(id: "antigravity.gemini-weekly", kind: .weekly, minutes: 10_080, scope: nil,
                                     usedPercent: 10, resetsAt: AgentTimestamp.parse(r7d))
                ],
                observedAt: observed, source: .account
            )
        }
        host.clock = t0
        host.antigravityAccountLimits = reading(sessionUsed: 20, at: t0)
        host.refreshStoredAntigravityLimits(now: t0)
        host.checkLimits()
        host.clock = t1
        host.antigravityAccountLimits = reading(sessionUsed: 85, at: t1)
        host.refreshStoredAntigravityLimits(now: t1)
        host.checkLimits()
        let tReset = AgentTimestamp.parse("2026-11-15T13:05:00Z")!
        host.clock = tReset
        host.refreshStoredAntigravityLimits(now: tReset)
        host.reportRenewals(now: tReset)
        suite.expect(host.events == [
            "warning antigravity.gemini-5h 2026-11-15T10:00:00Z",
            "reset antigravity.gemini-5h 2026-11-15T13:05:00Z"
        ], "Antigravity limits feed the shared threshold warning and renewal notifications")
    }

    private static func processRunner(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorssaint-agy-server-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let marker = folder.appending(path: "prompt-invoked")
            let tool = folder.appending(path: "agy")
            let script = """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              if [ "$FAKE_MODE" = "old" ]; then
                echo "1.1.10"
              elif [ "$FAKE_MODE" = "badver" ]; then
                echo "dev"
              else
                echo "1.5.9"
              fi
              exit 0
            fi
            touch "\(marker.path)"
            case "$FAKE_MODE" in
              ok)
                cat <<'JSON'
            {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","window":"5h","remaining_fraction":0.75,"reset_time":"2099-01-01T00:00:00Z"}]}]}}}
            JSON
                exit 0
                ;;
              signedOut)
                echo '{"status":"ERROR","message":"User must sign in before running /usage"}'
                exit 1
                ;;
              authWord)
                echo '{"status":"ERROR","message":"re-auth required for CLI"}'
                exit 1
                ;;
              authority)
                echo '{"status":"ERROR","message":"certificate authority check failed"}'
                exit 1
                ;;
              silent)
                sleep 10
                exit 0
                ;;
              *)
                echo "network timeout" >&2
                exit 1
                ;;
            esac
            """
            try Data(script.utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

            func run(_ mode: String, timeout: TimeInterval = 2) -> Result<AgentLimits, AgentAntigravityServer.Failure> {
                AgentAntigravityServer.Request().run(
                    tool, home: folder,
                    environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "FAKE_MODE": mode],
                    timeout: timeout
                )
            }

            let ok = run("ok")
            suite.expect((try? ok.get().windows.first?.usedPercent) == 25,
                         "valid agy 1.5.9 /usage JSON produces Antigravity limit windows")

            try? FileManager.default.removeItem(at: marker)
            let oldResult = run("old")
            let badVerResult = run("badver")
            suite.expect(oldResult == .failure(.outdated) && badVerResult == .failure(.outdated)
                            && !FileManager.default.fileExists(atPath: marker.path),
                         "outdated or unparseable agy versions fail cleanly without ever invoking /usage")

            suite.expect(run("signedOut") == .failure(.needsSignIn)
                            && run("authWord") == .failure(.needsSignIn)
                            && run("authority") == .failure(.unreachable)
                            && run("fail") == .failure(.unreachable),
                         "signed-out, auth-token, authority-error, and unreachable agy invocations return distinct failure states")

            let cancelReq = AgentAntigravityServer.Request()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancelReq.cancel() }
            let start = Date()
            let cancelled = cancelReq.run(tool, home: folder,
                                          environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "FAKE_MODE": "silent"],
                                          timeout: 10)
            suite.expect(cancelled == .failure(.unreachable) && Date().timeIntervalSince(start) < 4,
                         "cancelling an in-flight agy check terminates it promptly")
        } catch {
            suite.expect(false, "Antigravity CLI runner fixture: \(error)")
        }
    }

    private static func discovery(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory.appending(path: "vorssaint-agy-discovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        do {
            for rel in [".local/bin/agy", ".antigravity/bin/agy", ".gemini/bin/agy"] {
                let file = home.appending(path: rel)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
            let found = AgentAntigravityServer.candidates(home: home).map(\.path)
                .filter { $0.hasPrefix(home.path + "/") && FileManager.default.isExecutableFile(atPath: $0) }
                .map { String($0.dropFirst(home.path.count + 1)) }
            suite.expect(found == [".local/bin/agy", ".antigravity/bin/agy", ".gemini/bin/agy"],
                         "Antigravity CLI discovery prefers the standalone CLI over the app's ~/.gemini/bin copy")
        } catch {
            suite.expect(false, "Antigravity discovery fixture: \(error)")
        }
    }
}
