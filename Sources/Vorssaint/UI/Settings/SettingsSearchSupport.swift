// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One destination-aware Settings search result. Its identity is structural,
/// never derived from localized text or result ordering.
struct SettingsSearchItem: Identifiable {
    enum ID: Hashable {
        case page(SettingsPage)
        case feature(AppFeature)
    }

    let id: ID
    let destination: FeatureSettingsDestination
    let title: String
    let icon: String
    var keywords: [String] = []
    /// Optional feature owner for each keyword. This is parallel to
    /// `keywords`; absent entries are page-level settings.
    var keywordFeatures: [AppFeature?] = []
    /// The hub feature this result represents, when it corresponds to exactly
    /// one `AppFeature` — including a dedicated page result such as Homebrew,
    /// whose `id` stays `.page(...)` for identity stability. `nil` for a
    /// purely generic page (Features itself, General, ...).
    var feature: AppFeature?
}

/// One selectable row inside a grouped Settings search result. A page-level
/// keyword routes to its containing page, while a feature-owned keyword keeps
/// the same exact section destination and unavailable-feature fallback as the
/// feature row itself.
struct SettingsSearchSuggestion: Identifiable {
    enum ID: Hashable {
        case page(SettingsPage)
        case item(SettingsPage, SettingsSearchItem.ID)
        case keyword(SettingsPage, Int)
    }

    let id: ID
    let title: String
    let icon: String
    let item: SettingsSearchItem
    /// Features-page keyword rows use this to reveal the exact utility rather
    /// than opening the hub at an unrelated scroll position.
    var featureHubTarget: AppFeature? = nil
}

/// macOS Settings-style search group: the main page is shown once, followed
/// by every matching utility or setting that lives inside it.
struct SettingsSearchGroup: Identifiable {
    let pageItem: SettingsSearchItem
    let parentMatches: Bool
    let suggestions: [SettingsSearchSuggestion]

    var id: SettingsPage { pageItem.destination.page }

    var parentSuggestion: SettingsSearchSuggestion {
        SettingsSearchSuggestion(id: .page(id), title: pageItem.title,
                                 icon: pageItem.icon, item: pageItem)
    }
}

/// Pure filtering for the Settings sidebar search field, so the matching
/// rules (case, accents, word prefixes) are covered by the unit harness.
enum SettingsSearchSupport {
    private enum MatchRank {
        case exactTitle
        case title
        case keyword
    }

    /// Every feature contributes a localized label and exact Settings
    /// destination. Clipboard History uses its section name so it stays
    /// distinguishable from the containing Clipboard page.
    static func featureItems(language: AppLanguage,
                             title: (AppFeature) -> String) -> [SettingsSearchItem] {
        AppFeature.allCases.map { feature in
            SettingsSearchItem(id: .feature(feature),
                               destination: feature.settingsDestination,
                               title: feature == .clipboardHistory
                                   ? FeatureStrings.commandBar(language).sourceClipboard
                                   : title(feature),
                               icon: feature.symbolName,
                               feature: feature)
        }
    }

    /// A dedicated page row wins over a generated feature row only when their
    /// IDs, full destinations, and the page's one-to-one feature mapping all
    /// agree. The winning page keeps its stable identity and presentation while
    /// carrying the feature identity needed for unavailable-feature routing.
    static func combinedItems(pageItems: [SettingsSearchItem],
                               featureItems: [SettingsSearchItem]) -> [SettingsSearchItem] {
        let mergedPageItems = pageItems.map { pageItem -> SettingsSearchItem in
            guard let match = featureItems.first(where: {
                shouldMerge(pageItem: pageItem, featureItem: $0)
            }) else { return pageItem }
            var merged = pageItem
            merged.feature = match.feature
            return merged
        }
        let dedupedFeatureItems = featureItems.filter { featureItem in
            !pageItems.contains { pageItem in
                shouldMerge(pageItem: pageItem, featureItem: featureItem)
            }
        }
        return mergedPageItems + dedupedFeatureItems
    }

    private static func shouldMerge(pageItem: SettingsSearchItem,
                                    featureItem: SettingsSearchItem) -> Bool {
        guard case .page(let page) = pageItem.id,
              page == pageItem.destination.page,
              case .feature(let feature) = featureItem.id,
              featureItem.feature == feature,
              pageItem.destination == featureItem.destination else { return false }
        return FeatureVisibilitySupport.features(for: page) == [feature]
    }

