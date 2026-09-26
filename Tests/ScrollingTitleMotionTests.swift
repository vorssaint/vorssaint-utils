// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Uses the view's actual scroll decision with controlled environment inputs.
enum ScrollingTitleMotionTests {
    class Fixture {
        var scrolls = false
        var reduceMotion = false
        var overflows = false
    }

    static func run(_ suite: TestSuite) {
        let host = Host()
        for hovered in [false, true] {
            for overflow in [false, true] {
                for reduced in [false, true] {
                    host.scrolls = hovered
                    host.overflows = overflow
                    host.reduceMotion = reduced
                    suite.expect(host.shouldScroll == (hovered && overflow && !reduced),
                                 "title motion follows hover, overflow and Reduce Motion (\(hovered), \(overflow), \(reduced))")
                }
            }
        }
        host.scrolls = true
        host.overflows = true
        host.reduceMotion = true
        suite.expect(!host.shouldScroll, "a hovered overflowing title stays still under Reduce Motion")
        host.reduceMotion = false
        suite.expect(host.shouldScroll, "turning Reduce Motion off restores title scrolling")
    }
}
