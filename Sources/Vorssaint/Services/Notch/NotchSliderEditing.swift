// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

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

/// A drag stops the pointer on the bar's marker for a few points of travel,
/// which makes the marker easy to hit. The level holds there with the pointer
/// on it, and once the hand has moved on far enough the pointer is let go
/// from the marker and the level follows it again. The level is always where
/// the pointer is, so nothing has to be made up afterwards. A move that
/// overshoots the marker by the whole hold passes straight through, so a fast
/// flick never pulls the pointer back. Once let go, the pause waits until the
/// pointer has moved well away before it can hold again, so one pass stops
/// once rather than catching on the marker over and over.
///
/// Places are in points along the bar, rising with the level.
struct NotchSliderPause {
    enum Step: Equatable {
        case follow
        case hold
        /// Let the pointer go at this place, past the marker on the side the
        /// hand moved toward.
        case release(Double)
        /// The level stays where the pointer was let go: the event still
        /// reports the pointer where it was held, from before it was let go.
        case stay(Double)
    }

    static let points = 3.0
    /// How far from the marker a let-go pointer must move before it can be
    /// held again.
    static let rearm = 6.0
    private(set) var holding = false
    private var place: Double?
    private var travel = 0.0
    /// Where the pointer was let go, until it moves far enough to re-arm.
    private var released: Double?

    mutating func begin(at place: Double) {
        self = NotchSliderPause()
        self.place = place
    }

    /// `place` is where the pointer now is, and `moved` how far the hand moved
    /// since the last step; while the pointer is held, only the hand moves.
    mutating func step(to place: Double, moved: Double, stop: Double) -> Step {
        if holding {
            travel += moved
            guard abs(travel) >= Self.points else { return .hold }
            let side: Double = travel > 0 ? 1 : -1
            let released = stop + side * max(0.5, abs(travel) - Self.points)
            self = NotchSliderPause()
            self.place = released
            self.released = released
            return .release(released)
        }
        if let released {
            if place == stop { return .stay(released) }
            self.place = place
            if abs(place - stop) >= Self.rearm { self.released = nil }
            return .follow
        }
        let last = self.place ?? place
        self.place = place
        guard (last < stop) != (place < stop) || (place == stop && last != stop) else { return .follow }
        guard abs(place - stop) < Self.points else { return .follow }
        holding = true
        travel = place - stop
        self.place = stop
        return .hold
    }

    /// Whether a move reached or crossed the marker, for a click.
    static func arrived(from previous: Double?, to level: Double, stop: Double) -> Bool {
        guard previous != stop else { return false }
        guard let previous else { return level == stop }
        return level == stop || (previous < stop) != (level < stop)
    }
}

/// Holds and lets go of the system pointer for a drag's pause. Tests stand
/// in with one that leaves the real pointer alone.
struct NotchPointer {
    /// Puts the pointer at a point in global display coordinates and keeps it
    /// there while the hand moves on.
    var hold: (CGPoint) -> Void
    /// Lets the pointer move with the hand again, from a point if one is given.
    var release: (CGPoint?) -> Void
    /// Whether a held pointer stays put, so the hand's movement comes from the
    /// mouse event rather than the pointer's place.
    var freezes: Bool

    static let system = NotchPointer(hold: { point in
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(0)
    }, release: { point in
        if let point { CGWarpMouseCursorPosition(point) }
        CGAssociateMouseAndMouseCursorPosition(1)
    }, freezes: true)
    static let inert = NotchPointer(hold: { _ in }, release: { _ in }, freezes: false)
    @MainActor static var current = system
}

/// A scrolled bar is drawn just behind its level, closing the gap on each
/// display frame, so uneven scroll events do not show as jitter.
struct NotchSliderGlide {
    /// Seconds over which the drawn bar catches up.
    static let smoothing = 0.045
    /// How long after the last move the level stays with the gesture. A level
    /// that settles late, reported from elsewhere, would pull the bar back.
    static let hold = 0.35
    /// The level reaches its owner at this pace during a scroll. Each write
    /// redraws the whole mixer, which would otherwise take frames from the bar.
    static let writeInterval = 1.0 / 30

    var drawn: Double

