// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Moves macOS' volume banner off the screen while the island shows volume.
/// Runs alongside the island's volume keys, which keep the banner away only
/// for the presses they take.
final class NotchVolumeBannerGuard {
    private var observer: AXObserver?
    private var pid: pid_t?
    private var running = false
    private var workspaceObservers: [NSObjectProtocol] = []
    /// The banner this guard moved, and where macOS had placed it.
    private var hidden: (window: AXUIElement, origin: CGPoint)?
    private let notifications = [kAXCreatedNotification, kAXWindowCreatedNotification, kAXWindowMovedNotification]

    func start() {
        guard AXIsProcessTrusted() else { stop(); return }
        running = true
        if workspaceObservers.isEmpty {
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in self?.attach()
                })
            }
        }
        attach()
    }

    func stop() {
        running = false
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        detach()
        restore()
    }

    private func attach() {
        guard running else { return }
        let nextPID = NSRunningApplication.runningApplications(withBundleIdentifier: NotchVolumeBannerSupport.host)
            .first?.processIdentifier
        guard nextPID != pid || observer == nil else { return }
        detach()
        guard let nextPID else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, context in
            guard let context else { return }
            Unmanaged<NotchVolumeBannerGuard>.fromOpaque(context).takeUnretainedValue().hide(element)
        }
        guard AXObserverCreate(nextPID, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(nextPID)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var attached = false
        for name in notifications {
            if AXObserverAddNotification(created, app, name as CFString, context) == .success { attached = true }
        }
        guard attached else { return }
        pid = nextPID
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        pid = nil
    }

    /// Moves within the notification itself. The banner is created already
    /// in place and draws a few hundredths of a second later, so it never
    /// reaches the screen. A banner the menu bar places again is moved again.
    private func hide(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, 0.1)
        let showsVolume = NotchSupport.routes(.volume) && NotchService.shared.showsSystemFeedback
        guard NotchVolumeBannerSupport.hides(showsVolume: showsVolume,
                                             identifier: Self.string(element, kAXIdentifierAttribute)),
              let frame = Self.frame(element),
              let away = NotchVolumeBannerSupport.hiddenOrigin(for: frame, screens: Self.screens()),
              Self.move(element, to: away) else { return }
        hidden = (element, frame.origin)
    }

    /// A banner still on its way out comes back, so a press macOS handles
    /// while the island cannot show volume is not left without feedback.
    private func restore() {
        guard let hidden else { return }
        self.hidden = nil
        guard let frame = Self.frame(hidden.window),
              NotchVolumeBannerSupport.isOffScreen(frame, screens: Self.screens()) else { return }
        _ = Self.move(hidden.window, to: hidden.origin)
    }

    private static func screens() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Global coordinates with the origin at the top left, like the display bounds.
    private static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func move(_ element: AXUIElement, to origin: CGPoint) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }
}
