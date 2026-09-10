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

    /// Whether the digits may be registered as global hotkeys on a Super-key
    /// layer of this many modifiers. A layer narrowed to a single modifier
    /// turns them into ⌘1…⌘9 or ⌃1…⌃9: nothing global holds ⌘-digit, so
    /// RegisterEventHotKey would take it and preempt the tab switching every
    /// browser builds on it, and ⌃-digit is Mission Control's desktop
    /// switching. Both die everywhere while the toggle is on and nothing says
    /// why, so a one-modifier layer registers no digit at all. (A single
    /// digit can still collide with a system shortcut on a wider layer; that
    /// is caught per-digit at registration.)
    static func registersDigits(forModifierCount count: Int) -> Bool {
        count >= 2
    }

    /// One enabled system hotkey, reduced to what a digit collision needs: the
    /// key code and the Carbon modifier mask, both as `CopySymbolicHotKeys`
    /// reports them.
    struct SystemHotkey: Equatable {
        let keyCode: Int64
        let carbonModifiers: UInt32
    }

    /// Whether the digit's combination lands on an enabled system hotkey.
    /// `CopySymbolicHotKeys` reports the whole effective set — including the
    /// screenshot keys (⌘⇧3…6, ⌃⌘⇧3/4) and the other defaults that the
    /// `com.apple.symbolichotkeys` plist only lists once the user has
    /// customized them — so a digit sharing a combination with one is caught
    /// before it registers and fires alongside it.
    static func conflictsWithSystemHotkey(keyCode: Int64,
                                          carbonModifiers: UInt32,
                                          systemHotkeys: [SystemHotkey]) -> Bool {
        systemHotkeys.contains {
            $0.keyCode == keyCode && $0.carbonModifiers == carbonModifiers
        }
    }

    /// Why the digits are not all bound, for the one badge line the settings
    /// screen shows. `.ok` shows nothing.
    enum RegistrationStatus: Equatable {
        case ok
        /// These 1-based digits are a live system shortcut or were refused by
        /// macOS, so those numbers may not work. Carried so the badge can name
        /// exactly which ones. (A Super key narrowed to a single modifier binds
        /// no digits at all; the settings toggle shows that as an inactive,
        /// disabled state, so it needs no status of its own here.)
        case someUnavailable(digits: [Int])
    }

    /// The unavailable digits as a display list ("3, 4, 5, 6") for the badge.
    static func unavailableDigitsList(_ digits: [Int]) -> String {
        digits.map(String.init).joined(separator: ", ")
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
