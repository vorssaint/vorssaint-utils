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
}

/// Pure filtering for the Settings sidebar search field, so the matching
/// rules (case, accents, word prefixes) are covered by the unit harness.
enum SettingsSearchSupport {
    private enum MatchRank {
        case exactTitle
        case title
        case keyword
    }

    /// Every feature contributes its localized hub name and exact Settings
    /// destination. The feature case remains the stable result identity.
    static func featureItems(title: (AppFeature) -> String) -> [SettingsSearchItem] {
        AppFeature.allCases.map { feature in
            SettingsSearchItem(id: .feature(feature),
                               destination: feature.settingsDestination,
                               title: title(feature),
                               icon: feature.symbolName)
        }
    }

    /// A dedicated page row wins over a generated feature row only when both
    /// its visible name and full destination are equivalent. This keeps a
    /// single explicit Homebrew result while preserving differently named
    /// fallbacks such as Disk Image Installer -> Features.
    static func combinedItems(pageItems: [SettingsSearchItem],
                              featureItems: [SettingsSearchItem]) -> [SettingsSearchItem] {
        pageItems + featureItems.filter { featureItem in
            !pageItems.contains { pageItem in
                pageItem.destination == featureItem.destination
                    && fold(pageItem.title) == fold(featureItem.title)
            }
        }
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

    /// Every former screen-tool page remains discoverable after those settings
    /// move behind the single Screen capture destination.
    static func screenCaptureKeywords(_ strings: Strings,
                                      language: AppLanguage) -> [String] {
        let screenshot = FeatureStrings.screenshot(language)
        let recorder = FeatureStrings.recorder(language)
        return [
            screenshot.pageTitle,
            recorder.pageTitle,
            strings.ocrName,
            strings.colorPickerName,
            screenshot.freezeToggle,
            screenshot.fullScreenShortcutTitle,
            screenshot.previewPositionLabel,
            screenshot.pinButton,
            screenshot.toolPixelate,
            screenshot.toolArrow,
            recorder.startButton,
            recorder.systemAudioToggle,
            recorder.microphoneToggle,
            recorder.qualityLabel,
            recorder.frameRateLabel,
            strings.ocrQRToggle,
            strings.colorPickerFormatLabel,
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
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
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

    /// A saved size wins when it is at least the minimum (0 means unset);
    /// otherwise the tall default, capped to the screen's available height.
    static func initialContentSize(savedWidth: Double, savedHeight: Double,
                                   availableHeight: Double) -> (width: Double, height: Double) {
        if savedWidth >= minContentWidth, savedHeight >= minContentHeight {
            return (savedWidth, savedHeight)
        }
        let height = min(preferredContentHeight, max(availableHeight, minContentHeight))
        return (minContentWidth, height)
    }
}
