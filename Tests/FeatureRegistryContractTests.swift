// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Features hub is one enum plus a handful of tables the compiler cannot
/// tie back to it: the hub groups, the Settings page gates, the duplicated
/// monitor list, the alert-to-metric pairs, the Settings directory and search
/// rows, the first-run presets and the persisted availability/backup keys.
/// Adding a case satisfies the exhaustive enum switches but not these tables,
/// so a half-registered feature can ship as a row nothing opens instead of
/// failing to build. Each contract below names the table it pins.
///
/// Deliberately partial tables, left out of the completeness checks:
/// `AppFeature.offeredWhenNeverSwitchedOn` (only switches nothing leans on),
/// `dynamicIslandExtensions`/`dynamicIslandInitialExtensions` (the island
/// minus the couple that stay opt-in), `onboardingPermissions` (broad grants
/// only), `monitorsPermissionChanges` (only the features that must NOT poll)
/// and `FeaturePreset.features` (curated starting points, not an install
/// list). The preset table is still checked for internal consistency.
enum FeatureRegistryContractTests {
    /// The opt-in side of `AppFeature.installedByDefault`: features an update
    /// leaves uninstalled. A new case belongs here on purpose, so an update
    /// never grows the panel and Settings on its own.
    private static let availabilityExclusions: Set<AppFeature> = [
        .focusFollowsMouse, .scrollHorizontal, .scrollZoom, .linearScroll, .scrollSpeed,
        .diskImageInstaller, .audioPriority, .wallpaper, .killProcess, .portManager,
        .fanControl, .notchMascot, .spacesOrder, .quitApps,
    ]

    /// Features no Settings page gate lists because their controls live on a
    /// page that never hides (General) or on the hub itself. A feature whose
    /// destination is one of those pages is reachable without a gate; every
    /// other feature must appear in the gate of the page it opens.
    private static let alwaysVisibleDestinationFeatures: Set<AppFeature> = [
        .mixer, .soundOutputSwitcher, .audioPriority, .musicBlock,
        .diskImageInstaller,
    ]

    /// Every page the Settings window can show. `SettingsPage` is not
    /// `CaseIterable`, so this literal is the registry the directory is
    /// measured against.
    private static let allSettingsPages: Set<SettingsPage> = [
        .general, .features, .energy, .monitor,
        .mouse, .switcher, .dock, .keyDebounce, .superKey, .cutPaste, .autoQuit,
        .quitProtection, .cleaner, .uninstaller, .urlCleaner, .homebrew, .appUpdates,
        .media, .clipboard, .windowLayout, .shelf, .quickTools, .textSnippets,
        .screenshot, .radialMenu, .commandBar, .killProcess, .portManager, .notch,
        .notchMascot,
        .shortcuts, .advanced, .about, .releaseNotes, .support,
    ]

