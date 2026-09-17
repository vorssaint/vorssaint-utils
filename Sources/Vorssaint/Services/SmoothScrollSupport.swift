// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure math for smooth mouse-wheel scrolling, kept free of AppKit so the
/// unit harness can pin it.
///
/// Each wheel event adds a distance to a per-axis budget. Animation frames
/// consume that budget according to elapsed time, so the same gesture has the
/// same shape on displays with different refresh rates.
enum SmoothScrollSupport {
    struct Axes: Equatable {
        let vertical: Double
        let horizontal: Double
    }

    struct Frame {
        let vertical: Double
        let horizontal: Double
        let finished: Bool
    }

    struct Engine {
        private(set) var remainingVertical: Double = 0
        private(set) var remainingHorizontal: Double = 0

        var isActive: Bool {
            remainingVertical != 0 || remainingHorizontal != 0
        }

        /// Adds already-normalized pixel distances. A reversal replaces the
        /// old tail on that axis so the first opposite tick answers at once.
        mutating func add(vertical: Double, horizontal: Double) {
            Self.add(vertical, to: &remainingVertical)
            Self.add(horizontal, to: &remainingHorizontal)
        }

        mutating func advance(elapsed: TimeInterval, response: Int) -> Frame {
            let vertical = SmoothScrollSupport.frameDelta(
                remaining: remainingVertical,
                elapsed: elapsed,
                response: response
            )
            let horizontal = SmoothScrollSupport.frameDelta(
                remaining: remainingHorizontal,
                elapsed: elapsed,
                response: response
            )
            remainingVertical -= vertical
            remainingHorizontal -= horizontal
            return Frame(vertical: vertical, horizontal: horizontal, finished: !isActive)
        }

        mutating func reset() {
            remainingVertical = 0
            remainingHorizontal = 0
        }

        private static func add(_ distance: Double, to remaining: inout Double) {
            guard distance.isFinite, distance != 0 else { return }
            remaining = SmoothScrollSupport.directionsOppose(distance, remaining)
                ? distance : remaining + distance
        }
    }

    /// The timer is only a wakeup cadence; elapsed time controls the motion.
    static let frameInterval: TimeInterval = 1.0 / 60.0

    /// A long main-thread stall must not dump an entire old tail in one jump.
    /// Normal display cadences from 30 Hz upward remain unmodified.
    static let maximumFrameInterval: TimeInterval = 1.0 / 20.0

    /// Leftovers smaller than this are flushed in one final frame.
    static let finishThreshold: Double = 1.0

    /// Adjustable distance of one wheel tick, in pixels. Keeping the existing
    /// key and default preserves every current user's scrolling speed.
    static let stepRange = 20...100
    static let defaultStep = 40

    /// Higher response values make the glide follow the wheel sooner. The
    /// default keeps the former 60 Hz curve's initial movement while making
    /// the rest independent from the timer cadence.
    static let responseRange = 0...100
    static let defaultResponse = 65
    private static let slowResponseTime: TimeInterval = 0.16
    private static let fastResponseTime: TimeInterval = 0.04
    /// Time-based equivalent of the former one-point minimum at 60 Hz.
    private static let minimumGlideSpeed = 60.0

    /// The tick count of a discrete wheel event. High-resolution wheels
    /// report fractions of a line in the fixed-point field while the integer
    /// field truncates to zero, so the fixed-point value wins when present.
    static func ticks(line: Double, fixedPoint: Double) -> Double {
        fixedPoint != 0 ? fixedPoint : line
    }

