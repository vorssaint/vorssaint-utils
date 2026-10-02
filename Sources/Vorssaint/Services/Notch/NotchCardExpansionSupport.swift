// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum NotchCardExpansionSupport {
    /// A lifted card stays inside the page, including on the smallest preset.
    static func frame(card: CGRect, page: CGSize, preferred: CGSize) -> CGRect {
        let margin = min(8, max(0, min(page.width, page.height) / 2))
        let width = min(max(0, page.width - margin * 2), max(card.width, preferred.width))
        let height = min(max(0, page.height - margin * 2), max(card.height, preferred.height))
        let x = min(max(margin, card.midX - width / 2), max(margin, page.width - margin - width))
        let y = min(max(margin, card.midY - height / 2), max(margin, page.height - margin - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Transform the reader's page coordinates onto its source, independent of the layout box's centre.
    static func transitionTransform(card: CGRect, expanded: CGRect, progress: CGFloat) -> CGAffineTransform {
        let startX = card.width / max(1, expanded.width)
        let startY = card.height / max(1, expanded.height)
        let scaleX = startX + (1 - startX) * progress
        let scaleY = startY + (1 - startY) * progress
        let centerX = card.midX + (expanded.midX - card.midX) * progress
        let centerY = card.midY + (expanded.midY - card.midY) * progress
        return CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY,
                                 tx: centerX - expanded.midX * scaleX,
                                 ty: centerY - expanded.midY * scaleY)
    }

    static func hoverScale(enabled: Bool, hovered: Bool, reduceMotion: Bool) -> CGFloat {
        enabled && hovered && !reduceMotion ? 1.022 : 1
    }
}
