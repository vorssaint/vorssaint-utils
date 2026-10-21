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