    /// Where a search or command-bar result should route right now. A
    /// feature-backed result that is unavailable, or whose intentional
    /// destination is the Features hub itself, opens Features with an
    /// explicit target feature so the hub can reveal that exact row; every
    /// other result opens its own destination unchanged. Shared by the
    /// Settings sidebar search and the Command Bar so neither duplicates the
    /// other's fallback logic.
    static func route(for item: SettingsSearchItem,
                       isAvailable: (AppFeature) -> Bool = { $0.isAvailable })
        -> (destination: FeatureSettingsDestination, targetFeature: AppFeature?) {
        if let feature = item.feature {
            guard isAvailable(feature) else {
                return (FeatureSettingsDestination(.features), feature)
            }
            if item.destination.page == .features {
                return (item.destination, feature)
            }
            return (item.destination, nil)
        }
        guard FeatureVisibilitySupport.isPageVisible(item.destination.page, isAvailable: isAvailable) else {
            return (FeatureSettingsDestination(.features), nil)
        }
        return (item.destination, nil)
    }

    static func route(for suggestion: SettingsSearchSuggestion,
                      isAvailable: (AppFeature) -> Bool = { $0.isAvailable })
        -> (destination: FeatureSettingsDestination, targetFeature: AppFeature?) {
        if let feature = suggestion.featureHubTarget {
            return (FeatureSettingsDestination(.features), feature)
        }
        return route(for: suggestion.item, isAvailable: isAvailable)
    }

    /// Case-, diacritic- and width-insensitive containment: "métr" finds
    /// "Metrics", "moni" finds "Monitor". A blank query matches everything.
    /// Keywords let a page match by what lives inside it ("lid" finds
    /// Energy, "quick panel" finds Quick tools), not just by its name.
    static func matches(query: String, title: String, keywords: [String] = []) -> Bool {
        let foldedQuery = fold(query)
        guard !foldedQuery.isEmpty else { return true }
        return matchRank(foldedQuery: foldedQuery, title: title, keywords: keywords) != nil
    }

    /// Filters and ranks one query in a single stable pass: exact normalized
    /// titles, then title containment, then keyword-only matches.
    static func matchingItems(query: String,
                               items: [SettingsSearchItem]) -> [SettingsSearchItem] {
        let foldedQuery = fold(query)
        guard !foldedQuery.isEmpty else { return items }

        var exactTitleMatches: [SettingsSearchItem] = []
        var titleMatches: [SettingsSearchItem] = []
        var keywordMatches: [SettingsSearchItem] = []
        for item in items {
            switch matchRank(foldedQuery: foldedQuery,
                             title: item.title,
                             keywords: item.keywords) {
            case .exactTitle: exactTitleMatches.append(item)
            case .title: titleMatches.append(item)
            case .keyword: keywordMatches.append(item)
            case nil: break
            }
        }
        return exactTitleMatches + titleMatches + keywordMatches
    }

