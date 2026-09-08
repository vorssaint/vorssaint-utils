// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum MenuPanelChromeLayout {
    static let panelPadding: CGFloat = 12
    static let spacing: CGFloat = 12
    static let sectionNavigationHeight: CGFloat = 38
    static let metricNavigationHeight: CGFloat = 24
    static let headerHeight: CGFloat = 36
    static let footerHeight: CGFloat = 34

    private static let legacyChromeHeight: CGFloat = 180

    static func height(navigationHeight: CGFloat,
                       measuredBannerHeight: CGFloat?,
                       showsBrandMark: Bool,
                       showsBetaControls: Bool = false,
                       showsFooterActions: Bool) -> CGFloat {
        let bannerHeight = measuredBannerHeight.map { max($0, 48) + spacing } ?? 0

        // Preserve the existing panel height when both rows are visible.
        if showsBrandMark, showsFooterActions {
            return legacyChromeHeight + bannerHeight
        }

        var height = panelPadding * 2 + navigationHeight + spacing + bannerHeight
        if showsBrandMark || showsBetaControls {
            height += headerHeight + spacing
        }
        if showsFooterActions {
            height += footerHeight + spacing
        }
        return height
    }
}
