// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum MenuBarItemMoveError: Error {
    case permissionMissing
    case itemUnavailable
    case itemNotMovable
    case provisionalIdentity
    case menuOpen
    case eventCreationFailed
    case verificationFailed
    case busy
}

@MainActor
final class MenuBarItemMover {
    private(set) var isMoving = false

    func move(item: ManagedMenuBarItem,
              destinationFrame: CGRect,
              placeAfter: Bool) async throws {
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard item.identityState == .stable else {
            throw MenuBarItemMoveError.provisionalIdentity
        }
        guard item.isMovable, !item.isProtected else {
            throw MenuBarItemMoveError.itemNotMovable
        }
        guard !isMoving else { throw MenuBarItemMoveError.busy }
        // MenuBarAgent owns one composited surface on macOS 27. Addressing the
        // publishing app PID does not reach an individual item there; let the
        // system hit-test the globally posted Command-drag by AX coordinates.
        let targetPID: pid_t? = item.backend == .accessibility ? nil
            : MenuBarOrganizerSupport.eventTargetPID(
                ownerPID: item.ownerPID,
                ownerBundleIdentifier: item.ownerBundleIdentifier,
                sourcePID: item.sourcePID)
        let relevantPIDs = Set([item.ownerPID, item.sourcePID].compactMap { $0 })
        guard !Self.hasOpenMenu(for: relevantPIDs) else {
            throw MenuBarItemMoveError.menuOpen
        }
        isMoving = true
        defer { isMoving = false }

        try await waitForIdleInput()
        let originalPointer = CGEvent(source: nil)?.location
            ?? CGPoint(x: item.frame.midX, y: item.frame.midY)
        let displays = Self.activeDisplays()
        for display in displays { CGDisplayHideCursor(display) }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        defer {
            CGWarpMouseCursorPosition(originalPointer)
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            for display in displays { CGDisplayShowCursor(display) }
        }

        let targetX = placeAfter ? destinationFrame.maxX + 2 : destinationFrame.minX - 2
        let end = CGPoint(x: targetX, y: destinationFrame.midY)
        let screenFrames = NSScreen.screens.map(\.frame)
        guard screenFrames.contains(where: { $0.contains(
            CGPoint(x: item.frame.midX, y: item.frame.midY)) }),
              screenFrames.contains(where: { $0.contains(end) })
        else { throw MenuBarItemMoveError.itemNotMovable }
        try await postCommandDrag(
            from: CGPoint(x: item.frame.midX, y: item.frame.midY),
            to: end,
            targetPID: targetPID)
    }

    func click(item: ManagedMenuBarItem) async throws {
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard !isMoving else { throw MenuBarItemMoveError.busy }
        let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: source,
                                 mouseType: .leftMouseDown,
                                 mouseCursorPosition: point,
                                 mouseButton: .left),
              let up = CGEvent(mouseEventSource: source,
                               mouseType: .leftMouseUp,
                               mouseCursorPosition: point,
                               mouseButton: .left)
        else { throw MenuBarItemMoveError.eventCreationFailed }
        let targetPID = MenuBarOrganizerSupport.eventTargetPID(
            ownerPID: item.ownerPID,
            ownerBundleIdentifier: item.ownerBundleIdentifier,
            sourcePID: item.sourcePID)
        post(down, targetPID: targetPID)
        try await Task.sleep(for: .milliseconds(35))
        post(up, targetPID: targetPID)
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

    private func postCommandDrag(from start: CGPoint,
                                 to end: CGPoint,
                                 targetPID: pid_t?) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: source,
                                 mouseType: .leftMouseDown,
                                 mouseCursorPosition: start,
                                 mouseButton: .left),
              let up = CGEvent(mouseEventSource: source,
                               mouseType: .leftMouseUp,
                               mouseCursorPosition: end,
                               mouseButton: .left)
        else { throw MenuBarItemMoveError.eventCreationFailed }

        source.localEventsSuppressionInterval = 0
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
        down.flags = .maskCommand
        up.flags = .maskCommand

        CGWarpMouseCursorPosition(start)
        post(down, targetPID: targetPID)
        try await Task.sleep(for: .milliseconds(60))
        for step in 1...24 {
            let fraction = CGFloat(step) / 24
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction,
                                y: start.y + (end.y - start.y) * fraction)
            guard let drag = CGEvent(mouseEventSource: source,
                                     mouseType: .leftMouseDragged,
                                     mouseCursorPosition: point,
                                     mouseButton: .left)
            else { throw MenuBarItemMoveError.eventCreationFailed }
            drag.flags = .maskCommand
            post(drag, targetPID: targetPID)
            try await Task.sleep(for: .milliseconds(16))
        }
        post(up, targetPID: targetPID)
        try await Task.sleep(for: .milliseconds(40))
    }

    private func post(_ event: CGEvent, targetPID: pid_t?) {
        if let targetPID {
            event.postToPid(targetPID)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private static func hasOpenMenu(for pids: Set<pid_t>) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let menuLevels = Set([
            Int(CGWindowLevelForKey(.popUpMenuWindow)),
            Int(CGWindowLevelForKey(.mainMenuWindow)),
        ])
        return windows.contains { dictionary in
            guard let pid = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pids.contains(pid),
                  let level = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue
            else { return false }
            return menuLevels.contains(level)
        }
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }
}
