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
    /// Recovery runs before a replacement handler exists, so it must never
    /// disable a key, including an owned key the system has re-enabled.
    static func recoveryTransition(from current: Set<Int32>, keeping desired: Set<Int32>)
        -> SystemShortcutTransition {
        SystemShortcutTransition(suppress: [], restore: current.subtracting(desired))
    }

    static func transition(from current: Set<Int32>, to desired: Set<Int32>,
                           currentlyEnabled: Set<Int32>) -> SystemShortcutTransition {
        SystemShortcutTransition(suppress: desired.intersection(currentlyEnabled),
                                 restore: current.subtracting(desired))
    }

    /// One pass over a transition. The marker is written before each disable
    /// and again after each change, so a crash between the two still leaves a
    /// record of the key. A disable the WindowServer refuses takes its id back
    /// out of the marker; an enable it refuses keeps its id in, so the next
    /// pass or the next launch retries instead of dropping the key with
    /// nothing left to restore it.
    static func apply(_ transition: SystemShortcutTransition, owned: Set<Int32>,
                      setEnabled: (Int32, Bool) -> Bool,
                      persist: (Set<Int32>) -> Void) -> Set<Int32> {
        var next = owned
        for id in transition.suppress {
            let newlyOwned = next.insert(id).inserted
            if newlyOwned { persist(next) }
            if !setEnabled(id, false), newlyOwned {
                next.remove(id)
                persist(next)
            }
        }
        for id in transition.restore where setEnabled(id, true) {
            next.remove(id)
            persist(next)
        }
        return next
    }

    /// The switcher kept its own marker before the take-over was shared. Fold
    /// it into the shared one on first launch so a crash marker from an older
    /// build still restores; ids that do not fit Int32 are noise, not keys.
    static func migratedMarker(old: [Int]?, new: [Int]?) -> Set<Int32> {
        Set(((old ?? []) + (new ?? [])).compactMap { Int32(exactly: $0) })
    }
}
