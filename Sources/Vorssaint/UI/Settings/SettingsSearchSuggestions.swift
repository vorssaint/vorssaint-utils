// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Suggested and recent destinations resolved against the current catalog.
enum SettingsSearchSuggestions {
    static let suggestedPages: [SettingsPage] = [.general, .features, .media, .commandBar]

    struct Entry: Identifiable {
        enum Kind {
            case suggestion(SettingsSearchSuggestion)
            case recent(SettingsSearchHistory.Entry)
        }

        enum ID: Hashable {
            case suggestion(SettingsPage)
            case recent(String)
        }

        let id: ID
        let kind: Kind
        let title: String
        let icon: String
    }

    static func suggestions(items: [SettingsSearchItem],
                            isAvailable: (AppFeature) -> Bool) -> [Entry] {
        suggestedPages.compactMap { page in
            guard FeatureVisibilitySupport.isPageVisible(page, isAvailable: isAvailable),
                  let item = items.first(where: { $0.id == .page(page) })
            else { return nil }
            return Entry(id: .suggestion(page),
                         kind: .suggestion(SettingsSearchSuggestion(
                            id: .page(page), title: item.title, icon: item.icon, item: item)),
                         title: item.title, icon: item.icon)
        }
    }

    static func recents(items: [SettingsSearchItem],
                        isAvailable: (AppFeature) -> Bool,
                        defaults: UserDefaults = .standard) -> [Entry] {
        SettingsSearchHistory.entries(items: items,
                                      suggestions: catalogSuggestions(items: items),
                                      isAvailable: isAvailable,
                                      defaults: defaults)
            .map { entry in
                Entry(id: .recent(entry.id), kind: .recent(entry),
                      title: entry.title, icon: entry.icon)
            }
    }

    static func catalogSuggestions(items: [SettingsSearchItem]) -> [SettingsSearchSuggestion] {
        items.map { item in
            let id: SettingsSearchSuggestion.ID
            if case .page(let page) = item.id, page == item.destination.page {
                id = .page(page)
            } else {
                id = .item(item.destination.page, item.id)
            }
            return SettingsSearchSuggestion(id: id, title: item.title,
                                            icon: item.icon, item: item)
        }
    }
}
