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
                      let applications = NSWorkspace.shared.runningApplications
                      let identities = applications.compactMap { app -> (name: String, bundleIdentifier: String)? in
                          guard let name = app.localizedName, let identifier = app.bundleIdentifier else { return nil }
                          return (name, identifier)
                      }
                      guard let identifier = NotchNotificationSupport.sourceBundleIdentifier(for: labels, applications: identities)
                      else { return nil }
                      return applications.first(where: { $0.bundleIdentifier == identifier })?.localizedName
                  }, allowsNativeClose: { NotchNotificationSupport.dismissesNative() }, nativeCloseTitle: closeTitle)
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
