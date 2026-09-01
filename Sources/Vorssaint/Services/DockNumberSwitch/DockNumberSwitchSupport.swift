// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The pure decisions behind Dock number keys, kept out of the service so a
/// test can reach them without a live Dock: which tiles count as apps, and
/// which app a digit lands on.
enum DockNumberSwitchSupport {
    /// The digit keys the feature binds, 1…9.
    static let slotCount = 9

    /// The Accessibility subrole every application tile carries. Folders,
    /// stacks, separators, minimized-window tiles and the Trash carry a
    /// different one, so this is what tells an app apart from the rest.
    static let applicationSubrole = "AXApplicationDockItem"

    /// One Dock tile as far as this feature cares: its subrole and the file URL
    /// it points at.
    struct Tile {
        let subrole: String?
        let url: URL?
    }

    /// The URLs of the application tiles, in the order given — so a digit counts
    /// what the user sees as apps (Finder first), skipping everything else.
    static func applicationURLs(from tiles: [Tile]) -> [URL] {
        tiles.compactMap { tile in
            guard tile.subrole == applicationSubrole, let url = tile.url else { return nil }
            return url
        }
    }

    /// The app for a 1-based digit, or nil when nothing sits at that position —
    /// a Dock with fewer apps than the digit, or one that could not be read.
    static func target(in urls: [URL], slot: Int) -> URL? {
        guard slot >= 1, slot <= urls.count else { return nil }
        return urls[slot - 1]
    }

    /// What pressing the digit does with the app behind it.
    enum Action {
        /// Bring the app to the front, launching it first if it is not running.
        case activateOrLaunch
        /// Walk the app's windows: it is already the app the user is in, so the
        /// press means "next window" rather than "switch here", matching
        /// macOS ⌘`.
        case cycleWindows
    }

    /// Cycle only when the app is already frontmost; otherwise switch to (or
    /// launch) it. Keeping this a pure decision lets a test pin the branch.
    static func action(appIsFrontmost: Bool) -> Action {
        appIsFrontmost ? .cycleWindows : .activateOrLaunch
    }
}
