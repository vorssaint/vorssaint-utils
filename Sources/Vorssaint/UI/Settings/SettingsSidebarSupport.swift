// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A page or a directly selectable tool in the flat Settings sidebar.
struct SettingsSidebarItem: Identifiable {
    enum ID: Hashable {
        case page(SettingsPage)
        case feature(AppFeature)
        case setting(SettingsSectionAnchor)
    }

    let id: ID
    let destination: FeatureSettingsDestination
    let title: String
    let icon: String

    var stableKey: String {
        switch id {
        case .page(let page): "page:\(page)"
        case .feature(let feature): "feature:\(feature.rawValue)"
        case .setting(let anchor): "setting:\(anchor.rawValue)"
        }
    }

    var accentGroup: FeatureGroup? {
        switch id {
        case .feature(let feature): feature.group
        case .page(let page):
            AppFeature.allCases.first { $0.settingsDestination.page == page }?.group
                ?? Self.accentGroup(for: page)
        case .setting:
            AppFeature.allCases.first { $0.settingsDestination == destination }?.group
                ?? Self.accentGroup(for: destination.page)
        }
    }

    private static func accentGroup(for page: SettingsPage) -> FeatureGroup {
        switch page {
        case .energy: .energyDisplay
        case .monitor: .monitor
        case .dock, .switcher, .windowLayout: .windowsDock
        case .mouse, .keyDebounce, .keyRemapping, .superKey: .mouseKeyboard
        case .clipboard, .cutPaste, .shelf, .media: .clipboardFiles
        case .notch, .notchMascot: .dynamicIsland
        case .general, .features, .autoQuit, .quitProtection, .cleaner, .uninstaller,
             .urlCleaner, .homebrew, .appUpdates, .quickTools, .textSnippets, .screenshot,
             .radialMenu, .commandBar, .killProcess, .portManager, .shortcuts, .advanced,
             .about, .releaseNotes, .support: .tools
        }
    }

    func usingIcon(_ icon: String) -> SettingsSidebarItem {
        SettingsSidebarItem(id: id, destination: destination, title: title, icon: icon)
    }
}

/// A stable category in the sidebar; its title follows the selected language.
struct SettingsSidebarSection: Identifiable {
    let id: Int
    let title: String
    let items: [SettingsSidebarItem]
}

enum SettingsSidebarSortMode: String, CaseIterable, Identifiable {
    case defaultOrder
    case mostUsed
    case name
    case manual

    var id: Self { self }
}

/// Builds one row per tool, even when several tools share one Settings card.
enum SettingsSidebarSupport {
    static func items(page: SettingsPage, title: String, icon: String,
                      preferredFeatures: [AppFeature], includePage: Bool,
                      isAvailable: (AppFeature) -> Bool,
                      featureTitle: (AppFeature) -> String) -> [SettingsSidebarItem] {
        guard FeatureVisibilitySupport.isPageVisible(page, isAvailable: isAvailable) else { return [] }
        let pageItem = SettingsSidebarItem(id: .page(page),
                                           destination: FeatureSettingsDestination(page),
                                           title: title, icon: icon)
        var rows = includePage ? [pageItem] : []
        var seenFeatures: Set<AppFeature> = []
        for feature in preferredFeatures + AppFeature.allCases {
            guard seenFeatures.insert(feature).inserted else { continue }
            let destination = feature.settingsDestination
            guard destination.page == page, destination.sectionAnchor != nil,
                  isAvailable(feature) else { continue }
            rows.append(SettingsSidebarItem(id: .feature(feature),
                                            destination: destination,
                                            title: featureTitle(feature),
                                            icon: feature.symbolName))
        }
        if rows.isEmpty { rows.append(pageItem) }
        return rows
    }

    /// Splits window and control rows, and takes input, file and sound tools
    /// out of Utilities, so the sidebar groups them as the Features page does.
    /// Rows of other groups, or of no feature, stay where they are.
    static func featureGroupRows(windowsControls: [SettingsSidebarItem],
                                 utilities: [SettingsSidebarItem])
        -> (windowsDock: [SettingsSidebarItem], mouseKeyboard: [SettingsSidebarItem],
            files: [SettingsSidebarItem], sound: [SettingsSidebarItem],
            utilities: [SettingsSidebarItem]) {
        func group(_ item: SettingsSidebarItem) -> FeatureGroup? {
            if case .feature(let feature) = item.id { return feature.group }
            return AppFeature.allCases.first { $0.settingsDestination == item.destination }?.group
        }
        func moved(_ target: FeatureGroup) -> [SettingsSidebarItem] {
            utilities.filter { group($0) == target }
        }
        return (windowsControls.filter { group($0) == .windowsDock },
                windowsControls.filter { group($0) != .windowsDock } + moved(.mouseKeyboard),
                moved(.clipboardFiles), moved(.sound),
                utilities.filter { ![.mouseKeyboard, .clipboardFiles, .sound].contains(group($0)) })
    }

