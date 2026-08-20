// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// One text selection read from whatever app is in front: the text itself
/// (empty when there is a focused, editable field but nothing selected in
/// it — still worth a Paste-only bar), its screen rectangle (to anchor the
/// action bar), whether the element holding it accepts text edits (gates
/// transform actions), and the focused element's own on-screen frame —
/// distinct from `boundsInScreen`, which needs an actual selected range and
/// so is usually nil for an empty selection; `elementFrame` still lets the
/// staleness check in `SelectionActionsService` tell a genuinely-focused
/// empty field apart from one that's stale (e.g. still reported as focused
/// after switching browser tabs, but far from the click that switched them).
struct SelectionSnapshot {
    let text: String
    let boundsInScreen: CGRect?
    let isEditable: Bool
    let elementFrame: CGRect?
}

/// Reads the selected text of the frontmost app through Accessibility, the
/// same approach `CommandBarSelectionReader` uses, extended with the
/// selection's on-screen rectangle so a floating bar can anchor to it, and
/// with a `ShadowCopySelectionReader` fallback for apps that don't answer
/// the Accessibility selected-text query.
enum SelectionReader {
    /// A selection longer than this is a document, not a phrase; the bar's
    /// transforms would be slower than doing it by hand.
    static let maximumLength = 20_000

