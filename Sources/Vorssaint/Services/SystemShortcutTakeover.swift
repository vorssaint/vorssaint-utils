// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
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
    static let switcherSource = "switcher"
    private static var wanted: [String: Set<Int32>] = [:]
    private static var claims: [String: GlobalShortcut] = [:]
    private static var takeOverKeys: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: DefaultsKey.systemShortcutTakeOverKeys) ?? [])
    private static var wakeObserver: NSObjectProtocol?

    /// Raw-id callers (the switcher) say what they want under their own name.
    static func setWanted(_ ids: Set<Int32>, for source: String) {
        lock.lock()
        if ids.isEmpty { wanted.removeValue(forKey: source) } else { wanted[source] = ids }
        let desired = SystemShortcutTakeoverSupport.union(of: wanted)
        lock.unlock()
        apply(desired: desired)
    }

    /// A feature whose hotkey just registered. Only shortcuts the user chose to
    /// take over resolve to any ids; everything else is a no-op that costs one
    /// dictionary write.
    static func claim(_ storageKey: String, shortcut: GlobalShortcut) {
        lock.lock()
        claims[storageKey] = shortcut
        lock.unlock()
        refresh(storageKey)
    }

    static func release(_ storageKey: String) {
        lock.lock()
        claims.removeValue(forKey: storageKey)
        lock.unlock()
        setWanted([], for: storageKey)
    }

    /// The recorder's choice, kept as a preference so it survives a relaunch.
    static func setTakeOver(_ storageKey: String, _ on: Bool) {
        lock.lock()
        if on { takeOverKeys.insert(storageKey) } else { takeOverKeys.remove(storageKey) }
        UserDefaults.standard.set(takeOverKeys.sorted(), forKey: DefaultsKey.systemShortcutTakeOverKeys)
        lock.unlock()
        refresh(storageKey)
    }

    static func isTakenOver(_ storageKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return takeOverKeys.contains(storageKey)
    }

    /// The live table can change under us (System Settings, another app, wake).
    /// Re-resolve every claim; `apply` only writes what actually differs.
    static func reconcile() {
        let keys: [String]
        lock.lock()
        keys = Array(claims.keys)
        lock.unlock()
        for key in keys { refresh(key) }
    }

    private static func refresh(_ storageKey: String) {
        lock.lock()
        let shortcut = takeOverKeys.contains(storageKey) ? claims[storageKey] : nil
        lock.unlock()
        guard let shortcut, let entries = SymbolicHotKeys.liveEntries() else {
            setWanted([], for: storageKey)
            return
        }
        setWanted(SystemShortcutTakeoverSupport.ids(matching: shortcut, in: entries), for: storageKey)
    }

    private static func apply(desired: Set<Int32>) {
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
        // Wake can leave the live table changed under a claim that is still
        // ours; the switcher's own three seconds keep the two reconciles from
        // racing the WindowServer right after wake.
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reconcile() }
                }
        }
        lock.lock()
        defer { lock.unlock() }
        persist(suppressed)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
        guard let setEnabled = SymbolicHotKeys.setEnabled else { return }
        // A feature that claimed before recovery ran (keep-awake registers
        // first) is a source too; keeping only the switcher's ids would give
        // its key back and leave it off.
        let keep = desired.union(SystemShortcutTakeoverSupport.union(of: wanted))
        suppressed = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTakeoverSupport.recoveryTransition(from: suppressed, keeping: keep),
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
