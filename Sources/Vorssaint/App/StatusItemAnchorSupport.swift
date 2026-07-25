// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure geometry for anchoring the panel to a status item whose window frame
/// may be lying. macOS 27 can leave a (re)created status item's window frame
/// stranded at the slot it was born in (the far right of the status area)
/// while the icon is drawn — and clicked — at the user's arranged spot, and
/// the mismatch survives relaunches. A popover anchored through that frame
/// opens against the screen edge instead of under the icon. The click that is
/// opening the panel is the one position the window server vouches for, so it
/// outranks the reported frame when the two clearly disagree.
///
/// A menu bar set to hide itself parks that same window outside the visible
/// area once the bar slides away, which strands the panel in the same way the
/// moment its content changes height. Both cases are handled by pinning the
/// panel to an anchor captured while the bar was still up.
enum StatusItemAnchorSupport {
    /// Slack past the button's half-width before a click counts as drift: a
    /// click anywhere inside the button must never trigger a correction, and
    /// the margin absorbs the item's expanded hit area plus a sloppy click on
    /// its edge. A genuinely stale frame sits a hundred points or more away.
    static let clickDriftSlack: Double = 24

    /// How far the popover's positioning rect must shift on x so the panel
    /// anchors at the click, or nil when the click agrees with the reported
    /// frame (the healthy case, which must stay byte-for-byte untouched).
    static func anchorDriftX(clickX: Double,
                             reportedMidX: Double,
                             buttonWidth: Double) -> Double? {
        let drift = clickX - reportedMidX
        guard abs(drift) > buttonWidth / 2 + clickDriftSlack else { return nil }
        return drift
    }

    /// How far down from the top of a screen a status item's window can sit and
    /// still describe a menu bar. Clears the taller bar drawn around a camera
    /// housing with room to spare, while staying far from any ordinary window.
    static let menuBarBand: CGFloat = 48

    /// Breathing room kept between the panel and the edges of the usable area.
    static let panelEdgeMargin: CGFloat = 8

    /// Whether a status item's reported window frame is worth anchoring to.
    /// A bar that hides itself parks its window out of the visible area, so
    /// the frame still exists but points nowhere, and a panel positioned
    /// through it collapses into a screen corner. A frame only counts when it
    /// has real size and its middle sits in the bar band of an attached screen.
    static func isTrustworthyStatusFrame(_ frame: CGRect,
                                         screenFrames: [CGRect],
                                         band: CGFloat = menuBarBand) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        return screenFrames.contains { screen in
            guard screen.intersects(frame) else { return false }
            return frame.midY <= screen.maxY && frame.midY >= screen.maxY - band
        }
    }

    /// Where an open panel belongs for a cached anchor: centered on the
    /// anchor's horizontal middle with its top edge held, so content that
    /// grows or shrinks (switching panel tabs) extends downward instead of
    /// being placed again from a status item frame that may since have been
    /// parked away. Kept inside the usable area with a margin.
    static func pinnedPanelFrame(size: CGSize,
                                 anchorMidX: CGFloat,
                                 anchorTop: CGFloat,
                                 visibleFrame: CGRect,
                                 margin: CGFloat = panelEdgeMargin) -> CGRect {
        let lowestMidX = visibleFrame.minX + size.width / 2 + margin
        let highestMidX = visibleFrame.maxX - size.width / 2 - margin
        let midX = lowestMidX <= highestMidX
            ? min(max(anchorMidX, lowestMidX), highestMidX)
            : visibleFrame.midX
        // A screen too short to hold the panel keeps it at the top; the panel
        // caps its own height, so the overflow only shows on odd layouts.
        let lowestTop = visibleFrame.minY + size.height + margin
        let top = lowestTop <= visibleFrame.maxY
            ? min(max(anchorTop, lowestTop), visibleFrame.maxY)
            : visibleFrame.maxY
        return CGRect(x: (midX - size.width / 2).rounded(),
                      y: (top - size.height).rounded(),
                      width: size.width,
                      height: size.height)
    }
}
