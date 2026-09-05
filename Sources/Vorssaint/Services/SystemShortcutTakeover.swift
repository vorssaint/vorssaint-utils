// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Switches WindowServer symbolic hotkeys off for as long as a Vorssaint
/// feature wants a key macOS would otherwise answer, and gives them back on
/// every exit path. Only ids that are enabled right now are ever touched, and
/// the marker is written before each change so a crash can be repaired at the
/// next launch. Callers decide which ids; this decides how.
enum SystemShortcutTakeover {
    private static let lock = NSLock()
    private static var suppressed: Set<Int32> = SystemShortcutTakeoverSupport.migratedMarker(
        old: UserDefaults.standard.array(forKey: DefaultsKey.switcherNativeHotkeysSuppressed) as? [Int],
        new: UserDefaults.standard.array(forKey: DefaultsKey.systemShortcutsSuppressed) as? [Int])

    static func apply(desired: Set<Int32>) {
        lock.lock()
        defer { lock.unlock() }
        guard let setEnabled = SymbolicHotKeys.setEnabled,
              let isEnabled = SymbolicHotKeys.isEnabled else { return }
        let candidates = desired.union(suppressed)
        let currentlyEnabled = candidates.filter { isEnabled($0) }
        let transition = SystemShortcutTakeoverSupport.transition(
            from: suppressed, to: desired, currentlyEnabled: currentlyEnabled)
        suppressed = SystemShortcutTakeoverSupport.apply(
            transition, owned: suppressed,
            setEnabled: { setEnabled($0, $1) == .success },
            persist: persist)
    }

    /// Launch only repairs previous ownership. Keep ids a feature will claim
    /// again without toggling them; new suppression waits for its live handler.
    /// The old switcher marker, already absorbed into `suppressed`, is written to
    /// the shared key before it is removed, so a restore that fails here still
    /// has a marker to retry from.
    static func recoverIfNeeded(keeping desired: Set<Int32>) {
        lock.lock()
        defer { lock.unlock() }
        persist(suppressed)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
        guard let setEnabled = SymbolicHotKeys.setEnabled else { return }
        suppressed = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTakeoverSupport.recoveryTransition(from: suppressed, keeping: desired),
            owned: suppressed,
            setEnabled: { setEnabled($0, $1) == .success },
            persist: persist)
    }

    private static func persist(_ ids: Set<Int32>) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.systemShortcutsSuppressed)
        } else {
            UserDefaults.standard.set(ids.map(Int.init).sorted(), forKey: DefaultsKey.systemShortcutsSuppressed)
        }
    }
}
