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

    /// Live ids whose combination equals `shortcut` exactly. `enabled` is
    /// ignored on purpose: `apply` decides what to touch from the live state.
    static func ids(matching shortcut: GlobalShortcut, in entries: [LiveSystemShortcut]) -> Set<Int32> {
        Set(entries.filter { $0.shortcut == shortcut }.map(\.id))
    }

    /// What every source wants, together.
    static func union(of wanted: [String: Set<Int32>]) -> Set<Int32> {
        wanted.values.reduce(into: Set<Int32>()) { $0.formUnion($1) }
    }

    /// The switcher kept its own marker before the take-over was shared. Fold
    /// it into the shared one on first launch so a crash marker from an older
    /// build still restores; ids that do not fit Int32 are noise, not keys.
    static func migratedMarker(old: [Int]?, new: [Int]?) -> Set<Int32> {
        Set(((old ?? []) + (new ?? [])).compactMap { Int32(exactly: $0) })
    }
}

/// What the recorder does with a combination that has already passed every
/// Vorssaint-side check. One rule for all four rows, and testable.
enum RecorderTakeOverDecision: Equatable {
    /// Save it. `clearTakeOver` drops a stale take-over entry once the row has
    /// moved to a key macOS does not answer.
    case save(clearTakeOver: Bool)
    /// Ask first: macOS answers this combination and the user has not agreed
    /// to take exactly this one over.
    case offer
}

extension SystemShortcutTakeoverSupport {
    /// Whether macOS would answer this combination if Vorssaint were not
    /// holding it. The live rule only counts entries that are enabled, so a
    /// key already taken over reads as free; the ids the service suppresses
    /// are macOS's too, and count here.
    static func conflictsWithMacOS(_ shortcut: GlobalShortcut,
                                   liveEntries: [LiveSystemShortcut]?,
                                   symbolicHotKeys: @autoclosure () -> [String: Any]?,
                                   held: Set<Int32>,
                                   role: GlobalShortcutRole? = nil) -> Bool {
        if GlobalShortcut.conflictsWithSystemShortcut(shortcut,
                                                      liveEntries: liveEntries,
                                                      symbolicHotKeys: symbolicHotKeys(),
                                                      role: role) {
            return true
        }
        // Nothing can be held without a live table, so the fallback above is
        // the whole answer when the private calls are missing. A role's own
        // permitted ids are not in its way even while held, as in the live rule.
        guard let liveEntries else { return false }
        let permitted = role?.permittedSystemShortcutIDs ?? []
        return !ids(matching: shortcut, in: liveEntries).subtracting(permitted).isDisjoint(with: held)
    }

    static func recorderDecision(shortcut: GlobalShortcut,
                                 conflictsWithMacOS: Bool,
                                 takenOver: Bool,
                                 current: GlobalShortcut?) -> RecorderTakeOverDecision {
        guard conflictsWithMacOS else { return .save(clearTakeOver: true) }
        if takenOver, current == shortcut { return .save(clearTakeOver: false) }
        return .offer
    }
}