    static func run(_ suite: TestSuite) {
        let all = Set(AppFeature.allCases)

        // Hub groups: `features(in:)` is the only reader, so the union must be
        // every case, in exactly one group each.
        let grouped = FeatureGroup.allCases.flatMap { AppFeature.features(in: $0) }
        suite.expect(Set(grouped) == all && grouped.count == all.count,
                     "every feature belongs to exactly one hub group")
        suite.expect(FeatureGroup.allCases.allSatisfy { !AppFeature.features(in: $0).isEmpty },
                     "no hub group is empty")

        // Availability: the persisted raw value is the feature identity, so it
        // must round-trip. A renamed case would strand its saved choice.
        let availabilityPrefix = DefaultsKey.featureAvailable("")
        let availabilityKeys = Set(AppFeature.allCases.map(\.availabilityKey))
        suite.expect(availabilityKeys.count == all.count
                && availabilityKeys.allSatisfy { key in
                    guard key.hasPrefix(availabilityPrefix),
                          let feature = AppFeature(rawValue: String(key.dropFirst(availabilityPrefix.count)))
                    else { return false }
                    return feature.availabilityKey == key
                },
                     "every availability key resolves back to its feature")

        // The registered defaults are the update/backup contract: one Bool per
        // feature, derived from `allCases`, so a feature can never ship
        // without an availability choice.
        suite.expect(Set(AppFeature.availabilityDefaults.keys) == availabilityKeys
                && AppFeature.allCases.allSatisfy {
                    AppFeature.availabilityDefaults[$0.availabilityKey] as? Bool == $0.installedByDefault
                },
                     "the availability defaults cover every feature and match installedByDefault")

        // A backup must carry everything the feature needs to come back: its
        // availability choice, every one of its enable switches, and every
        // monitor alert that turns a metric's notifications on.
        let exported = SettingsBackupSupport.exportKeys()
        suite.expect(availabilityKeys.isSubset(of: exported),
                     "every feature availability choice travels in a backup")
        let featureEnableKeys = Set(AppFeature.allCases.flatMap(\.enabledKeys))
        suite.expect(featureEnableKeys.isSubset(of: exported),
                     "every feature switch travels in a backup")
        suite.expect(
            Set(AppFeature.monitorAlertPairs.map(\.key)).isSubset(of: exported),
            "every monitor alert travels in a backup")
        // A key that survives in the backup export must name a real feature,
        // or a restored Mac carries a preference nothing reads.
        let exportedAvailabilityKeys = exported.filter { $0.hasPrefix(availabilityPrefix) }
        suite.expect(!exportedAvailabilityKeys.isEmpty
                && exportedAvailabilityKeys.allSatisfy {
                    AppFeature(rawValue: String($0.dropFirst(availabilityPrefix.count))) != nil
                },
                     "every feature availability key in a backup belongs to a real feature")

        // Installed after an update: only the explicit opt-in side stays out.
        suite.expect(Set(AppFeature.allCases.filter { !$0.installedByDefault }) == availabilityExclusions,
                     "only the documented opt-in features stay uninstalled after an update")

        // Settings page gates: every feature either has a gate on its own page
        // or lands on a page that never hides. A gate may not list a feature
        // twice, and the gates together must account for every feature.
        let destinationPages = Set(AppFeature.allCases.map(\.settingsDestination.page))
        let gateLists = destinationPages.map {
            FeatureVisibilitySupport.features(for: $0)
        }
        let gated = Set(gateLists.flatMap { $0 })
        suite.expect(gateLists.allSatisfy { Set($0).count == $0.count },
                     "no Settings page gate lists a feature twice")
        suite.expect(gated == all.subtracting(alwaysVisibleDestinationFeatures),
                     "every feature is gated by its Settings page or lands on one that never hides")
        suite.expect(alwaysVisibleDestinationFeatures.allSatisfy {
                        FeatureVisibilitySupport.features(for: $0.settingsDestination.page).isEmpty
                    },
                     "features listed as landing on a never-hiding page do land there")
        for feature in all.subtracting(alwaysVisibleDestinationFeatures) {
            suite.expect(
                FeatureVisibilitySupport.features(for: feature.settingsDestination.page)
                    .contains(feature),
                "\(feature.rawValue) is gated by the page its settings open")
        }

        // The monitor page keeps its own copy of the monitor group. Drift here
        // hides the page while a metric is installed, so its settings vanish.
        suite.expect(Set(FeatureVisibilitySupport.features(for: .monitor))
                == Set(AppFeature.features(in: .monitor)),
                     "the Monitor page gates exactly the monitor group")

        // The island page lists every extension by hand; an extension added to
        // the group but not to the page would disappear with the island open.
        suite.expect(Set(FeatureVisibilitySupport.features(for: .notch))
                == Set(AppFeature.features(in: .dynamicIsland)),
                     "the Dynamic Island page gates every extension of its group")

        // Monitor alerts: one key per metric, and every metric that can ask for
        // notifications must have a pair, or its alert never counts as used.
        let alertPairs = AppFeature.monitorAlertPairs
        suite.expect(Set(alertPairs.map { $0.key }).count == alertPairs.count,
                     "every monitor alert key belongs to one metric")
        let alertingMetrics = Set(AppFeature.features(in: .monitor).filter {
            $0.permissions.contains(.notifications)
        })
        suite.expect(Set(alertPairs.map { $0.feature }) == alertingMetrics,
                     "every metric with a notification permission has an alert pair")
        suite.expect(alertPairs.allSatisfy { $0.feature.group == .monitor },
                     "every monitor alert names a monitor metric")

        // Settings directory and search: a feature whose Settings destination
        // has no page row, or no search result of its own, is a row the user
        // can see in the hub but can never find or open again.
        let suiteName = "com.vorssaint.tests.feature-registry.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let state = SettingsSearchState(defaults: defaults, hardware: .init(
                battery: false, notchedDisplay: false, plainDisplay: false,
                keyboardLight: false, bluetoothSleep: false, brightnessOSD: false))
            let sections = SettingsDirectory.sections(.enUS, language: .enUS, state: state)
            let directoryPages = Set(sections.flatMap(\.items).map(\.page))
            suite.expect(directoryPages == allSettingsPages,
                         "the Settings directory has a row for every page: missing "
                            + "\(allSettingsPages.subtracting(directoryPages).map(\.self))")
            suite.expect(destinationPages.isSubset(of: directoryPages),
                         "every feature's Settings destination is a page in the directory")
            suite.expect(AppFeature.allCases.allSatisfy(\.settingsDestination.hasValidSectionAnchor),
                         "every feature's Settings section anchor belongs to its page")

            let searchItems = SettingsDirectory.searchItems(.enUS, language: .enUS, state: state)
            let represented = Set(searchItems.compactMap(\.feature))
            suite.expect(represented == all,
                         "every feature has a Settings search result: missing "
                            + "\(all.subtracting(represented).map(\.rawValue).sorted())")
            for feature in all {
                suite.expect(searchItems.contains {
                    $0.feature == feature && $0.destination == feature.settingsDestination
                }, "\(feature.rawValue) searches to its own Settings destination")
            }
        } else {
            suite.expect(false, "feature registry defaults suite can be created")
        }

        // Presets are curated, not a full install list, but each one must only
        // switch on keys its own features own, and must not install betas.
        for preset in FeaturePreset.allCases {
            let ownKeys = Set(preset.features.flatMap(\.enabledKeys))
            suite.expect(!preset.features.isEmpty,
                         "the \(preset.rawValue) preset installs at least one feature")
            suite.expect(Set(preset.enableKeys).isSubset(of: ownKeys),
                         "the \(preset.rawValue) preset only enables switches of features it installs")
            suite.expect(!preset.features.contains(where: \.isBeta),
                         "the \(preset.rawValue) preset never installs a beta feature")
        }
    }
}
