// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ScrollWheelEventTraits: Equatable {
    let isContinuous: Bool
    let momentumPhase: Int64
    let scrollPhase: Int64
    let scrollCount: Int64
}

struct ScrollWheelInversionPlan: Equatable {
    let vertical: Bool
    let horizontal: Bool
}

/// The three delta fields a scroll event carries per axis: the line count,
/// the point count and the fixed-point line count.
struct ScrollWheelAxisDelta: Equatable {
    var line: Int64
    var point: Int64
    var fixedPoint: Double

    var hasMovement: Bool { line != 0 || point != 0 || fixedPoint != 0 }

    var negated: ScrollWheelAxisDelta {
        ScrollWheelAxisDelta(line: -line, point: -point, fixedPoint: -fixedPoint)
    }
}

/// Tells mouse wheels apart from touch devices, shared by the scroll
/// inverter and smooth scrolling so both features classify events the same
/// way: discrete events are wheels; events flagged continuous are wheels
/// only when they carry no gesture phase at all (how some mouse drivers
/// report their wheels).
enum ScrollWheelSupport {
    /// How long after a gesture-phased event a phaseless continuous event is
    /// still attributed to the same touch device.
    static let touchGestureGraceSeconds: TimeInterval = 1.0

    /// Marks the smooth glide so neither feature handles it twice. Events a
    /// process posts come back through that same process's taps (measured at
    /// every tap location), so without the mark the inverter would turn the
    /// glide around again and cancel the flip smooth scrolling already
    /// applied.
    static let syntheticTag: Int64 = 0x564F5253  // "VORS"

    /// Points in one scroll line. The window server measures the fixed-point
    /// delta in lines, so an event that moved forty points reports four;
    /// replaying that number as pixels would travel a tenth of the distance.
    static let pointsPerLine: Double = 10

    static func isMouseWheel(_ traits: ScrollWheelEventTraits,
                             secondsSinceLastGesturePhase: TimeInterval?) -> Bool {
        if !traits.isContinuous {
            return true
        }
        guard traits.momentumPhase == 0, traits.scrollPhase == 0 else {
            return false
        }
        // Trackpads/Magic Mouse can emit a phaseless transition event between
        // gesture end and momentum start that still carries the gesture's
        // scrollCount. Mouse wheels that report continuous never emit phases,
        // so only events right after a phased one are treated as touch.
        if traits.scrollCount != 0,
           let elapsed = secondsSinceLastGesturePhase,
           elapsed <= touchGestureGraceSeconds {
            return false
        }
        return true
    }

    /// Shift redirects a discrete vertical wheel tick sideways above the event tap.
    /// Select the setting for the direction the user will see, while leaving
    /// genuine two-axis events independent.
    static func inversionPlan(hasVerticalMovement: Bool,
                              hasHorizontalMovement: Bool,
                              shiftRedirectsVertical: Bool,
                              invertVertical: Bool,
                              invertHorizontal: Bool) -> ScrollWheelInversionPlan {
        let shiftRedirectsVertically = shiftRedirectsVertical
            && hasVerticalMovement
            && !hasHorizontalMovement
        return ScrollWheelInversionPlan(
            vertical: hasVerticalMovement
                && (shiftRedirectsVertically ? invertHorizontal : invertVertical),
            horizontal: hasHorizontalMovement && invertHorizontal
        )
    }
}

// MARK: - Linear scrolling

/// Every notch of a mouse wheel worth the same distance, however fast the
/// wheel spins. macOS keeps its wheel acceleration inside the delta itself,
/// so a fast spin arrives as several lines in one event; capping an event at
/// one notch is what takes it out again. Shared by both wheel taps, so the
/// glide and the raw wheel agree on what a notch is worth.
extension ScrollWheelSupport {
    /// Lines one notch scrolls. Three is what Windows and LinearMouse use, so
    /// someone switching lands on a familiar pace.
    static let linesPerNotchRange = 1...10
    static let defaultLinesPerNotch = 3

    /// Clamps the persisted value to its allowed range (0 or garbage falls
    /// back to the default).
    static func sanitizedLinesPerNotch(_ value: Int) -> Int {
        guard value != 0 else { return defaultLinesPerNotch }
        return min(max(value, linesPerNotchRange.lowerBound), linesPerNotchRange.upperBound)
    }

    /// The notch count of a continuous wheel event, in lines. The point field
    /// is what apps read, so it wins; the fixed-point field already counts
    /// lines and only stands in when the driver left the points empty.
    static func continuousTicks(fixedPointDelta: Double, pointDelta: Double) -> Double {
        guard fixedPointDelta.isFinite, pointDelta.isFinite else { return 0 }
        return pointDelta != 0 ? pointDelta / pointsPerLine : fixedPointDelta
    }

    /// The lines an event scrolls under linear scrolling: at most one notch,
    /// multiplied out. A high-resolution wheel's fraction of a notch stays a
    /// fraction, and the sign is untouched.
    static func linearLines(ticks: Double, linesPerNotch: Int) -> Double {
        guard ticks.isFinite, ticks != 0 else { return 0 }
        let lines = min(abs(ticks), 1) * Double(sanitizedLinesPerNotch(linesPerNotch))
        return ticks < 0 ? -lines : lines
    }

    /// The fields to write back into a wheel event under linear scrolling,
    /// plus the fraction of a line to carry into the next event. A discrete
    /// event gets only its line count, since the system rederives the other
    /// two fields from it; a continuous event gets all three, with the point
    /// count kept whole. The carry keeps sub-notch events from being lost and
    /// is dropped on a reversal, like the glide's.
    static func linearDelta(_ delta: ScrollWheelAxisDelta,
                            isContinuous: Bool,
                            linesPerNotch: Int,
                            carry: Double) -> (delta: ScrollWheelAxisDelta, carry: Double) {
        let ticks = isContinuous
            ? continuousTicks(fixedPointDelta: delta.fixedPoint, pointDelta: Double(delta.point))
            : SmoothScrollSupport.ticks(line: Double(delta.line), fixedPoint: delta.fixedPoint)
        let lines = linearLines(ticks: ticks, linesPerNotch: linesPerNotch)
        let kept = SmoothScrollSupport.carry(carry, continuing: lines)
        if isContinuous {
            let points = SmoothScrollSupport.wholePixels(lines * pointsPerLine,
                                                         carry: kept * pointsPerLine)
            let wholeLines = points.pixels / pointsPerLine
            return (ScrollWheelAxisDelta(line: Int64(wholeLines.rounded(.towardZero)),
                                         point: Int64(points.pixels),
                                         fixedPoint: wholeLines),
                    points.carry / pointsPerLine)
        }
        let wholeLines = SmoothScrollSupport.wholePixels(lines, carry: kept)
        return (ScrollWheelAxisDelta(line: Int64(wholeLines.pixels), point: 0, fixedPoint: 0),
                wholeLines.carry)
    }
}
