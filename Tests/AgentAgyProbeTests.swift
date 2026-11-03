// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

enum AgentAgyProbeTests {
    static func run(_ suite: TestSuite) {
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        // Visible, attempted at t0: isDue false at t0+61 s, false at t0+299 s, true at t0+300 s
        suite.expect(!AgentAgyServer.isDue(now: t0.addingTimeInterval(61), attempted: t0, pageVisible: true, failures: 0, graceUntil: .distantPast),
                     "visible isDue is false at t0+61s")
        suite.expect(!AgentAgyServer.isDue(now: t0.addingTimeInterval(299), attempted: t0, pageVisible: true, failures: 0, graceUntil: .distantPast),
                     "visible isDue is false at t0+299s")
        suite.expect(AgentAgyServer.isDue(now: t0.addingTimeInterval(300), attempted: t0, pageVisible: true, failures: 0, graceUntil: .distantPast),
                     "visible isDue is true at t0+300s")

        // Background: false at t0+300 s, true at t0+900 s
        suite.expect(!AgentAgyServer.isDue(now: t0.addingTimeInterval(300), attempted: t0, pageVisible: false, failures: 0, graceUntil: .distantPast),
                     "background isDue is false at t0+300s")
        suite.expect(AgentAgyServer.isDue(now: t0.addingTimeInterval(900), attempted: t0, pageVisible: false, failures: 0, graceUntil: .distantPast),
                     "background isDue is true at t0+900s")

        // Visible backoff: failures 1, 2, 3 give intervals 600, 1200, 2400 s; failures 4 gives 3600 (cap); failures 50 gives 3600 and does not trap
        suite.expect(AgentAgyServer.interval(pageVisible: true, failures: 1) == 600,
                     "visible interval after 1 failure is 600s")
        suite.expect(AgentAgyServer.interval(pageVisible: true, failures: 2) == 1200,
                     "visible interval after 2 failures is 1200s")
        suite.expect(AgentAgyServer.interval(pageVisible: true, failures: 3) == 2400,
                     "visible interval after 3 failures is 2400s")
        suite.expect(AgentAgyServer.interval(pageVisible: true, failures: 4) == 3600,
                     "visible interval after 4 failures is capped at 3600s")
        suite.expect(AgentAgyServer.interval(pageVisible: true, failures: 50) == 3600,
                     "visible interval after 50 failures does not trap and is capped at 3600s")

        // Background backoff: failures 1 gives 1800, 2 gives 3600, 3 gives 3600
        suite.expect(AgentAgyServer.interval(pageVisible: false, failures: 1) == 1800,
                     "background interval after 1 failure is 1800s")
        suite.expect(AgentAgyServer.interval(pageVisible: false, failures: 2) == 3600,
                     "background interval after 2 failures is 3600s")
        suite.expect(AgentAgyServer.interval(pageVisible: false, failures: 3) == 3600,
                     "background interval after 3 failures is capped at 3600s")

        // Zero failures after failures gives the base interval again
        suite.expect(AgentAgyServer.interval(pageVisible: true, failures: 0) == 300,
                     "zero failures gives the base interval 300s")

        // Grace: with graceUntil = t0 + 120 and attempted = .distantPast, isDue is false at t0+119 and true at t0+120
        let graceUntil = t0.addingTimeInterval(120)
        suite.expect(!AgentAgyServer.isDue(now: t0.addingTimeInterval(119), attempted: .distantPast, pageVisible: true, failures: 0, graceUntil: graceUntil),
                     "isDue is false within grace period at t0+119s")
        suite.expect(AgentAgyServer.isDue(now: t0.addingTimeInterval(120), attempted: .distantPast, pageVisible: true, failures: 0, graceUntil: graceUntil),
                     "isDue is true once grace period expires at t0+120s")

        // launch with a real executable URL (use /bin/sh as the stand-in agy path)
        let standIn = URL(fileURLWithPath: "/bin/sh")
        let launchResult = AgentAgyServer.launch(executable: standIn)
        switch launchResult {
        case .success(let plan):
            suite.expect(plan.url.path == "/usr/bin/sandbox-exec", "launch URL is /usr/bin/sandbox-exec")
            let expectedArgs = ["-p", AgentAgyServer.sandboxProfile, "/bin/sh", "-p", "/usage", "--output-format", "json"]
            suite.expect(plan.arguments == expectedArgs, "launch arguments match sandbox parameters")
        case .failure(let error):
            suite.expect(false, "launch should succeed with valid executable: \(error)")
        }

        // launch(executable:..., sandboxExec: "/nonexistent/sandbox-exec") returns .failure(.failed("sandbox-exec unavailable"))
        let missingSandboxResult = AgentAgyServer.launch(executable: standIn, sandboxExec: "/nonexistent/sandbox-exec")
        var missingSandboxFailed = false
        if case .failure(let f) = missingSandboxResult, f == .failed("sandbox-exec unavailable") {
            missingSandboxFailed = true
        }
        suite.expect(missingSandboxFailed,
                     "launch with nonexistent sandbox-exec returns failure")

        // sandboxProfile contains (deny appleevent-send) and /usr/bin/open
        suite.expect(AgentAgyServer.sandboxProfile.contains("(deny appleevent-send)"),
                     "sandboxProfile contains (deny appleevent-send)")
        suite.expect(AgentAgyServer.sandboxProfile.contains("/usr/bin/open"),
                     "sandboxProfile contains /usr/bin/open")

        // Request().run with nonexistent sandboxExec returns that failure and starts nothing
        let tempDir = FileManager.default.temporaryDirectory
        let runResult = AgentAgyServer.Request().run(executable: standIn, home: tempDir, sandboxExec: "/nonexistent/sandbox-exec")
        suite.expect(runResult == .failure(.failed("sandbox-exec unavailable")),
                     "Request.run with nonexistent sandboxExec returns failure and starts nothing")

        let fixtureDir = tempDir.appending(path: "agy-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDir) }
        let json = #"{"command":{"data":{"groups":[]}}}"#
        func fixture(_ name: String, _ body: String) -> URL {
            let url = fixtureDir.appending(path: name)
            try? ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }
        func request(_ name: String, _ body: String, timeout: TimeInterval = 2) -> Result<AgentLimits, AgentAgyServer.Failure> {
            AgentAgyServer.Request().run(executable: standIn, home: fixtureDir, timeout: timeout, sandboxExec: fixture(name, body).path)
        }
        if case .success(let limits) = request("success", "[ . -ef \"$HOME\" ] && [ \"$HOME\" = '\(fixtureDir.path)' ] && [ \"$AGY_CLI_DISABLE_AUTO_UPDATE\" = true ] || exit 8; printf '%s' '\(json)'; printf noise >&2") {
            suite.expect(limits.provider == .agy && limits.windows.isEmpty, "Request parses JSON while discarding stderr noise")
        } else { suite.expect(false, "Request succeeds with valid JSON and stderr noise") }
        let largeResult = request("large", "printf '%s' '\(json)'; head -c 200000 /dev/zero | tr '\\000' ' '")
        suite.expect({ if case .success = largeResult { return true }; return false }(), "Request drains large stdout and parses JSON")
        suite.expect(request("nonzero", "printf '%s' '\(json)'; exit 7") == .failure(.failed("agy exited with status 7")),
                     "Request rejects valid JSON from nonzero exit")
        let preCancelled = AgentAgyServer.Request()
        preCancelled.cancel()
        suite.expect(preCancelled.run(executable: standIn, home: fixtureDir, sandboxExec: fixture("unused", "exit 0").path) == .failure(.failed("Cancelled")),
                     "Request preserves cancellation before launch")
        let runningPID = fixtureDir.appending(path: "running.pid")
        let runningRequest = AgentAgyServer.Request()
        let runningResult = ProbeResultBox()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            runningResult.set(runningRequest.run(executable: standIn, home: fixtureDir, timeout: 2,
                                                 sandboxExec: fixture("during", "echo $$ > '\(runningPID.path)'; while :; do :; done").path))
            finished.signal()
        }
        let cancelDeadline = Date().addingTimeInterval(1)
        while !FileManager.default.fileExists(atPath: runningPID.path) && Date() < cancelDeadline { Thread.sleep(forTimeInterval: 0.01) }
        let childStarted = FileManager.default.fileExists(atPath: runningPID.path)
        let cancelStart = Date()
        runningRequest.cancel()
        let cancelFinished = finished.wait(timeout: .now() + 2) == .success
        suite.expect(childStarted && cancelFinished
                        && runningResult.get() == .failure(.failed("Cancelled"))
                        && Date().timeIntervalSince(cancelStart) < 2,
                     "Request cancellation during run returns promptly")
        if let cancelledPID = Int32((try? String(contentsOf: runningPID, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") {
            suite.expect(kill(cancelledPID, 0) == -1 && errno == ESRCH, "cancelled request child no longer exists")
        } else { suite.expect(false, "cancelled request wrote PID") }

        let pidFile = fixtureDir.appending(path: "stubborn.pid")
        let timeoutStart = Date()
        let timeoutResult = request("stubborn", "trap '' TERM; echo $$ > '\(pidFile.path)'; while :; do :; done", timeout: 1)
        let pid = Int32((try? String(contentsOf: pidFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        suite.expect(pid != nil && timeoutResult == .failure(.timeout) && Date().timeIntervalSince(timeoutStart) < 5,
                     "Request force-kills TERM-ignoring child on timeout")
        if let pid { suite.expect(kill(pid, 0) == -1 && errno == ESRCH, "timed out request child no longer exists") }
        else { suite.expect(false, "stubborn request wrote PID") }
    }

    private final class ProbeResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<AgentLimits, AgentAgyServer.Failure>?
        func set(_ value: Result<AgentLimits, AgentAgyServer.Failure>) { lock.lock(); result = value; lock.unlock() }
        func get() -> Result<AgentLimits, AgentAgyServer.Failure>? { lock.lock(); defer { lock.unlock() }; return result }
    }
}
