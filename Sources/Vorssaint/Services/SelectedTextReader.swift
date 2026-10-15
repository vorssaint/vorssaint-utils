// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// The text another app has selected, read through Accessibility.
///
/// Only Accessibility is asked. Nothing is copied to find the selection, so
/// text that is only highlighted never reaches the clipboard or its history.
/// An app that does not tell Accessibility what is selected gives no answer.
enum SelectedTextReader {
    struct Selection {
        /// The text as the app gives it, not trimmed.
        let text: String
        /// True when the text came from a text marker range: a web page
        /// where typed letters reach the page, not the selection.
        var fromTextMarkers = false
    }

    /// Reads the selection of the focused element in the app `processID`.
    /// Blocking, so callers run it off the main thread.
    static func read(processID: pid_t) -> Selection? {
        guard AXIsProcessTrusted() else { return nil }
        // Asked of the app, not of the system-wide element: a timeout set on
        // the system-wide element is the DEFAULT FOR THE WHOLE PROCESS, and
        // every other Accessibility call in the app would inherit this short
        // leash for the rest of the session. The app in front is the one
        // holding the selection anyway.
        let app = AXUIElementCreateApplication(processID)
        // A hung app must not hold the caller.
        AXUIElementSetMessagingTimeout(app, 0.35)
        guard let focused = copyElement(app, kAXFocusedUIElementAttribute) else { return nil }
        // The timeout applies only to the element that gets it. Give it to
        // the focused element too, which gets all the calls below.
        AXUIElementSetMessagingTimeout(focused, 0.35)
        // Some browsers give the selection on a page only as a text marker
        // range, not as selected text.
        if let text = copyString(focused, kAXSelectedTextAttribute) {
            return Selection(text: text)
        }
        guard let range = copyValue(focused, "AXSelectedTextMarkerRange"),
              let text = copyString(focused, "AXStringForTextMarkerRange", range) else { return nil }
        return Selection(text: text, fromTextMarkers: true)
    }

    // MARK: - Accessibility reading

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copyValue(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String,
                                   _ parameter: CFTypeRef? = nil) -> String? {
        guard let raw = copyValue(element, attribute, parameter),
              CFGetTypeID(raw) == CFStringGetTypeID() else { return nil }
        return raw as? String
    }

    /// With a parameter, asks the parameterized attribute of that name.
    private static func copyValue(_ element: AXUIElement, _ attribute: String,
                                  _ parameter: CFTypeRef? = nil) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = parameter.map {
            AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, $0, &value)
        } ?? AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }
}