    /// The pixel distance a continuous wheel event asks for. The whole-point
    /// field is already in points and is what apps themselves read, so it is
    /// the one to trust; the fixed-point field counts lines and only comes in
    /// when the driver left the point field empty, which is the case for a
    /// movement smaller than one point. Reading points first also means the
    /// distance never depends on how many points a line happens to be worth,
    /// a scale any process can change underneath us. The step then scales the
    /// result, which is what makes the speed setting work on mice whose driver
    /// reports the wheel this way, and the default step travels exactly what
    /// the system would have.
    static func continuousDistance(fixedPointDelta: Double,
                                   pointDelta: Double,
                                   step: Double) -> Double {
        guard fixedPointDelta.isFinite, pointDelta.isFinite, step.isFinite else { return 0 }
        let pixels = pointDelta != 0
            ? pointDelta
            : fixedPointDelta * ScrollWheelSupport.pointsPerLine
        return pixels * (step / Double(defaultStep))
    }

    /// Splits a frame's distance into whole pixels to post and the fraction
    /// to carry into the next one. Rounding each frame on its own would drop
    /// up to half a pixel every time, which a fine-grained wheel feels as
    /// distance that never arrives.
    static func wholePixels(_ distance: Double, carry: Double) -> (pixels: Double, carry: Double) {
        let total = distance + carry
        guard total.isFinite else { return (0, 0) }
        let whole = total.rounded(.towardZero)
        return (whole, total - whole)
    }

    /// The last frame of a glide rounds its leftover out instead of carrying
    /// it forward, because there is no next frame to spend it in. Without
    /// this the glide lands up to a pixel short of what the wheel asked for,
    /// every single time.
    static func finalPixels(_ distance: Double, carry: Double) -> Double {
        let total = distance + carry
        guard total.isFinite else { return 0 }
        return total.rounded(.toNearestOrAwayFromZero)
    }

    /// Leftover fractions only help while the glide keeps its direction; a
    /// reversal drops them so the first pixel of the new direction is not
    /// eaten by what the old one left behind.
    static func carry(_ current: Double, continuing distance: Double) -> Double {
        directionsOppose(current, distance) ? 0 : current
    }

    private static func directionsOppose(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs != 0 && rhs != 0 && (lhs < 0) != (rhs < 0)
    }

    /// A vertical wheel tick with Shift held scrolls sideways instead. That
    /// redirect happens above the event tap, so once the original tick is
    /// swallowed the glide has to perform it. Measured against a scroll view:
    /// a tick of one line with Shift moves the content the same way a
    /// horizontal delta of the same sign does, so the tick keeps its sign. A
    /// wheel that already reports a horizontal axis is left alone so its
    /// native direction is preserved.
    static func axes(vertical: Double, horizontal: Double, shiftPressed: Bool) -> Axes {
        guard shiftPressed, vertical != 0, horizontal == 0 else {
            return Axes(vertical: vertical, horizontal: horizontal)
        }
        return Axes(vertical: 0, horizontal: vertical)
    }

    /// Exponential decay has the composition property needed here: two short
    /// elapsed intervals produce the same remaining distance as one interval
    /// with their combined duration.
    static func frameDelta(remaining: Double,
                           elapsed: TimeInterval,
                           response: Int) -> Double {
        guard remaining.isFinite, remaining != 0,
              elapsed.isFinite, elapsed > 0 else { return 0 }
        let magnitude = abs(remaining)
        if magnitude <= finishThreshold { return remaining }
        let clampedElapsed = min(elapsed, maximumFrameInterval)
        let normalizedResponse = Double(sanitizedResponse(response) - responseRange.lowerBound)
            / Double(responseRange.upperBound - responseRange.lowerBound)
        let responseTime = slowResponseTime
            - normalizedResponse * (slowResponseTime - fastResponseTime)
        let eased = magnitude * (1 - exp(-clampedElapsed / responseTime))
        let emitted = min(magnitude, max(eased, minimumGlideSpeed * clampedElapsed))
        return remaining < 0 ? -emitted : emitted
    }

    /// Clamps the persisted step to its allowed range (0 or garbage falls
    /// back to the default).
    static func sanitizedStep(_ value: Int) -> Int {
        guard value != 0 else { return defaultStep }
        return min(max(value, stepRange.lowerBound), stepRange.upperBound)
    }

    static func sanitizedResponse(_ value: Int) -> Int {
        min(max(value, responseRange.lowerBound), responseRange.upperBound)
    }
}
