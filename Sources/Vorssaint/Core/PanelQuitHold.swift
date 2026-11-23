// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Timing for the menu panel's Quit button, which quits only after a hold.
enum PanelQuitHold {
    /// Long enough that a click, even a slow one, never quits.
    static let duration: Double = 0.8
    /// A small slip of the pointer while holding does not cancel the hold.
    static let maximumDrift: CGFloat = 20
    /// How long the "hold to quit" hint stays after a short click.
    static let hintLinger: Double = 1.6
}
