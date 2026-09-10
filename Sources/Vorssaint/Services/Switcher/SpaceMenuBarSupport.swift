// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure helpers for the optional menu bar Space digit.
///
/// Numbering matches Mission Control's left-to-right row for one display:
/// 1-based index of `current` in that display's `spaces` array. Fullscreen
/// Spaces stay in that row, so a fullscreen desktop keeps its full-row index
/// rather than being renumbered among ordinary desktops only.
enum SpaceMenuBarSupport {
    struct DisplayRow {
        let id: CGDirectDisplayID?
        let spaces: [UInt64]
        let current: UInt64?
    }

    /// 1-based index of `current` in `spaces`, or nil when it is missing.
    static func number(current: UInt64?, spaces: [UInt64]) -> Int? {
        guard let current, let index = spaces.firstIndex(of: current) else { return nil }
        return index + 1
    }

    /// Picks the Spaces row for the display that owns the menu bar. When that
    /// id is unknown, falls back to the first display so a single digit still
    /// appears on multi-display setups.
    static func row(forMenuBarDisplayID menuBarDisplayID: CGDirectDisplayID?,
                    displays: [DisplayRow]) -> DisplayRow? {
        if let menuBarDisplayID,
           let match = displays.first(where: { $0.id == menuBarDisplayID }) {
            return match
        }
        return displays.first
    }

    static func row(forMenuBarDisplayID menuBarDisplayID: CGDirectDisplayID?,
                    displays: [(id: CGDirectDisplayID?, spaces: [UInt64], current: UInt64?)]) -> DisplayRow? {
        row(forMenuBarDisplayID: menuBarDisplayID,
            displays: displays.map { DisplayRow(id: $0.id, spaces: $0.spaces, current: $0.current) })
    }
}
