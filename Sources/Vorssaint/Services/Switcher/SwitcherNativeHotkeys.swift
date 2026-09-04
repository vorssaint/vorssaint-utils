// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// Turns Dock's app/window switcher hotkeys off after explicit opt-in, and
/// restores only keys Vorssaint found enabled before it changed them. The
/// write-ahead marker lets a fresh process repair state left by a crash.
enum SwitcherNativeHotkeys {
    private static let lock = NSLock()
    /// The marker the previous process left behind, split once at load into
    /// the ids this build owns and the ids it no longer recognises.
    private static let storedMarker = SwitcherSupport.storedNativeHotkeys(
        UserDefaults.standard.array(
            forKey: DefaultsKey.switcherNativeHotkeysSuppressed) as? [Int] ?? [])
    private static var suppressed: Set<SwitcherNativeSymbolicHotKey> = storedMarker.known
    private static var orphansRepaired = false

    private typealias SetEnabledFunction = @convention(c) (Int32, Bool) -> CGError
    private typealias IsEnabledFunction = @convention(c) (Int32) -> Bool
    private typealias GetValueFunction =
        @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError
    private static let setEnabled: SetEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetEnabledFunction.self)
    }()
    private static let isEnabled: IsEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSIsSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: IsEnabledFunction.self)
    }()
    private static let getValue: GetValueFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSGetSymbolicHotKeyValue") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetValueFunction.self)
    }()

    /// Current WindowServer mappings, including user remaps and temporarily
    /// disabled entries. Matching these avoids a second hardcoded shortcut list.
    static func configuredShortcuts() -> [SwitcherNativeSymbolicHotKey: GlobalShortcut] {
        guard let getValue else { return [:] }
        return Dictionary(uniqueKeysWithValues: SwitcherNativeSymbolicHotKey.allCases.compactMap { id in
            var character: UInt32 = 0
            var keyCode: UInt32 = 0
            var modifiers: UInt32 = 0
            guard getValue(id.rawValue, &character, &keyCode, &modifiers) == .success,
                  keyCode != 0xFFFF else { return nil }
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
        guard let setEnabled else { return }
        repairOrphans(setEnabled)
    }

    private static func repairOrphans(_ setEnabled: SetEnabledFunction) {
        guard !orphansRepaired, !storedMarker.orphaned.isEmpty else { return }
        // Rewrite the marker only once every orphan is back on. A failed
        // enable keeps its id in the marker, so the next `apply` or the next
        // launch retries instead of dropping the key with nothing to restore it.
        let stillOff = storedMarker.orphaned.filter { setEnabled($0, true) != .success }
        guard stillOff.isEmpty else { return }
        orphansRepaired = true
        persist(suppressed)
    }

    static func apply(_ desired: Set<SwitcherNativeSymbolicHotKey>) {
        lock.lock()
        defer { lock.unlock() }
        guard let setEnabled, let isEnabled else { return }
        repairOrphans(setEnabled)
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
