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
    /// Every question to the menu bar waits for it to answer, up to a tenth
    /// of a second while it rebuilds for another app. Those waits stay here,
    /// off the main thread.
    private let queue = DispatchQueue(label: "com.vorssaint.notch-volume-banner", qos: .userInteractive)
    /// A move still on the queue when the guard stops sees a newer value and
    /// puts its banner back.
    private var generation = 0
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
        generation &+= 1
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        detach()
        guard let hidden else { return }
        self.hidden = nil
        queue.async { Self.restore(hidden.window, to: hidden.origin) }
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
            Unmanaged<NotchVolumeBannerGuard>.fromOpaque(context).takeUnretainedValue().noticed(element)
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
        // A banner raised just before the guard started leaves as well.
        queue.async { [weak self] in
            let windows = Self.windows(app)
            DispatchQueue.main.async { windows.forEach { self?.noticed($0) } }
        }
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        pid = nil
    }

    /// Decides without asking the menu bar anything, so a hidden island costs
    /// no call at all. Like the keys, an output without a level to read keeps
    /// its banner, since the island has nothing to show for it. The banner is
    /// created already in place, so at most the start of its fade-in shows.
    private func noticed(_ element: AXUIElement) {
        guard running, NotchSupport.routes(.volume), NotchService.shared.showsSystemFeedback,
              AppVolumeMixer.shared.systemOutputVolume != nil else { return }
        let requested = generation
        queue.async { [weak self] in
            guard let origin = Self.hide(element) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                if self.generation == requested {
                    self.hidden = (element, origin)
                } else {
                    self.queue.async { Self.restore(element, to: origin) }
                }
            }
        }
    }

    /// Where macOS had placed the banner, once it is out of sight. A banner
    /// the menu bar places again is moved again.
    private static func hide(_ element: AXUIElement) -> CGPoint? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard NotchVolumeBannerSupport.isBanner(string(element, kAXIdentifierAttribute)),
              string(element, kAXRoleAttribute) == kAXWindowRole,
              let frame = frame(element),
              let away = NotchVolumeBannerSupport.hiddenOrigin(for: frame, screens: screens()),
              move(element, to: away) else { return nil }
        return frame.origin
    }

    /// A banner still on its way out comes back, so a press macOS handles
    /// while the island cannot show volume is not left without feedback.
    private static func restore(_ window: AXUIElement, to origin: CGPoint) {
        AXUIElementSetMessagingTimeout(window, 0.1)
        guard let frame = frame(window), NotchVolumeBannerSupport.isOffScreen(frame, screens: screens()) else { return }
        _ = move(window, to: origin)
    }

    private static func screens() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    private static func windows(_ app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
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
