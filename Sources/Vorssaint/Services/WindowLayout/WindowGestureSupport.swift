// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct WindowGestureResizeEdges: OptionSet, Equatable {
    let rawValue: Int

    static let left = WindowGestureResizeEdges(rawValue: 1 << 0)
    static let right = WindowGestureResizeEdges(rawValue: 1 << 1)
    static let top = WindowGestureResizeEdges(rawValue: 1 << 2)
    static let bottom = WindowGestureResizeEdges(rawValue: 1 << 3)
}

/// Whether a press is still undecided, already moving a window, or none of
/// the two.
enum WindowGestureState: Equatable {
    case idle
    case pending
    case active
}

/// What the pointer tap saw, reduced to the facts the decision needs.
/// `tracked` means the event belongs to the button that started the press.
enum WindowGestureInput: Equatable {
    case buttonDown(sameButton: Bool, chordMatched: Bool)
    case buttonDragged(tracked: Bool, pastSlop: Bool)
    case buttonUp(tracked: Bool)
    case otherEvent
    /// The system switched the tap off. Unlike every other input this one does
    /// not mean the press is still under way: while the tap was off its events
    /// went straight to the app, so whether the button is still down has to be
    /// asked separately.
    case tapDisabled(buttonStillDown: Bool)
    case accessibilityLost
}

/// What the tap does with the event it is holding.
enum WindowGestureDecision: Equatable {
    /// Hand the event back to the system untouched.
    case passThrough
    /// Take custody of the press while it is still undecided.
    case arm
    /// Keep the press: the pointer has not moved enough to mean a gesture.
    case hold
    /// The press became a window gesture.
    case promote
    /// Keep driving the window with this movement.
    case applyMove
    /// Last movement of the gesture.
    case applyFinish
    /// The press was only a click: give the held press back, then the release.
    case replayThenPass
    /// Give the held press back and let this event through as well.
    case flushThenPass
    /// Forget the gesture without giving anything back.
    case dropState
    /// A new press arrived over a stale one: forget it and judge this event
    /// as if nothing were pending.
    case restartAsIdle
    /// A second button went down while the first press was still held: give
    /// that press back, since its own release is still coming, then judge
    /// this event as if nothing were pending.
    case flushThenRestart
}

enum WindowGestureSupport {
    static let defaultModifiers: GlobalShortcutModifiers = [.control, .command]
    static let moveModifierMask: GlobalShortcutModifiers = [.control, .option, .command]

    /// How far the pointer may wander between press and release and still
    /// count as a plain click. Below it the press is handed back to the app
    /// untouched, so a modifier click keeps working everywhere; past it the
    /// press becomes a window gesture. Deliberately its own constant: tuning
    /// one pointer feature must never move another.
    static let dragSlop: CGFloat = 6

    static func exceedsDragSlop(from origin: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return (dx * dx + dy * dy).squareRoot() > dragSlop
    }

    /// The whole custody rule in one pure function, so every path that takes
    /// or returns a press is provable without Accessibility, a tap or a
    /// window. A press is only ever kept while it may still become a gesture,
    /// and a press that never became one is always given back exactly once.
    static func decide(state: WindowGestureState,
                       input: WindowGestureInput) -> WindowGestureDecision {
        switch state {
        case .idle:
            if case .buttonDown(_, let chordMatched) = input {
                return chordMatched ? .arm : .passThrough
            }
            return .passThrough

        case .pending:
            switch input {
            case .buttonDragged(let tracked, let pastSlop):
                guard tracked else { return .flushThenPass }
                return pastSlop ? .promote : .hold
            case .buttonUp(let tracked):
                return tracked ? .replayThenPass : .flushThenPass
            case .buttonDown(let sameButton, _):
                // Same button pressing again means its release never arrived.
                // The app never saw that press, so dropping it leaves nothing
                // half done, and replaying it here would click at a stale
                // spot. A different button means the first one is still held
                // and its release is still coming, so that press has to go
                // back or the app would get a release it never pressed.
                return sameButton ? .restartAsIdle : .flushThenRestart
            case .tapDisabled(let buttonStillDown):
                // Giving the press back only closes into a whole click if a
                // release is still coming. With the button already up, the
                // release went to the app while the tap was off, so handing
                // the press back now would leave it pressed with nothing to
                // lift it.
                return buttonStillDown ? .flushThenPass : .dropState
            case .otherEvent, .accessibilityLost:
                return .flushThenPass
            }

        case .active:
            switch input {
            case .buttonDragged(let tracked, _):
                return tracked ? .applyMove : .passThrough
            case .buttonUp(let tracked):
                return tracked ? .applyFinish : .passThrough
            case .buttonDown, .otherEvent:
                return .passThrough
            case .tapDisabled, .accessibilityLost:
                // The app never received the press that started the gesture,
                // so there is nothing to give back.
                return .dropState
            }
        }
    }

