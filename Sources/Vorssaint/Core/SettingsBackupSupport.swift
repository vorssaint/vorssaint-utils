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
        DefaultsKey.radialMenuItems,
        DefaultsKey.language,
        DefaultsKey.appVolumes,
        DefaultsKey.appOutputDevices,
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
        DefaultsKey.dockPreviewIntroVersion,
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
        DefaultsKey.micMuteActive,
        DefaultsKey.micMuteSavedVolume,
        DefaultsKey.cleanerLastAutoRun,
        DefaultsKey.cleanerLastAutoFreed,
        DefaultsKey.cleanerBadgeSeen,
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
        DefaultsKey.simulateUpdate,
        DefaultsKey.updateShowcaseIntroVersion,
        DefaultsKey.updateShowcaseMediaOverride,
        DefaultsKey.settingsWindowWidth,
        DefaultsKey.settingsWindowHeight,
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
        guard let version = payload[formatVersionKey] as? Int,
              version >= 1, version <= formatVersion,
              let settings = payload[settingsKey] as? [String: Any]
        else { return nil }
        let allowed = exportKeys()
        return settings.filter { allowed.contains($0.key) }
    }
}
