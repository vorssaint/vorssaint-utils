// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The portable part of the app's settings: what a backup file carries and
/// how an incoming file is validated. Pure logic so the harness can pin down
/// exactly which keys travel (and, more importantly, which never do).
enum SettingsBackupSupport {
    static let formatVersionKey = "vorssaintBackupVersion"
    static let appVersionKey = "vorssaintBackupAppVersion"
    static let settingsKey = "settings"
    static let formatVersion = 1

    /// Keys the backup carries: every registered preference, the availability
    /// layer, and the deliberately unregistered selection/layout keys — minus
    /// state that belongs to one machine or one moment.
    static func exportKeys() -> Set<String> {
        var keys = Set(Defaults.registeredDefaults.keys)
        keys.formUnion(AppFeature.availabilityDefaults.keys)
        keys.formUnion(unregisteredPreferenceKeys)
        keys.subtract(machineStateKeys)
        return keys
    }

    /// Preferences stored without a registered default (absence means "use
    /// the built-in behavior"), still part of how the user set the app up.
    static let unregisteredPreferenceKeys: Set<String> = [
        DefaultsKey.autoQuitEnabled,
        DefaultsKey.shelfEnabled,
        DefaultsKey.finderCutPasteEnabled,
        DefaultsKey.textSnippets,
        DefaultsKey.scratchpadDocument,
        DefaultsKey.radialMenuItems,
        DefaultsKey.radialMenuProfiles,
        DefaultsKey.commandBarLinks,
        DefaultsKey.commandBarRowShortcuts,
        DefaultsKey.language,
        DefaultsKey.appVolumes,
        DefaultsKey.appOutputDevices,
        DefaultsKey.mixerHiddenApps,
        DefaultsKey.preferredInputDevice,
        DefaultsKey.soundOutputSwitcherDeviceUIDs,
        DefaultsKey.menuBarCPU,
        DefaultsKey.menuBarGPU,
        DefaultsKey.menuBarMemory,
        DefaultsKey.menuBarNetwork,
        DefaultsKey.menuBarBattery,
        DefaultsKey.menuBarPower,
        DefaultsKey.panelSectionOrder,
        DefaultsKey.panelUtilityOrder,
        DefaultsKey.panelControlOrder,
        DefaultsKey.panelToggleOrder,
        DefaultsKey.panelSystemOrder,
        DefaultsKey.panelNetworkOrder,
        DefaultsKey.panelDiskOrder,
        DefaultsKey.panelPowerOrder,
        DefaultsKey.panelCollapsedSections,
        DefaultsKey.quickLauncherItemOrder,
        // Experience flags: a restored Mac must not replay onboarding or the
        // feature intros the user has already been through.
        DefaultsKey.hasOnboarded,
        DefaultsKey.onboardingStep,
        DefaultsKey.featuresOnboardingVersion,
        DefaultsKey.lastUpdateIntroVersion,
        DefaultsKey.supportUpdateIntroVersion,
        DefaultsKey.updateHighlightsSeenVersion,
        DefaultsKey.panelCollapsedResetVersion,
    ]