    static var defaultModifierStorageValue: String {
        storageValue(for: defaultModifiers)
    }

    /// Invalid or empty values fall back to a deliberate two-key gesture. A
    /// primary modifier is required so Shift by itself can never take over
    /// ordinary range selection and text dragging throughout the system.
    static func modifiers(from storedValue: String?) -> GlobalShortcutModifiers {
        guard let storedValue else { return defaultModifiers }
        var modifiers: GlobalShortcutModifiers = []
        for token in storedValue.split(separator: "+") {
            switch token {
            case "control": modifiers.insert(.control)
            case "option": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "command": modifiers.insert(.command)
            default: return defaultModifiers
            }
        }
        // Shift is reserved as the resize variant of the same primary drag,
        // which keeps the feature fully usable from a trackpad.
        modifiers.formIntersection(moveModifierMask)
        return modifiers.hasPrimaryModifier ? modifiers : defaultModifiers
    }

    static func storageValue(for modifiers: GlobalShortcutModifiers) -> String {
        let sanitized = modifiers.intersection(moveModifierMask)
        let resolved = sanitized.hasPrimaryModifier ? sanitized : defaultModifiers
        return resolved.storageTokens.joined(separator: "+")
    }

    static func resizeModifiers(from moveModifiers: GlobalShortcutModifiers) -> GlobalShortcutModifiers {
        moveModifiers.intersection(moveModifierMask).union(.shift)
    }

    static func modifiersMatch(eventFlags: CGEventFlags,
                               expected: GlobalShortcutModifiers) -> Bool {
        GlobalShortcutModifiers(cgFlags: eventFlags) == expected.intersection(.validMask)
    }

    static func movedOrigin(from original: CGPoint,
                            pointerStart: CGPoint,
                            pointerNow: CGPoint) -> CGPoint {
        CGPoint(x: original.x + pointerNow.x - pointerStart.x,
                y: original.y + pointerNow.y - pointerStart.y)
    }

    /// Divides the window into nine intuitive regions. Corners resize in two
    /// axes and edge regions in one. The center chooses its nearest edge, so
    /// resizing from anywhere in the window always has a visible result.
    static func resizeEdges(at point: CGPoint, in frame: CGRect) -> WindowGestureResizeEdges {
        guard frame.width > 0, frame.height > 0 else { return [] }
        let localX = min(max(point.x - frame.minX, 0), frame.width)
        let localY = min(max(point.y - frame.minY, 0), frame.height)
        var edges: WindowGestureResizeEdges = []

        if localX < frame.width / 3 {
            edges.insert(.left)
        } else if localX > frame.width * 2 / 3 {
            edges.insert(.right)
        }
        if localY < frame.height / 3 {
            edges.insert(.top)
        } else if localY > frame.height * 2 / 3 {
            edges.insert(.bottom)
        }

        guard edges.isEmpty else { return edges }
        let candidates: [(CGFloat, WindowGestureResizeEdges)] = [
            (localX, .left),
            (frame.width - localX, .right),
            (localY, .top),
            (frame.height - localY, .bottom),
        ]
        return candidates.min { $0.0 < $1.0 }?.1 ?? .right
    }

    /// AX window coordinates use a top-left origin. Resizing a top or left
    /// edge therefore moves the origin while keeping the opposite edge fixed.
    /// The minimum is only a safety floor; apps remain free to enforce a
    /// larger minimum through Accessibility.
    static func resizedFrame(from original: CGRect,
                             pointerStart: CGPoint,
                             pointerNow: CGPoint,
                             edges: WindowGestureResizeEdges,
                             minimumSize: CGSize = CGSize(width: 120, height: 80)) -> CGRect {
        let deltaX = pointerNow.x - pointerStart.x
        let deltaY = pointerNow.y - pointerStart.y
        var origin = original.origin
        var size = original.size

        if edges.contains(.left) {
            size.width = max(minimumSize.width, original.width - deltaX)
            origin.x = original.maxX - size.width
        } else if edges.contains(.right) {
            size.width = max(minimumSize.width, original.width + deltaX)
        }

        if edges.contains(.top) {
            size.height = max(minimumSize.height, original.height - deltaY)
            origin.y = original.maxY - size.height
        } else if edges.contains(.bottom) {
            size.height = max(minimumSize.height, original.height + deltaY)
        }

        return CGRect(origin: origin, size: size)
    }

