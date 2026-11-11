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
        var menuItems: [CGRect] = []
        for item in items {
            guard Date() < deadline, let rect = frame(item, primaryTop: primaryTop) else { return nil }
            menuItems.append(rect)
        }
        var statusItems: [CGRect] = []
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
            statusItems.append(CGRect(x: x, y: primaryTop - y - height, width: width, height: height))
        }
        // On macOS 27 status items are drawn into the menu bar's own window,
        // so none show up as status-level windows. Without them every status
        // item would read as free space and the island would cover them, the
        // menu bar's overflow control included. Ask their owners through AX.
        if statusItems.isEmpty {
            guard let extras = NotchStatusItemOwners.shared.frames(primaryTop: primaryTop),
                  !extras.isEmpty else { return nil }
            statusItems = extras
        }
        // AX may describe only another display's menu bar. Require an item on
        // the selected display before status items can further constrain it.
        return NotchMenuBarLayout.measuredSideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                   barHeight: geometry.menuBarHeight,
                                                   menuItems: menuItems, statusItems: statusItems)
    }

    fileprivate static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    fileprivate static func frame(_ element: AXUIElement, primaryTop: CGFloat) -> CGRect? {
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

/// Which running apps own status items, and where those items are now.
/// Finding the owners asks every running app over AX and takes seconds when
/// some answer slowly, so that search runs on its own queue now and then;
/// each measurement asks only the owners already found. Until the first
/// search finishes there are no frames, and the measurement fails closed.
final class NotchStatusItemOwners: @unchecked Sendable {
    static let shared = NotchStatusItemOwners()

    /// Rare enough to keep the full search cheap, frequent enough that an
    /// item added by an app that was already running is found soon.
    private static let refreshInterval: TimeInterval = 15
    /// Apps that come and go in bursts do not restart the search every tick.
    private static let minimumSearchInterval: TimeInterval = 3
    private static let messagingTimeout: Float = 0.05
    private static let readBudget: TimeInterval = 0.3

    private let lock = NSLock()
    private var owners: [pid_t]?
    /// Owners that also draw items in their own windows (the system agent).
    private var hosts: Set<pid_t> = []
    private static let windowHostBundleID = "com.apple.MenuBarAgent"
    private var searchedRunning: Set<pid_t> = []
    private var searchedAt = Date.distantPast
    private var searching = false
    private let queue = DispatchQueue(label: "com.vorssaint.notch.status-item-owners", qos: .utility)

    /// Status item frames in the same flipped coordinates as the menus, or
    /// nil while the owners are unknown or a read runs out of time.
    func frames(primaryTop: CGFloat) -> [CGRect]? {
        guard let (owners, hosts) = currentOwners() else { return nil }
        let deadline = Date().addingTimeInterval(Self.readBudget)
        var rects: [CGRect] = []
        for pid in owners {
            guard Date() < deadline else { return nil }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
            // An owner may have quit, or dropped its items, since the search.
            guard let rawBar = NotchMenuBarSpace.value(app, kAXExtrasMenuBarAttribute),
                  CFGetTypeID(rawBar) == AXUIElementGetTypeID() else { continue }
            let bar = unsafeBitCast(rawBar, to: AXUIElement.self)
            guard let rawItems = NotchMenuBarSpace.value(bar, kAXChildrenAttribute),
                  CFGetTypeID(rawItems) == CFArrayGetTypeID(),
                  let items = rawItems as? [AXUIElement] else { continue }
            for item in items.prefix(64) {
                if let rect = NotchMenuBarSpace.frame(item, primaryTop: primaryTop) { rects.append(rect) }
            }
            if hosts.contains(pid) {
                rects += Self.hostedItemFrames(app, primaryTop: primaryTop)
            }
        }
        return rects
    }

    /// The system menu bar agent draws a Live Activity beside the camera as a
    /// menu bar item of its own full-width window, outside its extras menu
    /// bar. Only menu bar items count: that window also holds placeholders.
    private static func hostedItemFrames(_ app: AXUIElement, primaryTop: CGFloat) -> [CGRect] {
        guard let rawWindows = NotchMenuBarSpace.value(app, kAXWindowsAttribute),
              CFGetTypeID(rawWindows) == CFArrayGetTypeID(),
              let windows = rawWindows as? [AXUIElement] else { return [] }
        var rects: [CGRect] = []
        for window in windows.prefix(4) {
            guard let rawChildren = NotchMenuBarSpace.value(window, kAXChildrenAttribute),
                  CFGetTypeID(rawChildren) == CFArrayGetTypeID(),
                  let children = rawChildren as? [AXUIElement] else { continue }
            for child in children.prefix(64) {
                guard let role = NotchMenuBarSpace.value(child, kAXRoleAttribute) as? String,
                      role == kAXMenuBarItemRole as String,
                      let rect = NotchMenuBarSpace.frame(child, primaryTop: primaryTop) else { continue }
                rects.append(rect)
            }
        }
        return rects
    }

    private func currentOwners() -> ([pid_t], Set<pid_t>)? {
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        lock.lock(); defer { lock.unlock() }
        let elapsed = Date().timeIntervalSince(searchedAt)
        let stale = elapsed > Self.refreshInterval
            || (running != searchedRunning && elapsed > Self.minimumSearchInterval)
        if stale, !searching {
            searching = true
            queue.async { [self] in search() }
        }
        return owners.map { ($0, hosts) }
    }

    private func search() {
        let apps = NSWorkspace.shared.runningApplications
        var found: [pid_t] = []
        var foundHosts: Set<pid_t> = []
        for app in apps where !app.isTerminated {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            if NotchMenuBarSpace.value(element, kAXExtrasMenuBarAttribute) != nil {
                found.append(app.processIdentifier)
                if app.bundleIdentifier == Self.windowHostBundleID { foundHosts.insert(app.processIdentifier) }
            }
        }
        lock.lock()
        owners = found
        hosts = foundHosts
        searchedRunning = Set(apps.map(\.processIdentifier))
        searchedAt = Date()
        searching = false
        lock.unlock()
    }
}