    /// Never exported: live state, per-machine placement, private content and
    /// anything an update flow owns. Clipboard entries and shelf items stay
    /// out by construction (they are not preference keys), listed here only
    /// when they would otherwise slip in through the registered set.
    static let machineStateKeys: Set<String> = [
        // A Bluetooth restore owed by one sleeping Mac means nothing on another.
        DefaultsKey.bluetoothSleepRestorePending,
        DefaultsKey.micMuteActive,
        DefaultsKey.micMuteSavedVolume,
        // Levels and device ids belong to the microphones of one Mac.
        DefaultsKey.micMuteSavedVolumes,
        DefaultsKey.micMuteMutedDevices,
        DefaultsKey.cleanerLastAutoRun,
        // When the last check ran and what it found belong to one Mac.
        DefaultsKey.appUpdatesLastCheck,
        DefaultsKey.appUpdatesLastCount,
        DefaultsKey.appUpdatesNotifiedIDs,
        DefaultsKey.cleanerLastAutoFreed,
        DefaultsKey.whatsAppDownloadsAutomaticStartDate,
        DefaultsKey.whatsAppDownloadsLastAutoRun,
        DefaultsKey.whatsAppDownloadsLastCleanup,
        DefaultsKey.whatsAppDownloadsLastCleanupCount,
        DefaultsKey.whatsAppDownloadsLastCleanupBytes,
        DefaultsKey.whatsAppDownloadsLastCleanupFailed,
        DefaultsKey.whatsAppDownloadsLastCleanupAutomatic,
        DefaultsKey.whatsAppDownloadsExclusions,
        DefaultsKey.whatsAppDownloadsAccessConfirmed,
        DefaultsKey.whatsAppOrganizerDestinationPath,
        DefaultsKey.whatsAppOrganizerRecords,
        DefaultsKey.whatsAppOrganizerUndoTransaction,
        DefaultsKey.whatsAppOrganizerLastRun,
        DefaultsKey.whatsAppOrganizerLastMoved,
        DefaultsKey.whatsAppOrganizerLastDuplicates,
        DefaultsKey.whatsAppOrganizerLastFailed,
        // What one person runs most is habit, not configuration.
        DefaultsKey.commandBarUsage,
        // A chosen folder is authority on one Mac, not portable configuration.
        // Restoring it elsewhere could search a different volume or trigger a
        // protected-folder prompt without a fresh choice.
        DefaultsKey.commandBarFileScopes,
        // A local watermark file is authority on this Mac, not portable data.
        DefaultsKey.mediaImageWatermarkLogoPath,
        DefaultsKey.simulateUpdate,
        DefaultsKey.updateShowcaseIntroVersion,
        DefaultsKey.updateShowcaseMediaOverride,
        DefaultsKey.unifiedScreenCaptureShortcutMigrated,
        DefaultsKey.restoredScreenCaptureShortcutsMigrated,
        DefaultsKey.orphanedCaptureShortcutMigrated,
        DefaultsKey.settingsWindowWidth,
        DefaultsKey.settingsWindowHeight,
        DefaultsKey.screenshotSharingDeveloperEndpoint,
        DefaultsKey.fanControlRecoveryNeeded,
        DefaultsKey.fanControlHelperVersion,
        // DDC capability belongs to one physical monitor on one Mac port.
        DefaultsKey.brightnessDDCWriteOnlyPaths,
    ]

    /// The file's content: an envelope with the format version, the app
    /// version that wrote it, and the filtered settings.
    static func payload(appVersion: String,
                        valueFor: (String) -> Any?) -> [String: Any] {
        var settings: [String: Any] = [:]
        for key in exportKeys() {
            if let value = valueFor(key) {
                settings[key] = value
            }
        }
        settings = portableMediaSettings(settings)
        settings = portableMouseExceptions(settings)
        return [
            formatVersionKey: formatVersion,
            appVersionKey: appVersion,
            settingsKey: settings,
        ]
    }

    /// Validates an incoming file and returns only the keys this build knows
    /// and exports — unknown, renamed or never-exported keys are dropped, so
    /// a tampered or future file can never write outside the allowed set.
    static func sanitizedSettings(from payload: [String: Any]) -> [String: Any]? {
        guard let version = formatVersion(from: payload),
              version >= 1, version <= formatVersion,
              let settings = payload[settingsKey] as? [String: Any]
        else { return nil }
        let allowed = exportKeys()
        let filtered = settings.filter { allowed.contains($0.key) && valueLooksRight($0.key, $0.value) }
        return portableMouseExceptions(portableMediaSettings(filtered))
    }

