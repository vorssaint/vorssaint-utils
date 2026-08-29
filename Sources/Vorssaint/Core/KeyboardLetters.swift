// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// What a keystroke means to a shortcut, on every layout.
///
/// A keyboard answers by the letter it types, so a shortcut stays on the key
/// it is printed on even where the layout moves it: AZERTY puts A where ANSI
/// has Q, Turkish moves both. Layouts that type no Latin letter at all, like
/// Cyrillic and Greek, have no letter to answer with, so the key's position
/// stands in — which is where macOS resolves those layouts' own command
/// shortcuts anyway.
enum KeyboardLetters {
    /// The plain letter a keystroke typed, when it typed one. Accents fold
    /// away, so a letter of a Latin alphabet is never mistaken for one of the
    /// keys a panel claims.
    static func latinLetter(in text: String?) -> Character? {
        guard let folded = text?.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                         locale: .current),
              folded.count == 1,
              let letter = folded.first,
              letter.isASCII,
              letter.isLetter
        else { return nil }
        return letter
    }

    /// The character a key types on a US keyboard: the letters, plus the
    /// comma the Command Bar claims for Settings.
    static func usPositionCharacter(for keyCode: Int) -> Character? {
        switch keyCode {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_ANSI_Comma: return ","
        default: return nil
        }
    }

    /// The character a shortcut should be matched against: the letter the key
    /// prints, the character itself when it prints punctuation the keyboard
    /// owns outright, and the key's US position when it prints neither.
    ///
    /// The middle rule is what keeps AZERTY's comma, which sits on the ANSI M
    /// key, from being read as a ⌘M the app's menu would swallow.
    static func shortcutCharacter(typedCharacter: String?, keyCode: Int) -> Character? {
        if let letter = latinLetter(in: typedCharacter) { return letter }
        if let typed = typedCharacter, typed.count == 1, let character = typed.first,
           character.isASCII, !character.isLetter, !character.isWhitespace {
            return character
        }
        return usPositionCharacter(for: keyCode)
    }
}
