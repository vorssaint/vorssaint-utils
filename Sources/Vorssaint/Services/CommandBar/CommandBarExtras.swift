// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreWLAN

/// Typing into whatever app has the caret. The bar never activates, so the
/// target still has focus; the only thing to wait for is the summoning chord
/// leaving the keyboard, or every character would land as a shortcut.
enum CommandBarTyping {
    static func post(text: String, attempt: Int) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if attempt >= 100 {
            NSSound.beep()
            return
        }
        guard held.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                post(text: text, attempt: attempt + 1)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard !IsSecureEventInputEnabled() else {
                NSSound.beep()
                return
            }
            TextSnippetService.postExpansion(deleteCount: 0,
                                             text: text,
                                             trailingKeyCode: nil,
                                             trailingFlags: [])
        }
    }
}

/// The things a person tries in a command bar on the first day: put the Mac to
/// sleep, restart it, turn Wi-Fi off, drop an emoji into what they are
/// writing, get today's date, open a folder they use every day.
///
/// Each one is small on purpose and nothing here runs, polls or holds a
/// resource while the bar is closed.
enum CommandBarExtras {
    // MARK: - Power

    /// What the Mac itself can be told to do. Everything below sleep asks
    /// first, in the bar, because losing unsaved work to a search field would
    /// be unforgivable.
    enum PowerAction: String, CaseIterable {
        case sleep, restart, shutDown, logOut

        var symbolName: String {
            switch self {
            case .sleep: return "moon.zzz"
            case .restart: return "arrow.clockwise.circle"
            case .shutDown: return "power"
            case .logOut: return "rectangle.portrait.and.arrow.right"
            }
        }

        /// Sleep is instant and harmless; the rest close everything, so they
        /// are confirmed on the row before anything happens.
        var needsConfirmation: Bool { self != .sleep }

        fileprivate var appleScript: String? {
            switch self {
            case .sleep: return nil
            case .restart: return "tell application \"System Events\" to restart"
            case .shutDown: return "tell application \"System Events\" to shut down"
            case .logOut: return "tell application \"System Events\" to log out"
            }
        }
    }

    /// Runs the action. Sleep goes through pmset, which needs no permission
    /// at all; the others go through the system's own Apple Event, the same
    /// one the Apple menu uses, and it asks the person to confirm on its own
    /// screen as well.
    static func run(_ action: PowerAction) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let script = action.appleScript else {
                _ = Shell.run("/usr/bin/pmset", ["sleepnow"])
                return
            }
            let result = AppleScriptRunner.runDetailed(script)
            if !result.ok {
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }

    // MARK: - Wi-Fi

    /// The last known Wi-Fi state, filled in by a background pass. The row
    /// reads this instead of asking CoreWLAN on the main thread: the query
    /// crosses to the Wi-Fi daemon, and the bar opens on a keystroke.
    static var cachedWiFiPower: Bool?

    /// Whether this Mac has a Wi-Fi interface at all, and whether it is on.
    /// Blocking; callers run it on a background queue.
    static func readWiFiPowerState() -> Bool? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        return interface.powerOn()
    }

    @discardableResult
    static func setWiFiPower(_ on: Bool) -> Bool {
        guard let interface = CWWiFiClient.shared().interface() else { return false }
        do {
            try interface.setPower(on)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Folders people live in

    /// A fixed set of destinations, not a file search: the folders every Mac
    /// has, opened in the Finder.
    static func standardFolders() -> [(name: String, url: URL)] {
        let manager = FileManager.default
        let directories: [(FileManager.SearchPathDirectory, String)] = [
            (.downloadsDirectory, "Downloads"),
            (.documentDirectory, "Documents"),
            (.desktopDirectory, "Desktop"),
            (.moviesDirectory, "Movies"),
            (.picturesDirectory, "Pictures"),
            (.musicDirectory, "Music"),
        ]
        var folders: [(name: String, url: URL)] = []
        for (directory, fallbackName) in directories {
            guard let url = manager.urls(for: directory, in: .userDomainMask).first else { continue }
            let name = manager.displayName(atPath: url.path)
            folders.append((name.isEmpty ? fallbackName : name, url))
        }
        let home = manager.homeDirectoryForCurrentUser
        folders.append((manager.displayName(atPath: home.path), home))
        folders.append((manager.displayName(atPath: "/Applications"),
                        URL(fileURLWithPath: "/Applications")))
        return folders
    }
}
