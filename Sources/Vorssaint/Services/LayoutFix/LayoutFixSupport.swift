// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// One physical key with the modifiers that change what a layout types on it.
struct LayoutFixChord: Hashable {
    let keyCode: UInt16
    let shift: Bool
    let option: Bool
}

/// One keystroke as it was typed: the key, its modifiers and the layout that
/// was active, so the same keys can be shown in any other layout.
struct LayoutFixKey: Equatable {
    let keyCode: UInt16
    let shift: Bool
    let option: Bool
    let capsLock: Bool
    let layoutID: String

    var chord: LayoutFixChord { LayoutFixChord(keyCode: keyCode, shift: shift, option: option) }
}

/// An enabled keyboard layout reduced to what the fix needs: its id, the
/// language its words are checked in, and what each chord types with Caps
/// Lock off and on. Both tables come from the layout's own data, so custom
/// layouts and the number row of layouts like Kazakh are covered.
struct LayoutFixLayout: Equatable {
    let id: String
    let language: String
    let table: [LayoutFixChord: String]
    let capsTable: [LayoutFixChord: String]
}

/// The pure half of Layout Fix: key tables, the keystroke buffer, ranking of
/// the layouts a word could have been meant in, and the tap state machine.
/// Nothing here touches events, Accessibility or the text input server.
enum LayoutFixSupport {
    /// The keys of the main block. Higher codes are the keypad, function and
    /// navigation keys, which type the same thing in every layout.
    static let keyCodes = UInt16(0)...50

    // MARK: - Key tables

    /// What each chord of the layout types. Dead keys are read as their own
    /// character, and chords that type nothing or a control character are
    /// left out.
    static func table(from layoutData: Data, capsLock: Bool) -> [LayoutFixChord: String] {
        var table: [LayoutFixChord: String] = [:]
        layoutData.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for keyCode in keyCodes {
                for shift in [false, true] {
                    for option in [false, true] {
                        let modifiers = (shift ? shiftKey : 0) | (option ? optionKey : 0) | (capsLock ? alphaLock : 0)
                        var deadKeyState: UInt32 = 0
                        var length = 0
                        var characters = [UniChar](repeating: 0, count: 8)
                        let status = UCKeyTranslate(layout,
                                                    keyCode,
                                                    UInt16(kUCKeyActionDown),
                                                    UInt32(modifiers >> 8),
                                                    UInt32(LMGetKbdType()),
                                                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                                    &deadKeyState,
                                                    characters.count,
                                                    &length,
                                                    &characters)
                        guard status == noErr, length > 0 else { continue }
                        let text = String(utf16CodeUnits: characters, count: length)
                        guard !text.unicodeScalars.contains(where: {
                            CharacterSet.controlCharacters.contains($0)
                        }) else { continue }
                        table[LayoutFixChord(keyCode: keyCode, shift: shift, option: option)] = text
                    }
                }
            }
        }
        return table
    }

    // MARK: - Rendering

    static func render(_ key: LayoutFixKey, in layout: LayoutFixLayout) -> String? {
        (key.capsLock ? layout.capsTable : layout.table)[key.chord]
    }

    /// The keys as the layout types them, or nil when any key types nothing
    /// there: a partial word would be worse than no candidate.
    static func render(_ keys: [LayoutFixKey], in layout: LayoutFixLayout) -> String? {
        var text = ""
        for key in keys {
            guard let typed = render(key, in: layout) else { return nil }
            text += typed
        }
        return text
    }

    /// The keys as they appeared when typed: each in its own layout.
    static func renderOriginal(_ keys: [LayoutFixKey], layouts: [LayoutFixLayout]) -> String? {
        var text = ""
        for key in keys {
            guard let layout = layouts.first(where: { $0.id == key.layoutID }),
                  let typed = render(key, in: layout) else { return nil }
            text += typed
        }
        return text
    }

    /// The keys that type `text` in the layout, plain keys before Shift and
    /// Shift before Option, so a selection maps back the way a person would
    /// have typed it. Nil when any character has no key there.
    static func keys(for text: String, in layout: LayoutFixLayout) -> [LayoutFixKey]? {
        var reverse: [String: LayoutFixChord] = [:]
        let preference: [(shift: Bool, option: Bool)] = [(false, false), (true, false), (false, true), (true, true)]
        for (shift, option) in preference {
            for keyCode in keyCodes {
                let chord = LayoutFixChord(keyCode: keyCode, shift: shift, option: option)
                if let typed = layout.table[chord], reverse[typed] == nil {
                    reverse[typed] = chord
                }
            }
        }
        var keys: [LayoutFixKey] = []
        for character in text {
            guard let chord = reverse[String(character)] else { return nil }
            keys.append(LayoutFixKey(keyCode: chord.keyCode, shift: chord.shift, option: chord.option,
                                     capsLock: false, layoutID: layout.id))
        }
        return keys
    }

    /// The layout a selection was most likely typed in: the current one when
    /// it types every character, else the first in order that does.
    static func sourceLayout(for text: String, layouts: [LayoutFixLayout],
                             currentID: String?) -> LayoutFixLayout? {
        let covering = layouts.filter { keys(for: text, in: $0) != nil }
        return covering.first { $0.id == currentID } ?? covering.first
    }
}
