// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MouseNavigationDirection: Hashable, CaseIterable {
    case back
    case forward
}

enum MouseNavigationSupport {
    /// CoreGraphics numbers the first two side buttons after left, right and
    /// middle as 3 and 4. These are what standard Back and Forward buttons on
    /// multi-button mice expose when another driver has not remapped them.
    static let backButtonNumber: Int64 = 3
    static let forwardButtonNumber: Int64 = 4

    static func direction(forButtonNumber buttonNumber: Int64) -> MouseNavigationDirection? {
        switch buttonNumber {
        case backButtonNumber: return .back
        case forwardButtonNumber: return .forward
        default: return nil
        }
    }

    /// What apps declare the two commands as. Where a keyboard cannot type it,
    /// macOS moves the shortcut elsewhere and `MouseNavigationKeys` reports
    /// where it landed.
    static func commandCharacter(for direction: MouseNavigationDirection) -> String {
        direction == .back ? "[" : "]"
    }

    /// A key equivalent read back from the system is only usable as a single
    /// visible character: anything else means the answer did not come, and the
    /// declared bracket is the better guess.
    static func sanitizedCommandCharacter(_ keyEquivalent: String) -> String? {
        guard keyEquivalent.count == 1,
              let scalar = keyEquivalent.unicodeScalars.first,
              !CharacterSet.whitespacesAndNewlines.contains(scalar),
              !CharacterSet.controlCharacters.contains(scalar) else { return nil }
        return keyEquivalent
    }

    /// Whether a menu item carries the command being looked for.
    ///
    /// Menus report their shortcut key in upper case, whatever case the app
    /// wrote it in, so the comparison cannot be literal: on keyboards where the
    /// system moves Back onto a letter, the menu says "Ö" for a command written
    /// as ö. Both sides are measured, not assumed.
    static func matchesCommand(menuCharacter: String?,
                               menuModifiers: UInt32?,
                               character: String,
                               modifiers: UInt32) -> Bool {
        guard let menuCharacter, let menuModifiers else { return false }
        return menuCharacter.uppercased() == character.uppercased() && menuModifiers == modifiers
    }

    /// The modifier value a menu reports for a shortcut, from the modifiers the
    /// system put on it. Zero means Command alone; the other bits are Shift,
    /// Option and Control, and the last one marks a shortcut without Command.
    /// A shortcut written with an upper case letter carries Shift even when
    /// nobody asked for it, which is how menus have always spelled it.
    static func menuModifiers(shift: Bool, option: Bool, control: Bool,
                              command: Bool, character: String) -> UInt32 {
        var value: UInt32 = 0
        if shift || isUpperCaseLetter(character) { value |= 1 }
        if option { value |= 2 }
        if control { value |= 4 }
        if !command { value |= 8 }
        return value
    }

    private static func isUpperCaseLetter(_ character: String) -> Bool {
        guard let first = character.first, first.isLetter else { return false }
        return first.isUppercase
    }

    /// The menu item to press for Back or Forward, the shortcut it carries,
    /// and whether it read enabled. For each shortcut the command may sit on,
    /// most likely first, `enabled` holds the first item found carrying it
    /// that read enabled, and `disabled` every item carrying it that read
    /// disabled.
    ///
    /// What a menu reports can trail the app: right after Forward, Finder and
    /// Safari still report Back as disabled for up to about a second, while
    /// their menu may already have it enabled. With no enabled item under any
    /// of the shortcuts, one that reads disabled is pressed all the same.
    /// AppKit carries out a press only when the app's menu has the item
    /// enabled at that moment, without validating it again, so an item that
    /// really is off stays untouched. It has to be the only item that carries
    /// any of the shortcuts, found by a search that read every menu: a key the
    /// Go menu kept from another keyboard can belong to another command, and
    /// an app can give an editing command the same key, so of two items either
    /// may be the one really enabled, and a search cut short may have missed
    /// the second. An enabled item under any shortcut comes first.
    static func itemToPress<Item>(enabled: [Item?], disabled: [[Item]], searchedInFull: Bool)
        -> (item: Item, shortcut: Int, readEnabled: Bool)? {
        if let index = enabled.firstIndex(where: { $0 != nil }), let item = enabled[index] {
            return (item, index, true)
        }
        let found = disabled.enumerated().flatMap { index, items in
            items.map { (shortcut: index, item: $0) }
        }
        guard searchedInFull, found.count == 1, let only = found.first else { return nil }
        return (only.item, only.shortcut, false)
    }

    /// Apps whose side buttons must reach them untouched. These handle Back
    /// and Forward themselves (or forward the raw press to a guest system),
    /// and none of them exposes the command as a menu bar item the AX path
    /// could press, so swallowing the click would silently drop navigation
    /// the user already had.
    static let passThroughBundleIDs: Set<String> = [
        // Virtualization and remote screens: the press belongs to the guest
        // or remote machine, not to a local menu command.
        "com.parallels.desktop.console",
        "com.vmware.fusion",
        "com.utmapp.UTM",
        "org.virtualbox.app.VirtualBoxVM",
        "com.apple.ScreenSharing",
        "com.microsoft.rdc.macos",
        "com.codeweavers.CrossOver",
        "com.isaacmarovitz.Whisky",
        "com.moonlight-stream.Moonlight",
    ]

    /// The browser family behind this prefix navigates with the side
    /// buttons natively on macOS and keeps Back and Forward out of the
    /// menu bar entirely. One prefix covers every release channel of the
    /// family, including its mail client.
    static let passThroughBundleIDPrefixes = ["org.mozilla."]

    static func nativeWebHandlers(urlHandlers: Set<String>,
                                  documentHandlers: Set<String>) -> Set<String> {
        urlHandlers.intersection(documentHandlers)
    }

    static func shouldRefreshWebHandlers(isApplicationActivation: Bool,
                                         activatedPID: pid_t?,
                                         ownPID: pid_t) -> Bool {
        !isApplicationActivation || activatedPID == ownPID
    }

    static func shouldPassThrough(bundleIdentifier: String?,
                                  webURLHandlers: Set<String> = []) -> Bool {
        guard let bundleIdentifier else { return false }
        if passThroughBundleIDs.contains(bundleIdentifier) { return true }
        if passThroughBundleIDPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return true
        }
        // Third-party browsers normally own Back and Forward themselves.
        // Apple apps stay on the menu-command path, including the system browser.
        return !bundleIdentifier.hasPrefix("com.apple.")
            && webURLHandlers.contains(bundleIdentifier)
    }
}
