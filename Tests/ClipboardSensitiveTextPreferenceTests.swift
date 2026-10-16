// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClipboardSensitiveTextPreferenceTests {
    static func run(_ suite: TestSuite) {
        let key = DefaultsKey.clipboardHistoryFilterSensitiveText
        let legacyKey = "clipboardHistorySkipSensitive"
        suite.expect(Defaults.registeredDefaults[key] as? Bool == false,
                     "text-based clipboard filtering requires an explicit opt-in")
        suite.expect(Defaults.registeredDefaults[legacyKey] == nil,
                     "the old enabled-by-default filter is no longer registered")

        let domain = "com.vorssaint.tests.clipboard-sensitive-opt-in.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        // Registration is process-wide, so later migration checks need it back.
        let registrationDomain = UserDefaults.standard.volatileDomain(
            forName: UserDefaults.registrationDomain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            UserDefaults.standard.setVolatileDomain(registrationDomain,
                                                    forName: UserDefaults.registrationDomain)
        }
        defaults.register(defaults: Defaults.registeredDefaults)
        suite.expect(!defaults.bool(forKey: key), "a fresh clipboard history does not guess secrets")

        let history = Data("saved history sentinel".utf8)
        let ignoredApps = ["com.example.password-manager"]
        defaults.set(history, forKey: DefaultsKey.clipboardHistoryEntries)
        defaults.set(ignoredApps, forKey: DefaultsKey.clipboardHistoryIgnoredApps)
        defaults.set(true, forKey: DefaultsKey.clipboardHistoryEnabled)
        for oldValue in [true, false] {
            defaults.set(oldValue, forKey: legacyKey)
            Defaults.migrateClipboardSensitiveTextOptIn(in: defaults)
            suite.expect(defaults.persistentDomain(forName: domain)?[legacyKey] == nil
                         && !defaults.bool(forKey: key),
                         "an old saved filter value does not opt into the new filter")
        }
        for choice in [true, false] {
            defaults.set(choice, forKey: key)
            Defaults.migrateClipboardSensitiveTextOptIn(in: defaults)
            Defaults.migrateClipboardSensitiveTextOptIn(in: defaults)
            suite.expect(defaults.bool(forKey: key) == choice,
                         "later launches preserve the user's new filter choice")
        }
        suite.expect(defaults.data(forKey: DefaultsKey.clipboardHistoryEntries) == history
                     && defaults.stringArray(forKey: DefaultsKey.clipboardHistoryIgnoredApps) == ignoredApps
                     && defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled),
                     "the filter migration preserves history, capture and ignored apps")

        let backupKeys = SettingsBackupSupport.exportKeys()
        suite.expect(backupKeys.contains(key) && !backupKeys.contains(legacyKey),
                     "backups carry the explicit opt-in but never the retired filter")
        let oldBackup: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [
                legacyKey: true,
                DefaultsKey.clipboardHistoryIgnoredApps: ignoredApps
            ] as [String: Any]
        ]
        let restored = SettingsBackupSupport.sanitizedSettings(from: oldBackup)
        suite.expect(restored != nil && restored?[legacyKey] == nil && restored?[key] == nil
                     && restored?[DefaultsKey.clipboardHistoryIgnoredApps] as? [String] == ignoredApps,
                     "restoring an older backup cannot silently enable text guessing")
        suite.expect(SettingsBackupSupport.keysToClear(whenImporting: restored ?? [:]).contains(key),
                     "an older backup replaces an existing opt-in with the new off default")
        for choice in [true, false] {
            let payload = SettingsBackupSupport.payload(appVersion: "test") { candidate in
                candidate == key ? choice : nil
            }
            let imported = SettingsBackupSupport.sanitizedSettings(from: payload)
            suite.expect(imported?[key] as? Bool == choice,
                         "new backups preserve either explicit filter choice")
        }
    }
}
