// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Switches WindowServer symbolic hotkeys off for as long as a Vorssaint
/// feature wants a key macOS would otherwise answer, and gives them back on
/// every exit path. Only ids that are enabled right now are ever touched, the
/// marker is written before each change so a crash can be repaired at the
/// next launch, and a key the user has since switched off in System Settings
/// is never switched back on by us. Callers decide which ids; this decides how.
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
        var next = suppressed
        for id in transition.suppress {
            let newlyOwned = next.insert(id).inserted
            if newlyOwned { persist(next) }
            if setEnabled(id, false) != .success, newlyOwned {
                next.remove(id)
                persist(next)
            }
        }
        // A failed enable keeps its id in the marker, so the next `apply` or
        // the next launch retries instead of dropping the key with nothing
        // left to restore it.
        let leaveOff = SystemShortcutTakeoverSupport.idsUserDisabled(
            in: transition.restore, symbolicHotKeys: GlobalShortcut.systemSymbolicHotKeys)
        for id in transition.restore {
            if leaveOff.contains(id) || setEnabled(id, true) == .success {
                next.remove(id)
                persist(next)
            }
        }
        suppressed = next
    }

    /// Launch: whatever the previous process still owned is given back unless
    /// a feature claims it again in this one. Also retires the old switcher
    /// marker, which `suppressed` has already absorbed.
    static func recoverIfNeeded() {
        apply(desired: [])
        UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
    }

    static func suspend() { apply(desired: []) }

    private static func persist(_ ids: Set<Int32>) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.systemShortcutsSuppressed)
        } else {
            UserDefaults.standard.set(ids.map(Int.init).sorted(), forKey: DefaultsKey.systemShortcutsSuppressed)
        }
    }
}
