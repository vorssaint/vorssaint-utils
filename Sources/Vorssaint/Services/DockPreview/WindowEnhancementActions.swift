// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

enum WindowEnhancementAction: String, CaseIterable {
    case close, minimize, maximize, fullscreen, quit, hide, center, restore
}

enum WindowEnhancementActions {
    private static var restoredFrames: [CGWindowID: CGRect] = [:]
    static func reset() { restoredFrames.removeAll() }
    static func element(_ item: SwitcherItem) -> AXUIElement? {
        guard AXIsProcessTrusted(), let id = item.windowID, item.windowOwnerPID != getpid() else { return nil }
        let app = AXUIElementCreateApplication(item.windowOwnerPID)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let windows: [AXUIElement] = DockAccessibility.attribute(app, kAXWindowsAttribute) ?? []
        return windows.prefix(120).first { AXWindowResolver.windowID(for: $0) == id }
    }
    @discardableResult
    static func perform(_ action: WindowEnhancementAction, on item: SwitcherItem) -> Bool {
        guard AXIsProcessTrusted(), let app = NSRunningApplication(processIdentifier: item.pid),
              !app.isTerminated, item.pid != getpid() else { return false }
        switch action {
        case .quit: return app.terminate()
        case .hide: return app.hide()
        case .close:
            guard let id = item.windowID else { return false }
            return WindowActivator.closeWindow(windowID: id, appPID: item.pid, windowOwnerPID: item.windowOwnerPID)
        case .minimize:
            guard let id = item.windowID, !item.isFullscreen else { return false }
            return WindowActivator.setWindowMinimized(!WindowActivator.windowIsMinimized(windowID: id, pid: item.windowOwnerPID), windowID: id, pid: item.windowOwnerPID)
        case .fullscreen:
            guard let window = element(item) else { return false }
            let current: Bool = DockAccessibility.attribute(window, "AXFullScreen") ?? false
            return AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, NSNumber(value: !current)) == .success
        case .restore:
            guard let id = item.windowID, let frame = restoredFrames.removeValue(forKey: id), let window = element(item) else { return false }
            return setFrame(frame, of: window)
        case .maximize, .center:
            guard !item.isFullscreen, let window = element(item) else { return false }
            let appKitFrame = DockAccessibility.appKit(item.frame)
            let screen = NSScreen.screens.first { $0.frame.contains(appKitFrame.dockCenter) } ?? NSScreen.main
            guard let screen else { return false }
            let visible = screen.visibleFrame
            if action == .maximize, let id = item.windowID {
                if restoredFrames.count > 64 { restoredFrames.removeAll() }
                if restoredFrames[id] == nil { restoredFrames[id] = appKitFrame }
            }
            let size = action == .maximize ? visible.size : CGSize(width: min(appKitFrame.width, visible.width), height: min(appKitFrame.height, visible.height))
            let rect = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
            return setFrame(rect, of: window)
        }
    }
    static func setFrame(_ appKitFrame: CGRect, of window: AXUIElement) -> Bool {
        var origin = DockAccessibility.quartz(CGPoint(x: appKitFrame.minX, y: appKitFrame.maxY))
        var size = appKitFrame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) == .success else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success
    }
    static func focus(_ item: SwitcherItem) {
        WindowActivator.activate(item)
        movePointer(after: item)
    }
    static func movePointer(after item: SwitcherItem) {
        let setting = DockOption.pointerFollowsFocus.string
        guard setting != "off" else { return }
        let rect = DockAccessibility.appKit(item.frame)
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(rect.dockCenter) }) else { return }
        if setting == "display", targetScreen.frame.contains(NSEvent.mouseLocation) == true { return }
        CGWarpMouseCursorPosition(DockAccessibility.quartz(rect.dockCenter))
    }
}
