// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SystemShortcutTransition: Equatable {
    let suppress: Set<Int32>
    let restore: Set<Int32>
}

/// Pure rules behind `SystemShortcutTakeover`, kept apart so the unit tests
/// can exercise them without a WindowServer.
enum SystemShortcutTakeoverSupport {
    static func transition(from current: Set<Int32>, to desired: Set<Int32>,
                           currentlyEnabled: Set<Int32>) -> SystemShortcutTransition {
        SystemShortcutTransition(suppress: desired.intersection(currentlyEnabled),
                                 restore: current.subtracting(desired))
    }

    /// The switcher kept its own marker before the take-over was shared. Fold
    /// it into the shared one on first launch so a crash marker from an older
    /// build still restores; ids that do not fit Int32 are noise, not keys.
    static func migratedMarker(old: [Int]?, new: [Int]?) -> Set<Int32> {
        Set(((old ?? []) + (new ?? [])).compactMap { Int32(exactly: $0) })
    }
}
