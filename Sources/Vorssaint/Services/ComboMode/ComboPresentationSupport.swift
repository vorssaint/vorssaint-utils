// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where the combo overlay shows. Mirrors the Command Bar's choice of window
/// or island (`NotchCommandBarStyle` / `CommandBarPresentation`): the island
/// is used only while Dynamic Island is on and can open, and the centered
/// panel takes its place otherwise.
enum ComboPresentation: String, CaseIterable, Identifiable {
    /// A panel in the middle of the screen, as combo mode always opened.
    case centered
    /// Inside the opened Dynamic Island.
    case island
    /// A small pill near the bottom of the screen.
    case chip

    var id: String { rawValue }

    static let defaultValue: ComboPresentation = .centered

    /// The stored preference; anything missing or unknown reads as centered,
    /// so an edited backup or a later version's value never hides the overlay.
    static func stored(_ raw: String?) -> ComboPresentation {
        raw.flatMap(ComboPresentation.init(rawValue:)) ?? defaultValue
    }

    /// What a combo opens with right now. The island needs Dynamic Island to
    /// be on; without it the overlay is centered, the way the Command Bar
    /// falls back to its own window.
    static func resolved(_ preferred: ComboPresentation, islandEnabled: Bool) -> ComboPresentation {
        preferred == .island && !islandEnabled ? .centered : preferred
    }

    /// Whether the overlay is drawn by its own key panel. Elsewhere an unseen
    /// key panel holds the keyboard while another surface shows the keys.
    var drawsInKeyPanel: Bool { self == .centered }
}

/// How many of a level's keys a compact surface lists. Past the limit the
/// last slot becomes a "+N" count, so the row never grows past it.
enum ComboHintLayout {
    /// The bottom pill: one row, read at a glance.
    static let chipLimit = 6
    /// The island: a short grid below the camera.
    static let islandLimit = 9

    /// The keys shown and how many are left out.
    static func window(total: Int, limit: Int) -> (shown: Int, more: Int) {
        let total = max(0, total)
        guard limit > 0 else { return (0, total) }
        guard total > limit else { return (total, 0) }
        let shown = limit - 1
        return (shown, total - shown)
    }
}
