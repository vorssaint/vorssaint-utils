// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum MenuBarItemMoveError: LocalizedError {
    case permissionMissing
    case itemUnavailable
    case itemNotMovable
    case eventCreationFailed
    case verificationFailed
    case busy

    var errorDescription: String? {
        switch self {
        case .permissionMissing: return "Accessibility permission is required to move menu bar items."
        case .itemUnavailable: return "The menu bar item is no longer available."
        case .itemNotMovable: return "macOS does not allow this menu bar item to be moved."
        case .eventCreationFailed: return "Vorssaint could not create the drag operation."
        case .verificationFailed: return "The item did not reach the requested position."
        case .busy: return "Another menu bar operation is still running."
        }
    }
}

@MainActor
final class MenuBarItemMover {
    private(set) var isMoving = false

    func move(item: ManagedMenuBarItem,
              destinationFrame: CGRect,
              placeAfter: Bool,
              verify: @escaping () -> Bool) async throws {
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard item.isMovable, !item.isProtected else { throw MenuBarItemMoveError.itemNotMovable }
        guard !isMoving else { throw MenuBarItemMoveError.busy }
        isMoving = true
        defer { isMoving = false }

        try await waitForIdleInput()
        // CGEvents and CGWindow bounds share Quartz's global coordinate space.
        // NSEvent.mouseLocation uses AppKit coordinates and would restore the
        // cursor to the vertically mirrored point on the primary display.
        let originalPointer = CGEvent(source: nil)?.location
            ?? CGPoint(x: item.frame.midX, y: item.frame.midY)
        let displays = CGGetActiveDisplayList(maxDisplays: 16)
        for display in displays { CGDisplayHideCursor(display) }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        defer {
            CGWarpMouseCursorPosition(originalPointer)
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            for display in displays { CGDisplayShowCursor(display) }
        }

        var lastError: Error = MenuBarItemMoveError.verificationFailed
        for attempt in 0..<5 {
            do {
                try postCommandDrag(from: CGPoint(x: item.frame.midX, y: item.frame.midY),
                                    to: CGPoint(x: placeAfter ? destinationFrame.maxX + 2 : destinationFrame.minX - 2,
                                                y: destinationFrame.midY))
                try await Task.sleep(for: .milliseconds(80 + attempt * 45))
                if verify() { return }
                lastError = MenuBarItemMoveError.verificationFailed
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func click(item: ManagedMenuBarItem, button: CGMouseButton = .left) async throws {
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: source, mouseType: downType,
                                 mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: source, mouseType: upType,
                               mouseCursorPosition: point, mouseButton: button)
        else { throw MenuBarItemMoveError.eventCreationFailed }
        down.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(35))
        up.post(tap: .cghidEventTap)
    }

    private func waitForIdleInput() async throws {
        for _ in 0..<30 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let buttonsDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
                || CGEventSource.buttonState(.combinedSessionState, button: .right)
            if flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
               !buttonsDown {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw MenuBarItemMoveError.busy
    }

    private func postCommandDrag(from start: CGPoint, to end: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: start, mouseButton: .left),
              let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged,
                                 mouseCursorPosition: end, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: end, mouseButton: .left)
        else { throw MenuBarItemMoveError.eventCreationFailed }
        down.flags = .maskCommand
        drag.flags = .maskCommand
        up.flags = .maskCommand
        source.localEventsSuppressionInterval = 0
        let allLocalEvents: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents,
        ]
        source.setLocalEventsFilterDuringSuppressionState(allLocalEvents,
                                                           state: .eventSuppressionStateSuppressionInterval)
        CGWarpMouseCursorPosition(start)
        down.post(tap: .cghidEventTap)
        let steps = 8
        for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction,
                                y: start.y + (end.y - start.y) * fraction)
            guard let intermediate = CGEvent(mouseEventSource: source,
                                             mouseType: .leftMouseDragged,
                                             mouseCursorPosition: point,
                                             mouseButton: .left)
            else { continue }
            intermediate.flags = .maskCommand
            intermediate.post(tap: .cghidEventTap)
        }
        drag.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func CGGetActiveDisplayList(maxDisplays: UInt32) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        guard CoreGraphics.CGGetActiveDisplayList(maxDisplays, &displays, &count) == .success
        else { return [] }
        return Array(displays.prefix(Int(count)))
    }
}