    static func selection(for destination: FeatureSettingsDestination,
                          in items: [SettingsSidebarItem],
                          preferredID: SettingsSidebarItem.ID? = nil)
        -> SettingsSidebarItem.ID? {
        if let preferredID,
           items.contains(where: { $0.id == preferredID && $0.destination == destination }) {
            return preferredID
        }
        if destination.sectionAnchor != nil,
           let tool = items.first(where: { $0.destination == destination }) {
            return tool.id
        }
        if items.contains(where: { $0.id == .page(destination.page) }) {
            return .page(destination.page)
        }
        return items.first(where: { $0.destination.page == destination.page })?.id
    }

    static func organizedSections(_ sections: [SettingsSidebarSection],
                                  favorites: Set<String>,
                                  sortMode: SettingsSidebarSortMode,
                                  manualOrder: [String],
                                  usage: [String: Int],
                                  favoritesTitle: String) -> [SettingsSidebarSection] {
        let allItems = sections.flatMap(\.items)
        let availableKeys = Set(allItems.map(\.stableKey))
        let favoriteItems = allItems.filter {
            favorites.contains($0.stableKey) && availableKeys.contains($0.stableKey)
        }
        var manualRanks: [String: Int] = [:]
        for (index, key) in manualOrder.enumerated() where manualRanks[key] == nil {
            manualRanks[key] = index
        }

        func sorted(_ items: [SettingsSidebarItem]) -> [SettingsSidebarItem] {
            switch sortMode {
            case .defaultOrder:
                return items
            case .name:
                return items.sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            case .mostUsed:
                return items.enumerated().sorted { lhs, rhs in
                    let leftUse = usage[lhs.element.stableKey, default: 0]
                    let rightUse = usage[rhs.element.stableKey, default: 0]
                    return leftUse == rightUse
                        ? lhs.offset < rhs.offset
                        : leftUse > rightUse
                }.map(\.element)
            case .manual:
                return items.enumerated().sorted { lhs, rhs in
                    let leftRank = manualRanks[lhs.element.stableKey, default: Int.max]
                    let rightRank = manualRanks[rhs.element.stableKey, default: Int.max]
                    return leftRank == rightRank
                        ? lhs.offset < rhs.offset
                        : leftRank < rightRank
                }.map(\.element)
            }
        }

        var result = sections.compactMap { section -> SettingsSidebarSection? in
            let remaining = section.items.filter { !favorites.contains($0.stableKey) }
            guard !remaining.isEmpty else { return nil }
            return SettingsSidebarSection(id: section.id, title: section.title,
                                          items: sorted(remaining))
        }
        if !favoriteItems.isEmpty {
            result.insert(SettingsSidebarSection(id: Int.min, title: favoritesTitle,
                                                 items: sorted(favoriteItems)), at: 0)
        }
        return result
    }

    static func keys(from storage: String) -> [String] {
        storage.split(separator: "\n").map(String.init)
    }

    static func storage(for keys: [String]) -> String {
        keys.joined(separator: "\n")
    }

    static func usage(from storage: String) -> [String: Int] {
        guard let data = storage.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded.mapValues { max(0, $0) }
    }

    static func usageStorage(_ usage: [String: Int]) -> String {
        guard let data = try? JSONEncoder().encode(usage),
              let storage = String(data: data, encoding: .utf8) else { return "{}" }
        return storage
    }

    static func uniqueIcons(in sections: [SettingsSidebarSection]) -> [SettingsSidebarSection] {
        var used = Set<String>()
        let featureIcons = Set(sections.flatMap(\.items).compactMap { item -> String? in
            guard case .feature = item.id else { return nil }
            return item.icon
        })
        let alternatives = [
            "circle.grid.3x3", "square.stack.3d.up", "slider.horizontal.3",
            "circle.dashed.inset.filled", "rectangle.3.group", "arrow.triangle.branch",
            "square.grid.3x2", "circle.hexagongrid", "square.on.square",
            "arrow.up.forward.app", "rectangle.split.2x1", "circle.lefthalf.filled",
            "rectangle.and.pencil.and.ellipsis", "square.grid.2x2", "gearshape.2",
            "sparkle", "square.dashed", "rectangle.stack", "rectangle.split.3x1",
            "circle.slash", "arrowshape.turn.up.right", "square.and.arrow.up",
            "line.3.horizontal.decrease.circle", "switch.2", "circle.inset.filled",
            "circle.dotted", "circle.dashed", "circle.grid.cross", "square.3.layers.3d",
            "rectangle.on.rectangle.angled", "square.split.2x2", "list.bullet.rectangle",
            "square.text.square", "terminal", "curlybraces", "wrench.and.screwdriver",
            "puzzlepiece.extension", "folder.badge.gearshape", "rectangle.portrait",
            "arrow.up.forward.square", "chart.xyaxis.line", "slider.vertical.3",
        ]
        return sections.map { section in
            SettingsSidebarSection(
                id: section.id,
                title: section.title,
                items: section.items.map { item in
                    let isFeature: Bool
                    if case .feature = item.id {
                        isFeature = true
                    } else {
                        isFeature = false
                    }
                    if (isFeature || !featureIcons.contains(item.icon)),
                       used.insert(item.icon).inserted {
                        return item
                    }
                    let replacement = alternatives.first {
                        !used.contains($0) && !featureIcons.contains($0)
                    }
                        ?? "questionmark.circle"
                    used.insert(replacement)
                    return item.usingIcon(replacement)
                }
            )
        }
    }
}
