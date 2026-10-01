// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

extension Color {
    /// What the island draws in white. The island is always dark, where this is
    /// exactly white; its pages shown in the menu panel follow the panel's
    /// appearance instead.
    static let notchInk = Color(nsColor: NSColor(name: "notchInk") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    })
    /// What sits on a solid notchInk fill, such as the play button's symbol.
    static let notchInkInverse = Color(nsColor: NSColor(name: "notchInkInverse") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })
}
