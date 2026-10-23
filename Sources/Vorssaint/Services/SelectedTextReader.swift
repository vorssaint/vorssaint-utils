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
        /// True when the focused element accepts new text and lets the
        /// selection be moved, so a transform can type over the selection.
        let isEditable: Bool
        /// Where the selected text is drawn, in Accessibility coordinates
        /// (origin at the top left of the main display). Nil when the app does
        /// not give it.
        let bounds: CGRect?
        /// The frame of the focused element, in the same coordinates.
        let elementFrame: CGRect?
        /// True when the text came from a text marker range: a web page
        /// where typed letters reach the page, not the selection.
        var fromTextMarkers = false
    }

    /// Reads the selection of the focused element in the app `processID`.
    /// Blocking, so callers run it off the main thread. `details` adds the
    /// editable state and the geometry, which cost more calls. A selection
    /// with no text gets no details.
    static func read(processID: pid_t, details: Bool = false) -> Selection? {
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
        var markerRange: CFTypeRef?
        var text = copyString(focused, kAXSelectedTextAttribute)
        if text == nil, let range = copyValue(focused, "AXSelectedTextMarkerRange") {
            markerRange = range
            text = copyString(focused, "AXStringForTextMarkerRange", range)
        }
        guard let text else { return nil }
        guard details, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Selection(text: text, isEditable: false, bounds: nil, elementFrame: nil,
                             fromTextMarkers: markerRange != nil)
        }
        // Web pages that give the selected text often give its place only
        // through the marker range.
        let bounds = markerRange.flatMap { markerBounds(focused, $0) }
            ?? selectedBounds(focused)
            ?? (markerRange == nil
                ? copyValue(focused, "AXSelectedTextMarkerRange").flatMap { markerBounds(focused, $0) }
                : nil)
        // A terminal says its value can be set, but typed text goes to the
        // prompt, not over the selection. A text field also lets the selection
        // range be set; a terminal does not.
        return Selection(text: text,
                         isEditable: isSettable(focused, kAXValueAttribute)
                             && isSettable(focused, kAXSelectedTextRangeAttribute),
                         bounds: bounds,
                         elementFrame: frame(of: focused),
                         fromTextMarkers: markerRange != nil)
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

    private static func selectedBounds(_ element: AXUIElement) -> CGRect? {
        guard let range = copyValue(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(range) == AXValueGetTypeID() else { return nil }
        return rect(copyValue(element, kAXBoundsForRangeParameterizedAttribute, range))
    }

    private static func markerBounds(_ element: AXUIElement, _ range: CFTypeRef) -> CGRect? {
        rect(copyValue(element, "AXBoundsForTextMarkerRange", range))
    }

    private static func rect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = copyValue(element, kAXPositionAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              let extent = copyValue(element, kAXSizeAttribute),
              CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(extent as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }

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
