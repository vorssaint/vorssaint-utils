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

    /// Where a focused text is selected, with that text's length, both in the
    /// UTF-16 units Accessibility counts in.
    struct FocusedTextSelection {
        let range: NSRange
        let textLength: Int
        fileprivate let element: AXUIElement
        /// The uptime the questions that found the selection had to end by.
        fileprivate let deadline: TimeInterval

        /// The same element's text within `range`, asked as that range's
        /// string, else cut from the whole value for a field that only gives
        /// that when it is short. Nil when it answers neither, when it is too
        /// long to copy whole, or when the time the selection was asked with is
        /// spent. Asked the same way, never a role.
        func text(in range: NSRange) -> String? {
            var cfRange = CFRange(location: range.location, length: range.length)
            if let parameter = AXValueCreate(.cfRange, &cfRange),
               limit(element, to: deadline),
               let text = copyString(element, kAXStringForRangeParameterizedAttribute, parameter) {
                return text
            }
            // The whole value is copied only for a short field, such as an
            // address bar, never for a long document or a scrollback. NSString
            // counts in UTF-16 units, like the range.
            guard textLength <= wholeValueLimit,
                  limit(element, to: deadline),
                  let value = copyString(element, kAXValueAttribute).map({ $0 as NSString }),
                  range.location >= 0, NSMaxRange(range) <= value.length else { return nil }
            return value.substring(with: range)
        }
    }

    /// The longest text, in UTF-16 units, whose whole value is read when its
    /// range cannot be asked for directly.
    static let wholeValueLimit = 4096

    /// The selection of the focused text in the app `processID`. Nil when
    /// nothing is selected or the app does not say, and for this process: it
    /// answers from its main thread, so asking it from there would only wait
    /// out the timeout. Blocking, for at most `timeout` in all: each question,
    /// the selection's `text(in:)` included, gets what the ones before it
    /// left, so a slow app that answers each one just in time cannot stack
    /// them up.
    ///
    /// Only the selection, its length and its text are asked, never a role: a
    /// role query switches a Chromium app's renderers into full accessibility
    /// mode for the rest of its life (issue #953), and this is asked of
    /// whatever app is in front.
    static func focusedTextSelection(processID: pid_t, timeout: TimeInterval) -> FocusedTextSelection? {
        guard AXIsProcessTrusted(), processID != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let app = AXUIElementCreateApplication(processID)
        var range = CFRange()
        guard limit(app, to: deadline),
              let focused = copyElement(app, kAXFocusedUIElementAttribute),
              !CFEqual(focused, app),
              limit(focused, to: deadline),
              let rawRange = copyValue(focused, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rawRange) == AXValueGetTypeID(),
              AXValueGetValue(rawRange as! AXValue, .cfRange, &range),
              range.length > 0,
              limit(focused, to: deadline),
              let length = copyValue(focused, kAXNumberOfCharactersAttribute) as? Int
        else { return nil }
        return FocusedTextSelection(range: NSRange(location: range.location, length: range.length),
                                    textLength: length,
                                    element: focused,
                                    deadline: deadline)
    }

    /// Gives `element` what is left until `deadline` to answer, set on each
    /// element asked since a timeout bounds only the element it is set on.
    /// False once nothing is left: a zero timeout means the system default,
    /// which is seconds.
    private static func limit(_ element: AXUIElement, to deadline: TimeInterval) -> Bool {
        let left = deadline - ProcessInfo.processInfo.systemUptime
        guard left > 0 else { return false }
        AXUIElementSetMessagingTimeout(element, Float(left))
        return true
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
