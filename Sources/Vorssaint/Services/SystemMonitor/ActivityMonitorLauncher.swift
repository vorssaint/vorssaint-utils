// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Opens Activity Monitor on the category matching the detail pane. The tab
/// order is the toolbar's radio-group order, so it does not depend on the
/// user's language.
enum ActivityMonitorLauncher {
    enum Tab: Int, CaseIterable {
        case cpu, memory, energy, disk, network
    }

    private static let bundleIdentifier = "com.apple.ActivityMonitor"
    private static let launchTimeout: TimeInterval = 5
    private static let pollInterval: TimeInterval = 0.1

    static func open(_ tab: Tab) {
        let fallback = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) ?? fallback
        NSWorkspace.shared.open(url)

        // Without Accessibility the app still opens, on whichever tab it used
        // last. A prompt here would interrupt a plain "open" action.
        guard Permissions.shared.accessibility else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            select(tab)
        }
    }

    private static func select(_ tab: Tab) {
        let deadline = Date().addingTimeInterval(launchTimeout)
        while Date() < deadline {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
               app.isFinishedLaunching,
               let button = tabButton(pid: app.processIdentifier, tab: tab),
               AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                DispatchQueue.main.async {
                    app.activate(options: [])
                }
                return
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private static func tabButton(pid: pid_t, tab: Tab) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        for window in windows {
            guard let toolbar = descendant(of: window, role: kAXToolbarRole as String),
                  let group = descendant(of: toolbar, role: kAXRadioGroupRole as String),
                  let buttons = attribute(group, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            let radios = buttons.filter { role(of: $0) == kAXRadioButtonRole as String }
            if tab.rawValue < radios.count {
                return radios[tab.rawValue]
            }
        }
        return nil
    }

    private static func descendant(of element: AXUIElement, role target: String,
                                   depth: Int = 0) -> AXUIElement? {
        if role(of: element) == target { return element }
        guard depth < 4,
              let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let match = descendant(of: child, role: target, depth: depth + 1) { return match }
        }
        return nil
    }

    private static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
