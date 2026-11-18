// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Geometry only: never reads menu titles, opens menus or requests permission.
/// Run off-main. Missing geometry fails closed rather than covering a menu.
enum NotchMenuBarSpace {
    static func measure(pid: pid_t, geometry: NotchGeometry, primaryTop: CGFloat,
                        ownWindow: Int, hasAccessibility: () -> Bool = AXIsProcessTrusted) -> CGFloat? {
        guard hasAccessibility() else { return nil }
        let reader = NotchMenuBarAXReader(primaryTop: primaryTop)
        let app = AXUIElementCreateApplication(pid)
        guard let menu = reader.element(app, kAXMenuBarAttribute),
              let items = reader.children(menu), !items.isEmpty,
              let menuItems = NotchMenuBarLayout.completeFrames(items, limit: 64, read: reader.frame)
        else { return nil }
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
        let requiresExtras: Bool
        if #available(macOS 27, *) { requiresExtras = true } else { requiresExtras = false }
        guard let measured = NotchMenuBarLayout.statusFrames(
            screen: geometry.screen, barHeight: geometry.menuBarHeight, windows: statusItems,
            requiresExtras: requiresExtras, extras: { NotchStatusItemOwners.shared.frames(reader: reader) }),
              reader.timeRemaining > 0 else { return nil }
        return NotchMenuBarLayout.measuredSideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                   barHeight: geometry.menuBarHeight, menuItems: menuItems,
                                                   statusItems: measured, physicalCamera: geometry.physicalCamera)
    }
}

/// Geometry-only reads, all sharing one deadline across every app, child and attribute.
struct NotchMenuBarAXReader {
    let primaryTop: CGFloat
    let deadline: TimeInterval
    init(primaryTop: CGFloat, deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 0.30) {
        self.primaryTop = primaryTop
        self.deadline = deadline
    }
    var timeRemaining: TimeInterval { deadline - ProcessInfo.processInfo.systemUptime }

    private func read(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        let remaining = timeRemaining
        guard remaining > 0.001 else { return (.cannotComplete, nil) }
        AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining)))
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return timeRemaining > 0 ? (status, result) : (.cannotComplete, nil)
    }

    func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        let (status, value) = read(element, attribute)
        return status == .success ? value : nil
    }

    func extras(_ app: AXUIElement) -> [AXUIElement]? {
        let (status, value) = read(app, kAXExtrasMenuBarAttribute)
        if status == .attributeUnsupported || status == .noValue { return [] }
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return children(unsafeBitCast(value, to: AXUIElement.self))
    }

    func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(parent, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    func children(_ parent: AXUIElement, attribute: String = kAXChildrenAttribute) -> [AXUIElement]? {
        guard let raw = value(parent, attribute), CFGetTypeID(raw) == CFArrayGetTypeID() else { return nil }
        return raw as? [AXUIElement]
    }

    func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &p),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &s),
              p.x.isFinite, p.y.isFinite, s.width.isFinite, s.height.isFinite, s.width > 0, s.height > 0
        else { return nil }
        return CGRect(x: p.x, y: primaryTop - p.y - s.height, width: s.width, height: s.height)
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
    fileprivate func frames(reader: NotchMenuBarAXReader) -> [CGRect]? {
        guard let (owners, hosts) = currentOwners() else { return nil }
        var frames: [CGRect] = []
        for pid in owners {
            let app = AXUIElementCreateApplication(pid)
            guard let items = reader.extras(app),
                  let measured = NotchMenuBarLayout.completeFrames(items, limit: 128, read: reader.frame)
            else { return nil }
            frames += measured
        }
        for pid in hosts {
            // Live Activities live in the agent's windows even when its extras bar has no items.
            let app = AXUIElementCreateApplication(pid)
            guard let windows = reader.children(app, attribute: kAXWindowsAttribute), windows.count <= 32 else { return nil }
            for window in windows {
                guard let children = reader.children(window), children.count <= 128 else { return nil }
                for item in children {
                    guard let role = reader.value(item, kAXRoleAttribute) as? String else { return nil }
                    if role == kAXMenuBarItemRole as String {
                        guard let frame = reader.frame(item) else { return nil }
                        frames.append(frame)
                    }
                }
            }
        }
        return frames
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
        guard running == searchedRunning else { return nil }
        return owners.map { ($0, hosts) }
    }

    private func search() {
        let apps = NSWorkspace.shared.runningApplications
        var found: [pid_t] = []
        var foundHosts: Set<pid_t> = []
        for app in apps where !app.isTerminated {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            if app.bundleIdentifier == Self.windowHostBundleID { foundHosts.insert(app.processIdentifier) }
            var bar: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &bar)
            if foundHosts.contains(app.processIdentifier) || (result == .success && bar != nil) {
                found.append(app.processIdentifier)
            } else if result != .attributeUnsupported && result != .noValue {
                // A previously measured owner that times out must not disappear from the occupied area.
                if lock.withLock({ owners?.contains(app.processIdentifier) == true }) {
                    found.append(app.processIdentifier)
                }
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
