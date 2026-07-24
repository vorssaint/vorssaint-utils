// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The pure half of the mouse button shortcuts feature: which buttons can
/// carry a shortcut, how the mappings persist and who owns a button when two
/// features could answer the same click.
enum MouseButtonShortcutSupport {
    /// Buttons a shortcut can live on. CoreGraphics numbers left, right and
    /// middle as 0, 1 and 2; everything from 3 up is an extra button (3 and 4
    /// are the standard Back and Forward side buttons). Left and right never
    /// arrive as extra-button events, and the middle button stays with its
    /// own feature, so mappings start at 3.
    static let buttonRange: ClosedRange<Int64> = 3...31

    static let backButtonNumber: Int64 = 3
    static let forwardButtonNumber: Int64 = 4

    static func canMap(_ button: Int64) -> Bool {
        buttonRange.contains(button)
    }

    /// Mappings persist as a plain dictionary of button number to the same
    /// storage form every other shortcut in the app uses. Anything that does
    /// not parse (a hand-edited plist, an imported backup from a newer
    /// version) is dropped rather than trusted.
    static func decode(_ raw: [String: String]?) -> [Int64: GlobalShortcut] {
        guard let raw else { return [:] }
        var mappings: [Int64: GlobalShortcut] = [:]
        for (key, value) in raw {
            guard let button = Int64(key), canMap(button),
                  let shortcut = GlobalShortcut(storageValue: value) else { continue }
            mappings[button] = shortcut
        }
        return mappings
    }

    static func encode(_ mappings: [Int64: GlobalShortcut]) -> [String: String] {
        var raw: [String: String] = [:]
        for (button, shortcut) in mappings where canMap(button) {
            raw[String(button)] = shortcut.storageValue
        }
        return raw
    }

    /// Whether a button fires its shortcut right now, given plain readers so
    /// the rule is testable without touching real defaults. The radial menu
    /// keeps its summoner: a wheel button never doubles as a shortcut.
    static func firesShortcut(for button: Int64,
                              isAvailable: Bool,
                              isEnabled: Bool,
                              mappings: [Int64: GlobalShortcut],
                              claimedByWheel: (Int64) -> Bool) -> GlobalShortcut? {
        guard isAvailable, isEnabled, !claimedByWheel(button) else { return nil }
        return mappings[button]
    }

    /// Whether this feature currently owns the button. Mouse navigation asks
    /// this from its own tap and lets an owned button through, the same
    /// contract it already keeps with the radial menu; pure defaults reads,
    /// so asking never wakes the service.
    static func claimsButton(_ button: Int64) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppFeature.mouseButtonShortcuts.availabilityKey),
              defaults.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled),
              !RadialMenuSupport.claimsMouseButton(button) else { return false }
        // Runs inside a HID tap callback during side-button drags: look up
        // just this button's entry instead of decoding the whole dictionary.
        guard canMap(button) else { return false }
        let raw = defaults.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String]
        guard let stored = raw?[String(button)] else { return false }
        return GlobalShortcut(storageValue: stored) != nil
    }

    /// The rows in Settings sort by button number so the list never reorders
    /// itself between visits.
    static func sortedButtons(_ mappings: [Int64: GlobalShortcut]) -> [Int64] {
        mappings.keys.sorted()
    }

    /// What a button is called across the feature: the two standard side
    /// buttons by their job, anything above by the count printed on mouse
    /// software (button number 5 is the sixth button of the mouse).
    static func buttonName(for button: Int64, strings: MouseButtonFeatureStrings) -> String {
        switch button {
        case backButtonNumber: return strings.backButtonName
        case forwardButtonNumber: return strings.forwardButtonName
        default: return String(format: strings.otherButtonFormat, Int(button) + 1)
        }
    }
}
