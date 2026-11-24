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
            requiresExtras: requiresExtras, extras: { bar in
                NotchStatusItemOwners.shared.frames(reader: reader, modernBar: requiresExtras ? bar : nil)
            }),
              reader.timeRemaining > 0 else { return nil }
        return NotchMenuBarLayout.measuredSideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                   barHeight: geometry.menuBarHeight, menuItems: menuItems,
                                                   statusItems: measured, physicalCamera: geometry.physicalCamera)
    }
}

/// Geometry-only reads, all sharing one deadline across every app, child and attribute.
struct NotchMenuBarAXReader {
    typealias CopyAttribute = (AXUIElement, CFString, UnsafeMutablePointer<CFTypeRef?>) -> AXError

    let primaryTop: CGFloat
    let deadline: TimeInterval
    private let copyAttribute: CopyAttribute

    init(primaryTop: CGFloat, deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 0.30,
         copyAttribute: @escaping CopyAttribute = AXUIElementCopyAttributeValue) {
        self.primaryTop = primaryTop
        self.deadline = deadline
        self.copyAttribute = copyAttribute
    }
    var timeRemaining: TimeInterval { deadline - ProcessInfo.processInfo.systemUptime }

    private func read(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        let remaining = timeRemaining
        guard remaining > 0.001 else { return (.cannotComplete, nil) }
        AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining)))
        var result: CFTypeRef?
        let status = copyAttribute(element, attribute as CFString, &result)
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

    private static let windowHostBundleID = "com.apple.MenuBarAgent"
    private let lock = NSLock()
    private var discovery: Discovery?
    private var searchedRunning: Set<pid_t> = []
    private var searchedAt = Date.distantPast
    private var searching = false
    private let queue = DispatchQueue(label: "com.vorssaint.notch.status-item-owners", qos: .utility)

    /// Status item frames in the same flipped coordinates as the menus, or
    /// nil while the owners are unknown or a read runs out of time.
    fileprivate func frames(reader: NotchMenuBarAXReader, modernBar: CGRect?) -> [CGRect]? {
        guard let discovery = currentOwners() else { return nil }
        var hostWindows: [AXUIElement] = []
        for pid in discovery.hosts {
            let app = AXUIElementCreateApplication(pid)
            guard let windows = reader.children(app, attribute: kAXWindowsAttribute), windows.count <= 32 else { return nil }
            hostWindows += windows
        }
        return discovery.frames(windows: hostWindows, modernBar: modernBar,
            extras: { reader.extras(AXUIElementCreateApplication($0)) },
            children: { reader.children($0) }, frame: reader.frame,
            role: { reader.value($0, kAXRoleAttribute) as? String })
    }

    struct Discovery {
        private(set) var owners: [pid_t] = []
        private(set) var hosts: Set<pid_t> = []
        private var hasUnresolvedApps = false

        mutating func record(pid: pid_t, isHost: Bool, result: AXError, hasBar: Bool, previous: Set<pid_t>) {
            if isHost { hosts.insert(pid) }
            if isHost || (result == .success && hasBar) {
                owners.append(pid)
            } else if result != .attributeUnsupported && result != .noValue {
                if previous.contains(pid) { owners.append(pid) }
                else { hasUnresolvedApps = true }
            }
        }

        func frames<Item>(windows: [Item], modernBar: CGRect?, extras: (pid_t) -> [Item]?,
                          children: (Item) -> [Item]?, frame: (Item) -> CGRect?, role: (Item) -> String?) -> [CGRect]? {
            var needsHostBar = hasUnresolvedApps
            var frames: [CGRect] = []
            for pid in owners {
                guard let items = extras(pid) else {
                    guard modernBar != nil else { return nil }
                    needsHostBar = true
                    continue
                }
                // Once an owner lists its items, each one must be accounted for.
                guard let measured = NotchMenuBarLayout.completeFrames(items, limit: 128, read: frame) else { return nil }
                frames += measured
            }
            let requiredBar = needsHostBar ? modernBar : nil
            var measuredBar = false
            for window in windows {
                let bounds = requiredBar == nil ? nil : frame(window)
                if let bar = requiredBar, let bounds, !bounds.intersects(bar) { continue }
                guard let items = children(window), items.count <= 128 else { return nil }
                if let bar = requiredBar, !items.isEmpty {
                    guard let bounds else { return nil }
                    if abs(bounds.minX - bar.minX) <= 1, abs(bounds.maxX - bar.maxX) <= 1,
                       abs(bounds.maxY - bar.maxY) <= 1, bounds.minY <= bar.midY, bounds.height <= bar.height + 2 {
                        // The host lays out one direct child per slot, including items
                        // whose app did not answer. A slot can be a group or have no role.
                        guard let slots = NotchMenuBarLayout.completeFrames(items, limit: 128, read: frame) else { return nil }
                        if slots.contains(where: { bar.contains(CGPoint(x: $0.midX, y: $0.midY)) }) { measuredBar = true }
                        frames += slots
                        continue
                    }
                }
                // Live Activities can also appear as menu bar items in the agent's windows.
                for item in items {
                    guard let itemRole = role(item) else { return nil }
                    if itemRole == kAXMenuBarItemRole as String {
                        guard let rect = frame(item) else { return nil }
                        frames.append(rect)
                    }
                }
            }
            // A readable owner's extras alone cannot vouch for an app that timed out.
            guard requiredBar == nil || measuredBar else { return nil }
            return frames
        }
    }

    private func currentOwners() -> Discovery? {
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
        return discovery
    }

    private func search() {
        let apps = NSWorkspace.shared.runningApplications
        let previous = lock.withLock { Set(discovery?.owners ?? []) }
        var found = Discovery()
        for app in apps where !app.isTerminated {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            var bar: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &bar)
            found.record(pid: app.processIdentifier, isHost: app.bundleIdentifier == Self.windowHostBundleID,
                         result: result, hasBar: bar != nil, previous: previous)
        }
        lock.lock()
        discovery = found
        searchedRunning = Set(apps.map(\.processIdentifier))
        searchedAt = Date()
        searching = false
        lock.unlock()
    }
}
