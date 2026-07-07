// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DockClickAction: Equatable {
    case minimize
    case restore
    case cycleWindows
    case passThrough
}

/// What a click should do given the app's last handled click.
enum DockClickRepeatDecision: Equatable {
    /// Inside the double-click gap: do nothing, or an accidental double-click
    /// would toggle twice and look like the click bounced.
    case swallow
    /// The opposite of the last action, taken from our own record: while the
    /// animation settles the AX minimized state is ambiguous and deriving the
    /// action from it re-fires the SAME action instead of toggling back.
    case toggle(DockClickAction)
    /// No recent action: derive from the app's actual window state.
    case deriveFromState
}

enum DockClickSupport {
    /// Clicks closer together than this count as one intent.
    static let repeatClickGap: TimeInterval = 0.25

    /// After a handled click, how long a follow-up click keeps toggling from
    /// our own record instead of trusting the still-settling AX state.
    static let toggleIntentWindow: TimeInterval = 1.5

    /// Delay before sweeping up windows the Minimize All shortcut left behind
    /// (apps without the standard binding). Long enough for the batched
    /// animation to finish so the sweep sees the settled state.
    static let minimizeSweepDelay: TimeInterval = 0.9

    /// Delay before re-asserting a restore on windows whose minimize was still
    /// in flight when the restore clicked in.
    static let restoreSweepDelay: TimeInterval = 0.6

    static func repeatDecision(lastAction: DockClickAction?,
                               elapsed: TimeInterval?) -> DockClickRepeatDecision {
        guard let lastAction, let elapsed, elapsed < toggleIntentWindow else { return .deriveFromState }
        if elapsed < repeatClickGap { return .swallow }
        switch lastAction {
        case .minimize: return .toggle(.restore)
        case .restore: return .toggle(.minimize)
        case .cycleWindows: return .deriveFromState
        case .passThrough: return .deriveFromState
        }
    }

    /// Taskbar-style Dock click. Minimize when the clicked app is frontmost
    /// with windows on screen; restore when everything it has is minimized
    /// (the Dock's native click would activate without unminimizing — Finder
    /// would even open a brand-new window). Modifier clicks always keep the
    /// Dock's native behaviors (⌘ reveals in Finder, ⌥ hides the previous
    /// app, ⌃ opens the menu). Fullscreen windows can't minimize, and restoring
    /// siblings from inside a fullscreen Space would yank the user to another
    /// Space, so any fullscreen window means hands off.
    static func action(appIsFrontmost: Bool,
                       hasUnminimizedWindows: Bool,
                       hasMinimizedWindows: Bool,
                       hasFullscreenWindows: Bool,
                       hasModifiers: Bool,
                       minimizeEnabled: Bool = true,
                       cycleWindowsEnabled: Bool = false,
                       unminimizedWindowCount: Int = 0) -> DockClickAction {
        guard !hasModifiers, !hasFullscreenWindows else { return .passThrough }
        if cycleWindowsEnabled, appIsFrontmost, unminimizedWindowCount > 1 { return .cycleWindows }
        if minimizeEnabled, appIsFrontmost, hasUnminimizedWindows { return .minimize }
        if minimizeEnabled, !hasUnminimizedWindows, hasMinimizedWindows { return .restore }
        return .passThrough
    }

    /// Cheap geometric gate that runs before any Accessibility hit-test, in the
    /// event's top-left-origin coordinates. When the Dock reserves screen space
    /// (`visibleFrame` is inset on the bottom, left or right), the click must
    /// land inside that reserved strip — this keeps clicks on windows or panels
    /// hovering just above the Dock out, which matters because the AX item
    /// matching that follows can only trust the Dock's long axis. Without a
    /// reserved strip (auto-hide, or the Dock lives on another display) it
    /// falls back to a generous edge band.
    static func dockStripContains(_ point: CGPoint,
                                  screenFrame: CGRect,
                                  visibleFrame: CGRect,
                                  fallbackMargin: CGFloat = 120) -> Bool {
        // Small negative inset: the pointer clamps to the screen, but event
        // coordinates on the very edge can land fractionally outside.
        guard screenFrame.insetBy(dx: -8, dy: -8).contains(point) else { return false }

        let bottomGap = screenFrame.maxY - visibleFrame.maxY
        let leftGap = visibleFrame.minX - screenFrame.minX
        let rightGap = screenFrame.maxX - visibleFrame.maxX
        let reserved: CGFloat = 8

        if bottomGap > reserved || leftGap > reserved || rightGap > reserved {
            if bottomGap > reserved, point.y >= visibleFrame.maxY - 2 { return true }
            if leftGap > reserved, point.x <= visibleFrame.minX + 2 { return true }
            if rightGap > reserved, point.x >= visibleFrame.maxX - 2 { return true }
            return false
        }

        return point.y >= screenFrame.maxY - fallbackMargin
            || point.x <= screenFrame.minX + fallbackMargin
            || point.x >= screenFrame.maxX - fallbackMargin
    }
}
