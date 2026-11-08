// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The app's own accent colour, stored as one `#RRGGBB` preference.
///
/// An empty value means "follow the Mac", which is the default: with nothing
/// stored the app paints its windows with the system accent colour exactly as
/// before, and only a chosen colour changes what `Color.accentColor` resolves
/// to (see `AppAccentTint`).
///
/// Kept as a hex string so it can travel in a settings backup and be validated
/// through the shared hex support, rather than storing a `Color` that cannot
/// round-trip through `UserDefaults`.
enum AppAccentColor {
    /// A stored `#RRGGBB` value, or nil when the app should follow the Mac.
    /// Anything malformed falls back to following the system instead of
    /// painting an invalid colour; the normalisation is shared with the
    /// usage-bar colours so a preference is validated in exactly one place.
    static func sanitized(_ raw: String?) -> String? {
        guard let raw, let normalized = MenuBarUsageBarSupport.normalizedColorHex(raw),
              !normalized.isEmpty
        else { return nil }
        return normalized
    }

    /// What is actually stored, read through the same validation so a
    /// hand-edited or older preference cannot reach the UI. `defaults` is
    /// injectable so the resolver can be pinned down in tests without
    /// touching the real domain.
    static func storedHex(defaults: UserDefaults = .standard) -> String? {
        sanitized(defaults.string(forKey: DefaultsKey.appAccentColor))
    }

    /// The `#RRGGBB` written for a colour the user picked.
    static func hex(red: Double, green: Double, blue: Double) -> String {
        MenuBarUsageBarSupport.hex(red: red, green: green, blue: blue)
    }

    /// One colour the appearance menu offers.
    ///
    /// The case comes from `RadialMenuColor` so a swatch is named with the
    /// app's existing, already translated colour vocabulary rather than a
    /// second set of names. The hex is spelled out here because the app accent
    /// has to be one fixed colour that survives a settings backup, while the
    /// radial menu resolves its colours per light/dark scheme.
    struct Preset: Identifiable, Equatable {
        let color: RadialMenuColor
        let hex: String

        var id: String { color.rawValue }
    }

    /// The colours offered, in menu order. `RadialMenuColor.accent` is left
    /// out on purpose: it means "whatever the app accent is", which is the
    /// thing being chosen here.
    static let presets: [Preset] = [
        Preset(color: .blue, hex: "#007AFF"),
        Preset(color: .purple, hex: "#AF52DE"),
        Preset(color: .pink, hex: "#FF2D55"),
        Preset(color: .red, hex: "#FF3B30"),
        Preset(color: .orange, hex: "#FF9500"),
        Preset(color: .yellow, hex: "#FFCC00"),
        Preset(color: .green, hex: "#28CD41"),
        Preset(color: .mint, hex: "#00C7BE"),
        Preset(color: .cyan, hex: "#30B0C7"),
        Preset(color: .indigo, hex: "#5856D6"),
        Preset(color: .graphite, hex: "#8E8E93"),
    ]

    /// Whether a stored value already names this preset, compared through the
    /// same normalisation the store uses so case and spacing never matter.
    static func matches(_ storedHex: String?, preset: Preset) -> Bool {
        guard let stored = sanitized(storedHex) else { return false }
        return stored == sanitized(preset.hex)
    }
}
