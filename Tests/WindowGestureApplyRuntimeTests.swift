// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// The move and resize gesture's frame-write queue, extracted from production on
/// every test build and run on a real serial queue. Only the write itself is
/// replaced, by one that can be held the way a busy app holds its answer.
enum WindowGestureApplyRuntimeTests {
    class Fixture {
        let gestureApplyQueue = DispatchQueue(label: "test window gesture apply", qos: .userInteractive)
        let gestureApplyLock = NSLock()
        var pendingGestureApply: (gesture: WindowPointerGesture, pointer: CGPoint)?
        var gestureApplyDraining = false
        /// Set before the first frame is queued and released by the test.
        var firstWriteHold: DispatchSemaphore?
        var writeDuration: TimeInterval = 0
        private let writtenLock = NSLock()
        private var writtenPositions: [CGFloat] = []

        var written: [CGFloat] {
            writtenLock.lock()
            defer { writtenLock.unlock() }
            return writtenPositions
        }

        func apply(_ gesture: WindowPointerGesture, pointer: CGPoint) {
            if let hold = firstWriteHold {
                firstWriteHold = nil
                _ = hold.wait(timeout: .now() + 1)
            }
            if writeDuration > 0 { Thread.sleep(forTimeInterval: writeDuration) }
            writtenLock.lock()
            writtenPositions.append(pointer.x)
            writtenLock.unlock()
        }
    }

    static func run(_ suite: TestSuite) {
        let gesture = WindowPointerGesture(window: AXUIElementCreateApplication(getpid()),
                                           kind: .move, button: .primary, originalFrame: .zero,
                                           pointerStart: .zero, lastAppliedAt: 0)

        let held = Host()
        let hold = DispatchSemaphore(value: 0)
        held.firstWriteHold = hold
        held.writeDuration = 0.02
        let queueStart = ProcessInfo.processInfo.systemUptime
        for step in 1...40 {
            held.enqueueGestureApply(gesture, pointer: CGPoint(x: CGFloat(step), y: 0))
        }
        held.enqueueGestureApply(gesture, pointer: CGPoint(x: 1000, y: 0))
        let queueTime = ProcessInfo.processInfo.systemUptime - queueStart
        let nothingWrittenWhileHeld = held.written.isEmpty
        hold.signal()
        held.flushGestureApplies()
        let written = held.written
        suite.expect(queueTime < 0.5 && nothingWrittenWhileHeld,
                     "queueing gesture frames never waits for the app to answer the frame before")
        suite.expect(written.count <= 2 && written == written.sorted(),
                     "frames queued behind a slow write coalesce to the newest position, in order")
        suite.expect(written.last == 1000,
                     "a gesture's last frame write lands before the end of the gesture continues")

        var lostFinals = 0
        for round in 0..<400 {
            let host = Host()
            host.writeDuration = round.isMultiple(of: 4) ? 0.0001 : 0
            for step in 0..<(1 + round % 12) {
                host.enqueueGestureApply(gesture, pointer: CGPoint(x: CGFloat(step), y: 0))
                if round.isMultiple(of: 3) { usleep(UInt32(round % 50)) }
            }
            host.enqueueGestureApply(gesture, pointer: CGPoint(x: 1000, y: 0))
            host.flushGestureApplies()
            if host.written.last != 1000 { lostFinals += 1 }
        }
        suite.expect(lostFinals == 0, "no gesture loses its final frame write, however the writes interleave")

        let idle = Host()
        let idleStart = ProcessInfo.processInfo.systemUptime
        idle.flushGestureApplies()
        suite.expect(ProcessInfo.processInfo.systemUptime - idleStart < 0.5 && idle.written.isEmpty,
                     "ending a gesture with nothing queued returns at once")
    }
}
