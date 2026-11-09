// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Keyboard and accessibility actions have no mouse-tracking callbacks. They
/// form a complete edit around the value write; dragging keeps its one shared
/// edit open until the native cell finishes tracking.
struct NotchSliderEditing {
    private var tracking = false

    mutating func trackingChanged(_ value: Bool, onEditingChanged: ((Bool) -> Void)?) {
        guard tracking != value else { return }
        tracking = value
        onEditingChanged?(value)
    }

    func valueChanged(_ update: () -> Void, onEditingChanged: ((Bool) -> Void)?) {
        let callback = tracking ? nil : onEditingChanged
        callback?(true)
        update()
        callback?(false)
    }
}

/// A level that moves outside the slider, from a key or another surface,
/// eases to its new place instead of jumping there, starting from wherever
/// the bar is drawn.
struct NotchSliderEasing {
    static let duration: Double = 0.22
    let from: Double
    let to: Double
    let start: Double

    /// A change eases only on a slider that asks for it, is on screen and
    /// is not being dragged, and never with reduced motion. A slider just
    /// made, or in a window that is not visible, starts at its level.
    static func eases(enabled: Bool, onScreen: Bool, reduceMotion: Bool, tracking: Bool) -> Bool {
        enabled && onScreen && !reduceMotion && !tracking
    }

    /// The value drawn at `time`, ending on `to` exactly.
    func value(at time: Double) -> (value: Double, done: Bool) {
        let progress = min(1, max(0, (time - start) / Self.duration))
        guard progress < 1 else { return (to, true) }
        let eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
        return (from + (to - from) * eased, false)
    }
}

/// A scroll over a level bar moves it, so it can be set without dragging.
/// Up and right raise it whichever way content scrolls. A wheel notch is one
/// step, like a volume key; a trackpad moves it with the fingers. A trackpad
/// gesture belongs to the bar only when it starts there: a list scrolling
/// under a still pointer keeps scrolling, and the momentum of a flick that
/// moved the bar is swallowed rather than moving the bar or the list.
/// A vertical fader answers only to vertical movement. A trackpad gesture on
/// one picks its axis once, after a little travel: a swipe that is not clearly
/// vertical belongs to the strip around the fader for the rest of the gesture,
/// so scrolling past a level can never change it.
struct SliderScroll {
    enum Phase { case none, began, changed, ended, momentum }
    enum Outcome: Equatable { case pass, hold, move(Double) }

    static let wheelStep = 0.05
    /// Two hundred points of finger travel cross the whole range.
    static let pointStep = 0.005
    /// Trackpads may send one phaseless event between the lift and momentum.
    static let liftGap = 0.35
    /// Finger travel a fader waits for before it picks the gesture's axis.
    static let axisTravel = 6.0
    /// How much steeper than sideways a swipe must be to move a fader. Doubt
    /// goes to the strip, which only scrolls, rather than to the level.
    static let verticalBias = 1.5
    /// Reversals under the threshold can last indefinitely. Give those to the
    /// strip before the control has to keep more native movement events.
    static let maxPendingSamples = 64

    var verticalOnly = false
    /// Where the gesture on the bar is heading, ahead of a level that settles late.
    private var level: Double?
    /// The strip or the slider keeps the same events between lift and momentum.
    private var tail: (outcome: Outcome, timestamp: Double)?
    /// Travel so far of a gesture on a fader that has not picked its axis.
    private var unsettled: (dx: Double, dy: Double, samples: Int)?
    var isChoosingAxis: Bool { unsettled != nil }

    static func step(dx: Double, dy: Double, precise: Bool, inverted: Bool) -> Double {
        let up = dy * (inverted ? -1 : 1)
        let right = dx * (inverted ? 1 : -1)
        let amount = abs(dx) > abs(dy) ? right : up
        guard amount.isFinite, amount != 0 else { return 0 }
        return precise ? amount * pointStep : (amount > 0 ? wheelStep : -wheelStep)
    }

    private static func isSideways(dx: Double, dy: Double) -> Bool {
        abs(dy) < abs(dx) * verticalBias
    }

    mutating func handle(_ phase: Phase, dx: Double, dy: Double, precise: Bool, inverted: Bool,
                         timestamp: Double, current: Double, range: ClosedRange<Double>) -> Outcome {
        switch phase {
        case .began:
            level = current
            tail = nil
            unsettled = verticalOnly ? (0, 0, 0) : nil
        case .changed:
            guard level != nil else {
                tail = verticalOnly ? (.pass, timestamp) : nil
                return .pass
            }
        case .momentum where level == nil:
            let outcome = tail?.outcome ?? .pass
            if verticalOnly, outcome == .pass { tail = (.pass, timestamp) }
            return outcome
        case .ended, .momentum:
            // A swipe that lifts before choosing an axis still has all its
            // travel to give the strip. A fader scrolled under the pointer
            // might first see the lift and must also leave the tail alone.
            let outcome: Outcome = level != nil && !isChoosingAxis ? .hold : .pass
            if level != nil || verticalOnly { tail = (outcome, timestamp) }
            level = nil
            unsettled = nil
            return outcome
        case .none:
            if precise, let tail, timestamp >= tail.timestamp, timestamp - tail.timestamp <= Self.liftGap {
                return tail.outcome
            }
            tail = nil
        }
        var rise = dy
        if verticalOnly {
            if level != nil, var travel = unsettled {
                travel.dx += dx
                travel.dy += dy
                if dx != 0 || dy != 0 { travel.samples += 1 }
                let enoughTravel = max(abs(travel.dx), abs(travel.dy)) >= Self.axisTravel
                if !enoughTravel && travel.samples < Self.maxPendingSamples {
                    unsettled = travel
                    return .hold
                }
                unsettled = nil
                if !enoughTravel || Self.isSideways(dx: travel.dx, dy: travel.dy) {
                    level = nil
                    tail = (.pass, timestamp)
                    return .pass
                }
                rise = travel.dy
            } else if level == nil, Self.isSideways(dx: dx, dy: dy) {
                return .pass
            }
        }
        let span = range.upperBound - range.lowerBound
        let step = Self.step(dx: verticalOnly ? 0 : dx, dy: rise, precise: precise, inverted: inverted)
        guard span.isFinite, span > 0, step != 0 else { return .hold }
        let base = (level ?? current).isFinite ? (level ?? current) : range.lowerBound
        let next = min(range.upperBound, max(range.lowerBound, base + step * span))
        if level != nil { level = next }
        return .move(next)
    }
}
