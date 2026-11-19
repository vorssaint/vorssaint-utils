// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What a slide along a trackpad edge adjusts.
enum TrackpadEdgeSliderTarget: Equatable {
    case brightness
    case volume
}

/// What one edge does, as stored in preferences.
enum TrackpadEdgeSliderAction: String, CaseIterable {
    case off
    case brightness
    case volume

    var target: TrackpadEdgeSliderTarget? {
        switch self {
        case .off: return nil
        case .brightness: return .brightness
        case .volume: return .volume
        }
    }

    static func sanitized(_ raw: String?, fallback: TrackpadEdgeSliderAction) -> TrackpadEdgeSliderAction {
        raw.flatMap(TrackpadEdgeSliderAction.init(rawValue:)) ?? fallback
    }
}

/// Which side of the trackpad a finger is on.
enum TrackpadEdge: Equatable {
    case left
    case right
}

/// Everything the user can choose about edge sliders.
struct TrackpadEdgeSliderConfig: Equatable {
    var left = TrackpadEdgeSliderAction.brightness
    var right = TrackpadEdgeSliderAction.volume
    /// How much of the pad's width, from each side, counts as the edge.
    var zone = Float(Defaults.defaultTrackpadEdgeSliderWidth) / 100
    /// 1 is the default travel; 2 covers the whole range in half of it.
    var sensitivity = Float(Defaults.defaultTrackpadEdgeSliderSensitivity) / 100
    var reversed = false
    var haptics = true

    /// Reads the saved choices, falling back to the defaults for anything
    /// missing or out of range.
    init(defaults: UserDefaults) {
        left = .sanitized(defaults.string(forKey: DefaultsKey.trackpadEdgeSlidersLeft), fallback: .brightness)
        right = .sanitized(defaults.string(forKey: DefaultsKey.trackpadEdgeSlidersRight), fallback: .volume)
        zone = Float(Defaults.sanitizedTrackpadEdgeSliderWidth(
            defaults.integer(forKey: DefaultsKey.trackpadEdgeSlidersWidth))) / 100
        sensitivity = Float(Defaults.sanitizedTrackpadEdgeSliderSensitivity(
            defaults.integer(forKey: DefaultsKey.trackpadEdgeSlidersSensitivity))) / 100
        reversed = defaults.bool(forKey: DefaultsKey.trackpadEdgeSlidersReversed)
        haptics = defaults.bool(forKey: DefaultsKey.trackpadEdgeSlidersHaptics)
    }

    init() {}

    func action(for edge: TrackpadEdge) -> TrackpadEdgeSliderAction {
        switch edge {
        case .left: return left
        case .right: return right
        }
    }
}

/// What one contact frame asks for.
struct TrackpadEdgeSliderOutput: Equatable {
    /// What the finger is adjusting; nil while no edge touch is in progress.
    var target: TrackpadEdgeSliderTarget?
    /// Signed fine steps to send for this frame: positive raises the level.
    var steps = 0
    /// The slide passed a step of the system keys: a moment for a light tick.
    var haptic = false
    /// The pointer should stay where it was when the finger touched down, so
    /// the slide does not drag it along the edge of the screen.
    var holdsPointer = false

    static let idle = TrackpadEdgeSliderOutput()
}

enum TrackpadEdgeSliderSupport {
    /// A touch that starts in the edge but drifts this far past it before
    /// moving up or down is pointing, not sliding, and is left alone.
    static let zoneExitMargin: Float = 0.03

    /// Vertical travel (a fraction of the pad's height) before a touch becomes
    /// a slide. Short enough to feel immediate, long enough that a tap or a
    /// resting finger never moves a level.
    static let commitTravel: Float = 0.03

    /// A level has 64 fine steps (sixteen steps of the system keys, each in
    /// quarters). Sliding this fraction of the pad's height covers all of them,
    /// which leaves room above and below for the finger to start and stop.
    static let fullRangeTravel: Float = 0.75
    static let fineStepsPerRange = 64
    static let stepTravel: Float = fullRangeTravel / Float(fineStepsPerRange)

    /// Fine steps that make one step of the system keys, which is when a
    /// slide gives its light tick.
    static let fineStepsPerNotch = 4

    /// A frame that arrives late must not turn into a burst of steps.
    static let maxStepsPerFrame = 8

    /// The edge a touch at `x` (0 at the left of the pad, 1 at the right) is
    /// in, when each side counts `zone` of the width.
    static func edge(atX x: Float, zone: Float) -> TrackpadEdge? {
        if x <= zone { return .left }
        if x >= 1 - zone { return .right }
        return nil
    }

