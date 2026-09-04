// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Turns Dock's app/window switcher hotkeys off after explicit opt-in, and
/// restores only keys Vorssaint found enabled before it changed them. The
/// write-ahead marker lets a fresh process repair state left by a crash.
enum SwitcherNativeHotkeys {
    private static let lock = NSLock()
    private static var state = SwitcherNativeHotkeyState(
        stored: UserDefaults.standard.array(
            forKey: DefaultsKey.switcherNativeHotkeysSuppressed) as? [Int] ?? [])

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

    /// Gives back ids an earlier build owned under a meaning this one no
    /// longer has (28 was written as the reverse window key; it is the
    /// screenshot key), then drops them from the marker so this happens once.
    /// Runs at launch before any feature starts, so it depends neither on the
    /// switcher's tap coming up nor on the feature still being installed.
    static func recoverIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard let setEnabled = SymbolicHotKeys.setEnabled else { return }
        state.recoverOrphans(setEnabled: { setEnabled($0, $1) == .success },
                             persist: persist)
    }

    static func apply(_ desired: Set<SwitcherNativeSymbolicHotKey>) {
        lock.lock()
        defer { lock.unlock() }
        guard let setEnabled = SymbolicHotKeys.setEnabled,
              let isEnabled = SymbolicHotKeys.isEnabled else { return }
        state.apply(desired, isEnabled: { isEnabled($0) },
                    setEnabled: { setEnabled($0, $1) == .success },
                    persist: persist)
    }

    private static func persist(_ marker: [Int]) {
        if marker.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
        } else {
            UserDefaults.standard.set(marker,
                                      forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
        }
    }
}
