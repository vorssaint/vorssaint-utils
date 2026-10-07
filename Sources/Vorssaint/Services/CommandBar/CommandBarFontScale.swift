// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// How big the bar's own type reads: one multiplier laid over every point
/// size in the panel, from the 8 pt footer glyphs to the 17 pt answer row.
/// Raw values are the stored preference, so they never change.
///
/// A preset stores its name. A size typed by hand in Settings stores the
/// factor as a decimal string ("1.15"), and `factor(from:)` is what lets the
/// two shapes share one key — a wrong spelling must not blank the bar, so
/// anything unreadable is the medium default.
enum CommandBarFontScale: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case huge

    var id: String { rawValue }

    /// The multiplier every point size is asked through. The medium step is
    /// 1.0, so the bar out of the box is exactly the bar that was there
    /// before the setting existed.
    var factor: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.2
        case .huge: return 1.4
        }
    }

    /// How far a hand-typed factor may go, in either direction. Past the top
    /// the rows stop fitting the panel's fixed width; below the bottom the
    /// micro-glyphs stop being legible at all.
    static let range: ClosedRange<Double> = 0.85...1.6

    /// How a stored preference reads back as a preset. A hand-typed number
    /// is not a preset; anything unknown is the default.
    static func resolved(raw: String?) -> CommandBarFontScale {
        CommandBarFontScale(rawValue: raw ?? "") ?? .medium
    }

    /// The factor a stored preference resolves to. A named preset gives its
    /// constant, a decimal string is clamped into `range`, and anything
    /// unknown is the medium default.
    static func factor(from raw: String?) -> CGFloat {
        if let preset = CommandBarFontScale(rawValue: raw ?? "") { return preset.factor }
        guard let value = Double(raw ?? ""), value.isFinite else { return medium.factor }
        return CGFloat(clamped(value))
    }

    /// A hand-typed factor held inside the range. Pure so the tests can pin
    /// it.
    static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// How far the panel's own frame follows the type: half of the type's
    /// growth, so Huge reads as a bigger bar rather than a different one —
    /// the full 1.4 next to a fixed 560 pt width is what crowds the rows.
    /// Pure so the tests can pin it.
    static func layoutScale(from raw: String?) -> CGFloat {
        1 + (factor(from: raw) - 1) * 0.5
    }
}
