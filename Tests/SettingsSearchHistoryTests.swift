// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Behavioral checks for recent Settings search destinations: what a stored
/// record resolves to across launches, and what it must stop resolving to.
enum SettingsSearchHistoryTests {
    static func run(_ suite: TestSuite) {
        let domain = "vorss.tests.settings-search-history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        let allAvailable: (AppFeature) -> Bool = { _ in true }
        let catalog = items()

        // MARK: Record then read back

        defaults.removePersistentDomain(forName: domain)
        let homebrew = AppFeature.homebrew.settingsDestination
        SettingsSearchHistory.record(destination: homebrew, defaults: defaults)
        var entries = SettingsSearchHistory.entries(items: catalog,
                                                    isAvailable: allAvailable,
                                                    defaults: defaults)
        suite.expect(entries.count == 1, "a recorded destination comes back as one recent")
        suite.expect(entries.first?.destination == homebrew,
                     "a recent keeps the routed destination that was recorded")
        suite.expect(entries.first?.title == "Homebrew",
                     "a recent shows the catalog's current title")
        suite.expect(entries.first?.id == SettingsSearchHistory.identifier(destination: homebrew),
                     "a recent reports the stable identifier it was stored as")
        suite.expect((defaults.stringArray(forKey: SettingsSearchHistory.defaultsKey) ?? [])
                        .allSatisfy { !$0.contains("Homebrew") },
                     "stored identifiers never carry localized text")

        // MARK: Localized titles are read at display time

        SettingsSearchHistory.record(destination: homebrew, defaults: defaults)
        entries = SettingsSearchHistory.entries(
            items: items(homebrewTitle: "Homebrew (translated)"),
            isAvailable: allAvailable, defaults: defaults)
        suite.expect(entries.first?.title == "Homebrew (translated)",
                     "a recent follows the current localized title, not the stored one")

        // MARK: Dedupe, reorder and cap

        defaults.removePersistentDomain(forName: domain)
        let general = FeatureSettingsDestination(.general)
        let advanced = FeatureSettingsDestination(.advanced)
        SettingsSearchHistory.record(destination: general, defaults: defaults)
        SettingsSearchHistory.record(destination: advanced, defaults: defaults)
        SettingsSearchHistory.record(destination: general, defaults: defaults)
        entries = SettingsSearchHistory.entries(items: catalog, isAvailable: allAvailable,
                                                defaults: defaults)
        suite.expect(entries.map(\.destination) == [general, advanced],
                     "recording the same destination again moves it to the front instead of duplicating")
        suite.expect(entries.count == (defaults.stringArray(forKey: SettingsSearchHistory.defaultsKey) ?? []).count,
                     "the stored list holds no duplicate of what is displayed")

        // The sidebar hint never splits one destination into two recents.
        SettingsSearchHistory.record(destination: general, sidebarFeature: .shelf, defaults: defaults)
        SettingsSearchHistory.record(destination: general, sidebarFeature: .homebrew, defaults: defaults)
        entries = SettingsSearchHistory.entries(items: catalog, isAvailable: allAvailable,
                                                defaults: defaults)
        suite.expect(entries.filter { $0.destination == general }.count == 1,
                     "a sidebar hint does not duplicate one destination in the recents")
        suite.expect(entries.first?.sidebarFeature == .homebrew,
                     "the most recent sidebar hint is the one a recent carries")

        // MARK: Cap at five distinct destinations

        defaults.removePersistentDomain(forName: domain)
        let capped: [FeatureSettingsDestination] = [.init(.general), .init(.advanced), .init(.about),
                                                   .init(.releaseNotes), .init(.support),
                                                   .init(.shortcuts)]
        for destination in capped {
            SettingsSearchHistory.record(destination: destination, defaults: defaults)
        }
        entries = SettingsSearchHistory.entries(items: catalog, isAvailable: allAvailable,
                                                defaults: defaults)
        suite.expect(entries.map(\.destination) == Array(capped.reversed().prefix(5)),
                     "the recents keep the last five distinct destinations, newest first")
        suite.expect(SettingsSearchHistory.entries(items: catalog, isAvailable: allAvailable,
                                                   defaults: defaults).count == SettingsSearchHistory.limit,
                     "the recents never exceed the limit")
        SettingsSearchHistory.clear(defaults: defaults)
        suite.expect(SettingsSearchHistory.entries(items: catalog, isAvailable: allAvailable,
                                                   defaults: defaults).isEmpty,
                     "clearing the recents leaves nothing to show")

        // MARK: Unusable records are omitted

        defaults.removePersistentDomain(forName: domain)
        defaults.set(["", "garbage", "general/-/-/-extra/parts", "noSuchPage/-/-/-",
                      "general/shelf/-/-"], forKey: SettingsSearchHistory.defaultsKey)
        suite.expect(SettingsSearchHistory.entries(items: catalog, isAvailable: allAvailable,
                                                   defaults: defaults).isEmpty,
                     "malformed and unresolvable identifiers are dropped instead of crashing or misrouting")

        SettingsSearchHistory.record(destination: AppFeature.commandBar.settingsDestination,
                                     defaults: defaults)
        suite.expect(SettingsSearchHistory.entries(items: catalog, isAvailable: allAvailable,
                                                   defaults: defaults).first?.destination
                        == FeatureSettingsDestination(.commandBar),
                     "an available feature's recent opens its own page")

        // A switched-off feature routes to the Features hub. That fallback must
        // not turn it back into a destination the user can open.
        entries = SettingsSearchHistory.entries(
            items: catalog,
            isAvailable: { $0 != .commandBar && $0 != .homebrew && $0 != .shelf },
            defaults: defaults)
        suite.expect(entries.allSatisfy { $0.targetFeature != .commandBar },
                     "a recent for a switched-off feature is omitted, not left pointing at the Features fallback")
        suite.expect(entries.allSatisfy { $0.sidebarFeature.map { $0 != .shelf } ?? true },
                     "a sidebar hint for a switched-off feature is dropped")

        defaults.removePersistentDomain(forName: domain)
        SettingsSearchHistory.record(destination: AppFeature.homebrew.settingsDestination,
                                     defaults: defaults)
        SettingsSearchHistory.record(destination: AppFeature.shelf.settingsDestination,
                                     defaults: defaults)
        entries = SettingsSearchHistory.entries(items: catalog,
                                               isAvailable: { $0 != .homebrew },
                                               defaults: defaults)
        suite.expect(entries.map(\.destination) == [FeatureSettingsDestination(.shelf)],
                     "recents on hidden pages and rows for unavailable features are both omitted")

        // MARK: Suggestions resolve before plain rows

        defaults.removePersistentDomain(forName: domain)
        let homebrewItem = featureItem(.homebrew, title: "Homebrew")
        let keyword = SettingsSearchSuggestion(id: .keyword(.homebrew, 0),
                                              title: "Brew services",
                                              icon: "cup.and.saucer",
                                              item: homebrewItem)
        SettingsSearchHistory.record(destination: homebrew, defaults: defaults)
        entries = SettingsSearchHistory.entries(items: catalog, suggestions: [keyword],
                                               isAvailable: allAvailable, defaults: defaults)
        suite.expect(entries.first?.title == "Brew services",
                     "a recent keeps the specific row the user picked from a grouped result")
    }

    // MARK: - Fixture catalog

    private static func items(homebrewTitle: String = "Homebrew") -> [SettingsSearchItem] {
        let pages: [(SettingsPage, String)] = [
            (.general, "General"), (.features, "Features"), (.advanced, "Advanced"),
            (.about, "About"), (.releaseNotes, "Release Notes"), (.support, "Support"),
            (.shortcuts, "Shortcuts"), (.shelf, "Shelf"), (.commandBar, "Command Bar"),
        ]
        let pageItems = pages.map { page, title in
            SettingsSearchItem(id: .page(page), destination: FeatureSettingsDestination(page),
                               title: title, icon: "gear")
        }
        return pageItems + [
            featureItem(.homebrew, title: homebrewTitle),
            featureItem(.commandBar, title: "Command Bar"),
            featureItem(.shelf, title: "Shelf"),
        ]
    }

    private static func featureItem(_ feature: AppFeature, title: String) -> SettingsSearchItem {
        SettingsSearchItem(id: .feature(feature), destination: feature.settingsDestination,
                           title: title, icon: feature.symbolName, feature: feature)
    }
}
