// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AmbientLightSupport {
    static let defaultThreshold = 10_000.0
    static let thresholdRange = 1.0...100_000.0
    // Deliberately weighted toward indoor use; these are presets, not sensor limits.
    static let thresholdSteps: [Double] = [10, 25, 50, 100, 200, 400, 700, 1_000, 3_000, 10_000]
    static let sampleInterval = 2.0

    static func nearestStep(_ threshold: Double) -> Int {
        let value = sanitizedThreshold(threshold)
        return thresholdSteps.indices.min {
            abs(log(thresholdSteps[$0] / value)) < abs(log(thresholdSteps[$1] / value))
        } ?? 0
    }

    /// Interpolate the live meter using the same spacing as the preset slider.
    static func meterPosition(_ lux: Double) -> Double {
        guard let value = validLux(lux), value > thresholdSteps[0] else { return 0 }
        for index in 1..<thresholdSteps.count where value < thresholdSteps[index] {
            let lower = thresholdSteps[index - 1]
            let fraction = log(value / lower) / log(thresholdSteps[index] / lower)
            return (Double(index - 1) + fraction) / Double(thresholdSteps.count - 1)
        }
        return 1
    }

    static func sanitizedThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return defaultThreshold }
        return min(thresholdRange.upperBound, max(thresholdRange.lowerBound, value))
    }

    static func validLux(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

enum AmbientLightAppearance: String, CaseIterable {
    case dark, light

    static func sanitized(_ value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? .dark
    }

    var opposite: Self { self == .dark ? .light : .dark }
}

/// A target is returned only after four seconds of uninterrupted readings on
/// the same side of the trigger. Keep returning that target while stable so
/// automation also corrects changes made by the system appearance schedule.
/// Missing readings and sampling gaps require a new observation period.
struct AmbientLightGate {
    private var candidate: AmbientLightAppearance?
    private var candidateSince: TimeInterval?
    private var lastSample: TimeInterval?

    mutating func observe(lux: Double?, threshold: Double,
                          defaultAppearance: AmbientLightAppearance,
                          now: TimeInterval) -> AmbientLightAppearance? {
        guard now.isFinite, let lux = AmbientLightSupport.validLux(lux) else {
            self = AmbientLightGate()
            return nil
        }
        if let previous = lastSample, now < previous || now - previous > 6 {
            self = AmbientLightGate()
        }
        lastSample = now
        let target = lux >= AmbientLightSupport.sanitizedThreshold(threshold)
            ? defaultAppearance.opposite : defaultAppearance
        guard candidate == target, let start = candidateSince else {
            candidate = target
            candidateSince = now
            return nil
        }
        return now - start >= 4 ? target : nil
    }
}