    /// Runs off the main thread (the caller dispatches), completing on the
    /// main queue. Nil when nothing is selected or the app does not tell
    /// Accessibility what is selected — including our own app: the
    /// Scratchpad and other text views inside Vorssaint answer the same
    /// `kAXSelectedTextAttribute` query as anywhere else, and most of the
    /// app's own chrome (buttons, toggles) simply has no selected text to
    /// report, so this needs no exception for "front app is us."
    ///
    /// - Parameter pid: the process to read from, when the caller already
    ///   knows it for certain (a local-monitor mouse event, always our own
    ///   process). Nil falls back to `focusedApplication()`, for the
    ///   keyboard shortcut, which has no click to attribute to a process.
    static func read(pid: pid_t? = nil, completion: @escaping (SelectionSnapshot?) -> Void) {
        guard AXIsProcessTrusted() else { completion(nil); return }
        guard let targetPID = pid ?? focusedApplication()?.processIdentifier else { completion(nil); return }
        // See CommandBarSelectionReader: the timeout is set on the app
        // element, never the system-wide one, so a hung app cannot poison
        // every later Accessibility call for the rest of the session.
        let app = AXUIElementCreateApplication(targetPID)
        AXUIElementSetMessagingTimeout(app, 0.35)
        guard let focused = copyElement(app, kAXFocusedUIElementAttribute) else { completion(nil); return }
        let isEditable = isSettable(focused, kAXValueAttribute as String)
        let bounds = boundsInScreen(for: focused)
        let elementFrame = elementFrameInScreen(for: focused)

        if let text = copyString(focused, kAXSelectedTextAttribute) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.count <= maximumLength {
                completion(SelectionSnapshot(text: trimmed, boundsInScreen: bounds,
                                             isEditable: isEditable, elementFrame: elementFrame))
                return
            }
            // Accessibility *answered* — distinct from not answering at
            // all. Trust an explicit empty answer directly instead of
            // trying a real ⌘C: on a page with no selection, the ⌘C could
            // still find unrelated text elsewhere in the document, and in
            // a plain empty text field it would just beep (nothing to
            // copy) — except for a small set of apps verified to answer
            // this query inconsistently depending on *how* the selection
            // was made (VS Code reports a double-click word-select
            // correctly but an empty string for a drag-selected range,
            // even though the drag genuinely selected something), where
            // trusting "empty" outright would silently break dragging.
            if !hasUnreliableSelectionReporting(pid: targetPID) {
                guard isEditable else { completion(nil); return }
                completion(SelectionSnapshot(text: "", boundsInScreen: bounds,
                                             isEditable: true, elementFrame: elementFrame))
                return
            }
        }
        // Accessibility has no usable selected-text string here — some apps
        // (VS Code's editor, Mail's rich-text compose) never populate this
        // attribute even though a real Copy works fine. Falling back to a
        // real ⌘C mirrors PopClip's own documented "Simulated Keystroke"
        // strategy, an alternative to reading purely through Accessibility —
        // but only where the focused element actually looks like it holds
        // text: dragging a window by its title bar, or an empty area of
        // Finder's icon/list view, focuses something else entirely (window
        // chrome, an outline/table row), and sending a real ⌘C there does
        // nothing but trigger the system's disabled-menu-item beep.
        guard isEditable || looksLikeTextRole(focused) else { completion(nil); return }
        ShadowCopySelectionReader.read { copied in
            if let copied {
                let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.count <= maximumLength {
                    completion(SelectionSnapshot(text: trimmed, boundsInScreen: bounds,
                                                 isEditable: isEditable, elementFrame: elementFrame))
                    return
                }
            }
            // Nothing is actually selected anywhere. Still worth a
            // Paste-only bar if the caret is sitting in an editable field.
            guard isEditable else { completion(nil); return }
            completion(SelectionSnapshot(text: "", boundsInScreen: bounds,
                                         isEditable: true, elementFrame: elementFrame))
        }
    }

    /// Stable, decade-old AX role strings (not the exotic ones) for elements
    /// that plausibly hold readable text — as opposed to a list, outline,
    /// window, or other chrome that a real ⌘C would just beep at.
    private static let textRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXStaticText", "AXComboBox", "AXWebArea",
    ]

    private static func looksLikeTextRole(_ element: AXUIElement) -> Bool {
        guard let role = copyString(element, kAXRoleAttribute) else { return false }
        return textRoles.contains(role)
    }

    /// Bundle IDs verified (not guessed) to answer `kAXSelectedTextAttribute`
    /// inconsistently depending on how the selection was made — see the
    /// comment where this is checked.
    private static let axSelectionUnreliableBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
    ]

    private static func hasUnreliableSelectionReporting(pid: pid_t) -> Bool {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return axSelectionUnreliableBundleIDs.contains(bundleID)
    }

    // MARK: - Focused app

    /// The app Accessibility says currently holds keyboard focus — not
    /// necessarily `NSWorkspace.frontmostApplication`, which a
    /// `.nonactivatingPanel` (like the Scratchpad) can take key status
    /// away from without ever becoming. Falls back to the workspace's
    /// frontmost app if the system-wide read ever fails.
    static func focusedApplication() -> NSRunningApplication? {
        if let pid = focusedProcessIdentifier(), let app = NSRunningApplication(processIdentifier: pid) {
            return app
        }
        return NSWorkspace.shared.frontmostApplication
    }

    private static func focusedProcessIdentifier() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value)
                == .success,
              let raw = value, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid((raw as! AXUIElement), &pid) == .success else { return nil }
        return pid
    }

    // MARK: - Bounds

    private static func boundsInScreen(for element: AXUIElement) -> CGRect? {
        guard let axRange = copyAXValue(element, kAXSelectedTextRangeAttribute),
              AXValueGetType(axRange) == .cfRange
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axRange, .cfRange, &range) else { return nil }

        var boundsParam: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &boundsParam)
        guard status == .success,
              let boundsValue = boundsParam, CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }
        let axBounds = boundsValue as! AXValue
        guard AXValueGetType(axBounds) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axBounds, .cgRect, &rect), rect.width > 0 || rect.height > 0 else {
            return nil
        }
        return appKitRect(fromAX: rect)
    }

    /// The focused element's own on-screen frame — its position and size,
    /// not a selected range within it, so this works even with nothing (or
    /// only a collapsed caret) selected. Used only for the staleness check;
    /// visual anchoring still prefers `boundsInScreen` when there's a real
    /// selection, and falls back to the click location otherwise.
    private static func elementFrameInScreen(for element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAXValue(element, kAXPositionAttribute),
              AXValueGetType(positionValue) == .cgPoint,
              let sizeValue = copyAXValue(element, kAXSizeAttribute),
              AXValueGetType(sizeValue) == .cgSize
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return appKitRect(fromAX: CGRect(origin: point, size: size))
    }

    /// Accessibility bounds are given top-left-origin, anchored at the
    /// screen holding the menu bar — the same flipped system window geometry
    /// uses elsewhere (`WindowLayoutService.appKitFrame(fromAX:)`). AppKit's
    /// `NSScreen` math needs the bottom-left-origin equivalent.
    private static func appKitRect(fromAX rect: CGRect) -> CGRect {
        let menuBarScreen = NSScreen.screens.first {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        }
        let topY = (menuBarScreen ?? NSScreen.main ?? NSScreen.screens.first)?.frame.maxY ?? 0
        return CGRect(x: rect.origin.x,
                      y: topY - rect.origin.y - rect.height,
                      width: rect.width,
                      height: rect.height)
    }

    // MARK: - Accessibility reading

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copyValue(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let raw = copyValue(element, attribute),
              CFGetTypeID(raw) == CFStringGetTypeID() else { return nil }
        return raw as? String
    }

    private static func copyAXValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let raw = copyValue(element, attribute),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        return (raw as! AXValue)
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }
}
