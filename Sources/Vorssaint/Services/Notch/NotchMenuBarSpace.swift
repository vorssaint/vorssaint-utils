// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Geometry only: never reads menu titles, opens menus or requests permission.
/// Run off-main. Missing geometry fails closed rather than covering a menu.
enum NotchMenuBarSpace {
    static func measure(pid: pid_t, geometry: NotchGeometry, primaryTop: CGFloat,
                        ownWindow: Int) -> CGFloat? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let rawMenu = value(app, kAXMenuBarAttribute),
              CFGetTypeID(rawMenu) == AXUIElementGetTypeID() else { return nil }
        let menu = unsafeBitCast(rawMenu, to: AXUIElement.self)
        guard let rawItems = value(menu, kAXChildrenAttribute),
              CFGetTypeID(rawItems) == CFArrayGetTypeID(),
              let items = rawItems as? [AXUIElement], !items.isEmpty, items.count <= 64 else { return nil }
        let deadline = Date().addingTimeInterval(0.25)
        var occupied: [CGRect] = []
        for item in items {
            guard Date() < deadline, let rect = frame(item, primaryTop: primaryTop) else { return nil }
            occupied.append(rect)
        }
        let bar = CGRect(x: geometry.screen.minX, y: geometry.screen.maxY - geometry.menuBarHeight,
                         width: geometry.screen.width, height: geometry.menuBarHeight)
        // AX may describe only a different display's active menu bar.
        guard occupied.contains(where: { $0.intersects(bar) }) else { return nil }
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard let number = window[kCGWindowNumber as String] as? Int, number != ownWindow,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer >= Int(CGWindowLevelForKey(.statusWindow)),
                  layer <= Int(CGWindowLevelForKey(.statusWindow)) + 1,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 0, width < geometry.screen.width - 2,
                  height > 0, height <= geometry.menuBarHeight + 2 else { continue }
            occupied.append(CGRect(x: x, y: primaryTop - y - height, width: width, height: height))
        }
        return NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                           barHeight: geometry.menuBarHeight, occupied: occupied)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func frame(_ element: AXUIElement, primaryTop: CGFloat) -> CGRect? {
        guard let rawPosition = value(element, kAXPositionAttribute), CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              let rawSize = value(element, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        let position = unsafeBitCast(rawPosition, to: AXValue.self)
        let size = unsafeBitCast(rawSize, to: AXValue.self)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(x: point.x, y: primaryTop - point.y - dimensions.height,
                      width: dimensions.width, height: dimensions.height)
    }
}