    /// Reanchors the far edge after an app applies a larger minimum size than
    /// the requested frame. Right and bottom resizing keep the original origin;
    /// left and top resizing derive it from the size the app actually accepted.
    static func anchoredOrigin(original: CGRect,
                               requestedOrigin: CGPoint,
                               acceptedSize: CGSize,
                               edges: WindowGestureResizeEdges) -> CGPoint {
        var origin = requestedOrigin
        if edges.contains(.left) {
            origin.x = original.maxX - acceptedSize.width
        }
        if edges.contains(.top) {
            origin.y = original.maxY - acceptedSize.height
        }
        return origin
    }

    /// Returns no position mutation for the right and bottom edges. Keeping
    /// that distinction explicit prevents Accessibility from publishing an
    /// unnecessary intermediate frame during continuous resizing.
    static func anchoredOriginIfNeeded(original: CGRect,
                                       requestedOrigin: CGPoint,
                                       acceptedSize: CGSize,
                                       edges: WindowGestureResizeEdges) -> CGPoint? {
        guard edges.contains(.left) || edges.contains(.top) else { return nil }
        return anchoredOrigin(original: original,
                              requestedOrigin: requestedOrigin,
                              acceptedSize: acceptedSize,
                              edges: edges)
    }
}

/// Actions triggered by the hold-shortcut pointer wheel.
enum WindowDirectionalAction: Equatable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case minimize

    var layoutAction: WindowLayoutAction? {
        switch self {
        case .leftHalf: return .leftHalf
        case .rightHalf: return .rightHalf
        case .topHalf: return .topHalf
        case .bottomHalf: return .bottomHalf
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        case .maximize: return .maximize
        case .minimize: return nil
        }
    }
}

/// Pure direction and special-action selection for the hold-shortcut pointer layout mode.
enum WindowDirectionalGestureSupport {
    static let activationDistance: CGFloat = 28

    static func action(from origin: CGPoint,
                       to point: CGPoint,
                       activationDistance: CGFloat = activationDistance) -> WindowDirectionalAction? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        guard hypot(dx, dy) >= activationDistance else { return nil }

        // Standard 8-way angular division (45° per slice):
        var degrees = atan2(dy, dx) * 180.0 / .pi
        if degrees < 0 { degrees += 360.0 }

        if degrees >= 337.5 || degrees < 22.5 { return .rightHalf }
        if degrees >= 22.5 && degrees < 67.5 { return .topRight }
        if degrees >= 67.5 && degrees < 112.5 { return .topHalf }
        if degrees >= 112.5 && degrees < 157.5 { return .topLeft }
        if degrees >= 157.5 && degrees < 202.5 { return .leftHalf }
        if degrees >= 202.5 && degrees < 247.5 { return .bottomLeft }
        if degrees >= 247.5 && degrees < 292.5 { return .bottomHalf }
        return .bottomRight
    }
}

enum WindowEdgeDragClassification: Equatable {
    case waiting
    case moving
    case resizing
    case unrelated
}

struct WindowEdgeSnapScreen: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

struct WindowEdgeSnapTarget: Equatable {
    let action: WindowLayoutAction
    let frame: CGRect
    let visibleFrame: CGRect
}

