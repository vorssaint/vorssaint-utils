// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
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
        AXUIElementSetMessagingTimeout(element, AXCopy.messagingTimeout)
        guard let window = AXCopy.element(element, kAXFocusedWindowAttribute) else { return nil }
        if let url = copyURL(window, kAXDocumentAttribute) { return url.host }
        if let url = copyURL(window, kAXURLAttribute) { return url.host }
        return nil
    }

    private static func copyURL(_ element: AXUIElement, _ attribute: String) -> URL? {
        guard let raw = AXCopy.value(element, attribute) else { return nil }
        if let url = raw as? URL { return url }
        if let string = raw as? String { return URL(string: string) }
        return nil
    }
}
