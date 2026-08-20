// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What to do with an incoming physical trackpad press.
enum MiddleClickClickAction: Equatable {
    case transform
    case passThrough
    /// A second synthesized click right on the heels of a transformed one
    /// (tap-to-click fires an extra click as the fingers release): passing it
    /// through would open in the same tab, transforming it would open a
    /// second tab, so it is dropped.
    case swallow
}

enum MiddleClickSupport {
    /// How recent the last contact frame must be for its finger count to
    /// describe "now". Frames stream continuously while fingers touch the
    /// trackpad, so anything older means the fingers already lifted.
    static let fingerFreshness: TimeInterval = 0.25

    /// The three fingers must have been resting this long before the press:
    /// a click that arrives together with the third finger's touchdown is a
    /// synthesized tap-to-click, not a press (a real press needs the fingers
    /// on the pad before the force builds up).
    static let minimumSettle: TimeInterval = 0.04

    /// Window after a transformed click in which another qualifying click is
    /// treated as a synthesizer bounce and dropped.
    static let repeatGuard: TimeInterval = 0.30

    /// Decides what an incoming press becomes. Only real presses count
    /// (owner decision: taps, swipes and resting fingers must never click),
    /// and while the system's own three-finger drag gesture is enabled it
    /// owns three-finger touches: it synthesizes clicks from unpressed
    /// contact that are indistinguishable from real presses here, so the
    /// feature stands down entirely rather than firing falsely.
    static func actionForClick(fingerCount: Int,
                               frameAge: TimeInterval,
                               settledFor: TimeInterval,
                               sinceLastTransformEnd: TimeInterval?,
                               systemDragGestureEnabled: Bool) -> MiddleClickClickAction {
        guard !systemDragGestureEnabled else { return .passThrough }
        guard fingerCount == 3, frameAge >= 0, frameAge <= fingerFreshness else { return .passThrough }
        if let sinceLastTransformEnd, sinceLastTransformEnd >= 0,
           sinceLastTransformEnd < repeatGuard {
            return .swallow
        }
        guard settledFor >= minimumSettle else { return .passThrough }
        return .transform
    }

    // MARK: - Tap to middle click (issue #161, opt-in)

    /// A touch that lasts longer than this is a rest or a press, not a tap.
    static let tapMaxDuration: TimeInterval = 0.35

    /// How far the fingers' average position may travel (normalized trackpad
    /// units, 0...1 across the pad) before the touch counts as a swipe. Space
    /// switching and Mission Control travel far past this.
    static let tapMovementLimit: Float = 0.03

    /// How much the fingers' spread (mean distance from their centroid) may
    /// change before the touch counts as a pinch. A pinch or spread keeps the
    /// centroid still, so the movement limit alone would let Launchpad and
    /// show-desktop gestures fire a phantom middle click.
    static let tapSpreadChangeLimit: Float = 0.04

    /// Briefly ignore tap candidates after ordinary typing so incidental
    /// trackpad contact cannot move focus while the user is entering text.
    static let tapKeyboardIdle: TimeInterval = 0.5

    /// Decides whether a finished touch was a deliberate tap. `tapFingers` is
    /// the user's chosen count (3 or 4); with the system three-finger drag
    /// gesture enabled a three-finger tap belongs to macOS, so only the
    /// four-finger option stays available.
    static func tapShouldFire(duration: TimeInterval,
                              maxMovement: Float,
                              maxSpreadChange: Float,
                              exceededFingerCount: Bool,
                              buttonPressedDuring: Bool,
                              positionUnavailable: Bool,
                              systemDragGestureEnabled: Bool,
                              tapFingers: Int,
                              secondsSinceLastKeyDown: TimeInterval = .infinity) -> Bool {
        guard tapFingers == 3 || tapFingers == 4 else { return false }
        guard !exceededFingerCount, !buttonPressedDuring, !positionUnavailable else { return false }
        guard secondsSinceLastKeyDown >= tapKeyboardIdle else { return false }
        guard duration > 0, duration <= tapMaxDuration else { return false }
        guard maxMovement <= tapMovementLimit else { return false }
        guard maxSpreadChange <= tapSpreadChangeLimit else { return false }
        if tapFingers == 3, systemDragGestureEnabled { return false }
        return true
    }
}
