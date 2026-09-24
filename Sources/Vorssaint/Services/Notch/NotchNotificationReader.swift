// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

typealias NotchNotificationReader = NotchNotificationReaderCore<NotchNativeNotificationAccess>

extension NotchNotificationReaderCore where Access == NotchNativeNotificationAccess {
    convenience init(pid: pid_t, cancellation: DispatchWorkItem) {
        let bundle = Bundle(path: "/System/Library/CoreServices/NotificationCenter.app")
        let closeTitle = bundle?.localizedString(forKey: "Close", value: "Close", table: "Localizable") ?? "Close"
        self.init(access: NotchNativeNotificationAccess(pid: pid),
                  allowed: { !cancellation.isCancelled && NotchNotificationSupport.isEnabled() && AXIsProcessTrusted() },
                  sourceApplicationName: { labels in
                      guard !labels.isEmpty else { return nil }
                      return NotchNotificationSources.source(for: labels)?.name
                  }, allowsNativeClose: { NotchNotificationSupport.dismissesNative() }, nativeCloseTitle: closeTitle)
    }
}

/// Resolves a notification's source among running and installed apps, so a
/// message from a closed app keeps its icon and can still open the app after
/// its native banner is gone (issue #2027). The installed list is walked on
/// the notification queue at most every few minutes; the main thread only
/// reads the last walk.
enum NotchNotificationSources {
    typealias Identity = (name: String, bundleIdentifier: String)
    private static let lock = NSLock()
    private static var installed: [Identity] = []
    private static var walkedAt: TimeInterval?
    private static let maximumAge: TimeInterval = 10 * 60

    static func refreshIfStale() {
        let now = ProcessInfo.processInfo.systemUptime
        guard lock.withLock({ walkedAt.map { now - $0 >= maximumAge } ?? true }) else { return }
        let apps = InstalledApps.installedApplications(includeSystemApplications: true)
            .compactMap { app -> Identity? in app.bundleID.map { (app.name, $0) } }
        lock.withLock { installed = apps; walkedAt = now }
    }

    static func source(for labels: [String]) -> (name: String, bundleIdentifier: String)? {
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> Identity? in
            guard let name = app.localizedName, let identifier = app.bundleIdentifier else { return nil }
            return (name, identifier)
        }
        let installed = lock.withLock { self.installed }
        guard let identifier = NotchNotificationSupport.sourceBundleIdentifier(
            for: labels, running: running, installed: installed) else { return nil }
        guard let name = (running.first { $0.bundleIdentifier == identifier }
                          ?? installed.first { $0.bundleIdentifier == identifier })?.name else { return nil }
        return (name, identifier)
    }
}

/// Thin native adapter. The core owns traversal, identity checks, budgets and
/// action order; this type only translates its operations to accessibility calls.
struct NotchNativeNotificationAccess: NotchNotificationAccess {
    typealias Element = AXUIElement
    private enum Failure: Error { case unavailable }
    private let application: AXUIElement

    init(pid: pid_t) {
        application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
    }

    func windows() throws -> [AXUIElement] {
        guard let value = try value(application, kAXWindowsAttribute) else { return [] }
        guard let elements = value as? [AXUIElement] else { throw Failure.unavailable }
        return elements
    }

    func hasFocusedWindow() throws -> Bool {
        // AXNoValue means no focused window; an unsupported attribute cannot
        // establish that the center is closed, so it fails the read instead.
        guard let value = try value(application, kAXFocusedWindowAttribute, allowsUnsupported: false) else { return false }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw Failure.unavailable }
        return true
    }

    func string(_ element: AXUIElement, _ attribute: String) throws -> String? {
        guard let value = try value(element, attribute) else { return nil }
        if attribute == "AXAttributedDescription", let text = value as? NSAttributedString { return text.string }
        guard let string = value as? String else { throw Failure.unavailable }
        return string
    }

    func children(_ element: AXUIElement) throws -> [AXUIElement] {
        guard let value = try value(element, kAXChildrenAttribute) else { return [] }
        guard let elements = value as? [AXUIElement] else { throw Failure.unavailable }
        return elements
    }

    func actions(_ element: AXUIElement) throws -> [String] {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var result: CFArray?
        let error = AXUIElementCopyActionNames(element, &result)
        if error == .notImplemented || error == .actionUnsupported { return [] }
        guard error == .success, let actions = result as? [String] else { throw Failure.unavailable }
        return actions
    }

    func press(_ element: AXUIElement) -> Bool {
        perform(kAXPressAction, on: element)
    }

    func perform(_ action: String, on element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.1)
        return AXUIElementPerformAction(element, action as CFString) == .success
    }

    func same(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool { CFEqual(lhs, rhs) }

    private func value(_ element: AXUIElement, _ attribute: String, allowsUnsupported: Bool = true) throws -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        if error == .noValue || (allowsUnsupported && error == .attributeUnsupported) { return nil }
        guard error == .success else { throw Failure.unavailable }
        return result
    }
}
