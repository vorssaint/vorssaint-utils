// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentWaitTests {
    private typealias Status = AgentWaitSupport.SessionStatus

    static func run(_ suite: TestSuite) {
        // pid 1 always started at 50 and its files were last written at 100,
        // so a start no later than 100 is this same process.
        let startedBeforeFile: (Int32) -> UInt64? = { $0 == 1 ? 50 : nil }

        let waiting = Status(status: "waiting", pid: 1, name: "vorssaint-utils-bf", cwd: "/tmp/vorssaint-utils", modifiedAt: 100)
        let busy = Status(status: "busy", pid: 2, name: "other", cwd: "/tmp/other", modifiedAt: 100)
        let idle = Status(status: "idle", pid: 3, name: "third", cwd: "/tmp/third", modifiedAt: 100)
        let dead = Status(status: "waiting", pid: 4, name: "dead", cwd: "/tmp/dead", modifiedAt: 100)
        let unnamed = Status(status: "waiting", pid: 1, name: nil, cwd: "/Users/me/Documents/some-project", modifiedAt: 100)
        let blank = Status(status: "waiting", pid: 1, name: "", cwd: nil, modifiedAt: 100)

        suite.expect(AgentWaitSupport.waitingSessions([waiting, busy, idle], processStartTime: startedBeforeFile)
                     == [AgentWaitingSession(id: 1, name: "vorssaint-utils-bf")],
                     "only a session the CLI marked waiting is reported")

        suite.expect(AgentWaitSupport.waitingSessions([dead], processStartTime: startedBeforeFile).isEmpty,
                     "a waiting status left behind by a process no longer running is not reported")

        // macOS handed pid 1 to an unrelated process that started at 150,
        // after this file was last written at 100 — it cannot be the writer.
        let reused = Status(status: "waiting", pid: 1, name: "reused", cwd: nil, modifiedAt: 100)
        suite.expect(AgentWaitSupport.waitingSessions([reused]) { $0 == 1 ? 150 : nil }.isEmpty,
                     "a pid reused by a newer process after the file was last written is not reported")

        suite.expect(AgentWaitSupport.waitingSessions([unnamed], processStartTime: startedBeforeFile)
                     == [AgentWaitingSession(id: 1, name: "some-project")],
                     "a session with no name falls back to its working directory's last component")

        suite.expect(AgentWaitSupport.waitingSessions([blank], processStartTime: startedBeforeFile).isEmpty,
                     "a blank name with no working directory to fall back to is skipped rather than shown empty")

        let second = Status(status: "waiting", pid: 1, name: "second", cwd: nil, modifiedAt: 100)
        let first = Status(status: "waiting", pid: 1, name: "first", cwd: nil, modifiedAt: 100)
        suite.expect(AgentWaitSupport.waitingSessions([second, first], processStartTime: startedBeforeFile).map(\.name)
                     == ["first", "second"],
                     "multiple waiting sessions are sorted by name")

        suite.expect(AgentWaitSupport.sessionName(Status(status: nil, pid: nil, name: "", cwd: "/a/b/c", modifiedAt: nil)) == "c",
                     "an empty name is treated the same as a missing one")

        let a = AgentWaitingSession(id: 1, name: "a")
        let b = AgentWaitingSession(id: 2, name: "b")
        suite.expect(AgentWaitSupport.newlyWaitingSessions(current: [a, b], previous: [a]) == [b],
                     "only a session absent from the previous scan counts as newly waiting")
        suite.expect(AgentWaitSupport.newlyWaitingSessions(current: [a], previous: [a, b]).isEmpty,
                     "a session that stopped waiting is not itself a new wait")
        suite.expect(AgentWaitSupport.newlyWaitingSessions(current: [], previous: [a, b]).isEmpty,
                     "a stop that clears every session produces no new waits")

        let now = Date()
        suite.expect(!AgentWaitSupport.waitedLongEnough(since: now, now: now.addingTimeInterval(1), minimum: 3)
                     && AgentWaitSupport.waitedLongEnough(since: now, now: now.addingTimeInterval(3), minimum: 3),
                     "a notice waits for the minimum hold before counting as long enough")
    }
}
