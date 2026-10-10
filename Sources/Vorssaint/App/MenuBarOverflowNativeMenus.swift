// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Locate and dismiss the native popup opened from a hidden status item.
/// Popup geometry uses Core Graphics screen coordinates, just like AX frames.
enum MenuBarOverflowNativeMenus {
    private static func owner(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private static func popupWindows(for pid: pid_t) -> [(owner: pid_t, frame: CGRect)] {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? Int32,
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 24,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.height > 40 else { return nil }
            let bundle = NSRunningApplication(processIdentifier: owner)?.bundleIdentifier ?? ""
            guard owner == pid || bundle == "com.apple.MenuBarAgent" || bundle.hasPrefix("com.apple.controlcenter") else { return nil }
            return (owner, frame)
        }
    }

    static func contains(point: CGPoint, for element: AXUIElement) -> Bool {
        popupWindows(for: owner(of: element)).contains { $0.frame.contains(point) }
    }

    static func cancel(_ element: AXUIElement) {
        let pid = owner(of: element)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            _ = AXUIElementPerformAction(focused as! AXUIElement, kAXCancelAction as CFString)
        }
        _ = AXUIElementPerformAction(element, kAXCancelAction as CFString)
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
            for child in children as? [AXUIElement] ?? [] {
                _ = AXUIElementPerformAction(child, kAXCancelAction as CFString)
            }
        }
        // AX-opened menus can lack normal outside-click tracking. Escape is
        // targeted only at an owner that still has a visible popup after AXCancel.
        if let popup = popupWindows(for: pid).first {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.postToPid(popup.owner)
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.postToPid(popup.owner)
        }
    }
}
