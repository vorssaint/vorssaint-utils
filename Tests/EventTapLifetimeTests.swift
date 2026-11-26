// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The shared tap's re-arm decisions, tested without an event chain: a tap can
/// only be re-armed while its owner still holds it, and a refused re-arm is
/// decided once rather than on every notice.
enum EventTapLifetimeTests {
    static func run(_ suite: TestSuite) {
        suite.run("event tap lifetime") {
            var featureWanted = true
            var asks = 0
            let lifetime = EventTapLifetime(rearm: {
                asks += 1
                return featureWanted
            })

            suite.expect(lifetime.recovery() == .rearm,
                         "a timeout notice re-arms a tap whose feature still wants it")
            suite.expect(asks == 1 && lifetime.isActive,
                         "a re-armed tap keeps its lifetime and its policy")
            suite.expect(lifetime.recovery() == .rearm,
                         "a second timeout re-arms the same tap instead of ignoring it")

            featureWanted = false
            suite.expect(lifetime.recovery() == .tearDown,
                         "a disabled feature tears the tap down instead of re-arming it")
            suite.expect(!lifetime.isActive,
                         "a refused re-arm ends the tap's lifetime")

            let asksBeforeStopped = asks
            suite.expect(lifetime.recovery() == .leaveStopped,
                         "a stopped lifetime refuses the notice that follows its teardown")
            suite.expect(lifetime.recovery() == .leaveStopped && asks == asksBeforeStopped,
                         "a stopped tap is not asked again, so a refused teardown cannot loop")

            var askedWhileWanted = 0
            let stoppedByHand = EventTapLifetime(rearm: {
                askedWhileWanted += 1
                return true
            })
            stoppedByHand.stop()
            suite.expect(stoppedByHand.recovery() == .leaveStopped && askedWhileWanted == 0,
                         "a tap the owner suspended by hand stays stopped although it is wanted")
            suite.expect(!stoppedByHand.stop(),
                         "stopping a lifetime twice does not restart or repeat it")
        }
    }
}