    static func formatVersion(from payload: [String: Any]) -> Int? {
        if let intValue = payload[formatVersionKey] as? Int {
            return intValue
        }
        if let number = payload[formatVersionKey] as? NSNumber {
            return number.intValue
        }
        if let string = payload[formatVersionKey] as? String,
           let intValue = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intValue
        }
        return nil
    }

    /// The half of an exception list a backup file never carries, because
    /// `portableMouseExceptions` filters it out on the way out.
    static func pathIdentities(in list: [String]) -> [String] {
        list.filter(MouseAppExceptionSupport.isExecutablePathIdentity)
    }

    /// What an exception list should hold once a backup has been applied.
    /// Restoring clears every exported key before writing the file's values,
    /// and the file only has the portable half -- so without carrying the
    /// paths across, applying a backup would delete the entries for programs
    /// that are not apps, including on the Mac the backup was written on. The
    /// restored order wins and a carried path already present is not doubled,
    /// so applying the same backup twice lands on the same list. All five keys
    /// register `[String]()`, so after the clear the read is `[]` rather than
    /// the pre-restore list -- which is what makes this safe on a backup
    /// written before these keys existed, and not only on one that carries an
    /// empty array. (Reasoning from @PathGao's review.)
    static func restoredExceptionList(restored: [String], carried: [String]) -> [String] {
        restored + carried.filter { !restored.contains($0) }
    }

    /// A mouse exception list holds two kinds of identity at once: a bundle
    /// identifier, which names the same app on any Mac, and the resolved path
    /// of a program that has no identifier to be named by (issue #1009). The
    /// never-exported list above already refuses the second kind wherever it
    /// has a key to itself -- `commandBarFileScopes`,
    /// `mediaImageWatermarkLogoPath`, `brightnessDDCWriteOnlyPaths`, all for
    /// the same stated reason: authority on one Mac, not portable
    /// configuration. Here the two kinds share one array, so the refusal has
    /// to be per value rather than per key. Left in, a backup would carry the
    /// short username inside the path, and restoring it on another Mac would
    /// leave a row pointing at a file that is not there -- which
    /// `valueLooksRight` cannot catch, since the value is a perfectly good
    /// `[String]`.
    ///
    /// Driven from `MouseExceptionScope.allCases` rather than a list of keys
    /// spelled here, so a scope that renames its key, or two scopes that come
    /// to share one, are covered without this file being edited.
    private static func portableMouseExceptions(_ source: [String: Any]) -> [String: Any] {
        var settings = source
        for key in Set(MouseExceptionScope.allCases.map(\.defaultsKey)) {
            guard let stored = settings[key] as? [String] else { continue }
            let portable = stored.filter { !MouseAppExceptionSupport.isExecutablePathIdentity($0) }
            guard portable.count != stored.count else { continue }
            // An emptied list still means "no exceptions", so the key stays
            // rather than falling back to whatever a missing key would do.
            settings[key] = portable
        }
        return settings
    }

    private static func portableMediaSettings(_ source: [String: Any]) -> [String: Any] {
        var settings = source
        if let rawProfiles = settings[DefaultsKey.mediaImageProfiles] as? String {
            if let portableProfiles = MediaSupport.portableImageProfiles(rawProfiles) {
                settings[DefaultsKey.mediaImageProfiles] = portableProfiles
            } else {
                settings.removeValue(forKey: DefaultsKey.mediaImageProfiles)
            }
        }
        guard let kind = settings[DefaultsKey.mediaImageWatermarkKind] as? String else {
            return settings
        }
        let hasText = ((settings[DefaultsKey.mediaImageWatermarkText] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        switch MediaImageWatermarkKind.sanitized(kind) {
        case .logo:
            settings[DefaultsKey.mediaImageWatermarkKind] = MediaImageWatermarkKind.off.rawValue
        case .textAndLogo:
            settings[DefaultsKey.mediaImageWatermarkKind] = hasText
                ? MediaImageWatermarkKind.text.rawValue : MediaImageWatermarkKind.off.rawValue
        case .off, .text:
            break
        }
        return settings
    }

    /// A backup is a file the user can hand around and edit, so a value has to
    /// look like the setting it claims to be before it is written back. The
    /// registered defaults already say what each setting is, and a value of
    /// the wrong shape is dropped rather than restored: a number where a
    /// switch belongs, or text where a number belongs, would otherwise reach
    /// code that trusts its own settings.
    static func valueLooksRight(_ key: String, _ value: Any) -> Bool {
        if key == DefaultsKey.scratchpadDocument {
            return ScratchpadDocument.decoded(value as? Data, defaultName: "Scratchpad") != nil
        }
        guard let expected = Defaults.registeredDefaults[key] else {
            // Not a registered setting, so there is nothing to compare
            // against; the allowed list is the only gate for these.
            return true
        }
        switch expected {
        case is Bool: return isBoolean(value)
        case is Int: return isInteger(value)
        case is Double: return isNumber(value)
        case is String: return value is String
        case is [String]: return value is [String]
        case is [String: String]: return value is [String: String]
        case is [Any]: return value is [Any]
        case is [String: Any]: return value is [String: Any]
        default: return true
        }
    }

    private static func number(_ value: Any) -> NSNumber? {
        value as? NSNumber
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let value = number(value) else { return false }
        return CFGetTypeID(value) == CFBooleanGetTypeID()
    }

    private static func isInteger(_ value: Any) -> Bool {
        guard let value = number(value), CFGetTypeID(value) != CFBooleanGetTypeID() else {
            return false
        }
        return !CFNumberIsFloatType(unsafeBitCast(value, to: CFNumber.self))
    }

    private static func isNumber(_ value: Any) -> Bool {
        guard let value = number(value) else { return false }
        return CFGetTypeID(value) != CFBooleanGetTypeID()
    }
}
