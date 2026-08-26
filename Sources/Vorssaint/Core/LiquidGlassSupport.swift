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

    /// Whether Liquid Glass is enabled by user preference on a supported system.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard isSupported else { return false }
        return defaults.bool(forKey: DefaultsKey.liquidGlassEnabled)
    }
}
