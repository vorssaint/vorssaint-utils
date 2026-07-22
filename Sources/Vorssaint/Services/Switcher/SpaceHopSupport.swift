// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Pure decisions behind showing and reaching windows that live on a Space the
/// user is not currently looking at (issue #339). Kept free of AppKit and
/// window-server calls so the unit tests can exercise every branch.
enum SpaceHopSupport {
    /// The largest number of "move a space" steps a hop will replay. Spaces
    /// beyond that are treated as unreachable rather than flooding the session
    /// with synthetic shortcuts.
    static let maximumArrowSteps = 16

    /// A window the window server places on at least one Space, none of which
    /// is visible right now, is a real window parked elsewhere. A window on no
    /// Space at all is a leftover surface (the ghosts the Accessibility veto
    /// exists for), and a window on a visible Space needs no special handling.
    static func isParkedOnHiddenSpace(windowSpaces: [UInt64], visibleSpaces: Set<UInt64>) -> Bool {
        guard !windowSpaces.isEmpty, !visibleSpaces.isEmpty else { return false }
        return !windowSpaces.contains { visibleSpaces.contains($0) }
    }

    /// How many "move a space" presses take the user from the visible Space to
    /// `target`. Positive means move right, negative means move left. Returns
    /// nil when the target is already visible, cannot be found, or sits
    /// farther than `maximumArrowSteps` away. With more than one display it
    /// always returns nil: the replayed shortcut moves whichever display has
    /// keyboard focus, which is not necessarily the display owning the target,
    /// so a hop there could shuffle the wrong display's desktops.
    static func arrowSteps(orderedSpacesPerDisplay: [[UInt64]],
                           visibleSpaces: Set<UInt64>,
                           target: UInt64) -> Int? {
        guard orderedSpacesPerDisplay.count == 1, let row = orderedSpacesPerDisplay.first else { return nil }
        guard !visibleSpaces.contains(target) else { return nil }
        guard let targetIndex = row.firstIndex(of: target),
              let currentIndex = row.firstIndex(where: { visibleSpaces.contains($0) })
        else { return nil }
        let steps = targetIndex - currentIndex
        guard steps != 0, abs(steps) <= maximumArrowSteps else { return nil }
        return steps
    }

    /// Translates the modifier mask reported for a system Spaces shortcut into
    /// event flags for replaying it. The mask uses the classic modifier bit
    /// layout; the function-key bit matters, because the system only honors a
    /// replayed Spaces shortcut whose modifiers match the registered ones
    /// exactly (arrow keys carry the function bit on real presses).
    static func eventFlags(fromCarbonModifiers modifiers: UInt32) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers & 0x20000 != 0 { flags.insert(.maskShift) }
        if modifiers & 0x40000 != 0 { flags.insert(.maskControl) }
        if modifiers & 0x80000 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 0x100000 != 0 { flags.insert(.maskCommand) }
        if modifiers & 0x800000 != 0 { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
