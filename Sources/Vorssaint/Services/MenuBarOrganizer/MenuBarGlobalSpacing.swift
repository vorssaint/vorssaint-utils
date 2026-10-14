// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Explicit global preference changes. This never terminates another app.
/// The saved original is local machine state and is deliberately unregistered,
/// so settings backup cannot import another Mac's restore transaction.
enum MenuBarGlobalSpacing {
    static let keys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]
    static let restoreKey = "menuBarOrganizerSpacingRestoreOnThisMac"
    struct Saved: Codable, Equatable {
        let spacing: Int?
        let padding: Int?
    }
    static var hasSavedValues: Bool { UserDefaults.standard.object(forKey: restoreKey) != nil }
    static func sanitized(_ value: Int) -> Int { min(32, max(4, value)) }

    static func apply(spacing: Int, defaults: UserDefaults = .standard,
                      read: () -> Saved = readCurrent,
                      write: (Saved) -> Bool = writeCurrent) -> Bool {
        let before = read()
        let hadSavedValues = defaults.object(forKey: restoreKey) != nil
        if hadSavedValues {
            guard let data = defaults.data(forKey: restoreKey),
                  (try? JSONDecoder().decode(Saved.self, from: data)) != nil else { return false }
        } else {
            guard let data = try? JSONEncoder().encode(before) else { return false }
            defaults.set(data, forKey: restoreKey)
        }
        let value = sanitized(spacing)
        guard write(Saved(spacing: value, padding: value)) else {
            // A failed write may have partially changed the global domain.
            // Forget a new journal only after rollback confirms recovery.
            if write(before), !hadSavedValues { defaults.removeObject(forKey: restoreKey) }
            return false
        }
        return true
    }

    static func restore(defaults: UserDefaults = .standard,
                        read: () -> Saved = readCurrent,
                        write: (Saved) -> Bool = writeCurrent) -> Bool {
        guard let data = defaults.data(forKey: restoreKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return false }
        let before = read()
        guard write(saved) else { _ = write(before); return false }
        defaults.removeObject(forKey: restoreKey)
        return true
    }

    /// Removal may delete the only recovery snapshot. Missing state is a no-op;
    /// malformed or failed restoration must keep the app and its preferences.
    static func restoreForRemoval(defaults: UserDefaults = .standard,
                                  read: () -> Saved = readCurrent,
                                  write: (Saved) -> Bool = writeCurrent) -> Bool {
        guard defaults.object(forKey: restoreKey) != nil else { return true }
        return restore(defaults: defaults, read: read, write: write)
    }

    private static func readCurrent() -> Saved {
        func value(_ key: String) -> Int? {
            (CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                    kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? NSNumber)?.intValue
        }
        return Saved(spacing: value(keys[0]), padding: value(keys[1]))
    }

    private static func writeCurrent(_ values: Saved) -> Bool {
        for (key, value) in zip(keys, [values.spacing, values.padding]) {
            CFPreferencesSetValue(key as CFString, value.map { NSNumber(value: $0) },
                                  kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        return CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                        kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}