    static func isStillInside(_ edge: TrackpadEdge, x: Float, zone: Float) -> Bool {
        switch edge {
        case .left: return x <= zone + zoneExitMargin
        case .right: return x >= 1 - zone - zoneExitMargin
        }
    }

    /// The system media key a step of `target` presses: volume up and down are
    /// 0 and 1, brightness up and down 2 and 3 (NX_KEYTYPE_*).
    static func keyCode(for target: TrackpadEdgeSliderTarget, raising: Bool) -> Int32 {
        switch (target, raising) {
        case (.volume, true): return 0
        case (.volume, false): return 1
        case (.brightness, true): return 2
        case (.brightness, false): return 3
        }
    }
}

/// Follows one finger along the left or right edge of the trackpad and turns
/// its vertical travel into fine volume or brightness steps.
///
/// A slide only starts when a single finger lands in an edge zone on an empty
/// pad and nothing was typed just before. A second finger, a physical click, a
/// finger that lands anywhere else, an edge set to Off or a layout the reader
/// cannot trust blocks the touch until the pad is empty again, so scrolling,
/// pointing and system gestures stay what they were.
struct TrackpadEdgeSliderEngine {
    private enum Phase: Equatable {
        /// Waiting for the pad to empty before another touch may count.
        case blocked
        case idle
        /// A finger landed in the edge and has not moved far enough to commit.
        case pending(edge: TrackpadEdge, startY: Float)
        case sliding(edge: TrackpadEdge, lastY: Float)
    }

    private var phase = Phase.blocked
    private var carry: Float = 0
    private var stepsSinceTick = 0

    var config = TrackpadEdgeSliderConfig()

    /// A finger that is already on the pad when the engine starts does not
    /// count: the first touch that can start a slide lands on an empty pad.
    mutating func reset() {
        block()
    }

    /// A physical click ends the touch: it is a press, not a slide.
    mutating func cancel() {
        switch phase {
        case .pending, .sliding: block()
        case .blocked, .idle: break
        }
    }

    /// `position` is the normalized position of the finger when exactly one is
    /// down (x from the left, y from the bottom), nil when it cannot be read.
    /// `typedRecently` is only asked for when a touch lands.
    mutating func update(fingerCount: Int,
                         position: (x: Float, y: Float)?,
                         typedRecently: @autoclosure () -> Bool) -> TrackpadEdgeSliderOutput {
        guard fingerCount > 0 else {
            phase = .idle
            carry = 0
            stepsSinceTick = 0
            return .idle
        }
        guard fingerCount == 1, let position else {
            block()
            return .idle
        }

        switch phase {
        case .blocked:
            return .idle

        case .idle:
            guard let edge = TrackpadEdgeSliderSupport.edge(atX: position.x, zone: config.zone),
                  config.action(for: edge) != .off,
                  !typedRecently() else {
                block()
                return .idle
            }
            phase = .pending(edge: edge, startY: position.y)
            return output(for: edge)

        case let .pending(edge, startY):
            guard TrackpadEdgeSliderSupport.isStillInside(edge, x: position.x, zone: config.zone) else {
                block()
                return .idle
            }
            if abs(position.y - startY) >= TrackpadEdgeSliderSupport.commitTravel {
                // Counting starts where the slide commits, so crossing the
                // dead zone never jumps the level.
                phase = .sliding(edge: edge, lastY: position.y)
                carry = 0
                stepsSinceTick = 0
            }
            return output(for: edge)

        case let .sliding(edge, lastY):
            let travel = TrackpadEdgeSliderSupport.stepTravel / config.sensitivity
            carry += position.y - lastY
            phase = .sliding(edge: edge, lastY: position.y)
            let whole = Int((carry / travel).rounded(.towardZero))
            carry -= Float(whole) * travel
            let limit = TrackpadEdgeSliderSupport.maxStepsPerFrame
            let raised = max(-limit, min(limit, whole))
            stepsSinceTick += abs(raised)
            let notches = stepsSinceTick / TrackpadEdgeSliderSupport.fineStepsPerNotch
            stepsSinceTick %= TrackpadEdgeSliderSupport.fineStepsPerNotch
            return output(for: edge, steps: config.reversed ? -raised : raised,
                          haptic: config.haptics && notches > 0)
        }
    }

    private func output(for edge: TrackpadEdge, steps: Int = 0, haptic: Bool = false) -> TrackpadEdgeSliderOutput {
        TrackpadEdgeSliderOutput(target: config.action(for: edge).target,
                                 steps: steps,
                                 haptic: haptic,
                                 holdsPointer: true)
    }

    private mutating func block() {
        phase = .blocked
        carry = 0
        stepsSinceTick = 0
    }
}