    /// Moves toward `target` and reports whether it has arrived.
    mutating func advance(toward target: Double, interval: Double, span: Double, reduceMotion: Bool) -> Bool {
        let gap = target - drawn
        guard !reduceMotion, abs(gap) > span * 0.0005, interval.isFinite else {
            drawn = target
            return true
        }
        drawn += gap * (1 - exp(-max(0, interval) / Self.smoothing))
        return false
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
/// A slow swipe sets a level finely and a fast one crosses more of the bar. A
/// bar's `stop`, the top of its normal range, sets the rate and catches a swipe
/// that crosses it: the level rests there for a little travel, then goes on, so
/// either side is still easy to reach. Only a really fast swipe stays caught
/// until the fingers lift. Rising beyond the stop slows the longer one swipe
/// goes on, so its reach grows with the logarithm of its travel and a new swipe
/// starts afresh: one gesture cannot run away, and none feels heavy.
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
    /// Scroll points a second at and below which a swipe has `fineGain`, and
    /// at and above which it has `fastGain`. Gain runs evenly on a log scale
    /// between them, as a change in speed is felt by its ratio.
    static let slowSpeed = 30.0
    static let fastSpeed = 1500.0
    static let fineGain = 0.3
    static let fastGain = 2.0
    /// Finger travel beyond the stop in one swipe that halves its rate there.
    static let boostFade = 300.0
    /// Finger travel a level rests at the stop before it goes on.
    static let snapTravel = 8.0
    /// Finger travel over which the rate builds up again after the rest, from
    /// `leavingGain`, so the level goes on from the stop rather than leaps off it.
    static let leavingTravel = 30.0
    static let leavingGain = 0.25
    /// Scroll points a second from which a swipe rising to the stop stays there.
    static let flickSpeed = 1000.0
    /// Seconds over which the measured speed follows the fingers, so one
    /// uneven sample does not make the bar lurch.
    static let speedSmoothing = 0.05
    /// Events can share a timestamp; this keeps their speed finite.
    static let shortestInterval = 1.0 / 240

    var verticalOnly = false
    var stop: Double?
    /// Where the gesture on the bar is heading, ahead of a level that settles late.
    private var level: Double?
    /// The strip or the slider keeps the same events between lift and momentum.
    private var tail: (outcome: Outcome, timestamp: Double)?
    /// Travel at the stop so far, while the level rests there.
    private var resting: Double?
    private var flickCaught = false
    private var boostTravel = 0.0
    /// Travel since the level left its rest, while the rate builds up again.
    private var leaving: Double?
    private var didSnap = false
    private var speed = 0.0
    private var lastEvent: Double?
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

    static func gain(speed: Double) -> Double {
        guard speed.isFinite, speed > slowSpeed else { return fineGain }
        guard speed < fastSpeed else { return fastGain }
        let progress = log(speed / slowSpeed) / log(fastSpeed / slowSpeed)
        return fineGain * pow(fastGain / fineGain, progress)
    }

    /// Whether the level reached the stop since this was last asked, for a click.
    mutating func takeSnap() -> Bool {
        defer { didSnap = false }
        return didSnap
    }

    private mutating func trackSpeed(travel: Double, timestamp: Double) {
        defer { lastEvent = timestamp }
        guard let lastEvent, travel.isFinite else { return }
        let interval = max(Self.shortestInterval, timestamp - lastEvent)
        speed += (travel / interval - speed) * (1 - exp(-interval / Self.speedSmoothing))
    }

    mutating func handle(_ phase: Phase, dx: Double, dy: Double, precise: Bool, inverted: Bool,
                         timestamp: Double, current: Double, range: ClosedRange<Double>) -> Outcome {
        switch phase {
        case .began:
            level = current
            tail = nil
            unsettled = verticalOnly ? (0, 0, 0) : nil
            resting = current == stop ? 0 : nil
            flickCaught = false
            boostTravel = 0
            leaving = nil
            speed = 0
            lastEvent = nil
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
        if level != nil {
            trackSpeed(travel: verticalOnly ? abs(dy) : max(abs(dx), abs(dy)), timestamp: timestamp)
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
        let span = min(range.upperBound, stop ?? range.upperBound) - range.lowerBound
        let base = (level ?? current).isFinite ? (level ?? current) : range.lowerBound
        var step = Self.step(dx: verticalOnly ? 0 : dx, dy: rise, precise: precise, inverted: inverted)
        if precise, level != nil {
            let gain = Self.gain(speed: speed)
            if let travel = leaving {
                step *= min(1, Self.leavingGain + (1 - Self.leavingGain) * travel / Self.leavingTravel)
                let further = travel + (verticalOnly ? abs(rise) : max(abs(dx), abs(rise)))
                leaving = further < Self.leavingTravel ? further : nil
            }
            if let stop, base >= stop, step > 0, range.upperBound > stop {
                // A fast swipe gets no extra reach here.
                step *= min(1, gain) / (1 + boostTravel / Self.boostFade)
                if resting == nil { boostTravel += abs(rise) }
            } else {
                step *= gain
            }
        }
        guard span.isFinite, span > 0, step != 0 else { return .hold }
        if level != nil, let travel = resting {
            if flickCaught, step > 0 { return .hold }
            let amount = verticalOnly ? abs(rise) : max(abs(dx), abs(rise))
            let moved = travel + (step > 0 ? 1 : -1) * amount
            guard abs(moved) >= Self.snapTravel else { resting = moved; return .hold }
            resting = nil
            leaving = 0
            // Only the travel past the rest moves the level, at the slowest rate.
            step *= min(1, (abs(moved) - Self.snapTravel) / amount) * Self.leavingGain
        }
        var next = min(range.upperBound, max(range.lowerBound, base + step * span))
        if let stop, base != stop, (base < stop) == (next >= stop) || next == stop {
            next = stop
            didSnap = true
            if level != nil {
                resting = 0
                leaving = nil
                flickCaught = step > 0 && speed >= Self.flickSpeed
            }
        }
        if level != nil { level = next }
        return .move(next)
    }
}
