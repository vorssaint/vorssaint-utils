// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import Foundation

enum TextBaseDirection: Equatable {
    case leftToRight
    case rightToLeft
    case natural
}

/// Infers the base direction from the first strong alphabetic character,
/// ignoring bracketed teleprompter cues such as `[pause]`.
func textBaseDirection(in text: String) -> TextBaseDirection {
    var isInsideAnnotation = false

    for scalar in text.unicodeScalars {
        if scalar == "[" {
            isInsideAnnotation = true
            continue
        }
        if scalar == "]", isInsideAnnotation {
            isInsideAnnotation = false
            continue
        }
        guard !isInsideAnnotation, scalar.properties.isAlphabetic else { continue }
        return isRightToLeftScript(scalar) ? .rightToLeft : .leftToRight
    }

    return .natural
}

private func isRightToLeftScript(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x0590...0x05FF,   // Hebrew
         0x0600...0x06FF,   // Arabic
         0x0700...0x074F,   // Syriac
         0x0750...0x077F,   // Arabic Supplement
         0x0780...0x07BF,   // Thaana
         0x07C0...0x07FF,   // NKo
         0x0800...0x083F,   // Samaritan
         0x0840...0x085F,   // Mandaic
         0x0870...0x089F,   // Arabic Extended-B
         0x08A0...0x08FF,   // Arabic Extended-A
         0xFB50...0xFDFF,   // Arabic Presentation Forms-A
         0xFE70...0xFEFF,   // Arabic Presentation Forms-B
         0x1E800...0x1E8DF, // Mende Kikakui
         0x1E900...0x1E95F, // Adlam
         0x1EE00...0x1EEFF: // Arabic Mathematical Alphabetic Symbols
        return true
    default:
        return false
    }
}