enum WindowEdgeSnapSupport {
    static let activationDistance: CGFloat = 12
    static let resizeCornerDistance: CGFloat = 12
    static let resizeEdgeDistance: CGFloat = 5
    static let desktopAndDockSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
    )!
    private static let systemTilingKeys = [
        "EnableTilingByEdgeDrag",
        "EnableTilingOptionAccelerator",
        "EnableTopTilingByEdgeDrag",
    ]
    private static let movementThreshold: CGFloat = 2
    private static let sizeTolerance: CGFloat = 2

    static var isSystemTilingEnabled: Bool {
        guard #available(macOS 15.0, *),
              let defaults = UserDefaults(suiteName: "com.apple.WindowManager") else { return false }
        return systemTilingEnabled { key in
            guard defaults.object(forKey: key) != nil else { return nil }
            return defaults.bool(forKey: key)
        }
    }

    /// The system's edge tiling choices arrive enabled when their preference
    /// has never been written. Keeping this pure makes the conflict gate
    /// testable without changing somebody's desktop settings.
    static func systemTilingEnabled(valueFor: (String) -> Bool?) -> Bool {
        systemTilingKeys.contains { valueFor($0) ?? true }
    }

    static var isSystemTopWindowOverviewDragEnabled: Bool {
        guard #available(macOS 15.0, *) else { return true }
        guard let defaults = UserDefaults(suiteName: "com.apple.dock") else { return true }
        let key = "enterMissionControlByTopWindowDrag"
        let value = defaults.object(forKey: key).map { _ in defaults.bool(forKey: key) }
        return systemTopWindowOverviewDragEnabled(value: value)
    }

    /// The top-edge gesture also arrives enabled before its preference is
    /// written. The event tap keeps a confirmed window drag away from the
    /// physical top while edge snapping uses the menu bar's lower boundary.
    static func systemTopWindowOverviewDragEnabled(value: Bool?) -> Bool {
        value ?? true
    }

    /// Keeps a confirmed window drag one point inside the display while the
    /// pointer is pressed against its top edge. The snap target still sees the
    /// edge, but the system never receives the exact coordinate that opens its
    /// window overview. Callers must only use this after proving that a window,
    /// rather than content inside it, is moving.
    static func locationAvoidingSystemTopDrag(_ point: CGPoint,
                                              screenFrames: [CGRect]) -> CGPoint {
        guard let screen = screenFrames.first(where: {
            point.x >= $0.minX && point.x <= $0.maxX
                && abs(point.y - $0.minY) < 0.5
        }) else { return point }
        return CGPoint(x: point.x, y: screen.minY + 1)
    }

    static func startsAtResizeHandle(_ point: CGPoint,
                                     frame: CGRect) -> Bool {
        guard point.x >= frame.minX - resizeCornerDistance,
              point.x <= frame.maxX + resizeCornerDistance,
              point.y >= frame.minY - resizeCornerDistance,
              point.y <= frame.maxY + resizeCornerDistance else { return false }
        let nearVerticalCorner = abs(point.x - frame.minX) <= resizeCornerDistance
            || abs(point.x - frame.maxX) <= resizeCornerDistance
        let nearHorizontalCorner = abs(point.y - frame.minY) <= resizeCornerDistance
            || abs(point.y - frame.maxY) <= resizeCornerDistance
        let nearEdge = abs(point.x - frame.minX) <= resizeEdgeDistance
            || abs(point.x - frame.maxX) <= resizeEdgeDistance
            || abs(point.y - frame.minY) <= resizeEdgeDistance
            || abs(point.y - frame.maxY) <= resizeEdgeDistance
        return nearEdge || (nearVerticalCorner && nearHorizontalCorner)
    }

    /// A pointer drag is only a window move after the same window follows it.
    /// Content drags leave the frame still, while native resizing keeps at
    /// least two frame edges anchored. Neither may turn into a placement just
    /// because the pointer ends at a screen edge. A tiled window restoring its
    /// old size while it starts moving is still a move.
    static func classify(initialFrame: CGRect,
                         currentFrame: CGRect,
                         pointerStart: CGPoint,
                         pointerNow: CGPoint) -> WindowEdgeDragClassification {
        let sizeChanged = abs(currentFrame.width - initialFrame.width) > sizeTolerance
            || abs(currentFrame.height - initialFrame.height) > sizeTolerance
        if sizeChanged, sharesPerpendicularEdges(initialFrame, currentFrame) {
            return .resizing
        }

        let windowDelta = CGPoint(x: currentFrame.minX - initialFrame.minX,
                                  y: currentFrame.minY - initialFrame.minY)
        let pointerDelta = CGPoint(x: pointerNow.x - pointerStart.x,
                                   y: pointerNow.y - pointerStart.y)
        let windowDistance = hypot(windowDelta.x, windowDelta.y)
        guard windowDistance > movementThreshold else { return .waiting }

        let pointerDistance = hypot(pointerDelta.x, pointerDelta.y)
        guard pointerDistance > movementThreshold else { return .unrelated }
        let alignment = (windowDelta.x * pointerDelta.x + windowDelta.y * pointerDelta.y)
            / (windowDistance * pointerDistance)
        let ratio = windowDistance / pointerDistance
        return alignment >= 0.6 && ratio >= 0.2 && ratio <= 1.8 ? .moving : .unrelated
    }

    /// Resolves the hot zone under an AppKit-coordinate pointer. Screen frames
    /// choose the reachable edge; visible frames keep the result clear of the
    /// menu bar and Dock. A seam shared by two displays is not an edge, so a
    /// window can cross it without being caught halfway through.
    static func target(at point: CGPoint,
                       screens: [WindowEdgeSnapScreen],
                       distance: CGFloat = activationDistance) -> WindowEdgeSnapTarget? {
        let ordered = screens.enumerated().sorted {
            distanceSquared(from: point, to: $0.element.frame)
                < distanceSquared(from: point, to: $1.element.frame)
        }
        for (index, screen) in ordered {
            let frame = screen.frame
            guard frame.width > 0, frame.height > 0,
                  screen.visibleFrame.width > 0, screen.visibleFrame.height > 0,
                  point.x >= frame.minX - distance,
                  point.x <= frame.maxX + distance,
                  point.y >= frame.minY - distance,
                  point.y <= frame.maxY + distance
            else { continue }

            let otherFrames = screens.enumerated().compactMap { offset, value in
                offset == index ? nil : value.frame
            }
            let nearLeft = abs(point.x - frame.minX) <= distance
                && !hasNeighbor(beyond: .left, point: point, distance: distance, frames: otherFrames)
            let nearRight = abs(point.x - frame.maxX) <= distance
                && !hasNeighbor(beyond: .right, point: point, distance: distance, frames: otherFrames)
            let visibleTop = min(max(screen.visibleFrame.maxY, frame.minY), frame.maxY)
            let physicalTop = CGPoint(x: point.x, y: frame.maxY)
            let nearTop = point.y >= visibleTop - distance
                && point.y <= frame.maxY + distance
                && !hasNeighbor(beyond: .top,
                                point: physicalTop,
                                distance: distance,
                                frames: otherFrames)
            let nearBottom = abs(point.y - frame.minY) <= distance
                && !hasNeighbor(beyond: .bottom, point: point, distance: distance, frames: otherFrames)
            guard nearLeft || nearRight || nearTop || nearBottom else { continue }

            let horizontalCorner = min(max(frame.width * 0.18, 96), 180)
            let verticalCorner = min(max(frame.height * 0.18, 80), 160)
            let action: WindowLayoutAction
            if nearTop {
                if point.x <= frame.minX + horizontalCorner {
                    action = .topLeft
                } else if point.x >= frame.maxX - horizontalCorner {
                    action = .topRight
                } else {
                    action = .topHalf
                }
            } else if nearBottom {
                if point.x <= frame.minX + horizontalCorner {
                    action = .bottomLeft
                } else if point.x >= frame.maxX - horizontalCorner {
                    action = .bottomRight
                } else {
                    action = .bottomHalf
                }
            } else if nearLeft {
                if point.y >= frame.maxY - verticalCorner {
                    action = .topLeft
                } else if point.y <= frame.minY + verticalCorner {
                    action = .bottomLeft
                } else {
                    action = .leftHalf
                }
            } else {
                if point.y >= frame.maxY - verticalCorner {
                    action = .topRight
                } else if point.y <= frame.minY + verticalCorner {
                    action = .bottomRight
                } else {
                    action = .rightHalf
                }
            }

            let targetFrame = WindowLayoutGeometry.rect(for: action,
                                                        current: screen.visibleFrame,
                                                        visibleFrame: screen.visibleFrame)
            return WindowEdgeSnapTarget(action: action,
                                        frame: targetFrame.integral,
                                        visibleFrame: screen.visibleFrame)
        }
        return nil
    }

    private enum Edge {
        case left, right, top, bottom
    }

    private static func hasNeighbor(beyond edge: Edge,
                                    point: CGPoint,
                                    distance: CGFloat,
                                    frames: [CGRect]) -> Bool {
        var probe = point
        switch edge {
        case .left: probe.x -= distance + 1
        case .right: probe.x += distance + 1
        case .top: probe.y += distance + 1
        case .bottom: probe.y -= distance + 1
        }
        return frames.contains { inclusiveContains($0, probe) }
    }

    private static func sharesPerpendicularEdges(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let sharesVerticalEdge = abs(lhs.minX - rhs.minX) <= sizeTolerance
            || abs(lhs.maxX - rhs.maxX) <= sizeTolerance
        let sharesHorizontalEdge = abs(lhs.minY - rhs.minY) <= sizeTolerance
            || abs(lhs.maxY - rhs.maxY) <= sizeTolerance
        return sharesVerticalEdge && sharesHorizontalEdge
    }

    private static func inclusiveContains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    private static func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}
