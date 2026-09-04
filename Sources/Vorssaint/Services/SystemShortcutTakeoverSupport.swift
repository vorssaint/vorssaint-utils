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

    /// Entries the user switched off in System Settings carry `enabled = false`
    /// in the preferences plist. Switching one back on because we once owned it
    /// would undo a choice made after ours, so those ids are dropped instead.
    static func idsUserDisabled(in ids: Set<Int32>, symbolicHotKeys: [String: Any]?) -> Set<Int32> {
        guard let symbolicHotKeys else { return [] }
        return ids.filter { id in
            guard let entry = symbolicHotKeys[String(id)] as? [String: Any],
                  let enabled = entry["enabled"] as? NSNumber else { return false }
            return !enabled.boolValue
        }
    }

    /// The switcher kept its own marker before the take-over was shared. Fold
    /// it into the shared one on first launch so a crash marker from an older
    /// build still restores; ids that do not fit Int32 are noise, not keys.
    static func migratedMarker(old: [Int]?, new: [Int]?) -> Set<Int32> {
        Set(((old ?? []) + (new ?? [])).compactMap { Int32(exactly: $0) })
    }
}
