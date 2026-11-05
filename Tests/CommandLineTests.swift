// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// `vors` shares the app's executable, so an ordinary launch must stay an
/// ordinary launch. The request also crosses a boundary any local process can
/// reach, and keep awake turns an unknown duration into an indefinite session.
enum CommandLineContract {
    static func run(_ suite: TestSuite) {
        typealias Support = CommandLineSupport
        let app = "/Applications/Vorssaint.app/Contents/MacOS/Vorssaint"

        suite.expect(Support.command(in: [app]) == nil, "an ordinary launch stays the app")
        suite.expect(Support.command(in: [app, "--selftest"]) == nil, "app flags stay with the app")
        suite.expect(Support.command(in: [app, "keepawake", "off"]) == .keepAwake(.off),
                     "the app's own name reaches the commands without the link")

        suite.expect(Support.command(in: ["vors"]) == .help, "the tool alone shows help")
        suite.expect(Support.command(in: ["/usr/local/bin/vors", "--help"]) == .help, "the tool's full path shows help")
        if case .invalid? = Support.command(in: ["vors", "--selftest"]) {} else {
            suite.expect(false, "the tool never falls through to starting the app")
        }

        suite.expect(Support.command(in: ["vors", "keepawake"]) == .keepAwake(.start), "no option starts a session")
        suite.expect(Support.command(in: ["vors", "keepawake", "on"]) == .keepAwake(.start), "on starts a session")
        suite.expect(Support.command(in: ["vors", "keepawake", "status"]) == .keepAwake(.status), "status is read only")
        suite.expect(Support.command(in: ["vors", "keepawake", "-m", "120"]) == .keepAwake(.minutes(120)), "-m reads minutes")
        suite.expect(Support.command(in: ["vors", "keepawake", "--minutes", "90"]) == .keepAwake(.minutes(90)),
                     "--minutes reads minutes")
        suite.expect(Support.command(in: ["vors", "keepawake", "-m", "0"]) == .keepAwake(.minutes(0)),
                     "zero asks for no end time")
        suite.expect(Support.command(in: ["vors", "keepawake", "-m", "\(Support.maximumMinutes)"])
                        == .keepAwake(.minutes(Support.maximumMinutes)), "the longest session is accepted")

        let rejected = [["-m"], ["-m", "soon"], ["-m", "-5"], ["-m", "1.5"], ["-m", "\(Support.maximumMinutes + 1)"],
                        ["-m", "5", "off"], ["off", "now"], ["on", "-m"], ["status", "-m"], ["--mintues", "5"]]
        for words in rejected {
            if case .invalid? = Support.command(in: ["vors", "keepawake"] + words) { continue }
            suite.expect(false, "\(words) is rejected before reaching the app")
        }

        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        for minutes in Defaults.allowedDurations {
            suite.expect(Support.endDate(forMinutes: minutes, now: now) == nil, "\(minutes) stays a preset")
        }
        for minutes in [1, 45, 90, 121, Support.maximumMinutes] {
            suite.expect(Support.endDate(forMinutes: minutes, now: now) == now.addingTimeInterval(TimeInterval(minutes) * 60),
                         "\(minutes) becomes an end time, never an indefinite session")
        }

        let actions: [Support.KeepAwakeAction] = [.start, .off, .status, .minutes(0), .minutes(90)]
        for action in actions {
            let request = Support.Request(id: "a", action: action)
            suite.expect(Support.Request(userInfo: request.userInfo) == request, "\(action) survives the trip to the app")
        }
        let forged: [[AnyHashable: Any]?] = [
            nil, [:], ["id": "a"], ["action": "off"], ["id": 1, "action": "off"], ["id": "a", "action": "toggle"],
            ["id": "a", "action": "minutes"], ["id": "a", "action": "minutes", "minutes": "90"],
            ["id": "a", "action": "minutes", "minutes": -1],
            ["id": "a", "action": "minutes", "minutes": Support.maximumMinutes + 1],
        ]
        for userInfo in forged {
            suite.expect(Support.Request(userInfo: userInfo) == nil, "\(String(describing: userInfo)) is ignored")
        }

        let timed = Support.Answer(id: "a", isAvailable: true, isActive: true, endDate: now)
        suite.expect(Support.Answer(userInfo: timed.userInfo) == timed, "an end time survives the trip back")
        let open = Support.Answer(id: "a", isAvailable: true, isActive: true, endDate: nil)
        suite.expect(Support.Answer(userInfo: open.userInfo) == open, "no end time stays indefinite")
        suite.expect(Support.Answer(userInfo: ["id": "a"]) == nil, "a partial answer is ignored")

        suite.expect(Support.requestName(bundleIdentifier: "com.vorssaint.utils")
                        != Support.requestName(bundleIdentifier: "com.vorssaint.utils.dev"),
                     "the Developer app never answers for the official one")
    }
}
