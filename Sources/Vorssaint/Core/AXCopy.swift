// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices

/// Shared low-level Accessibility attribute reads. `CommandBarSelectionReader`,
/// `CommandBarMenus`, `SelectionReader` and `BrowserURLReader` each walk AX
/// elements on a timed budget and previously carried their own copy of the
/// same three functions.
enum AXCopy {
    /// Set on the target app element, never the system-wide one: a timeout
    /// there is the default for the whole process, and every other
    /// Accessibility call in the app would inherit it for the rest of the
    /// session. A hung app must not hold up whichever of these is waiting on it.
    static let messagingTimeout: Float = 0.35

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return (raw as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == CFStringGetTypeID()
        else { return nil }
        return raw as? String
    }
}
