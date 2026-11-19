// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules for hiding the pointer while it sits still, kept out of the
/// service that owns the timer and the cursor so every branch can be tested
/// without a display, a run loop or a running session.
enum PointerHideSupport {
    /// Bounds for the idle threshold, in seconds. The low end keeps the cursor
    /// from flickering during a pause in reading; the high end is past the point
    /// where anyone still calls the pointer "idle".
    static let thresholdRange: ClosedRange<Double> = 1...60
    static let defaultThreshold: Double = 5

    /// Whether a stored threshold is usable, clamping a value that is out of
    /// range, not finite, or missing into the range. A hand-edited or migrated
    /// preference must never be able to park the decision in a state where the
    /// cursor is hidden with no way back.
    static func sanitizedThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return defaultThreshold }
        return min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    /// The one decision: hide, or show.
    ///
    /// Movement and a key press both mean the user is present, so either one
    /// ends the hiding immediately — including on the very tick the movement is
    /// first seen, which is why movement is an input and not a reset of the idle
    /// counter. With the threshold switched off nothing is ever hidden, because a
    /// feature that cannot be switched off is not a feature the user controls.
    static func shouldHide(idleSeconds: TimeInterval,
                           thresholdEnabled: Bool,
                           threshold: TimeInterval,
                           pointerMoved: Bool) -> Bool {
        guard !pointerMoved else { return false }
        guard thresholdEnabled else { return false }
        return idleSeconds >= sanitizedThreshold(threshold)
    }

    /// The escape rule, kept separate from `shouldHide` so it can be tested
    /// without a timer. Any of the four true means the cursor comes back now,
    /// with no reference to how long it has been hidden — a hidden cursor that
    /// waits for its threshold to expire again is the stranding case.
    static func shouldShow(pointerMoved: Bool,
                           keyPressed: Bool,
                           displayAsleep: Bool,
                           screenLocked: Bool) -> Bool {
        pointerMoved || keyPressed || displayAsleep || screenLocked
    }
}
