// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Turns Dock's app/window switcher hotkeys off after explicit opt-in, and
/// restores only keys Vorssaint found enabled before it changed them. The
/// write-ahead marker lets a fresh process repair state left by a crash.
enum SwitcherNativeHotkeys {
    private static let lock = NSLock()
    private static var suppressed: Set<SwitcherNativeSymbolicHotKey> = {
        let stored = UserDefaults.standard.array(
            forKey: DefaultsKey.switcherNativeHotkeysSuppressed) as? [Int] ?? []
        return Set(stored.compactMap { value in
            guard let rawValue = Int32(exactly: value) else { return nil }
            return SwitcherNativeSymbolicHotKey(rawValue: rawValue)
        })
    }()

    /// Current WindowServer mappings, including user remaps and temporarily
    /// disabled entries. Matching these avoids a second hardcoded shortcut list.
    static func configuredShortcuts() -> [SwitcherNativeSymbolicHotKey: GlobalShortcut] {
        guard let getValue = SymbolicHotKeys.getValue else { return [:] }
        return Dictionary(uniqueKeysWithValues: SwitcherNativeSymbolicHotKey.allCases.compactMap { id in
            var character: UInt32 = 0
            var keyCode: UInt32 = 0
            var modifiers: UInt32 = 0
            guard getValue(id.rawValue, &character, &keyCode, &modifiers) == .success,
                  keyCode != SymbolicHotKeys.unassignedKeyCode else { return nil }
            let shortcut = GlobalShortcut(
                keyCode: Int64(keyCode),
                modifiers: GlobalShortcutModifiers(
                    cgFlags: SpaceHopSupport.eventFlags(fromCarbonModifiers: modifiers)))
            return (id, shortcut)
        })
    }

    static func apply(_ desired: Set<SwitcherNativeSymbolicHotKey>) {
        lock.lock()
        defer { lock.unlock() }
        guard let setEnabled = SymbolicHotKeys.setEnabled,
              let isEnabled = SymbolicHotKeys.isEnabled else { return }
        let currentlyEnabled = Set(SwitcherNativeSymbolicHotKey.allCases.filter {
            isEnabled($0.rawValue)
        })
        let transition = SwitcherSupport.nativeHotkeyTransition(
            from: suppressed, to: desired, currentlyEnabled: currentlyEnabled)
        var next = suppressed
        for key in transition.suppress {
            let newlyOwned = next.insert(key).inserted
            if newlyOwned { persist(next) }
            if setEnabled(key.rawValue, false) != .success, newlyOwned {
                next.remove(key)
                persist(next)
            }
        }
        for key in transition.restore where setEnabled(key.rawValue, true) == .success {
            next.remove(key)
            persist(next)
        }
        suppressed = next
    }

    private static func persist(_ keys: Set<SwitcherNativeSymbolicHotKey>) {
        if keys.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
        } else {
            UserDefaults.standard.set(keys.map { Int($0.rawValue) }.sorted(),
                                      forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
        }
    }
}
