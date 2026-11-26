// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure math for the extra brightness boost, kept free of AppKit and Metal so
/// the unit tests can pin its behavior.
///
/// The boost scales the built-in display's hardware transfer (gamma) table
/// above 1.0 while a 1x1 extended-range Metal trigger keeps macOS's EDR
/// headroom engaged. Because the transfer table runs in the display pipeline
/// after WindowServer compositing, window switches, Space transitions, and
/// Mission Control cannot drop the boost. Blacks stay black and contrast is
/// preserved, since multiplication only scales.
enum ExtraBrightnessSupport {
    /// Native per-channel transfer table samples for one display.
    struct GammaTable: Equatable {
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]

        var sampleCount: Int { red.count }
        var count: UInt32 { UInt32(red.count) }
    }

    /// The panel has real headroom past this (values near 1 are noise).
    static let headroomThreshold: Double = 1.05

    /// Highest channel value accepted as an unmodified SDR baseline gamma
    /// table. Standard macOS SDR tables lie in `0...1`, and CoreGraphics clamps
    /// values above 1.0 when writing a full-capacity 1,024-entry restore table,
    /// so rejecting anything above 1.0 guarantees both no double-boosting and
    /// lossless native restoration.
    static let gammaBaselineMaxPeak: CGGammaValue = 1.0

    /// Per-sample tolerance when checking whether the live hardware transfer
    /// table matches an expected baseline or scaled curve.
    static let gammaDriftTolerance: CGGammaValue = 0.003

    /// Minimum factor change that warrants rewriting the display transfer
    /// table. Factors at or below `1.0 + gammaFactorEpsilon` are treated as
    /// neutral so restoring the baseline is exact.
    static let gammaFactorEpsilon: Double = 0.0005

    /// Minimum per-sample lift above the baseline that counts as an actively
    /// boosted live table on readback.
    static let observedBoostThreshold: CGGammaValue = 0.001

    /// Maximum table length written when applying a > 1.0 boost. On Apple
    /// Silicon XDR panels (native capacity 1,024), CoreGraphics clamps values
    /// above 1.0 down to 1.0 when `CGSetDisplayTransferByTable` receives a
    /// full-capacity 1,024-sample table, but preserves extended > 1.0 values
    /// and linearly interpolates them across all 1,024 hardware entries when
    /// given a 256-sample table. Restoring always writes the full native
    /// baseline.
    static let boostTableSampleLimit = 256

    /// Backoff schedule for off-state restore retries while a failed baseline
    /// restore is pending and the display is awake. Caps at the last interval
    /// so retries stay light without giving up.
    static let pendingRestoreRetryDelays: [TimeInterval] = [0.25, 0.5, 1.0, 2.0, 5.0]

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

    /// The factor to apply right now: while EDR headroom is unavailable or not
    /// yet engaged, returns 1.0 so the hardware transfer table stays untouched
    /// and never clips highlights (the 1x1 Metal trigger engages EDR headroom
    /// on its own). Once headroom is engaged, the user level maps into whatever
    /// headroom is actually granted, never past it.
    static func renderFactor(level: Double, currentEDR: Double, potentialEDR: Double,
                             reference: (referenceEDR: Double, bonus: Double)) -> Double {
        guard potentialEDR.isFinite, potentialEDR > headroomThreshold,
              currentEDR.isFinite, currentEDR > headroomThreshold else { return 1.0 }
        return min(boostFactor(level: level, maxEDR: currentEDR, reference: reference),
                   max(currentEDR, 1.0))
    }

    // MARK: - Smoothing between poll ticks

    /// While HDR video plays, the granted headroom moves constantly: the
    /// video spends the same headroom the boost uses, and the boost itself
    /// raises panel power, so macOS keeps revising its grant. Rendering each
    /// reading as-is turned that into brightness steps four times a second
    /// (the reported flashing). Downward moves take a share of the gap per
    /// tick, so reductions track smoothly; upward moves are one small fixed
    /// step, so the boost never chases the grant back up fast enough to
    /// trigger the next revocation.
    static let rampUpStep: Double = 0.03
    static let rampDownShare: Double = 0.25
    static let rampMinStep: Double = 0.01

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

    /// Whether the live 1x1 EDR trigger window already followed a Space
    /// transition and can keep presenting without a teardown. A window in the
    /// helper's own Space never leaves, though AppKit never reports it on the
    /// active Space; otherwise it must still sit on the active Space so macOS
    /// does not revoke the panel's headroom.
    static func canReuseTriggerWindow(sameDisplay: Bool,
                                      inOwnSpace: Bool,
                                      triggerOnActiveSpace: Bool) -> Bool {
        sameDisplay && (inOwnSpace || triggerOnActiveSpace)
    }

    // MARK: - Gamma transfer table

    /// Peak finite sample value across all three channels of `table`, or 0
    /// when empty.
    static func gammaTablePeak(_ table: GammaTable) -> CGGammaValue {
        var peak: CGGammaValue = 0
        for channel in [table.red, table.green, table.blue] {
            for value in channel where value.isFinite {
                if value > peak { peak = value }
            }
        }
        return peak
    }

    /// Highest multiplier that keeps every written sample of a table peaking
    /// at `baselinePeak` within `currentEDR` headroom (never below 1.0).
    static func maxFactorForHeadroom(currentEDR: Double, baselinePeak: Double = 1.0) -> Double {
        guard currentEDR.isFinite, currentEDR > headroomThreshold else { return 1.0 }
        let peak = (baselinePeak.isFinite && baselinePeak > 0) ? baselinePeak : 1.0
        return max(currentEDR / peak, 1.0)
    }

    /// Whether a captured display transfer table looks like a valid,
    /// unmodified SDR baseline: non-empty, matching channel lengths, all
    /// finite non-negative entries, non-zero peak (rejects sleeping/blank
    /// tables), and peak at or below `gammaBaselineMaxPeak` (rejects already-
    /// boosted tables).
    static func isUsableGammaBaseline(_ table: GammaTable) -> Bool {
        guard !table.red.isEmpty,
              table.red.count == table.green.count,
              table.red.count == table.blue.count else { return false }
        var peak: CGGammaValue = 0
        for channel in [table.red, table.green, table.blue] {
            for value in channel {
                guard value.isFinite, value >= 0 else { return false }
                if value > peak { peak = value }
            }
        }
        return peak > 0 && peak <= gammaBaselineMaxPeak
    }

    /// Scales a baseline gamma channel by `factor`. Factors at or below
    /// neutral (or non-finite) return the input untouched so restoring is
    /// bit-exact.
    static func scaledGammaChannel(_ channel: [CGGammaValue], factor: Double) -> [CGGammaValue] {
        guard factor.isFinite, factor > 1.0 + gammaFactorEpsilon else { return channel }
        let scale = CGGammaValue(factor)
        return channel.map { $0 * scale }
    }

    /// Scales all three channels of a baseline transfer table by `factor`.
    static func scaledGammaTable(_ table: GammaTable, factor: Double) -> GammaTable {
        guard factor.isFinite, factor > 1.0 + gammaFactorEpsilon else { return table }
        return GammaTable(red: scaledGammaChannel(table.red, factor: factor),
                          green: scaledGammaChannel(table.green, factor: factor),
                          blue: scaledGammaChannel(table.blue, factor: factor))
    }

    /// Resamples one channel to `targetCount` samples with piecewise linear
    /// interpolation, preserving exact start and end values.
    static func resampledGammaChannel(_ channel: [CGGammaValue], to targetCount: Int) -> [CGGammaValue] {
        guard targetCount > 0, !channel.isEmpty else { return [] }
        guard channel.count != targetCount else { return channel }
        guard targetCount > 1, channel.count > 1 else { return [channel[0]] }
        let lastSource = Double(channel.count - 1)
        let lastTarget = Double(targetCount - 1)
        return (0..<targetCount).map { index in
            let position = Double(index) * lastSource / lastTarget
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, channel.count - 1)
            let fraction = CGGammaValue(position - Double(lower))
            return channel[lower] + (channel[upper] - channel[lower]) * fraction
        }
    }

    /// Builds the transfer table to write to `CGSetDisplayTransferByTable` for
    /// a > 1.0 boost: resamples the native baseline down to at most
    /// `boostTableSampleLimit` (256) entries so CoreGraphics preserves values
    /// above 1.0 instead of clamping a full-capacity 1,024-entry table to 1.0,
    /// then scales every sample by `factor`.
    static func boostTransferTable(from baseline: GammaTable, factor: Double) -> GammaTable {
        let targetCount = min(baseline.sampleCount, boostTableSampleLimit)
        let base = targetCount == baseline.sampleCount
            ? baseline
            : GammaTable(red: resampledGammaChannel(baseline.red, to: targetCount),
                         green: resampledGammaChannel(baseline.green, to: targetCount),
                         blue: resampledGammaChannel(baseline.blue, to: targetCount))
        return scaledGammaTable(base, factor: factor)
    }

    /// The native-resolution transfer table CoreGraphics produces when
    /// `boostTransferTable(from: baseline, factor: factor)` is written and
    /// linearly interpolated back across all `baseline.sampleCount` entries.
    /// Comparing readback against this (rather than directly scaling the
    /// native curve) keeps nonlinear calibration curves exact across
    /// 1,024 -> 256 -> 1,024 round-trips.
    static func expectedBoostedNativeTable(from baseline: GammaTable, factor: Double) -> GammaTable {
        guard factor.isFinite, factor > 1.0 + gammaFactorEpsilon else { return baseline }
        let written = boostTransferTable(from: baseline, factor: factor)
        guard written.sampleCount != baseline.sampleCount else { return written }
        return GammaTable(red: resampledGammaChannel(written.red, to: baseline.sampleCount),
                          green: resampledGammaChannel(written.green, to: baseline.sampleCount),
                          blue: resampledGammaChannel(written.blue, to: baseline.sampleCount))
    }

    /// Whether every native sample of `observed` matches `expected` within
    /// `tolerance`. Rejects empty or mismatched sample counts.
    static func gammaTableMatches(_ observed: GammaTable,
                                  expected: GammaTable,
                                  tolerance: CGGammaValue = gammaDriftTolerance) -> Bool {
        guard !expected.red.isEmpty,
              expected.red.count == expected.green.count,
              expected.red.count == expected.blue.count,
              observed.red.count == expected.red.count,
              observed.green.count == expected.green.count,
              observed.blue.count == expected.blue.count else { return false }
        for (expectedChannel, observedChannel) in [(expected.red, observed.red),
                                                   (expected.green, observed.green),
                                                   (expected.blue, observed.blue)] {
            for (expectedValue, observedValue) in zip(expectedChannel, observedChannel) {
                guard expectedValue.isFinite, observedValue.isFinite,
                      abs(observedValue - expectedValue) <= tolerance else { return false }
            }
        }
        return true
    }

    /// Whether the live display transfer table no longer matches the native
    /// representation of the boost written for `factor` across all native
    /// samples (for example after macOS resets the LUT on wake, mode change,
    /// or color-profile update).
    static func gammaTableDrifted(baseline: GammaTable,
                                  observed: GammaTable,
                                  factor: Double,
                                  tolerance: CGGammaValue = gammaDriftTolerance) -> Bool {
        guard !baseline.red.isEmpty,
              baseline.red.count == baseline.green.count,
              baseline.red.count == baseline.blue.count else { return false }
        let safeFactor = factor.isFinite ? max(factor, 1.0) : 1.0
        let expected = expectedBoostedNativeTable(from: baseline, factor: safeFactor)
        return !gammaTableMatches(observed, expected: expected, tolerance: tolerance)
    }

    /// Tolerance used when checking whether a previously applied boost has
    /// left the live table. Tightens below half the boost delta so even a
    /// small first ramp step (such as 1.03) is never mistaken for a clean
    /// baseline.
    static func boostClearanceTolerance(forAppliedFactor factor: Double) -> CGGammaValue {
        guard factor.isFinite, factor > 1.0 else { return gammaDriftTolerance }
        let delta = CGGammaValue(factor - 1.0)
        return min(gammaDriftTolerance, max(delta * 0.5, 0.0005))
    }

    /// Whether a failed restore can be cleared based on readback alone:
    /// requires a valid clean table that provably no longer matches the
    /// native representation of the previously written boost.
    static func canClearPendingRestore(baseline: GammaTable,
                                       appliedFactor: Double,
                                       observed: GammaTable) -> Bool {
        guard isUsableGammaBaseline(observed) else { return false }
        guard appliedFactor.isFinite, appliedFactor > 1.0 + gammaFactorEpsilon else { return true }
        let expected = expectedBoostedNativeTable(from: baseline, factor: appliedFactor)
        let tolerance = boostClearanceTolerance(forAppliedFactor: appliedFactor)
        return !gammaTableMatches(observed, expected: expected, tolerance: tolerance)
    }

    enum PendingRestoreAction: Equatable {
        /// The live display already carries a clean table without this
        /// service's boost (for example a newly loaded ColorSync profile or an
        /// OS wake reset); clear the pending restore without overwriting it.
        case clearWithoutWrite
        /// The live display still carries the old boost (or could not be
        /// proven clean); replay the saved baseline.
        case replayBaseline
    }

    /// Decides whether a pending baseline restore should clear without writing
    /// (preserving a newly loaded clean profile) or replay the saved baseline.
    static func pendingRestoreAction(baseline: GammaTable,
                                     appliedFactor: Double,
                                     observed: GammaTable?) -> PendingRestoreAction {
        if let observed,
           canClearPendingRestore(baseline: baseline,
                                  appliedFactor: appliedFactor,
                                  observed: observed) {
            return .clearWithoutWrite
        }
        return .replayBaseline
    }

    /// Backoff delay before the next off-state restore retry (0-based attempt).
    static func pendingRestoreRetryDelay(attempt: Int) -> TimeInterval {
        guard !pendingRestoreRetryDelays.isEmpty else { return 1.0 }
        let index = min(max(attempt, 0), pendingRestoreRetryDelays.count - 1)
        return pendingRestoreRetryDelays[index]
    }

    /// Whether a live table read after a display color-profile change can be
    /// adopted as the new baseline. When the service was boosting, refuses to
    /// adopt readback that still matches the old boosted curve.
    static func canAdoptProfileBaseline(previousBaseline: GammaTable,
                                        appliedFactor: Double,
                                        observed: GammaTable) -> Bool {
        canClearPendingRestore(baseline: previousBaseline,
                               appliedFactor: appliedFactor,
                               observed: observed)
    }

    /// Whether readback currently shows a boost above the baseline table.
    static func observedBoostActive(baseline: GammaTable,
                                    observed: GammaTable) -> Bool {
        guard !baseline.red.isEmpty,
              baseline.red.count == baseline.green.count,
              baseline.red.count == baseline.blue.count,
              observed.red.count == baseline.red.count,
              observed.green.count == baseline.green.count,
              observed.blue.count == baseline.blue.count else { return false }
        for (baseChannel, liveChannel) in [(baseline.red, observed.red),
                                           (baseline.green, observed.green),
                                           (baseline.blue, observed.blue)] {
            for (base, live) in zip(baseChannel, liveChannel) where base.isFinite && live.isFinite {
                if live > base + observedBoostThreshold { return true }
            }
        }
        return false
    }

    enum GammaAction: Equatable {
        case noop
        case restore
        case apply(Double)
    }

    /// Decides whether the hardware transfer table needs a write on this tick.
    /// Never writes a boosted factor when `currentEDR` is at or below the
    /// headroom threshold, and caps the factor against `baselinePeak` so no
    /// written sample ever exceeds available EDR headroom.
    static func gammaAction(targetFactor: Double,
                            appliedFactor: Double,
                            currentEDR: Double,
                            baselinePeak: Double = 1.0,
                            drifted: Bool) -> GammaAction {
        let neutralLimit = 1.0 + gammaFactorEpsilon
        let maxFactor = maxFactorForHeadroom(currentEDR: currentEDR, baselinePeak: baselinePeak)
        guard targetFactor.isFinite, targetFactor > neutralLimit else {
            return appliedFactor > neutralLimit ? .restore : .noop
        }
        let clampedTarget = min(targetFactor, maxFactor)
        guard clampedTarget > neutralLimit else {
            return appliedFactor > neutralLimit ? .restore : .noop
        }
        if abs(clampedTarget - appliedFactor) > gammaFactorEpsilon || drifted {
            return .apply(clampedTarget)
        }
        return .noop
    }

    /// Composed per-tick gamma decision combining `renderFactor`, smoothing
    /// ramp, live headroom/peak capping, and drift repair. Guarantees no
    /// written transfer-table sample ever exceeds available EDR headroom.
    static func effectiveGammaAction(level: Double,
                                     currentEDR: Double,
                                     potentialEDR: Double,
                                     reference: (referenceEDR: Double, bonus: Double),
                                     previousFactor: Double,
                                     appliedFactor: Double,
                                     baselinePeak: Double = 1.0,
                                     immediate: Bool,
                                     drifted: Bool) -> (nextFactor: Double, action: GammaAction) {
        let instantaneous = renderFactor(level: level, currentEDR: currentEDR,
                                         potentialEDR: potentialEDR, reference: reference)
        guard potentialEDR.isFinite, potentialEDR > headroomThreshold,
              currentEDR.isFinite, currentEDR > headroomThreshold else {
            let action = gammaAction(targetFactor: 1.0, appliedFactor: appliedFactor,
                                     currentEDR: currentEDR, baselinePeak: baselinePeak,
                                     drifted: drifted)
            return (1.0, action)
        }
        let maxFactor = maxFactorForHeadroom(currentEDR: currentEDR, baselinePeak: baselinePeak)
        let cappedTarget = min(instantaneous, maxFactor)
        let stepped = immediate ? cappedTarget
            : rampedFactor(previous: previousFactor, target: cappedTarget)
        let clamped = min(stepped, maxFactor)
        let action = gammaAction(targetFactor: clamped, appliedFactor: appliedFactor,
                                 currentEDR: currentEDR, baselinePeak: baselinePeak,
                                 drifted: drifted)
        return (clamped, action)
    }
}
