// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Stores stable destination identifiers, resolving titles from the live catalog.
/// Unavailable destinations are hidden without deleting their stored records.
enum SettingsSearchHistory {
    static let limit = 5
    /// `[String]` of identifiers, most recent first.
    static let defaultsKey = DefaultsKey.settingsSearchRecentDestinations

    struct Entry: Identifiable, Equatable {
        let id: String
        let destination: FeatureSettingsDestination
        let targetFeature: AppFeature?
        let sidebarFeature: AppFeature?
        let title: String
        let icon: String
    }

    static func record(destination: FeatureSettingsDestination,
                       targetFeature: AppFeature? = nil,
                       sidebarFeature: AppFeature? = nil,
                       defaults: UserDefaults = .standard) {
        guard destination.hasValidSectionAnchor else { return }
        let identifier = identifier(destination: destination,
                                    targetFeature: targetFeature,
                                    sidebarFeature: sidebarFeature)
        var stored = storedIdentifiers(defaults: defaults)
        let key = routingKey(ofIdentifier: identifier)
        stored.removeAll { routingKey(ofIdentifier: $0) == key }
        stored.insert(identifier, at: 0)
        defaults.set(Array(stored.prefix(limit)), forKey: defaultsKey)
    }

    /// Resolves recents in order, omitting missing or unavailable destinations.
    static func entries(items: [SettingsSearchItem],
                        suggestions: [SettingsSearchSuggestion] = [],
                        isAvailable: (AppFeature) -> Bool = { $0.isAvailable },
                        defaults: UserDefaults = .standard) -> [Entry] {
        let candidates = resolvedCandidates(items: items, suggestions: suggestions,
                                           isAvailable: isAvailable)
        var seen: Set<String> = []
        var entries: [Entry] = []
        for identifier in storedIdentifiers(defaults: defaults) {
            guard let key = routingKey(ofIdentifier: identifier),
                  !seen.contains(key),
                  let candidate = candidates[key] else { continue }
            seen.insert(key)
            let sidebar = sidebarFeature(ofIdentifier: identifier)
            entries.append(Entry(id: identifier,
                                 destination: candidate.destination,
                                 targetFeature: candidate.targetFeature,
                                 sidebarFeature: sidebar.flatMap { isAvailable($0) ? $0 : nil },
                                 title: candidate.title,
                                 icon: candidate.icon))
        }
        return entries
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    // MARK: - Identifiers

    /// `page/anchor/target/sidebar`, using stable tokens and `-` for absent parts.
    static func identifier(destination: FeatureSettingsDestination,
                           targetFeature: AppFeature? = nil,
                           sidebarFeature: AppFeature? = nil) -> String {
        let sidebar = sidebarFeature?.rawValue ?? "-"
        return routingKey(destination: destination, targetFeature: targetFeature)
            + "/" + sidebar
    }

    /// Sidebar hints don't distinguish destinations when deduplicating or resolving.
    private static func routingKey(destination: FeatureSettingsDestination,
                                   targetFeature: AppFeature?) -> String {
        [destination.pageToken,
         destination.sectionAnchor?.rawValue ?? "-",
         targetFeature?.rawValue ?? "-"].joined(separator: "/")
    }

    private static func routingKey(ofIdentifier identifier: String) -> String? {
        let parts = identifier.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] != "-" else { return nil }
        return parts.prefix(3).joined(separator: "/")
    }

    private static func sidebarFeature(ofIdentifier identifier: String) -> AppFeature? {
        let parts = identifier.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[3] != "-" else { return nil }
        return AppFeature(rawValue: String(parts[3]))
    }

    private static func storedIdentifiers(defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    // MARK: - Resolution

    private struct Candidate {
        let destination: FeatureSettingsDestination
        let targetFeature: AppFeature?
        let title: String
        let icon: String
    }

    /// Prefer suggestion titles when multiple catalog rows resolve to the same route.
    private static func resolvedCandidates(items: [SettingsSearchItem],
                                           suggestions: [SettingsSearchSuggestion],
                                           isAvailable: (AppFeature) -> Bool)
        -> [String: Candidate] {
        var candidates: [String: Candidate] = [:]

        func add(_ destination: FeatureSettingsDestination,
                 _ targetFeature: AppFeature?,
                 _ title: String,
                 _ icon: String) {
            // A disabled feature's fallback to the hub isn't a usable recent.
            guard targetFeature.map(isAvailable) ?? true,
                  destination.hasValidSectionAnchor,
                  FeatureVisibilitySupport.isPageVisible(destination.page,
                                                         isAvailable: isAvailable)
            else { return }
            let key = routingKey(destination: destination, targetFeature: targetFeature)
            guard candidates[key] == nil else { return }
            candidates[key] = Candidate(destination: destination,
                                        targetFeature: targetFeature,
                                        title: title, icon: icon)
        }

        for suggestion in suggestions {
            let route = SettingsSearchSupport.route(for: suggestion, isAvailable: isAvailable)
            add(route.destination, route.targetFeature, suggestion.title, suggestion.icon)
        }
        for item in items {
            let route = SettingsSearchSupport.route(for: item, isAvailable: isAvailable)
            add(route.destination, route.targetFeature, item.title, item.icon)
        }
        return candidates
    }
}

private extension FeatureSettingsDestination {
    var pageToken: String {
        switch page {
        case .general: return "general"
        case .features: return "features"
        case .energy: return "energy"
        case .monitor: return "monitor"
        case .mouse: return "mouse"
        case .switcher: return "switcher"
        case .dock: return "dock"
        case .keyDebounce: return "keyDebounce"
        case .superKey: return "superKey"
        case .cutPaste: return "cutPaste"
        case .autoQuit: return "autoQuit"
        case .quitProtection: return "quitProtection"
        case .cleaner: return "cleaner"
        case .uninstaller: return "uninstaller"
        case .urlCleaner: return "urlCleaner"
        case .homebrew: return "homebrew"
        case .appUpdates: return "appUpdates"
        case .media: return "media"
        case .clipboard: return "clipboard"
        case .windowLayout: return "windowLayout"
        case .shelf: return "shelf"
        case .quickTools: return "quickTools"
        case .textSnippets: return "textSnippets"
        case .screenshot: return "screenshot"
        case .radialMenu: return "radialMenu"
        case .commandBar: return "commandBar"
        case .killProcess: return "killProcess"
        case .portManager: return "portManager"
        case .notch: return "notch"
        case .notchMascot: return "notchMascot"
        case .shortcuts: return "shortcuts"
        case .advanced: return "advanced"
        case .about: return "about"
        case .releaseNotes: return "releaseNotes"
        case .support: return "support"
        }
    }
}