    /// Groups ranked matches beneath their main Settings pages. Page keywords
    /// become visible setting rows instead of silently producing only a page
    /// result, and generated feature rows retain their anchored destinations.
    static func groupedMatchingItems(query: String,
                                     items: [SettingsSearchItem],
                                     isAvailable: (AppFeature) -> Bool = { $0.isAvailable })
        -> [SettingsSearchGroup] {
        let foldedQuery = fold(query)
        guard !foldedQuery.isEmpty else { return [] }

        let navigableItems = items.compactMap { item -> SettingsSearchItem? in
            if let feature = item.feature, !isAvailable(feature) {
                // The utility itself remains navigable through its Features
                // row, but settings that do not exist until installation must
                // not make that utility appear as a field-level match.
                var fallbackItem = item
                fallbackItem.keywords = []
                fallbackItem.keywordFeatures = []
                return fallbackItem
            }
            guard FeatureVisibilitySupport.isPageVisible(
                item.destination.page, isAvailable: isAvailable) else { return nil }
            return item
        }

        let pagePairs: [(SettingsPage, SettingsSearchItem)] = navigableItems.compactMap { item in
            guard case .page(let page) = item.id,
                  item.destination.page == page,
                  FeatureVisibilitySupport.isPageVisible(page, isAvailable: isAvailable)
            else { return nil }
            return (page, item)
        }
        let pageItems = Dictionary(uniqueKeysWithValues: pagePairs)
        var builders: [SettingsPage: SearchGroupBuilder] = [:]
        var pageOrder: [SettingsPage] = []

        for item in matchingItems(query: query, items: navigableItems) {
            let page = route(for: item, isAvailable: isAvailable).destination.page
            guard let pageItem = pageItems[page] else { continue }
            if builders[page] == nil {
                builders[page] = SearchGroupBuilder(pageItem: pageItem)
                pageOrder.append(page)
            }
            guard var builder = builders[page] else { continue }

            if case .page(let itemPage) = item.id, itemPage == page {
                if matchRank(foldedQuery: foldedQuery, title: item.title, keywords: []) != nil {
                    builder.parentMatches = true
                }
                for (index, keyword) in item.keywords.enumerated()
                    where fold(keyword).contains(foldedQuery) {
                    let keywordFeature = item.keywordFeatures.indices.contains(index)
                        ? item.keywordFeatures[index] : nil
                    if let keywordFeature, !isAvailable(keywordFeature) { continue }
                    let suggestionItem = keywordFeature.map { feature in
                        SettingsSearchItem(id: .feature(feature),
                                           destination: feature.settingsDestination,
                                           title: keyword,
                                           icon: feature.symbolName,
                                           feature: feature)
                    } ?? pageItem
                    appendSuggestion(
                        SettingsSearchSuggestion(id: .keyword(page, index),
                                                 title: keyword,
                                                 icon: pageItem.icon,
                                                 item: suggestionItem,
                                                 featureHubTarget: page == .features
                                                    ? keywordFeature : nil),
                        to: &builder)
                }
            } else {
                appendSuggestion(
                    SettingsSearchSuggestion(id: .item(page, item.id),
                                             title: item.title,
                                             icon: item.icon,
                                             item: item),
                    to: &builder)
            }
            builders[page] = builder
        }

        return pageOrder.compactMap { page in
            guard let builder = builders[page],
                  builder.parentMatches || !builder.suggestions.isEmpty else { return nil }
            return SettingsSearchGroup(pageItem: builder.pageItem,
                                       parentMatches: builder.parentMatches,
                                       suggestions: builder.suggestions)
        }
    }

    private struct SearchGroupBuilder {
        let pageItem: SettingsSearchItem
        var parentMatches = false
        var suggestions: [SettingsSearchSuggestion] = []
    }

    private static func appendSuggestion(_ suggestion: SettingsSearchSuggestion,
                                         to builder: inout SearchGroupBuilder) {
        guard !builder.suggestions.contains(where: {
            fold($0.title) == fold(suggestion.title)
        }) else { return }
        builder.suggestions.append(suggestion)
    }

    /// Every former screen-tool page remains discoverable after those settings
    /// move behind the single Screen capture destination.
    static func screenCaptureKeywords(_ strings: Strings,
                                       language: AppLanguage) -> [String] {
        screenCaptureFeatureKeywords(strings, language: language).flatMap(\.titles)
    }

    static func screenCaptureFeatureKeywords(_ strings: Strings,
                                              language: AppLanguage)
        -> [(feature: AppFeature, titles: [String])] {
        let screenshot = FeatureStrings.screenshot(language)
        let recorder = FeatureStrings.recorder(language)
        return [
            (.screenshot, [screenshot.pageTitle, screenshot.freezeToggle,
                           screenshot.loupeStartsOnToggle,
                           screenshot.fullScreenShortcutTitle, screenshot.previewPositionLabel,
                           screenshot.pinButton, screenshot.toolPixelate, screenshot.toolArrow]),
            (.screenRecorder, [recorder.pageTitle, recorder.startButton,
                               recorder.systemAudioToggle, recorder.microphoneToggle,
                               recorder.qualityLabel, recorder.frameRateLabel]),
            (.screenOCR, [strings.ocrName, strings.ocrRemoveLineBreaksToggle, strings.ocrQRToggle]),
            (.colorPicker, [strings.colorPickerName, strings.colorPickerFormatLabel]),
        ]
    }

    /// Keeps only the sections that still have items for the query, so an
    /// empty section never renders just its header.
    static func filteredIndices(query: String,
                                sections: [[String]]) -> [[Int]] {
        sections.map { titles in
            titles.indices.filter { matches(query: query, title: titles[$0]) }
        }
    }

