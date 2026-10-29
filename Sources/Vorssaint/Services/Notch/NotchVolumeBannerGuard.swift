// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine

/// Moves macOS' volume banner off the screen while the island shows the same
/// level. Runs alongside the island's volume keys, which keep the banner away
/// only for the presses they take.
final class NotchVolumeBannerGuard {
    private var observer: AXObserver?
    private var pid: pid_t?
    /// Kept past detach so banners already hidden can still be put back.
    private var access: NotchNativeNotificationAccess?
    private var running = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var islandWatch: AnyCancellable?
    /// Questions to the menu bar can wait a tenth of a second for its
    /// answer, so they stay off the main thread.
    private let queue = DispatchQueue(label: "com.vorssaint.notch-volume-banner", qos: .userInteractive)
    /// Banners this guard moved, and where macOS had placed each. A banner
    /// per display at most, so only the latest few are kept.
    private var hidden: [(window: AXUIElement, origin: CGPoint)] = []
    /// A new window is announced already named. Its earlier creation
    /// notice would only cost a read.
    private let notifications = [kAXWindowCreatedNotification, kAXWindowMovedNotification]

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
        if islandWatch == nil {
            // A banner already up leaves once the notice shows. Once
            // something covers the island the banners come back, and a
            // notice that simply ends leaves its banner to expire.
            // Published values arrive before they land, so the island is
            // read a turn later.
            islandWatch = NotchService.shared.volumeNoticeChanges
                .receive(on: DispatchQueue.main)
                .map { _ in NotchService.shared.volumeBanner }
                .removeDuplicates()
                .sink { [weak self] state in
                    switch state {
                    case .shown: self?.scan()
                    case .covered: self?.restoreHidden()
                    case .quiet: break
                    }
                }
        }
        attach()
    }

    /// Puts back what it moved without waiting. On quit that may not finish,
    /// which is fine: the menu bar places each new banner in view itself.
    func stop() {
        running = false
        islandWatch = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        detach()
        restoreHidden()
    }

    private func restoreHidden() {
        let banners = hidden
        hidden.removeAll()
        guard !banners.isEmpty, let access else { return }
        queue.async { banners.forEach { Self.restore($0.window, to: $0.origin, using: access) } }
    }

    private func attach() {
        guard running else { return }
        // Other apps launching or quitting leave a live menu bar as it was.
        if observer != nil, let pid, let host = NSRunningApplication(processIdentifier: pid),
           !host.isTerminated, host.bundleIdentifier == NotchVolumeBannerSupport.host { return }
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
        access = NotchNativeNotificationAccess(pid: nextPID)
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        // A banner raised just before the guard started leaves as well.
        scan()
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        pid = nil
    }

    private func scan() {
        guard running, let access else { return }
        queue.async { [weak self] in
            let windows = (try? access.windows()) ?? []
            DispatchQueue.main.async { windows.forEach { self?.noticed($0) } }
        }
    }

    /// Decides without asking the menu bar, so an island showing no volume
    /// costs no call. The first frame of the fade-in still shows, since the
    /// menu bar takes a move only after it.
    private func noticed(_ element: AXUIElement) {
        guard running, let access, NotchService.shared.volumeBanner == .shown else { return }
        let queue = self.queue
        queue.async { [weak self] in
            guard let origin = Self.hide(element, using: access) else { return }
            DispatchQueue.main.async {
                // Decided again as it lands: the guard may have stopped, or
                // the island stopped showing volume, while the move ran.
                guard let self, self.running, NotchService.shared.volumeBanner == .shown else {
                    queue.async { Self.restore(element, to: origin, using: access) }
                    return
                }
                self.hidden.removeAll { CFEqual($0.window, element) }
                self.hidden.append((element, origin))
                self.hidden = Array(self.hidden.suffix(8))
            }
        }
    }

    /// Where macOS had placed the banner, once it is out of sight.
    private static func hide(_ element: AXUIElement, using access: NotchNativeNotificationAccess) -> CGPoint? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        let window = read(element)
        guard window.identifier == NotchVolumeBannerSupport.identifier, window.role == kAXWindowRole,
              let frame = window.frame,
              let away = NotchVolumeBannerSupport.hiddenOrigin(for: frame, screens: screens()),
              access.move(element, to: away) else { return nil }
        return frame.origin
    }

    /// A banner still on its way out comes back, so a change the island
    /// cannot show is not left without feedback.
    private static func restore(_ window: AXUIElement, to origin: CGPoint, using access: NotchNativeNotificationAccess) {
        AXUIElementSetMessagingTimeout(window, 0.1)
        guard let frame = read(window).frame, NotchVolumeBannerSupport.isOffScreen(frame, screens: screens()) else { return }
        _ = access.move(window, to: origin)
    }

    private static func screens() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    /// One round trip for everything the guard needs. A value the window
    /// cannot give comes back as an error in its place and reads as nil. The
    /// frame is in global coordinates with the origin at the top left, like
    /// the display bounds.
    private static func read(_ element: AXUIElement) -> (identifier: String?, role: String?, frame: CGRect?) {
        let names = [kAXIdentifierAttribute, kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute] as CFArray
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0),
                                                     &result) == .success,
              let values = result as? [CFTypeRef], values.count == 4 else { return (nil, nil, nil) }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        let placed = CFGetTypeID(values[2]) == AXValueGetTypeID() && CFGetTypeID(values[3]) == AXValueGetTypeID()
            && AXValueGetValue(unsafeBitCast(values[2], to: AXValue.self), .cgPoint, &origin)
            && AXValueGetValue(unsafeBitCast(values[3], to: AXValue.self), .cgSize, &extent)
        return (values[0] as? String, values[1] as? String, placed ? CGRect(origin: origin, size: extent) : nil)
    }
}
