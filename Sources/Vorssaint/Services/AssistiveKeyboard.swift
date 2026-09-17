// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// macOS's on-screen Accessibility Keyboard.
///
/// Someone who cannot use a physical keyboard presses every key on that panel
/// with the mouse, so a mouse-down accompanies every character they type.
/// Anything that reads a click as "the user did something other than type" —
/// dismissing a panel, clearing a typed-so-far buffer — has to make an
/// exception for clicks that landed on it, or the feature cannot be used from
/// that keyboard at all.
///
/// Resolve the current process before judging the click. A cached absence or
/// an asynchronous first answer would dismiss the panel before its key arrives.
enum AssistiveKeyboard {
    static let bundleID = "com.apple.inputmethod.AssistiveControl"

    // NSRunningApplication is thread-safe; this asks for the current matching
    // applications without waiting for our own background work or a launch
    // notification (which background input methods do not emit).
    private static func currentPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.processIdentifier
    }

    /// Also used once at startup to pay the first AppKit lookup before input.
    static var isRunning: Bool { currentPID() != nil }

    private static func onScreenWindows() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]]
    }

    /// True when `point` lands on the Accessibility Keyboard's own panel, i.e.
    /// the click pressed a key rather than pointing at something else.
    ///
    /// `point` is in CoreGraphics screen coordinates, origin top-left — what
    /// `CGEvent.location` returns. For `NSEvent.mouseLocation` use
    /// ``ownsCocoaPoint(_:)``, which flips first.
    ///
    /// Answers "is the keyboard the window that was clicked", not "is it
    /// somewhere under the point": the topmost clickable window containing the
    /// point wins, so a window stacked over the panel correctly reads as a
    /// click on that window. Fully transparent layers are skipped, since a
    /// click passes straight through them.
    static func ownsPoint(_ point: CGPoint) -> Bool {
        ownsPoint(point, keyboardPID: currentPID, windows: onScreenWindows)
    }

    // Keep the system reads at the decision point. Supplying them separately
    // lets the same path exercise first use and process changes without UI.
    static func ownsPoint(_ point: CGPoint,
                          keyboardPID: () -> pid_t?,
                          windows: () -> [[String: Any]]?) -> Bool {
        guard let pid = keyboardPID(), let windows = windows() else { return false }

        // Front to back: the first window that could have taken the click is
        // the one that did.
        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  CGRect(x: x, y: y, width: width, height: height).contains(point)
            else { continue }
            // A fully transparent layer cannot have been clicked; the click
            // went through it to whatever is behind. Worth keeping for foreign
            // windows, but it is not enough on its own — see below.
            if let alpha = window[kCGWindowAlpha as String] as? CGFloat, alpha <= 0 { continue }
            let owner = window[kCGWindowOwnerPID as String] as? pid_t
            if owner == pid { return true }
            // Our own windows never block the answer. Several are click-through
            // (`ignoresMouseEvents`), and `CGWindowListCopyWindowInfo` cannot
            // report that; they also leave `alphaValue` alone, so they arrive
            // here looking like ordinary opaque windows. One of them is
            // full-screen at shielding level for as long as Extra Brightness is
            // boosting, which would put it above every point of the display and
            // make this answer false everywhere — every call site silently back
            // to the bug it fixes.
            //
            // The trade: one of our windows that *does* take clicks, overlapping
            // the keyboard, now reads as a keystroke. That is a false positive —
            // a buffer that survives, a panel that stays open — against a false
            // negative that disables the feature outright. The rarer and milder
            // of the two.
            if owner == ProcessInfo.processInfo.processIdentifier { continue }
            return false
        }
        return false
    }

    /// True when `point` lands on the Accessibility Keyboard's own panel.
    ///
    /// `point` is in Cocoa screen coordinates, origin bottom-left — what
    /// `NSEvent.mouseLocation` returns. The flip is against the primary
    /// screen's height, which is the origin of the CoreGraphics space, so this
    /// stays correct on a multi-display setup where no single screen height
    /// would do.
    static func ownsCocoaPoint(_ point: NSPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        return ownsPoint(CGPoint(x: point.x, y: primary.frame.maxY - point.y))
    }
}
