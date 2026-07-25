// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

extension NSScreen {
    /// The screen under the mouse pointer, where summoned panels (switcher,
    /// shelf, cut HUD) belong. Falls back to the main screen. Returns nil only
    /// in the rare window where the app has no active display at all, e.g. a
    /// headless Mac at login, an external-only rig whose display is asleep or
    /// waking, or a display reconfiguration in flight during launch. Callers
    /// must treat nil as "there is nothing to show onto" and skip, never force
    /// a screen: reading `screens[0]` in that state traps the whole app.
    static var withMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? main
    }

    /// Whether this display is still plugged in. Compared by display id rather
    /// than by object identity: AppKit is free to hand out fresh NSScreen
    /// objects after a display reconfiguration, and this app sees those in
    /// bursts, so identity would report a display gone while it is still there.
    var isStillAttached: Bool {
        let id = displayID
        guard id != 0 else { return false }
        return NSScreen.screens.contains { $0.displayID == id }
    }

    /// The display that owns the menu bar, which is the one at the coordinate
    /// origin. Anything anchored to the bar belongs here, and `main` is the
    /// wrong answer for it: `main` follows the key window, so on a second
    /// display it points at a screen with no menu bar on it.
    static var withMenuBar: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }

    /// A visible frame to lay a summoned panel out against, guaranteed non-nil.
    /// Prefers the screen under the pointer, then any attached screen, then a
    /// sane default, so window-placement math can never trap when there is
    /// momentarily no display. Nothing renders in the no-display case anyway,
    /// so the exact fallback rectangle is immaterial.
    static var pointerVisibleFrame: CGRect {
        (withMouse ?? screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