    private static func fold(_ value: String) -> String {
        // No locale: Turkish folds a dotted I to a dotless one, which would
        // make this page search answer differently there.
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchRank(foldedQuery: String,
                                   title: String,
                                   keywords: [String]) -> MatchRank? {
        let foldedTitle = fold(title)
        if foldedTitle == foldedQuery { return .exactTitle }
        if foldedTitle.contains(foldedQuery) { return .title }
        if keywords.contains(where: { fold($0).contains(foldedQuery) }) { return .keyword }
        return nil
    }

    /// Returns the next selection index with deterministic wrapping.
    static func moveSelection(index: Int?, delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let current = clampedSelection(index: index, count: count)
            ?? (delta >= 0 ? count - 1 : 0)
        let remainder = (current + delta % count) % count
        return remainder >= 0 ? remainder : remainder + count
    }

    static func clampedSelection(index: Int?, count: Int) -> Int? {
        guard count > 0, let index else { return nil }
        return min(max(index, 0), count - 1)
    }

    /// Keeps the same result selected if it moved, otherwise clamps its old
    /// position to the new result count.
    static func reconciledSelection<ID: Equatable>(index: Int?,
                                                    previousIDs: [ID],
                                                    resultIDs: [ID]) -> Int? {
        guard !resultIDs.isEmpty else { return nil }
        guard let index else { return 0 }
        if previousIDs.indices.contains(index),
           let movedIndex = resultIDs.firstIndex(of: previousIDs[index]) {
            return movedIndex
        }
        return clampedSelection(index: index, count: resultIDs.count)
    }
}

/// Content sizing for the resizable Settings window: tall enough by default
/// to show the whole sidebar without scrolling, and a size the user chose is
/// restored as is. Kept pure so the unit harness pins the rules.
enum SettingsWindowSupport {
    /// The layout's design size; the window can only grow from here.
    static let minContentWidth: Double = 772
    static let minContentHeight: Double = 528
    /// Tall default so every sidebar entry is visible on regular screens.
    static let preferredContentHeight: Double = 838

    static func isValidContentSize(width: Double, height: Double) -> Bool {
        width >= minContentWidth && height >= minContentHeight
    }

    /// A saved size wins when it is at least the minimum (0 means unset);
    /// otherwise the tall default, capped to the screen's available height.
    static func initialContentSize(savedWidth: Double, savedHeight: Double,
                                   availableHeight: Double) -> (width: Double, height: Double) {
        if isValidContentSize(width: savedWidth, height: savedHeight) {
            return (savedWidth, savedHeight)
        }
        let height = min(preferredContentHeight, max(availableHeight, minContentHeight))
        return (minContentWidth, height)
    }

    static func panelPlacement(preferredFrame: CGRect,
                               panelFrame: CGRect,
                               visibleFrame: CGRect) -> (frame: CGRect, closesPanel: Bool) {
        let avoidedFrame = frame(preferredFrame, avoiding: panelFrame, in: visibleFrame)
        let closesPanel = avoidedFrame.intersects(panelFrame)
        return (closesPanel ? clamped(preferredFrame, to: visibleFrame) : avoidedFrame,
                closesPanel)
    }

    private static func frame(_ frame: CGRect, avoiding panelFrame: CGRect,
                              in visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 28
        let margin: CGFloat = 20
        var adjusted = frame

        let leftX = panelFrame.minX - gap - frame.width
        let rightX = panelFrame.maxX + gap
        if panelFrame.midX >= visibleFrame.midX, leftX >= visibleFrame.minX + margin {
            adjusted.origin.x = min(frame.origin.x, leftX)
        } else if panelFrame.midX < visibleFrame.midX,
                  rightX + frame.width <= visibleFrame.maxX - margin {
            adjusted.origin.x = max(frame.origin.x, rightX)
        } else {
            let belowY = panelFrame.minY - gap - frame.height
            let aboveY = panelFrame.maxY + gap
            if belowY >= visibleFrame.minY + margin {
                adjusted.origin.y = min(frame.origin.y, belowY)
            } else if aboveY + frame.height <= visibleFrame.maxY - margin {
                adjusted.origin.y = max(frame.origin.y, aboveY)
            }
        }

        return clamped(adjusted, to: visibleFrame)
    }

    private static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 20
        var clamped = frame
        clamped.origin.x = min(max(clamped.origin.x, visibleFrame.minX + margin),
                               visibleFrame.maxX - frame.width - margin)
        clamped.origin.y = min(max(clamped.origin.y, visibleFrame.minY + margin),
                               visibleFrame.maxY - frame.height - margin)
        return clamped
    }
}
