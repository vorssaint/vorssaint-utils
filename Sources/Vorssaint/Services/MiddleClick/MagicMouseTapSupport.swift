// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The button a Magic Mouse tap stands for, after the mouse's own button
/// setting is applied.
enum MagicMouseTapButton: Equatable {
    case primary
    case secondary
}

/// The Magic Mouse's Secondary click setting in System Settings, as macOS
/// stores it (`MouseButtonMode`). A tap clicks what pressing the same spot
/// would click, so a left-handed or one-button setup keeps its meaning.
enum MagicMouseButtonMode: Equatable {
    case oneButton
    case twoButton
    case twoButtonSwapped

    init(preference: String?) {
        switch preference {
        case "OneButton": self = .oneButton
        case "TwoButtonSwapped": self = .twoButtonSwapped
        default: self = .twoButton
        }
    }
}

/// A finished one-finger touch on a Magic Mouse surface.
struct MagicMouseTouch: Equatable {
    var duration: TimeInterval
    /// Largest distance the finger travelled from where it landed, in the
    /// surface's normalized units (0...1 across the mouse).
    var maxMovement: Float
    /// Where the finger landed across the mouse, 0 at the left edge.
    var x: Float
}

/// Follows one Magic Mouse's contacts from the moment its surface stops
/// being empty until it is empty again. Only a touch that is one finger from
/// start to end, with readable positions throughout, is handed back; a
/// second finger (gripping the mouse) or an unreadable record drops it.
struct MagicMouseTapTracker {
    private var startedAt: TimeInterval?
    private var start: (x: Float, y: Float)?
    private var maxMovement: Float = 0
    private var disqualified = false

    /// A touch is being followed: the surface has not been empty since it
    /// began.
    var isTracking: Bool { startedAt != nil }

    /// Feeds one contact frame. Returns the finished touch when the surface
    /// empties after a qualifying one-finger touch.
    mutating func frame(count: Int,
                        position: (x: Float, y: Float)?,
                        now: TimeInterval) -> MagicMouseTouch? {
        if count <= 0 {
            defer { reset() }
            guard let startedAt, let start, !disqualified else { return nil }
            return MagicMouseTouch(duration: now - startedAt, maxMovement: maxMovement, x: start.x)
        }
        if startedAt == nil {
            startedAt = now
            start = position
            maxMovement = 0
            disqualified = count != 1 || position == nil
            return nil
        }
        guard !disqualified else { return nil }
        guard count == 1, let position, let start else {
            disqualified = true
            return nil
        }
        maxMovement = max(maxMovement, max(abs(position.x - start.x), abs(position.y - start.y)))
        return nil
    }

    mutating func reset() {
        startedAt = nil
        start = nil
        maxMovement = 0
        disqualified = false
    }
}

/// One synthesized click, kept so the next tap can continue a double click.
struct MagicMouseClickRecord: Equatable {
    var button: MagicMouseTapButton
    var uptime: TimeInterval
    var location: CGPoint
    var clickState: Int64
}

enum MagicMouseTapSupport {
    /// MultitouchSupport family IDs of the Magic Mouse: 112 is the one a
    /// Magic Mouse 2 (product 0x0269) reports. Only verified families belong
    /// here, since a trackpad family would turn its one-finger taps into a
    /// second click on top of the system's own tap to click.
    static let familyIDs: Set<Int32> = [112]

    /// Measured on a Magic Mouse 2: deliberate taps last 0.03 to 0.11 s,
    /// a physical click keeps the finger down far longer (0.7 s and up).
    static let maxDuration: TimeInterval = 0.25

    /// Taps moved at most 0.012 of the surface; the shortest scroll strokes
    /// travel 0.05 and more.
    static let movementLimit: Float = 0.03

    /// Picking the mouse up or sliding it while one finger brushes the
    /// surface also looks like a short, still touch; the pointer moving
    /// during the touch tells the two apart.
    static let pointerTravelLimit: CGFloat = 6

    /// How far apart two taps may land on screen and still make a double
    /// click, in points.
    static let doubleClickDistance: CGFloat = 4

    /// Decides whether a finished touch was a tap and which button it stands
    /// for. A touch with a physical press inside it is that press, not a tap.
    static func button(for touch: MagicMouseTouch,
                       pressedDuring: Bool,
                       pointerTravel: CGFloat,
                       mode: MagicMouseButtonMode) -> MagicMouseTapButton? {
        guard !pressedDuring else { return nil }
        guard touch.duration > 0, touch.duration <= maxDuration else { return nil }
        guard touch.maxMovement <= movementLimit else { return nil }
        guard pointerTravel <= pointerTravelLimit else { return nil }
        let leftSide = touch.x < 0.5
        switch mode {
        case .oneButton: return .primary
        case .twoButton: return leftSide ? .primary : .secondary
        case .twoButtonSwapped: return leftSide ? .secondary : .primary
        }
    }

    /// A physical press began after the touch landed. `secondsSinceLastPress`
    /// is the system's count since the last primary or secondary button down.
    static func pressedDuring(touchDuration: TimeInterval, secondsSinceLastPress: TimeInterval) -> Bool {
        secondsSinceLastPress >= 0 && secondsSinceLastPress <= touchDuration
    }

    /// The click count to stamp on a synthesized click: a tap right after
    /// another one with the same button, at the same spot, continues it, so
    /// two taps open a file the way a double click does.
    static func clickState(button: MagicMouseTapButton,
                           uptime: TimeInterval,
                           location: CGPoint,
                           previous: MagicMouseClickRecord?,
                           doubleClickInterval: TimeInterval) -> Int64 {
        guard let previous,
              previous.button == button,
              uptime - previous.uptime >= 0,
              uptime - previous.uptime <= doubleClickInterval,
              abs(location.x - previous.location.x) <= doubleClickDistance,
              abs(location.y - previous.location.y) <= doubleClickDistance else { return 1 }
        return previous.clickState + 1
    }
}
