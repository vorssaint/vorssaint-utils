// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure filtering for the Settings sidebar search field, so the matching
/// rules (case, accents, word prefixes) are covered by the unit harness.
enum SettingsSearchSupport {
    /// Case-, diacritic- and width-insensitive containment: "métr" finds
    /// "Metrics", "moni" finds "Monitor". A blank query matches everything.
    /// Keywords let a page match by what lives inside it ("lid" finds
    /// Energy, "quick panel" finds Quick tools), not just by its name.
    static func matches(query: String, title: String, keywords: [String] = []) -> Bool {
        let folded = fold(query)
        guard !folded.isEmpty else { return true }
        if fold(title).contains(folded) { return true }
        return keywords.contains { fold($0).contains(folded) }
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
