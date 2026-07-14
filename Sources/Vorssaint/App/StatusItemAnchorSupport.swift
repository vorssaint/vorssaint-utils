// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure geometry for anchoring the panel to a status item whose window frame
/// may be lying. macOS 27 can leave a (re)created status item's window frame
/// stranded at the slot it was born in (the far right of the status area)
/// while the icon is drawn — and clicked — at the user's arranged spot, and
/// the mismatch survives relaunches. A popover anchored through that frame
/// opens against the screen edge instead of under the icon. The click that is
/// opening the panel is the one position the window server vouches for, so it
/// outranks the reported frame when the two clearly disagree.
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
}
