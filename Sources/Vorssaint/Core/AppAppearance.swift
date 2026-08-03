// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How the app paints its own windows. `system` follows the Mac's Appearance
/// setting, the other two keep the app light or dark whatever the Mac does.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    static let fallback: AppAppearance = .system

    /// A stored value from an older or hand-edited preference never breaks the
    /// picker; anything unknown falls back to following the system.
    static func sanitized(_ raw: String?) -> AppAppearance {
        guard let raw, let value = AppAppearance(rawValue: raw) else { return fallback }
        return value
    }

    func title(_ strings: AppearanceStrings) -> String {
        switch self {
        case .system: return strings.system
        case .light: return strings.light
        case .dark: return strings.dark
        }
    }
}
