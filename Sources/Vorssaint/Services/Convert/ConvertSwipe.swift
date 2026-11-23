// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A two-finger horizontal swipe over the converter's tiles. One swipe moves one page: it fires
/// once the fingers have travelled far enough sideways, then stays quiet until they lift and
/// the momentum that follows has run out.
struct ConvertSwipe {
    /// How far the fingers travel, in points, before the page changes.
    static let threshold = 44.0

    private var dx = 0.0
    private var dy = 0.0
    private var fired = false

    /// `step` is +1 for a swipe to the next page, -1 for the previous, 0 for none.
    /// `consumed` says the island should swallow the event, so nothing else reacts to it.
    /// `ended` is true on the last event of the fingers' phase or of the momentum.
    mutating func handle(deltaX: Double, deltaY: Double, began: Bool, ended: Bool,
                         momentum: Bool, precise: Bool, hasPhase: Bool, fingersMoveWithContent: Bool) -> (consumed: Bool, step: Int) {
        // A wheel or a mouse has no fingers to swipe with.
        guard precise, hasPhase || momentum else { self = ConvertSwipe(); return (false, 0) }
        if momentum {
            // The glide after a swipe that changed page belongs to that swipe, so it is swallowed too.
            let swallowed = fired
            if ended { self = ConvertSwipe() }
            return (swallowed, 0)
        }
        if began { self = ConvertSwipe() }
        if fired {
            // Lifting the fingers keeps `fired`: the momentum events come after the phase ends.
            return (true, 0)
        }
        defer { if ended { self = ConvertSwipe() } }
        dx += deltaX
        dy += deltaY
        guard abs(dx) > abs(dy) * 1.2 else { return (false, 0) }
        guard abs(dx) >= Self.threshold else { return (abs(dx) > 8, 0) }
        fired = true
        // With natural scrolling the content follows the fingers, so fingers moving left is dx < 0.
        let fingersLeft = fingersMoveWithContent ? dx < 0 : dx > 0
        return (true, fingersLeft ? 1 : -1)
    }
}
