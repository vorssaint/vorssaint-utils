// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Step and limits for the keys that move a monitor's speakers. The DDC
/// range comes from the monitor, so even a one-percent step moves at least
/// one unit and a coarse monitor cannot round a write above the ceiling.
struct MonitorVolumeKeySettings: Equatable {
    static let defaultStepPercent = 6.25
    static let stepChoices: [Double] = [1, 2, 3, 5, defaultStepPercent, 10]

    let stepPercent: Double
    let minimumPercent: Int
    let maximumPercent: Int

    init(stepPercent: Double = MonitorVolumeKeySettings.defaultStepPercent,
         minimumPercent: Int = 0, maximumPercent: Int = 100) {
        self.stepPercent = Self.stepChoices.contains(stepPercent) ? stepPercent : Self.defaultStepPercent
        let upper = maximumPercent > 0 ? min(maximumPercent, 100) : 100
        self.maximumPercent = upper
        self.minimumPercent = min(max(minimumPercent, 0), upper - 1)
    }

    init(in defaults: UserDefaults) {
        self.init(stepPercent: defaults.double(forKey: DefaultsKey.ddcVolumeStep),
                  minimumPercent: defaults.integer(forKey: DefaultsKey.ddcVolumeMinimum),
                  maximumPercent: defaults.integer(forKey: DefaultsKey.ddcVolumeMaximum))
    }

    /// Captured for each key press. A level changed on the monitor rejoins the step grid.
    func requestedLevel(from current: Double, direction: Int, fine: Bool) -> Double {
        let stepsPerRange = 100 / (fine ? 1 : stepPercent)
        // Normalizing a UInt16 reading can put an exact half-step one ULP below the tie.
        let nearest = (current * stepsPerRange).nextUp.rounded()
        return (nearest + Double(direction)) / stepsPerRange
    }

    func ceiling(for maximum: UInt16) -> UInt16 {
        UInt16(Int(maximum) * maximumPercent / 100)
    }

    /// Enforced with the range read by the DDC transaction. Down below the floor
    /// and up above the ceiling leave the monitor alone. Moving back toward the
    /// range still takes one step, even when the monitor's buttons moved it far away.
    func boundedStep(from raw: UInt16, maximum: UInt16, to proposed: Double) -> UInt16? {
        guard maximum > 0, raw <= maximum, proposed.isFinite else { return nil }
        let upper = ceiling(for: maximum)
        let lower = UInt16((Int(maximum) * minimumPercent + 99) / 100)
        guard lower <= upper else { return nil }
        let current = Double(raw) / Double(maximum)
        let target = BrightnessSupport.deviceValue(for: proposed, maximum: maximum)
        if proposed > current, raw < upper { return min(max(target, raw + 1), upper) }
        if proposed < current, raw > lower { return max(min(target, raw - 1), lower) }
        return nil
    }
}
