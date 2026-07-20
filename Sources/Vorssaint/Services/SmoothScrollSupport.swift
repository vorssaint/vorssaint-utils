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

    /// The system normally treats Shift plus a vertical wheel tick as
    /// horizontal scrolling. Once the original tick is swallowed, the glide
    /// must perform that axis change itself. Pixel events use the opposite
    /// sign for this redirected axis, so the tick is flipped to keep the
    /// system's normal Shift direction. A wheel that already reports a
    /// horizontal axis is left alone so its native direction is preserved.
    static func axes(vertical: Double, horizontal: Double, shiftPressed: Bool) -> Axes {
        guard shiftPressed, vertical != 0, horizontal == 0 else {
            return Axes(vertical: vertical, horizontal: horizontal)
        }
        return Axes(vertical: 0, horizontal: -vertical)
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

    /// The system applies the natural scroll direction to continuous pixel
    /// events but not to discrete wheel ticks (verified by posting both), so
    /// with natural scrolling on, the glide must pre-flip its deltas for the
    /// replay to keep the wheel's direction.
    static func postedDelta(_ frameDelta: Double, naturalScrolling: Bool) -> Double {
        naturalScrolling ? -frameDelta : frameDelta
    }
}
