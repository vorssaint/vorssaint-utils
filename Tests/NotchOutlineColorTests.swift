// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchOutlineColorTests {
    private static let white = Defaults.defaultNotchOutlineColor

    static func run(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchOutlineColor] as? String == "#FFFFFF",
                     "the island outline starts white so nobody sees a colour they did not pick")

        for raw in [nil, "", "purple", "#GGGGGG", "#FFF", " ", "#A020F"] as [String?] {
            suite.expect(MenuBarUsageBarSupport.sanitizedColorHex(raw, fallback: white) == "#FFFFFF",
                         "an unusable outline colour falls back to white instead of drawing nothing")
        }

        for raw in ["#a020f0", "a020f0", " #A020F0 "] {
            suite.expect(MenuBarUsageBarSupport.sanitizedColorHex(raw, fallback: white) == "#A020F0",
                         "a typed outline colour is stored in one uppercase hashed form")
        }

        for hex in ["#FFFFFF", "#000000", "#A020F0", "#123456"] {
            let rgb = MenuBarUsageBarSupport.rgb(for: hex, fallback: white)
            suite.expect(MenuBarUsageBarSupport.hex(red: rgb.red, green: rgb.green, blue: rgb.blue) == hex,
                         "an outline colour survives the trip through the drawing components unchanged")
        }

        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchOutlineWidth] as? Double == 2,
                     "the island outline starts at its old 2 pt so no existing island changes shape")

        suite.expect(Defaults.allowedNotchOutlineWidthRange == 1.0...6.0,
                     "an outline thin enough to vanish or thick enough to swallow the island is out of reach")
        suite.expect(Defaults.allowedNotchOutlineWidthRange.contains(Defaults.defaultNotchOutlineWidth),
                     "the shipped outline width is a width the user could have picked themselves")

        for raw in [0.4, 0, -3, 12] as [Double] {
            let clamped = min(max(raw, Defaults.allowedNotchOutlineWidthRange.lowerBound),
                              Defaults.allowedNotchOutlineWidthRange.upperBound)
            suite.expect(Defaults.allowedNotchOutlineWidthRange.contains(clamped),
                         "a stored width from an older build or a stray write still draws a visible outline")
        }
    }
}
