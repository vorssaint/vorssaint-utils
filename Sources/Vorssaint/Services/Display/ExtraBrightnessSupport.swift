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
    /// The overlay needs to show extended range content before macOS engages
    /// the panel's headroom, so the first frame renders this small boost;
    /// polling then ramps to the real factor as the headroom rises.
    static let engagementFactor: Double = 1.10

    /// The panel has real headroom past this (values near 1 are noise).
    static let headroomThreshold: Double = 1.05

    /// Panels that only fake EDR by dimming the rest of the screen (every
    /// MacBook Air, the Intel MacBook Pro, the iMac) report a potential
    /// headroom of exactly 2.0; true XDR panels report far above it (16.0
    /// at the default preset). Anything past this floor is real headroom.
    static let capabilityFloor: Double = 2.05

    /// Every Mac model with a built-in mini LED XDR panel: the 14 and 16 inch
    /// MacBook Pro, M1 Pro/Max through M5 generations. A known model is
    /// trusted outright so support never hinges on what headroom the current
    /// preset happens to report.
    static let xdrModelIdentifiers: Set<String> = [
        // 2021 14"/16" (M1 Pro/Max)
        "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
        // 2023 14"/16" (M2 Pro/Max)
        "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10",
        // 2023 14"/16" (M3, M3 Pro/Max)
        "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
        // 2024 14"/16" (M4, M4 Pro/Max)
        "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8",
        // 2025 14"/16" (M5 generation)
        "Mac17,2", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9",
    ]

    /// AppKit names every built-in panel "Built-in Retina Display" or
    /// "Built-in Display" regardless of the hardware, so the XDR product
    /// name never reaches NSScreen today (requiring it was the 3.1.9 bug
    /// that hid the feature on real XDR MacBooks, issue 191). The token
    /// survives localization where a product name does appear, so this
    /// stays as a free extra acceptance path, never a requirement.
    static func isXDRPanelName(_ localizedName: String) -> Bool {
        localizedName.localizedCaseInsensitiveContains("XDR")
    }

    /// Whether a built-in panel can truly exceed its SDR brightness. Known
    /// XDR MacBook Pro models pass by identifier; unknown (future) models
    /// pass when the panel reports more potential headroom than the fake
    /// EDR panels do, or when its product name says XDR. Air and iMac
    /// panels fail every path: wrong model, potential capped at 2.0, and
    /// no XDR in the name.
    static func isSupportedPanel(model: String?, localizedName: String,
                                 potentialEDR: Double) -> Bool {
        if let model, xdrModelIdentifiers.contains(model) { return true }
        return potentialEDR > capabilityFloor || isXDRPanelName(localizedName)
    }

    /// The 2021 and 2023 M1/M2 MacBook Pro panels reference 500 nits in SDR;
    /// the M3 generation onwards references 600 (the reference is the panel's
    /// 1600 nit peak over its SDR maximum). The pair per generation is
    /// (referenceEDR, bonus): the multiplier tops out at 1 + bonus, chosen a
    /// touch below the ceiling proven sustainable in the field. Asking for
    /// more looks brighter for an instant, but exceeds what the panel holds
    /// across a full screen and macOS answers by clawing the headroom back,
    /// which visibly kills the whole boost. Unknown (future) models get the
    /// conservative 600 nit curve.
    static let sdr500nitModels: Set<String> = [
        "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
        "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10",
    ]

    static func panelReference(model: String?) -> (referenceEDR: Double, bonus: Double) {
        if let model, sdr500nitModels.contains(model) { return (3.2, 0.58) }
        return (2.66, 0.48)
    }

    /// How strong the multiplier is for a user level of 0...1 given the
    /// panel's currently available EDR headroom. Level 0 means no boost;
    /// level 1 applies the panel's full sustainable bonus, scaled down
    /// proportionally while macOS grants less headroom than the reference
    /// (thermals, low battery, bright ambient light).
    static func boostFactor(level: Double, maxEDR: Double,
                            reference: (referenceEDR: Double, bonus: Double)) -> Double {
        let clampedLevel = min(max(level, 0), 1)
        let granted = min(max(maxEDR, 0) / reference.referenceEDR, 1.0)
        return 1 + clampedLevel * reference.bonus * granted
    }

    /// The factor the overlay should render right now: before the panel
    /// engages its headroom only the small engagement boost is shown (enough
    /// extended range content to make macOS turn the headroom on), afterwards
    /// the level maps into whatever headroom is actually available, never
    /// past it (a multiplier above the granted headroom only clips). A panel
    /// whose current mode reports no potential headroom at all (a reference
    /// preset without HDR) gets no boost attempt: the nudge could never
    /// engage anything and would only clip the brightest tones.
    static func renderFactor(level: Double, currentEDR: Double, potentialEDR: Double,
                             reference: (referenceEDR: Double, bonus: Double)) -> Double {
        guard potentialEDR > headroomThreshold else { return 1.0 }
        guard currentEDR > headroomThreshold else {
            return min(engagementFactor,
                       boostFactor(level: level, maxEDR: reference.referenceEDR, reference: reference))
        }
        return min(boostFactor(level: level, maxEDR: currentEDR, reference: reference),
                   max(currentEDR, 1.0))
    }

    // MARK: - Smoothing between poll ticks

    /// While HDR video plays, the granted headroom moves constantly: the
    /// video spends the same headroom the boost uses, and the boost itself
    /// raises panel power, so macOS keeps revising its grant. Rendering each
    /// reading as-is turned that into brightness steps four times a second
    /// (the reported flashing). Downward moves take a share of the gap per
    /// tick, so a real revocation is respected within a couple of seconds;
    /// upward moves are one small fixed step, so the boost never chases the
    /// grant back up fast enough to trigger the next revocation.
    static let rampUpStep: Double = 0.03
    static let rampDownShare: Double = 0.25
    static let rampMinStep: Double = 0.01

    /// Consecutive no-headroom readings to ride out before believing them.
    /// Entering fullscreen video briefly reports no headroom at all; acting
    /// on that slammed the boost to the engagement nudge and back, a hard
    /// flash. Holding is safe: the compositor clamps the overlay to the
    /// range that is really available, so a held factor never over-asks.
    static let dropoutGraceTicks = 3

    /// The factor to put on screen this tick, one smoothing step from
    /// `previous` toward `target`.
    static func rampedFactor(previous: Double, target: Double) -> Double {
        if target > previous { return min(previous + rampUpStep, target) }
        if target < previous {
            let step = max((previous - target) * rampDownShare, rampMinStep)
            return max(previous - step, target)
        }
        return previous
    }

    /// The target for this tick: a grant that vanished moments ago keeps the
    /// previous factor through the grace window; a persistent dropout (or
    /// one with no boost worth protecting) is taken at face value.
    static func gracedTarget(instantaneous: Double, previous: Double,
                             engaged: Bool, disengagedTicks: Int) -> Double {
        guard !engaged, disengagedTicks <= dropoutGraceTicks else { return instantaneous }
        return max(instantaneous, previous)
    }

    /// Whether the live window pair already followed a Space transition and
    /// can keep presenting without a teardown. Both windows matter: losing the
    /// one-pixel trigger lets macOS revoke the headroom moments later.
    static func canReuseSpaceWindows(sameDisplay: Bool,
                                     overlayOnActiveSpace: Bool,
                                     triggerOnActiveSpace: Bool) -> Bool {
        sameDisplay && overlayOnActiveSpace && triggerOnActiveSpace
    }
}
