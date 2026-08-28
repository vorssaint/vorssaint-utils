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

    /// What a hop does right after activating the app.
    enum FirstStage: Equatable {
        /// Activating the app travels on its own, so wait for it to land.
        case waitForActivationTravel
        /// Activation cannot travel; the move has to be asked for right away.
        case moveASpace
    }

    /// macOS follows an activation to another Space only when the app has no
    /// window where the user is already looking. With one there, activating
    /// just raises that window, so waiting for a travel that cannot happen is
    /// pure delay and the hop asks for the move immediately (issue #422).
    static func firstStage(appHasWindowOnVisibleSpace: Bool) -> FirstStage {
        appHasWindowOnVisibleSpace ? .moveASpace : .waitForActivationTravel
    }

    /// A window the window server places on at least one Space, none of which
    /// is visible right now, is a real window parked elsewhere. A window on no
    /// Space at all is a leftover surface (the ghosts the Accessibility veto
    /// exists for), and a window on a visible Space needs no special handling.
    static func isParkedOnHiddenSpace(windowSpaces: [UInt64], visibleSpaces: Set<UInt64>) -> Bool {
        guard !windowSpaces.isEmpty, !visibleSpaces.isEmpty else { return false }
        return !windowSpaces.contains { visibleSpaces.contains($0) }
    }

    /// Whether at least one Space assigned to a window is a native fullscreen
    /// Space. This is stronger than guessing from the window frame: a tiled or
    /// zoomed window can fill the same rectangle without owning its own Space.
    static func isOnFullscreenSpace(windowSpaces: [UInt64],
                                    fullscreenSpaces: Set<UInt64>) -> Bool {
        windowSpaces.contains { fullscreenSpaces.contains($0) }
    }

    /// The window server marks surfaces that must stay out of app window
    /// cycling. This remains meaningful when Accessibility cannot inspect a
    /// window because it lives on another Space.
    static func isExcludedFromWindowCycle(windowTagsLow: UInt32) -> Bool {
        let ignoresCycleTag: UInt32 = 1 << 18
        return windowTagsLow & ignoresCycleTag != 0
    }

    /// How many "move a space" presses take the user from the visible Space to
    /// `target`. Positive means move right, negative means move left. Returns
    /// nil when the target is already visible, cannot be found, or sits
    /// farther than `maximumArrowSteps` away.
    static func arrowSteps(orderedSpacesPerDisplay: [[UInt64]],
                           visibleSpaces: Set<UInt64>,
                           target: UInt64) -> Int? {
        guard let row = orderedSpacesPerDisplay.first(where: { $0.contains(target) }) else { return nil }
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
