// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowStickyEchoTests {
    static func run(expect: (Bool, String) -> Void) {
        typealias S = WindowStickyEdgeSupport
        let written = CGRect(x: 600, y: 0, width: 400, height: 800)

        // Echo recognition goes by the frame, not by time.
        var echoes = WindowStickyEchoGuard()
        echoes.noteWrite(written, now: 10)
        expect(echoes.classify(reported: written, now: 10.01) == .echo, "the frame we wrote is an echo")
        expect(echoes.classify(reported: written.offsetBy(dx: 0.5, dy: 0), now: 10.02) == .echo,
               "a sub-point difference still counts as the echo")
        expect(echoes.classify(reported: CGRect(x: 640, y: 0, width: 360, height: 800), now: 10.02) == .real,
               "a different frame right after our write is a real move")
        expect(echoes.classify(reported: written, now: 10.9) == .echo, "a late echo is still recognised")
        expect(echoes.classify(reported: written, now: 11.2) == .real, "an echo entry is forgotten after its lifetime")

        var several = WindowStickyEchoGuard()
        for step in 0..<10 { several.noteWrite(written.offsetBy(dx: CGFloat(step) * 5, dy: 0), now: 20) }
        expect(several.expected.count == WindowStickyEchoGuard.capacity, "the guard keeps only the latest writes")
        expect(several.classify(reported: written.offsetBy(dx: 45, dy: 0), now: 20.01) == .echo,
               "the newest write is remembered")
        expect(several.classify(reported: written, now: 20.01) == .real, "an evicted write is no echo any more")

        // A drag of 60 events in one second: none may be swallowed, our echoes all are.
        var driver = CGRect(x: 0, y: 0, width: 500, height: 800)
        var follower = CGRect(x: 508, y: 0, width: 492, height: 800)
        var driverGuard = WindowStickyEchoGuard()
        var followerGuard = WindowStickyEchoGuard()
        driverGuard.noteWrite(driver, now: 0)
        followerGuard.noteWrite(follower, now: 0)
        let gap = S.facingGap(edge: .right, driver: driver, follower: follower)
        var processed = 0
        var echoed = 0
        var overlapped = false
        for step in 1...60 {
            let now = Double(step) / 60
            driver.size.width += 4
            if driverGuard.classify(reported: driver, now: now) == .real {
                processed += 1
                if case .follow(let target) = S.flushedFrame(edge: .right, driver: driver, follower: follower, gap: gap) {
                    follower = target
                    followerGuard.noteWrite(target, now: now)
                }
            }
            // The follower's echo arrives for every write.
            if followerGuard.classify(reported: follower, now: now + 0.002) == .echo { echoed += 1 }
            if follower.minX < driver.maxX { overlapped = true }
        }
        expect(processed == 60, "every one of 60 drag events in a second is processed")
        expect(echoed == 60, "every echo of our own writes is recognised")
        expect(follower.minX == driver.maxX + gap && follower.maxX == 1000, "the neighbour follows to the end with the gap kept")
        expect(!overlapped, "the neighbour never overlaps the driver during the drag")

        // The old rule (0.4 s quiet window per window) would have processed only a few of these.
        let oldRuleProcessed = (1...60).reduce((count: 0, quietUntil: 0.0)) { acc, step in
            let now = Double(step) / 60
            return now >= acc.quietUntil ? (acc.count + 1, now + 0.4) : acc
        }.count
        expect(oldRuleProcessed < 10, "the former fixed quiet window processed only \(oldRuleProcessed) of 60 events")

        // Flush position, exact and absolute.
        let a = CGRect(x: 0, y: 0, width: 500, height: 800)
        let b = CGRect(x: 500, y: 0, width: 500, height: 800)
        let lost = CGRect(x: 0, y: 0, width: 800, height: 800)
        expect(S.flushedFrame(edge: .right, driver: lost, follower: b, gap: 0) == .follow(CGRect(x: 800, y: 0, width: 200, height: 800)),
               "after lost events the neighbour is set flush in one step")
        expect(S.flushedFrame(edge: .right, driver: a, follower: b, gap: 0) == .unaffected,
               "a neighbour already flush stays untouched")
        expect(S.flushedFrame(edge: .right, driver: lost, follower: b, gap: 8) == .follow(CGRect(x: 808, y: 0, width: 192, height: 800)),
               "a layout gap is kept when setting flush")
        expect(S.flushedFrame(edge: .right, driver: lost, follower: b, gap: -20) == .follow(CGRect(x: 800, y: 0, width: 200, height: 800)),
               "a negative gap never lets the neighbour overlap")
        expect(S.flushedFrame(edge: .right, driver: CGRect(x: 0, y: 0, width: 950, height: 800), follower: b, gap: 0) == .tooSmall,
               "a neighbour squeezed below the minimum stays as it is")
        expect(S.flushedFrame(edge: .left, driver: CGRect(x: 300, y: 0, width: 700, height: 800), follower: a, gap: 0)
               == .follow(CGRect(x: 0, y: 0, width: 300, height: 800)), "a left neighbour is set flush at its right side")
        let top = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let bottom = CGRect(x: 0, y: 400, width: 1000, height: 400)
        expect(S.flushedFrame(edge: .bottom, driver: CGRect(x: 0, y: 0, width: 1000, height: 600), follower: bottom, gap: 0)
               == .follow(CGRect(x: 0, y: 600, width: 1000, height: 200)), "a lower neighbour is set flush below")
        expect(S.flushedFrame(edge: .top, driver: CGRect(x: 0, y: 250, width: 1000, height: 550), follower: top, gap: 0)
               == .follow(CGRect(x: 0, y: 0, width: 1000, height: 250)), "an upper neighbour is set flush above")
        expect(S.flushedFrame(edge: .right, driver: CGRect(x: 0, y: 0, width: 500, height: 500), follower: b, gap: 0) == .unaffected,
               "a change of the driver's other axis leaves the neighbour alone")
        expect(S.facingGap(edge: .right, driver: a, follower: CGRect(x: 508, y: 0, width: 492, height: 800)) == 8,
               "the gap between facing edges is measured")
        expect(S.facingGap(edge: .right, driver: a, follower: CGRect(x: 496, y: 0, width: 504, height: 800)) == 0,
               "an overlap at the start counts as flush")

        // End of a drag: the idle tracker reports it once, and not while events continue.
        var idle = WindowStickyIdleTracker()
        expect(!idle.consumeIfIdle(at: 5), "without any event there is no drag end")
        idle.note(at: 5.0)
        idle.note(at: 5.1)
        expect(!idle.consumeIfIdle(at: 5.25), "the drag is not over while events keep coming")
        expect(idle.consumeIfIdle(at: 5.31), "a drag without a last event ends after the quiet interval")
        expect(!idle.consumeIfIdle(at: 6), "the end is reported only once")

        // Log line shape, read by Tools/sticky-snap-report.py.
        expect(WindowStickyEventLog.line(time: 1.5, kind: "ax", window: 7, frame: written, note: "drive")
               == "1.5000 ax 7 600.0 0.0 400.0 800.0 drive", "a log line carries time, kind, window, frame and note")
        expect(WindowStickyEventLog.line(time: 1.5, kind: "stop", window: 0, frame: .zero) == "1.5000 stop 0 0.0 0.0 0.0 0.0",
               "a log line without a note has no trailing space")
    }
}
