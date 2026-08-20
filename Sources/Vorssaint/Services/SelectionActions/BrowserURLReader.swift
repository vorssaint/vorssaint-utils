// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Best-effort read of the frontmost browser's current page, so Selection
/// Actions can skip websites the person excluded. Browsers differ in how
/// (or whether) they expose this over Accessibility, so a miss here just
/// means the website exclusion list quietly does nothing for that browser
/// rather than crashing or misreading the page.
enum BrowserURLReader {
    /// Bundle identifiers verified against the actual installed apps, not
    /// guessed.
    private static let knownBrowserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "org.mozilla.firefox",
    ]

    static func currentHost(for app: NSRunningApplication) -> String? {
        guard let bundleID = app.bundleIdentifier, knownBrowserBundleIDs.contains(bundleID) else {
            return nil
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.35)
        guard let window = copyElement(element, kAXFocusedWindowAttribute) else { return nil }
        if let url = copyURL(window, kAXDocumentAttribute) { return url.host }
        if let url = copyURL(window, kAXURLAttribute) { return url.host }
        return nil
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copyValue(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return (raw as! AXUIElement)
    }

    private static func copyURL(_ element: AXUIElement, _ attribute: String) -> URL? {
        guard let raw = copyValue(element, attribute) else { return nil }
        if let url = raw as? URL { return url }
        if let string = raw as? String { return URL(string: string) }
        return nil
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }
}
