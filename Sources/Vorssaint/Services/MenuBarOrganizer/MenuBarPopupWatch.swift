// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Whether a status menu or popover of `ownerPID` is on screen. Menus and
/// popovers sit at window layers of 24 and above; a normal window does not.
/// System items draw their menus from Control Center, not from the agent.
enum MenuBarPopupWatch {
    /// `NSWindow.Level.popUpMenu` is 101 and a status bar popover sits at 25;
    /// floating and normal windows stay below 24, so a click that opened a
    /// window instead of a menu is not mistaken for one.
    private static let minimumLayer = 24
    /// The status item's own window is bar high (about 33 points, more around
    /// a camera housing). Anything taller is a menu or a popover.
    private static let minimumHeight: CGFloat = 40
    private static let controlCenterPrefix = "com.apple.controlcenter"

    static func hasPopup(ownerPID: pid_t, systemItem: Bool) -> Bool {
        let owners = systemItem ? systemOwners().union([ownerPID]) : [ownerPID]
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(owner),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= minimumLayer,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return frame.height > minimumHeight
        }
    }

    /// Control Center and the menu bar agent, the processes that draw the
    /// menus of system items.
    private static func systemOwners() -> Set<pid_t> {
        Set(NSWorkspace.shared.runningApplications.lazy.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return bundleID.hasPrefix(controlCenterPrefix) || bundleID == MenuBarOrganizerPolicy.agentBundleID
        }.map(\.processIdentifier))
    }
}
