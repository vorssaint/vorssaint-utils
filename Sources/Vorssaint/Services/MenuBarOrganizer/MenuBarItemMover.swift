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
    private let inputCleanup = MenuBarInputCleanup()

    func cancel() { inputCleanup.finish() }

    func move(item: ManagedMenuBarItem,
              destinationFrame: CGRect,
              destinationWindowID: CGWindowID,
              placeAfter: Bool,
              onDragStart: (() -> Void)? = nil) async throws {
        guard MenuBarOrganizerPolicy.supportsAdvancedBackend else { throw MenuBarItemMoveError.itemUnavailable }
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard MenuBarOrganizerPolicy.validFrame(item.frame), MenuBarOrganizerPolicy.validFrame(destinationFrame) else { throw MenuBarItemMoveError.itemUnavailable }
        guard item.identityState == .stable else {
            throw MenuBarItemMoveError.provisionalIdentity
        }
        guard item.isMovable, !item.isProtected else {
            throw MenuBarItemMoveError.itemNotMovable
        }
        guard !isMoving else { throw MenuBarItemMoveError.busy }
        let targetPID = MenuBarOrganizerSupport.eventTargetPID(
            ownerPID: item.ownerPID,
            ownerBundleIdentifier: item.ownerBundleIdentifier,
            sourcePID: item.sourcePID)
        let relevantPIDs = Set([targetPID, item.sourcePID].compactMap { $0 })
        guard !Self.hasOpenMenu(for: relevantPIDs) else {
            throw MenuBarItemMoveError.menuOpen
        }
        isMoving = true
        defer { inputCleanup.finish(); isMoving = false }

        try await waitForIdleInput()
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard !Self.hasOpenMenu(for: relevantPIDs) else { throw MenuBarItemMoveError.menuOpen }
        guard let fresh = MenuBarWindowServerBridge.frame(of: item.windowID),
              abs(fresh.midX - item.frame.midX) < 2, abs(fresh.midY - item.frame.midY) < 2 else {
            throw MenuBarItemMoveError.itemUnavailable
        }
        let originalPointer = CGEvent(source: nil)?.location
            ?? CGPoint(x: item.frame.midX, y: item.frame.midY)
        let displays = Self.activeDisplays()
        inputCleanup.restoreCursor = {
            CGWarpMouseCursorPosition(originalPointer)
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            for display in displays { CGDisplayShowCursor(display) }
        }
        for display in displays { CGDisplayHideCursor(display) }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))

        let targetX = placeAfter ? destinationFrame.maxX + 2 : destinationFrame.minX - 2
        let end = CGPoint(x: targetX, y: destinationFrame.midY)
        try await postCommandDrag(
            from: CGPoint(x: item.frame.midX, y: item.frame.midY),
            to: end,
            windowID: item.windowID,
            destinationWindowID: destinationWindowID,
            targetPID: targetPID,
            onDragStart: onDragStart)
    }

    func click(item: ManagedMenuBarItem) async throws {
        guard MenuBarOrganizerPolicy.supportsAdvancedBackend else { throw MenuBarItemMoveError.itemUnavailable }
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard !isMoving else { throw MenuBarItemMoveError.busy }
        guard item.identityState == .stable, !item.isProtected,
              MenuBarOrganizerPolicy.validFrame(item.frame) else { throw MenuBarItemMoveError.itemUnavailable }
        isMoving = true
        defer { inputCleanup.finish(); isMoving = false }
        try await waitForIdleInput()
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard let fresh = MenuBarWindowServerBridge.frame(of: item.windowID),
              abs(fresh.midX - item.frame.midX) < 2, abs(fresh.midY - item.frame.midY) < 2 else {
            throw MenuBarItemMoveError.itemUnavailable
        }
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
        MenuBarOrganizerSupport.routeEvent(down, to: item.windowID, pid: targetPID, command: false)
        MenuBarOrganizerSupport.routeEvent(up, to: item.windowID, pid: targetPID, command: false)
        inputCleanup.release = { [weak self] in self?.post(up) }
        post(down)
        do {
            try await Task.sleep(for: .milliseconds(35))
        } catch {
            // The button is already down in the target process; a cancelled
            // click must still release it.
            inputCleanup.finish()
            throw error
        }
        inputCleanup.finish()
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
                                 windowID: CGWindowID,
                                 destinationWindowID: CGWindowID,
                                 targetPID: pid_t,
                                 onDragStart: (() -> Void)?) async throws {
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
        MenuBarOrganizerSupport.routeEvent(down, to: windowID, pid: targetPID, command: true)
        MenuBarOrganizerSupport.routeEvent(up, to: destinationWindowID, pid: targetPID, command: false)

        CGWarpMouseCursorPosition(start)
        inputCleanup.release = { [weak self] in self?.post(up) }
        onDragStart?()
        post(down)
        do {
            try await Task.sleep(for: .milliseconds(18))
            for step in 1...10 {
                try Task.checkCancellation()
                guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
                let fraction = CGFloat(step) / 10
                let point = CGPoint(x: start.x + (end.x - start.x) * fraction,
                                    y: start.y + (end.y - start.y) * fraction)
                guard let drag = CGEvent(mouseEventSource: source,
                                         mouseType: .leftMouseDragged,
                                         mouseCursorPosition: point,
                                         mouseButton: .left)
                else { throw MenuBarItemMoveError.eventCreationFailed }
                MenuBarOrganizerSupport.routeEvent(drag, to: windowID, pid: targetPID, command: true)
                post(drag)
                try await Task.sleep(for: .milliseconds(8))
            }
        } catch {
            // The Command-drag is mid-flight in the target process; a thrown
            // step must still release the button or the user's next real
            // click keeps dragging the status item.
            inputCleanup.finish()
            throw error
        }
        inputCleanup.finish()
    }

    private func post(_ event: CGEvent) {
        // Enter the session stream so WindowServer participates in reordering;
        // posting only to the application bypasses the native drag machinery.
        event.post(tap: .cgSessionEventTap)
    }

    static func hasOpenMenu(for pids: Set<pid_t>) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]]
        else { return true }
        let statusItems = Set(MenuBarWindowServerBridge.menuBarWindowIDs() ?? [])
        return windows.contains { dictionary in
            guard let pid = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pids.contains(pid),
                  let level = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue
            else { return false }
            let id = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return MenuBarOrganizerPolicy.isOpenMenuWindow(
                level: level, popupLevel: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                isStatusItem: statusItems.contains(id), alpha: alpha)
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
