// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure math for smooth mouse-wheel scrolling, kept free of AppKit so the
/// unit harness can pin it.
///
/// Each discrete wheel tick adds a distance to a per-axis "remaining" budget;
/// an animation frame then emits a fraction of what remains, which decays the
/// jump into a short glide that slows down as it lands.
enum SmoothScrollSupport {
    struct Axes: Equatable {
        let vertical: Double
        let horizontal: Double
    }

    /// Animation frame length. Sixty steps a second reads as continuous and
    /// stays far below what event posting can sustain.
    static let frameInterval: TimeInterval = 1.0 / 60.0

    /// The fraction of the remaining distance emitted per frame. 0.18 at
    /// sixty frames a second lands a tick in roughly a quarter second.
    static let emitFactor: Double = 0.18

    /// Leftovers smaller than this are flushed in one final frame.
    static let finishThreshold: Double = 1.0

    /// Adjustable distance of one wheel tick, in pixels.
    static let stepRange = 20...100
    static let defaultStep = 40

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
        guard distance != 0, current != 0, (distance < 0) != (current < 0) else { return current }
        return 0
    }

    /// The remaining distance after new wheel ticks arrive. Scrolling the
    /// opposite way abandons what was left instead of fighting it, so a
    /// direction change reacts instantly.
    static func remaining(afterTicks ticks: Double, step: Double, current: Double) -> Double {
        let added = ticks * step
        guard added != 0 else { return current }
        if current != 0, (added < 0) != (current < 0) {
            return added
        }
        return current + added
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

    /// The distance one frame should emit for this remaining budget: a
    /// fraction of it, at least one pixel so the glide never stalls, and
    /// everything once the leftover is small enough to finish.
    static func frameDelta(remaining: Double) -> Double {
        guard remaining != 0 else { return 0 }
        let magnitude = abs(remaining)
        if magnitude <= finishThreshold { return remaining }
        let emitted = max(magnitude * emitFactor, 1.0)
        return remaining < 0 ? -emitted : emitted
    }

    /// Clamps the persisted step to its allowed range (0 or garbage falls
    /// back to the default).
    static func sanitizedStep(_ value: Int) -> Int {
        guard value != 0 else { return defaultStep }
        return min(max(value, stepRange.lowerBound), stepRange.upperBound)
    }
}
