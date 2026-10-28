// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One sidebar row of the post-update "What's New" window.
struct WhatsNewRow: Identifiable, Equatable {
    enum ID: Hashable {
        case newFeature(AppFeature)
        /// An installed feature, under its Settings sidebar row.
        case settings(SettingsSidebarItem.ID)
        /// An installed feature that has no row of its own in Settings.
        case feature(AppFeature)
        case general
        case notInstalled(AppFeature)
    }

    let id: ID
    let title: String
    let icon: String
    /// The feature the row stands for, when it stands for a single one. The
    /// Dynamic Island row stands for the island, not for its extensions.
    let feature: AppFeature?
    let destination: FeatureSettingsDestination?
    let changes: [ReleaseChange]

    var isNewFeature: Bool {
        if case .newFeature = id { return true }
        return false
    }
}

/// The window's sidebar, laid out like the Settings sidebar it mirrors.
struct WhatsNewSections: Equatable {
    var newFeatures: [WhatsNewRow] = []
    var yourFeatures: [WhatsNewRow] = []
    var notInstalled: [WhatsNewRow] = []

    var rows: [WhatsNewRow] { newFeatures + yourFeatures + notInstalled }

    /// Changes that concern this person, once each, for the overview counts.
    var changesForYou: Set<ReleaseChange> {
        Set((newFeatures + yourFeatures).flatMap(\.changes))
    }

    /// Nothing worth an interruption: no new feature, and every change is
    /// about a feature this Mac does not have.
    var hasContentForYou: Bool { !newFeatures.isEmpty || !yourFeatures.isEmpty }
}

enum WhatsNewSupport {
    /// Installed features group under the row Settings shows them in, in the
    /// Settings order, with app-wide changes last. Features left out of the
    /// Mac's install are listed one by one, since each installs on its own;
    /// a Dynamic Island extension does nothing without the island, so it
    /// counts as installed only beside it. New features come first and
    /// appear nowhere else.
    static func sections(digest: ReleaseDigest,
                         newFeatures: [AppFeature],
                         sidebarItems: [SettingsSidebarItem],
                         isAvailable: (AppFeature) -> Bool,
                         title: (AppFeature) -> String,
                         generalTitle: String) -> WhatsNewSections {
        let introduced = Set(newFeatures)
        func isInstalled(_ feature: AppFeature) -> Bool {
            isAvailable(feature)
                && (feature.group != .dynamicIsland || feature == .notch || isAvailable(.notch))
        }
        var installedChanges: [WhatsNewRow.ID: [ReleaseChange]] = [:]
        var missingChanges: [AppFeature: [ReleaseChange]] = [:]
        func add(_ change: ReleaseChange, to list: inout [ReleaseChange]?) {
            if !(list ?? []).contains(change) { list = (list ?? []) + [change] }
        }
        for change in digest.changes {
            if change.isAppWide {
                add(change, to: &installedChanges[.general])
            }
            for feature in change.features where !introduced.contains(feature) {
                if isInstalled(feature) {
                    add(change, to: &installedChanges[rowID(for: feature, in: sidebarItems)])
                } else {
                    add(change, to: &missingChanges[feature])
                }
            }
        }

        var sections = WhatsNewSections()
        sections.newFeatures = newFeatures.map { feature in
            WhatsNewRow(id: .newFeature(feature), title: title(feature), icon: feature.symbolName,
                        feature: feature, destination: navigableDestination(of: feature),
                        changes: digest.changes.filter { $0.features.contains(feature) })
        }
        for item in sidebarItems {
            guard let changes = installedChanges[.settings(item.id)] else { continue }
            let feature = representedFeature(of: item.id)
            sections.yourFeatures.append(WhatsNewRow(
                id: .settings(item.id), title: item.title, icon: item.icon, feature: feature,
                destination: item.destination, changes: changes))
        }
        for feature in AppFeature.allCases {
            guard let changes = installedChanges[.feature(feature)] else { continue }
            sections.yourFeatures.append(WhatsNewRow(
                id: .feature(feature), title: title(feature), icon: feature.symbolName, feature: feature,
                destination: navigableDestination(of: feature), changes: changes))
        }
        if let changes = installedChanges[.general] {
            sections.yourFeatures.append(WhatsNewRow(
                id: .general, title: generalTitle, icon: "gearshape", feature: nil,
                destination: nil, changes: changes))
        }
        sections.notInstalled = AppFeature.allCases.compactMap { feature in
            missingChanges[feature].map {
                WhatsNewRow(id: .notInstalled(feature), title: title(feature), icon: feature.symbolName,
                            feature: feature, destination: navigableDestination(of: feature), changes: $0)
            }
        }
        return sections
    }

    /// The Settings sidebar row an installed feature belongs to. Dynamic
    /// Island extensions, the companion included, live on the island's page;
    /// a feature Settings files under the General page, or keeps only in the
    /// Features page, gets a row of its own beside them.
    static func rowID(for feature: AppFeature, in items: [SettingsSidebarItem]) -> WhatsNewRow.ID {
        let ids = Set(items.map(\.id))
        if ids.contains(.feature(feature)) { return .settings(.feature(feature)) }
        let page = feature.settingsDestination.page
        if page == .general { return .general }
        if page != .features, ids.contains(.page(page)) { return .settings(.page(page)) }
        if feature.group == .dynamicIsland, ids.contains(.page(.notch)) { return .settings(.page(.notch)) }
        return .feature(feature)
    }

    /// Each row's title in the current language, from the same sources the
    /// rows were built with, so a language change mid-window relabels them.
    static func titles(of rows: [WhatsNewRow], sidebarItems: [SettingsSidebarItem],
                       title: (AppFeature) -> String, generalTitle: String) -> [WhatsNewRow.ID: String] {
        Dictionary(rows.map { row -> (WhatsNewRow.ID, String) in
            switch row.id {
            case .settings(let item):
                return (row.id, sidebarItems.first { $0.id == item }?.title ?? row.title)
            case .general:
                return (row.id, generalTitle)
            case .newFeature(let feature), .feature(let feature), .notInstalled(let feature):
                return (row.id, title(feature))
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The one feature a Settings row stands for, if any: a tool row, or a
    /// page that belongs to a single feature (the Dynamic Island page counts
    /// as the island's, not its extensions'). The System Monitor page holds
    /// several and stands for none.
    static func representedFeature(of id: SettingsSidebarItem.ID) -> AppFeature? {
        switch id {
        case .feature(let feature): return feature
        case .page(let page):
            let owners = AppFeature.allCases.filter {
                $0.settingsDestination == FeatureSettingsDestination(page)
                    && !AppFeature.dynamicIslandExtensions.contains($0)
            }
            return owners.count == 1 ? owners[0] : nil
        case .setting: return nil
        }
    }

    private static func navigableDestination(of feature: AppFeature) -> FeatureSettingsDestination? {
        feature.hasNavigableSettingsDestination ? feature.settingsDestination : nil
    }

    /// Changes in the order the window lists them: new, then changed, then
    /// fixed, each keeping the newest version first.
    static func grouped(_ changes: [ReleaseChange]) -> [WhatsNewChangeGroup] {
        ReleaseChangeKind.allCases.compactMap { kind in
            let matching = changes.filter { $0.kind == kind }
            return matching.isEmpty ? nil : WhatsNewChangeGroup(kind: kind, changes: matching)
        }
    }
}

struct WhatsNewChangeGroup: Identifiable {
    let kind: ReleaseChangeKind
    let changes: [ReleaseChange]
    var id: ReleaseChangeKind { kind }
}
