// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MouseNavigationDirection: Equatable {
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

    static func commandCharacter(for direction: MouseNavigationDirection) -> String {
        direction == .back ? "[" : "]"
    }
}
