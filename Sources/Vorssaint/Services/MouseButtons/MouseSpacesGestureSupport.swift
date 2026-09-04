// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The pure half of the Spaces and Mission Control drag (issue #1012): how far
/// a held button has to travel before the gesture means something, which
/// direction that something is, and when a continued drag may say it again.
///
/// The tracker is fed pointer positions and answers with an action or with
/// nothing at all. Nothing here presses a key or reads a preference, so every
/// rule below is provable without a mouse.
enum MouseSpacesGestureSupport {
    // MARK: - Calibration
    //
    // These four numbers are the whole feel of the gesture and the only part
    // of it that needs a real hand and a real mouse to judge. They live
    // together, named, so tuning never means hunting through the service.

    /// Pixels of horizontal travel that make one Space change. Roughly a third
    /// of a laptop screen's width: far enough that a nudge while a side button
    /// is held never moves the desk, short enough to cross two Spaces in one
    /// comfortable stroke.
    static let spaceStep: CGFloat = 220

    /// Pixels of vertical travel that open an overview. Lower than the
    /// horizontal step because the vertical gesture fires once and cannot run
    /// away with a long drag, and because a mouse has less room upward.
    static let overviewStep: CGFloat = 150

    /// Seconds a fired Space change holds the next one off. The system's slide
    /// animation takes about a third of a second, and a change posted during
    /// it is dropped by the window server, so a faster repeat would silently
    /// lose steps rather than move faster.
    static let spaceRepeatCooldown: TimeInterval = 0.35

    /// How much travel may be banked while the cooldown runs. One step: a fast
    /// flick then queues at most one further change instead of a burst that
    /// keeps arriving after the hand has stopped.
    static let bankedTravelLimit: CGFloat = spaceStep

    // MARK: - Decisions

    /// What a stretch of drag asked for.
    enum Action: Equatable {
        case spaceLeft
        case spaceRight
        case missionControl
        case appExpose
    }

    /// The same drag read the way a trackpad reads a swipe: the desk follows
    /// the hand, so going right brings the Space on the left. Only the two
    /// Space directions swap, because dragging up already opens Mission
    /// Control on both devices.
    static func resolved(_ action: Action, followsDrag: Bool) -> Action {
        guard followsDrag else { return action }
        switch action {
        case .spaceLeft: return .spaceRight
        case .spaceRight: return .spaceLeft
        case .missionControl, .appExpose: return action
        }
    }

    /// The axis a gesture settled on at its first firing. A press stays on it
    /// for the rest of its life, so a drag that wanders diagonally cannot
    /// switch Spaces and throw up Mission Control at the same time.
    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    /// One held press. Positions come from the event's own location, in the
    /// window server's top-left origin, so a smaller y means upward.
    ///
    /// Travel is measured from the pointer, which means a drag that pins the
    /// cursor against a screen edge stops counting; releasing and dragging
    /// again continues where it left off. Lowering `spaceStep` is the knob for
    /// a small screen.
    struct Tracker {
        private(set) var axis: Axis?
        /// True once the press has done something. The release of such a press
        /// belongs to the gesture; a press that never fired is still a click.
        private(set) var didFire = false

        private var lastPoint: CGPoint
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var lastFiredAt: TimeInterval?

        init(origin: CGPoint) {
            lastPoint = origin
        }

        /// Takes the next pointer position and answers with the action it
        /// completed, if any. Below the thresholds this returns nil every
        /// time, which is what keeps a short drag an ordinary click.
        mutating func advance(to point: CGPoint, now: TimeInterval) -> Action? {
            guard point.x.isFinite, point.y.isFinite else { return nil }
            let deltaX = point.x - lastPoint.x
            let deltaY = point.y - lastPoint.y
            lastPoint = point
            accumulatedX += deltaX
            accumulatedY += deltaY

            guard let resolved = axis ?? committedAxis() else { return nil }
            switch resolved {
            case .vertical:
                axis = .vertical
                // An overview is a toggle: saying it twice in one press would
                // open it and close it again.
                guard !didFire else { return nil }
                didFire = true
                return accumulatedY < 0 ? .missionControl : .appExpose
            case .horizontal:
                axis = .horizontal
                if let lastFiredAt, now - lastFiredAt < MouseSpacesGestureSupport.spaceRepeatCooldown {
                    accumulatedX = min(max(accumulatedX, -MouseSpacesGestureSupport.bankedTravelLimit),
                                       MouseSpacesGestureSupport.bankedTravelLimit)
                    return nil
                }
                guard abs(accumulatedX) >= MouseSpacesGestureSupport.spaceStep else { return nil }
                let goesLeft = accumulatedX < 0
                // The surplus carries over, so an even drag keeps an even
                // rhythm instead of losing whatever overshot the threshold.
                accumulatedX += goesLeft ? MouseSpacesGestureSupport.spaceStep
                                         : -MouseSpacesGestureSupport.spaceStep
                lastFiredAt = now
                didFire = true
                return goesLeft ? .spaceLeft : .spaceRight
            }
        }

        /// Which axis, if either, has travelled far enough to claim the press.
        /// Whichever threshold is crossed first wins; a drag that crosses both
        /// in the same step is read as the one that went further past its own.
        private func committedAxis() -> Axis? {
            let horizontal = abs(accumulatedX) / MouseSpacesGestureSupport.spaceStep
            let vertical = abs(accumulatedY) / MouseSpacesGestureSupport.overviewStep
            if horizontal >= 1, horizontal >= vertical { return .horizontal }
            if vertical >= 1 { return .vertical }
            return nil
        }
    }

    /// Buttons the gesture can live on. The same extra buttons a shortcut can
    /// use, minus the side wheel: a wheel direction is a tick, not a drag, so
    /// there is nothing to hold and nothing to measure.
    static func canBind(_ input: Int64) -> Bool {
        MouseButtonShortcutSupport.buttonRange.contains(input)
    }

    /// The bound button, or nil when the gesture is off, unavailable, has no
    /// button yet, or the button belongs to another mouse feature. Pure
    /// defaults reads, so asking never wakes a service; the radial menu keeps
    /// its summoner and an existing shortcut keeps its button, exactly the way
    /// the shortcut feature already yields to the wheel.
    static func boundButton(isAvailable: Bool,
                            isEnabled: Bool,
                            button: Int64,
                            hasShortcut: (Int64) -> Bool,
                            claimedByWheel: (Int64) -> Bool) -> Int64? {
        guard isAvailable, isEnabled, canBind(button),
              !hasShortcut(button), !claimedByWheel(button) else { return nil }
        return button
    }
}
