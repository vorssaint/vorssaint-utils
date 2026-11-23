// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One colour per page, the tints its section already has elsewhere.
enum NotchTopBarPalette {
    static let clay = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let amber = Color(red: 1, green: 0.698, blue: 0.141)
    static let rose = Color(red: 1, green: 0.216, blue: 0.373)
    static let purple = Color(red: 0.749, green: 0.353, blue: 0.949)
    static let red = Color(red: 1, green: 0.271, blue: 0.227)
    static let tan = Color(red: 0.831, green: 0.639, blue: 0.451)
    static let yellow = Color(red: 1, green: 0.839, blue: 0.039)
    static let green = Color(red: 0.188, green: 0.82, blue: 0.345)
    static let blue = Color(red: 0.039, green: 0.518, blue: 1)
    static let orange = Color(red: 1, green: 0.624, blue: 0.039)
    static let gray = Color(red: 0.596, green: 0.596, blue: 0.616)
    /// Keep Awake while it is on: a bright red that reads from across the bar.
    static let awake = Color(red: 1, green: 0.33, blue: 0.42)

    /// Each item's colour at rest, before its live state shifts it.
    static func tint(_ item: NotchTopBarItem) -> Color {
        switch item {
        case .agents: return clay
        case .keepAwake: return amber
        case .music: return rose
        case .mixer: return purple
        case .calendar: return red
        case .clipboard: return tan
        case .scratchpad: return yellow
        case .microphone: return green
        case .system: return blue
        case .battery: return green
        case .settings: return gray
        }
    }

    /// Green, then yellow at a fifth and red at a tenth while on battery.
    static func battery(charge: Int?, charging: Bool) -> Color {
        guard let charge, !charging else { return green }
        return charge <= 10 ? red : charge <= 20 ? yellow : green
    }
}
