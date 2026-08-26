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
/// The check is deliberately cheap when the keyboard is not running, which is
/// the overwhelmingly common case: the pid is cached and kept current from
/// workspace notifications, so callers on an event tap pay one lock and a nil
/// test rather than a window enumeration.
enum AssistiveKeyboard {

    static let bundleID = "com.apple.inputmethod.AssistiveControl"

    private static let lock = NSLock()
    private static var cachedPID: pid_t?
    private static var lastLookup: TimeInterval = -.greatestFiniteMagnitude
    private static var lookupInFlight = false

    /// Floor between two resolutions when the keyboard is not running, so a
    /// machine that never opens it does not pay a lookup per click.
    private static let minLookupInterval: TimeInterval = 2

    /// Seeds the cache and installs the observers. Runs once, on first use.
    private static let bootstrap: Void = {
        scheduleLookup(force: true)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      app.bundleIdentifier == bundleID
                else { return }
                scheduleLookup(force: true)
            }
        }
    }()

    /// The keyboard's pid, or nil when it is not running.
    ///
    /// Deliberately does not trust the workspace notifications on their own.
    /// Assistive Control is an input method rather than an ordinary app, and it
    /// does not reliably announce launching or terminating — so a cache fed only
    /// by those notifications goes wrong in both directions and does it
    /// silently: restart the keyboard and every check compares against a dead
    /// pid, or start it after this process and the cache stays nil forever. In
    /// both cases the feature simply stops working with nothing to point at.
    ///
    /// So the cached pid is verified against the live process on each call —
    /// `kill(pid, 0)` is a bare syscall, which is affordable even on an event
    /// tap — and re-resolved off-thread whenever it turns out to be wrong.
    private static func livePID() -> pid_t? {
        _ = bootstrap
        lock.lock()
        let cached = cachedPID
        lock.unlock()

        // The hot path: still the process we know about.
        if let cached, kill(cached, 0) == 0 { return cached }

        if cached != nil {
            lock.lock()
            if cachedPID == cached { cachedPID = nil }
            lock.unlock()
        }
        // Resolving means asking NSWorkspace, which is far too slow for a tap
        // callback. Kick it off and answer "not running" for now; the next click
        // gets the corrected answer.
        scheduleLookup(force: cached != nil)
        return nil
    }

    private static func scheduleLookup(force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if lookupInFlight || (!force && now - lastLookup < minLookupInterval) {
            lock.unlock()
            return
        }
        lookupInFlight = true
        lastLookup = now
        lock.unlock()

        DispatchQueue.global(qos: .utility).async {
            let pid = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first?
                .processIdentifier
            lock.lock()
            cachedPID = pid
            lookupInFlight = false
            lock.unlock()
        }
    }

    /// Whether the Accessibility Keyboard is running. Cheap enough for an event
    /// tap: a lock and, at most, one `kill(pid, 0)`.
    static var isRunning: Bool { livePID() != nil }

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
        guard let pid = livePID() else { return false }

        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        // Front to back: the first window that could have taken the click is
        // the one that did.
        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  CGRect(x: x, y: y, width: width, height: height).contains(point)
            else { continue }
            // A fully transparent layer cannot have been clicked; the click
            // went through it to whatever is behind.
            if let alpha = window[kCGWindowAlpha as String] as? CGFloat, alpha <= 0 { continue }
            let owner = window[kCGWindowOwnerPID as String] as? pid_t
            return owner == pid
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
