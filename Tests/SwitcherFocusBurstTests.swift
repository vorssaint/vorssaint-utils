// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// A Dock click on an application raises every one of its windows and the
/// window server announces focus for each. The burst exists so only the window
/// that actually kept focus is promoted to the use history (#4457).
enum SwitcherFocusBurstTests {
    static func run(_ suite: TestSuite) {
        suite.run("SwitcherFocusBurst") {
            var single = SwitcherFocusBurst()
            single.add(11, pid: 400)
            suite.expect(single.pid == 400, "the burst remembers the announced application")
            suite.expect(single.resolve(frontToBack: [11, 12, 13]) == 11,
                         "a single focus announcement promotes its own window")
            suite.expect(single.resolve(frontToBack: [11]) == nil,
                         "resolving empties the burst")

            var dockClick = SwitcherFocusBurst()
            for id: CGWindowID in [21, 22, 23] { dockClick.add(id, pid: 500) }
            suite.expect(dockClick.resolve(frontToBack: [21, 30, 22, 23]) == 21,
                         "a Dock click promotes only the first raised window when it stays in front")

            var raisedBehind = SwitcherFocusBurst()
            for id: CGWindowID in [31, 32, 33] { raisedBehind.add(id, pid: 550) }
            suite.expect(raisedBehind.resolve(frontToBack: [32, 31, 33]) == 32,
                         "the window the window server puts in front wins over the first announcement")

            var repeated = SwitcherFocusBurst()
            for id: CGWindowID in [21, 22, 23, 21] { repeated.add(id, pid: 500) }
            suite.expect(repeated.resolve(frontToBack: [23, 21, 22]) == 23,
                         "a repeated announcement neither duplicates nor reorders the candidates")

            var unlisted = SwitcherFocusBurst()
            for id: CGWindowID in [41, 42] { unlisted.add(id, pid: 600) }
            suite.expect(unlisted.resolve(frontToBack: [90, 91]) == 41,
                         "with no candidate on screen the first announcement is promoted")
            var emptyOrder = SwitcherFocusBurst()
            for id: CGWindowID in [51, 52] { emptyOrder.add(id, pid: 700) }
            suite.expect(emptyOrder.resolve(frontToBack: []) == 51,
                         "an empty window server order promotes the first announcement")

            var switchedApps = SwitcherFocusBurst()
            switchedApps.add(61, pid: 800)
            switchedApps.add(62, pid: 900)
            suite.expect(switchedApps.pid == 900,
                         "another application starts a new burst instead of joining the old one")
            suite.expect(switchedApps.resolve(frontToBack: [61, 62]) == 62,
                         "the new application's window is resolved on its own")

            var nothing = SwitcherFocusBurst()
            suite.expect(nothing.resolve(frontToBack: [71]) == nil,
                         "an empty burst promotes nothing")

            var reset = SwitcherFocusBurst()
            reset.add(81, pid: 950)
            reset.reset()
            suite.expect(reset.resolve(frontToBack: [81]) == nil,
                         "a reset burst promotes nothing")
        }
    }
}
