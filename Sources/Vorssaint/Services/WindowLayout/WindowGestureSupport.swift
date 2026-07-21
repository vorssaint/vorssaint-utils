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
