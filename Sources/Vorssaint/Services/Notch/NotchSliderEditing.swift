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
struct SliderScroll {
    enum Phase { case none, began, changed, ended, momentum }
    enum Outcome: Equatable { case pass, hold, move(Double) }

    static let wheelStep = 0.05
    /// Two hundred points of finger travel cross the whole range.
    static let pointStep = 0.005
    /// Trackpads may send one phaseless event between the lift and momentum.
    static let liftGap = 0.35

    /// Where the gesture on the bar is heading, ahead of a level that settles late.
    private var level: Double?
    private var coasting = false
    private var liftedAt: Double?

    static func step(dx: Double, dy: Double, precise: Bool, inverted: Bool) -> Double {
        let up = dy * (inverted ? -1 : 1)
        let right = dx * (inverted ? 1 : -1)
        let amount = abs(dx) > abs(dy) ? right : up
        guard amount.isFinite, amount != 0 else { return 0 }
        return precise ? amount * pointStep : (amount > 0 ? wheelStep : -wheelStep)
    }

    mutating func handle(_ phase: Phase, dx: Double, dy: Double, precise: Bool, inverted: Bool,
                         timestamp: Double, current: Double, range: ClosedRange<Double>) -> Outcome {
        switch phase {
        case .began:
            level = current
            coasting = false
        case .changed:
            guard level != nil else { coasting = false; return .pass }
        case .ended:
            guard level != nil else { return .pass }
            level = nil
            coasting = true
            liftedAt = timestamp
            return .hold
        case .momentum:
            return coasting ? .hold : .pass
        case .none:
            if coasting, precise, let liftedAt, timestamp >= liftedAt, timestamp - liftedAt <= Self.liftGap {
                return .hold
            }
            coasting = false
        }
        let span = range.upperBound - range.lowerBound
        let step = Self.step(dx: dx, dy: dy, precise: precise, inverted: inverted)
        guard span.isFinite, span > 0, step != 0 else { return .hold }
        let base = (level ?? current).isFinite ? (level ?? current) : range.lowerBound
        let next = min(range.upperBound, max(range.lowerBound, base + step * span))
        if level != nil { level = next }
        return .move(next)
    }
}
