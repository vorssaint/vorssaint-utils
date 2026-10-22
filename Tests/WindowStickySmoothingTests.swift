// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowStickySmoothingTests {
    static func run(expect: (Bool, String) -> Void) {
        typealias M = WindowStickySmoothing
        let a = CGRect(x: 600, y: 0, width: 400, height: 800)

        expect(M.deviation(a, a) == 0, "equal frames deviate by zero")
        expect(M.deviation(a, a.offsetBy(dx: 3, dy: -5)) == 5, "deviation is the largest component")
        expect(M.deviation(a, CGRect(x: 600, y: 0, width: 396, height: 800)) == 4, "a size change counts too")

        // Jitter floor: tiny changes are not written.
        expect(!M.shouldWrite(deviation: 1), "one point is not written")
        expect(!M.shouldWrite(deviation: M.jitterThreshold), "the threshold itself is not written")
        expect(M.shouldWrite(deviation: M.jitterThreshold + 0.5), "above the threshold is written")
        let follower = CGRect(x: 608, y: 0, width: 392, height: 800)
        let nudged = CGRect(x: 0, y: 0, width: 601.5, height: 800)
        expect(WindowStickyEdgeSupport.flushedFrame(edge: .right, driver: nudged, follower: follower, gap: 8) == .unaffected,
               "a 1.5 point driver step leaves the follower alone")
        let big = WindowStickyEdgeSupport.flushedFrame(edge: .right, driver: CGRect(x: 0, y: 0, width: 610, height: 800),
                                                       follower: follower, gap: 8)
        var moved = false
        if case .follow = big { moved = true }
        expect(moved, "a 10 point driver step moves the follower")

        // Settle correction only for a real deviation.
        expect(!M.settleNeeded(deviation: 1), "a one point deviation is left standing at the end")
        expect(!M.settleNeeded(deviation: 0), "no deviation needs no correction")
        expect(M.settleNeeded(deviation: 1.5), "a larger deviation is corrected at the end")

        // Missed echo: close to our write and soon after, but not in the guard.
        expect(M.isMissedEcho(reported: a.offsetBy(dx: 5, dy: 0), lastWritten: a, secondsSinceWrite: 0.05),
               "a near frame right after our write is a missed echo")
        expect(!M.isMissedEcho(reported: a.offsetBy(dx: 5, dy: 0), lastWritten: a, secondsSinceWrite: 0.5),
               "a late frame is not counted as a missed echo")
        expect(!M.isMissedEcho(reported: a.offsetBy(dx: 80, dy: 0), lastWritten: a, secondsSinceWrite: 0.05),
               "a far frame is a real move")
        expect(!M.isMissedEcho(reported: a, lastWritten: nil, secondsSinceWrite: 0.05), "no write, no echo")
        expect(WindowStickyEchoGuard.matches(a, a.offsetBy(dx: 2, dy: 0)), "an app that rounds by two points still echoes")
        expect(!WindowStickyEchoGuard.matches(a, a.offsetBy(dx: 2.5, dy: 0)), "beyond the tolerance is no echo")

        // Pacer: a second write inside one step is deferred and counted.
        var pacer = WindowStickyWritePacer()
        expect(pacer.decide(now: 1.0) == .writeNow, "the first write goes out")
        pacer.noteWrite(at: 1.0)
        var waits = false
        if case .deferred(let delay) = pacer.decide(now: 1.002) { waits = delay > 0 && delay <= M.minimumWriteInterval }
        expect(waits, "a write 2 ms later waits for the rest of the step")
        expect(pacer.decide(now: 1.0 + M.minimumWriteInterval + 0.001) == .writeNow, "after the step the next write goes out")
        pacer.noteWrite(at: 1.005)
        pacer.noteWrite(at: 1.2)
        expect(pacer.count == 3, "writes are counted per drag")
        expect(pacer.multiPerStep == 1, "only the write within one 60 Hz step counts as a multiple")
        pacer.resetCount()
        expect(pacer.count == 0 && pacer.multiPerStep == 0, "the counters reset after a drag")
    }
}
