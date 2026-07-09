// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure math for the extra brightness boost, kept free of AppKit and Metal so
/// the unit tests can pin its behavior.
///
/// The boost is a fullscreen overlay whose Metal layer composites with a
/// multiply filter: every pixel beneath is multiplied by a gray above 1.0 in
/// extended range, which pushes regular content into the brightness the XDR
/// panel reserves for HDR. Blacks stay black and contrast is preserved, since
/// multiplication only scales.
enum ExtraBrightnessSupport {
    /// The largest multiplier worth applying: XDR panels top out near twice
    /// the SDR reference, and pushing past the real headroom only clips.
    static let factorCap: Double = 2.0

    /// The overlay needs to show extended range content before macOS engages
    /// the panel's headroom, so the first frame renders this small boost;
    /// polling then ramps to the real factor as the headroom rises.
    static let engagementFactor: Double = 1.12

    /// The panel has real headroom past this (values near 1 are noise).
    static let headroomThreshold: Double = 1.05

    /// Whether a built-in panel can truly exceed its SDR brightness. Only the
    /// XDR (mini LED) panels of the 14 and 16 inch MacBook Pro can; Air and
    /// older panels report EDR potential too, but they fake headroom by
    /// dimming everything else, which would darken the screen instead of
    /// brightening it. The XDR token is part of the product name and survives
    /// localization, and it covers future XDR MacBooks without a model list.
    static func isXDRPanelName(_ localizedName: String) -> Bool {
        localizedName.localizedCaseInsensitiveContains("XDR")
    }

    /// How strong the multiplier is for a user level of 0...1 given the
    /// display's currently available EDR headroom. Level 0 means no boost;
    /// level 1 uses all the headroom the panel reports, capped for sanity.
    static func boostFactor(level: Double, maxEDR: Double) -> Double {
        let clampedLevel = min(max(level, 0), 1)
        let usableHeadroom = min(max(maxEDR, 1.0), factorCap)
        return 1 + clampedLevel * (usableHeadroom - 1)
    }

    /// The factor the overlay should render right now: before the panel
    /// engages its headroom only the small engagement boost is shown (enough
    /// extended range content to make macOS turn the headroom on), afterwards
    /// the level maps into whatever headroom is actually available.
    static func renderFactor(level: Double, currentEDR: Double) -> Double {
        guard currentEDR > headroomThreshold else {
            return min(engagementFactor, max(boostFactor(level: level, maxEDR: factorCap), 1.0))
        }
        return boostFactor(level: level, maxEDR: currentEDR)
    }
}
