// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Foundation

/// Measures the controls hosted by MenuBarAgent, not the app's placeholder
/// NSWindows. Never requests permission, reads menu contents or sends input.
enum MenuBarHiderAccessibility {
    static func separatorPositions(pid: pid_t, normalHelp: String,
                                   permanentHelp: String) -> (normal: CGRect, permanent: CGRect)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.03)
        let deadline = Date().addingTimeInterval(0.25)
        var pending: [AXUIElement] = [app]
        var visited = 0
        var normal: CGRect?
        var permanent: CGRect?
        while !pending.isEmpty, visited < 160, Date() < deadline {
            let element = pending.removeLast()
            // The timeout is per element; children otherwise wait seconds.
            AXUIElementSetMessagingTimeout(element, 0.03)
            visited += 1
            let labels = [kAXHelpAttribute, kAXDescriptionAttribute, kAXTitleAttribute]
                .compactMap { value(element, $0) as? String }
            if labels.contains(normalHelp) || labels.contains(permanentHelp),
               let frame = frame(element) {
                if labels.contains(normalHelp) { normal = frame }
                if labels.contains(permanentHelp) { permanent = frame }
                if let normal, let permanent, normal != permanent { return (normal, permanent) }
            }
            if let children = value(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(64))
            }
            if visited == 1, let windows = value(element, kAXWindowsAttribute) as? [AXUIElement] {
                pending.append(contentsOf: windows.prefix(8))
            }
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let raw = value(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID(),
              let sizeRaw = value(element, kAXSizeAttribute), CFGetTypeID(sizeRaw) == AXValueGetTypeID() else { return nil }
        let position = unsafeBitCast(raw, to: AXValue.self)
        let size = unsafeBitCast(sizeRaw, to: AXValue.self)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
