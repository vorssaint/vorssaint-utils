// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Darwin

/// Shared, bounded Dock reads. AX timeouts keep a restarting Dock from blocking
/// the main thread; no Accessibility calls run inside an input-tap callback.
enum DockAccessibility {
    struct Item {
        let element: AXUIElement
        let url: URL?
        let title: String
        let frame: CGRect
        let subrole: String
    }
    static var orientation: DockPreviewOrientation {
        DockPreviewOrientation.sanitized(UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation"))
    }
    static func attribute<T>(_ element: AXUIElement, _ name: String, as: T.Type = T.self) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p: AXValue = attribute(element, kAXPositionAttribute),
              let s: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func appKit(_ frame: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
    }
    static func quartz(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
    static func items() -> [Item] {
        guard AXIsProcessTrusted(), let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        return items(dockPID: dock.processIdentifier, screenTop: NSScreen.screens.first?.frame.maxY ?? 0)
    }
    /// The caller snapshots AppKit geometry on main before dispatching IPC.
    static func items(dockPID: pid_t, screenTop: CGFloat) -> [Item] {
        guard AXIsProcessTrusted() else { return [] }
        let root = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(root, 0.04)
        let children: [AXUIElement] = attribute(root, kAXChildrenAttribute) ?? []
        guard let list = children.first(where: { (attribute($0, kAXRoleAttribute) as String?) == kAXListRole }) else { return [] }
        return (attribute(list, kAXChildrenAttribute) as [AXUIElement]? ?? []).prefix(160).compactMap { element in
            guard let rect = frame(element) else { return nil }
            return Item(element: element, url: attribute(element, kAXURLAttribute),
                        title: attribute(element, kAXTitleAttribute) ?? "", frame: CGRect(x: rect.minX, y: screenTop - rect.maxY, width: rect.width, height: rect.height),
                        subrole: attribute(element, kAXSubroleAttribute) ?? "")
        }
    }
    static func application(for item: Item) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier > 0 }
        return application(for: item, apps: apps)
    }
    static func application(for item: Item, apps: [NSRunningApplication]) -> NSRunningApplication? {
        if let url = item.url {
            if let shortcut = Bundle(url: url), let target = shortcut.object(forInfoDictionaryKey: "ParallAppBundleId") as? String {
                let storage = shortcut.object(forInfoDictionaryKey: "ParallDataStorage") as? String
                let matches = apps.filter { $0.bundleIdentifier == target && DockProcessIdentity.matches(
                    processArguments($0.processIdentifier), launcher: shortcut.bundleIdentifier, storage: storage) }
                return matches.count == 1 ? matches[0] : nil
            }
            let direct = apps.filter { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
            if direct.count == 1 { return direct[0] }
            // Ambiguous identical-bundle processes never pick an arbitrary tile.
            let titled = direct.filter { $0.localizedName == item.title }
            if titled.count == 1 { return titled[0] }
            // A URL identifies this launcher, even when it is not running.
            // A different app sharing its label must never become its target.
            return nil
        }
        let named = apps.filter { $0.localizedName == item.title }
        return named.count == 1 ? named[0] : nil
    }
    private static func processID(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }
    private static func processArguments(_ pid: pid_t) -> String {
        // KERN_PROCARGS2 is local and bounded. It avoids spawning ps on hover.
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var count = 0
        guard sysctl(&mib, 3, nil, &count, nil, 0) == 0, count > 4, count <= 262144 else { return "" }
        var data = [UInt8](repeating: 0, count: count)
        guard sysctl(&mib, 3, &data, &count, nil, 0) == 0 else { return "" }
        return String(decoding: data.dropFirst(4), as: UTF8.self)
    }
}

extension CGRect {
    var dockCenter: CGPoint { CGPoint(x: midX, y: midY) }
}
