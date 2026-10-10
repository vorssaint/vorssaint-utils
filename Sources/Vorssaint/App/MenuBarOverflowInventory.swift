// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import ApplicationServices
import Foundation

/// Accessibility discovery has no UI objects and runs off the main thread.
enum MenuBarOverflowInventory {
    static let menuBarAgentBundle = "com.apple.MenuBarAgent"

    struct Application: Sendable {
        let pid: pid_t
        let bundle: String
        let name: String
    }

    struct Record {
        let identifier: String?
        let id: String
        let bundle: String
        let name: String
        let element: AXUIElement
        let frame: CGRect
    }

    private static func menuElements(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 4 else { return [] }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if role as? String == kAXMenuBarItemRole as String { return [element] }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        return (children as? [AXUIElement] ?? []).flatMap { menuElements($0, depth: depth + 1) }
    }

    static func drawerFrame() -> CGRect? {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == menuBarAgentBundle }) else { return nil }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05)
        func find(_ element: AXUIElement, depth: Int) -> CGRect? {
            guard depth < 6 else { return nil }
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
            if identifier as? String == "vorssaint.icon-drawer" {
                var position: CFTypeRef?
                var size: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                      AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
                      let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
                var point = CGPoint.zero
                var dimensions = CGSize.zero
                AXValueGetValue(position as! AXValue, .cgPoint, &point)
                AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
                return CGRect(origin: point, size: dimensions)
            }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success else { return nil }
            for child in children as? [AXUIElement] ?? [] {
                if let frame = find(child, depth: depth + 1) { return frame }
            }
            return nil
        }
        return find(app, depth: 0)
    }

    static func read(_ apps: [Application]) -> [Record] {
        var records: [Record] = []
        for descriptor in apps {
            let (pid, bundle, appName) = (descriptor.pid, descriptor.bundle, descriptor.name)
            let system = bundle == menuBarAgentBundle
            guard system || !bundle.hasPrefix("com.apple.") else { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success,
                  let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let elements = children as? [AXUIElement] else { continue }
            let candidates = system ? elements.flatMap { menuElements($0) } : elements
            for (index, element) in candidates.enumerated() {
                var position: CFTypeRef?
                var size: CFTypeRef?
                var identifier: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
                let systemInfo = system ? MenuBarOverflowSupport.systemControl(identifier: identifier as? String) : nil
                if system && systemInfo == nil { continue }
                let recordBundle = systemInfo?.selectionKey ?? bundle
                let name = systemInfo?.name ?? appName
                var frame = CGRect.zero
                if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                   AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
                   let position, let size,
                   CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                    var point = CGPoint.zero
                    var dimensions = CGSize.zero
                    if AXValueGetValue(position as! AXValue, .cgPoint, &point),
                       AXValueGetValue(size as! AXValue, .cgSize, &dimensions) {
                        frame = CGRect(origin: point, size: dimensions)
                    }
                }
                records.append(.init(identifier: identifier as? String, id: system ? recordBundle : "\(recordBundle):\(identifier as? String ?? String(index))", bundle: recordBundle, name: name, element: element, frame: frame))
            }
        }
        return records.sorted { $0.frame.minX < $1.frame.minX }
    }
}
