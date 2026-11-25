// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Automatic preserves each menu bar reading's original weight. An explicit
/// choice applies to both labels and values, including rasterized blocks.
enum MenuBarFontWeight: String, CaseIterable {
    case automatic, regular, medium, semibold, bold

    static func current(in defaults: UserDefaults = .standard) -> MenuBarFontWeight {
        let raw = defaults.string(forKey: DefaultsKey.menuBarFontWeight) ?? ""
        return MenuBarFontWeight(rawValue: raw) ?? .automatic
    }

    func resolve(_ defaultWeight: NSFont.Weight) -> NSFont.Weight {
        switch self {
        case .automatic: return defaultWeight
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}
