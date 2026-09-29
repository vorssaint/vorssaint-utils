// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Color conversion for the command bar: "#a2b3b4 to rgb". Strict like
/// `CommandBarUnits`: anything else is left to the search.
enum CommandBarColors {
    struct Result: Equatable {
        let color: ColorValue
        let formatted: String
    }

    /// The `a` forms always write alpha; the others only for a translucent color.
    private static let targets: [String: (format: ColorCopyFormat, alwaysAlpha: Bool)] = [
        "hex": (.hex, false),
        "rgb": (.rgb, false), "rgba": (.rgb, true),
        "hsl": (.hsl, false), "hsla": (.hsl, true),
        "swift": (.swiftui, false), "swiftui": (.swiftui, false),
    ]

    /// The conversion for `input`, or nil when it is not one.
    static func convert(_ input: String) -> Result? {
        guard input.utf8.count <= ColorValue.maxLength + 16 else { return nil }
        let tokens = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 3,
              CommandBarUnits.conversionWords.contains(tokens[tokens.count - 2].lowercased()),
              let target = targets[tokens[tokens.count - 1].lowercased()],
              let color = ColorValue(text: tokens.dropLast(2).joined(separator: " "))
        else { return nil }
        let alpha = target.alwaysAlpha || color.alpha < 1 ? color.alpha : nil
        return Result(color: color,
                      formatted: ColorValue.string(red: color.red, green: color.green, blue: color.blue,
                                                   alpha: alpha, format: target.format))
    }
}
