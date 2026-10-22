// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure rules that keep a coupled neighbour from twitching: a jitter floor for
/// writes, a floor for the settle correction, a write pacer and the test for
/// an echo that was not recognised. No Accessibility calls.
enum WindowStickySmoothing {
    /// Changes up to this many points are not written (micro movements).
    static let jitterThreshold: CGFloat = 2
    /// The settle correction at the end of a drag runs only above this.
    static let settleThreshold: CGFloat = 1
    /// Frames this close to a written frame count as our own echo (apps round).
    static let echoTolerance: CGFloat = 2
    /// Two writes to one follower closer than this are merged into the later one.
    static let minimumWriteInterval: TimeInterval = 1.0 / 120.0
    /// A foreign-looking frame this soon after our write is a missed echo.
    static let missedEchoWindow: TimeInterval = 0.3

    /// The largest difference of origin or size between two frames, in points.
    static func deviation(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height))
    }

    /// Whether a drag step is large enough to write.
    static func shouldWrite(deviation: CGFloat) -> Bool { deviation > jitterThreshold }

    /// Whether the settle step at the end of a drag has anything to correct.
    static func settleNeeded(deviation: CGFloat) -> Bool { deviation > settleThreshold }

    /// A reported frame that is not an echo but sits within the echo tolerance
    /// of what we wrote a moment ago: the guard was too strict for that app.
    static func isMissedEcho(reported: CGRect, lastWritten: CGRect?, secondsSinceWrite: TimeInterval) -> Bool {
        guard let lastWritten, secondsSinceWrite >= 0, secondsSinceWrite <= missedEchoWindow else { return false }
        return deviation(reported, lastWritten) <= 4 * echoTolerance
    }
}

/// Limits writes per follower and counts them per drag step.
struct WindowStickyWritePacer {
    enum Decision: Equatable {
        case writeNow
        /// Too soon after the last write; retry after this many seconds.
        case deferred(by: TimeInterval)
    }

    private(set) var lastWrite: TimeInterval?
    /// Writes since `resetCount()`, one drag of one follower.
    private(set) var count = 0
    /// Writes that followed the previous one within one 60 Hz step.
    private(set) var multiPerStep = 0

    mutating func decide(now: TimeInterval) -> Decision {
        guard let lastWrite else { return .writeNow }
        let elapsed = now - lastWrite
        return elapsed >= WindowStickySmoothing.minimumWriteInterval
            ? .writeNow : .deferred(by: WindowStickySmoothing.minimumWriteInterval - elapsed)
    }

    mutating func noteWrite(at now: TimeInterval) {
        if let lastWrite, now - lastWrite < 1.0 / 60.0 { multiPerStep += 1 }
        lastWrite = now
        count += 1
    }

    mutating func resetCount() {
        count = 0
        multiPerStep = 0
    }
}
