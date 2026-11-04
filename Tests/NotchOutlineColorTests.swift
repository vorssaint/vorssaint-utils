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
    }
}
