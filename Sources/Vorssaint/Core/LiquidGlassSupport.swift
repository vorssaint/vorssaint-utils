// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Detection and settings gate for Liquid Glass visuals on macOS 26 and later.
enum LiquidGlassSupport {
    /// Whether the host operating system supports native Liquid Glass.
    static var isSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    /// Select the preference for the surface that owns the mixer.
    static func isEnabled(inNotch: Bool, windows: Bool, island: Bool) -> Bool {
        guard isSupported else { return false }
        return inNotch ? island : windows
    }
}
