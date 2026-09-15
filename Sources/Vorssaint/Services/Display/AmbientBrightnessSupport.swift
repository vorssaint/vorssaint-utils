// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure helpers for synchronizing external displays with the built-in screen
/// (and, in clamshell mode, the ambient light sensor). No IOKit here so the
/// unit tests can cover every mapping byte by byte.
///
/// Model: the built-in panel's brightness is the reference `R` (0...1), the
/// value macOS already moves for both the ambient light sensor and manual key
/// presses. Each external display keeps an additive `offset` (0...1, positive
/// = brighter than the built-in) calibrated once against real-world luminance,
/// and its target is `clamp(R + offset)`. The offset is what the feature brief
/// means by a relative difference: a screen that reads 70% when the built-in
/// reads 50% stays 20 points apart as the light changes, rather than being
/// forced to the same percentage as the built-in.
enum AmbientBrightnessSupport {
    /// How far a reference level must move before externals are re-derived.
    /// Smaller than this and a display's own read noise just churns DDC.
    static let minimumReferenceStep = 0.02
    /// How often a connected external display may be re-commanded at most.
    static let refreshInterval: TimeInterval = 1
    /// Step each offset nudge button applies, on the shared 0...1 scale.
    static let offsetNudgeStep = 0.05
    /// How long a brightness transition ramps between two levels before it
    /// settles, on the shared 0...1 scale. Kept comfortably inside the 1 s
    /// sample window so a fresh reference always finds the last ramp settled.
    static let smoothTransitionDuration: TimeInterval = 0.4
    /// How often intermediate brightness values are steered during a
    /// transition, on the main thread. 60 FPS reads as buttery-smooth to the
    /// eye; the hardware write rate is throttled independently by
    /// `BrightnessService`'s DDC/CI pacing, so this cadence costs no DDC
    /// traffic beyond the pacing the monitor bus already needs.
    static let smoothTransitionFramesPerSecond: Double = 60

    /// The brightness an external display should take so it keeps `offset`
    /// above or below a reference level of `reference`.
    static func clampedTarget(reference: Double, offset: Double) -> Double {
        min(max(reference + offset, 0), 1)
    }

    /// The offset that pins `external` to `reference` right now, on the shared
    /// 0...1 scale. This is what calibration writes so we never store absolute
    /// percentages, only the relative gap the user matched by eye.
    static func offset(reference: Double, external: Double) -> Double {
        min(max(external - reference, -1), 1)
    }

    /// Whether a newly observed reference level is different enough from the
    /// last one already applied that the externals should move again.
    static func shouldPropagate(previous: Double, current: Double, step: Double) -> Bool {
        abs(current - previous) >= step
    }

    /// The eased progress fraction (0...1) for a transition at linear
    /// progress `t`, using smoothstep `t²(3-2t)`. Starts and settles at rest so
    /// the eye reads no hard start/stop, only a fluid glide between levels.
    static func easedTransition(progress t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// The current animated value between `from` and `to` at linear progress
    /// `progress` (0...1), eased so the brightness neither lurches off its
    /// old level nor slams onto its new one.
 static func transitionedValue(from: Double, to: Double, progress: Double) -> Double {
        from + (to - from) * easedTransition(progress: progress)
    }

    /// Maps a raw ambient light count onto the same 0...1 scale the built-in
    /// brightness lives on, used only when there is no built-in screen to read
    /// (clamshell lid closed). `floor`/`ceiling` are the sensor's sensible
    /// minimum and maximum; brightest ambience maps to 1, darkness to 0.
    static func reference(forAmbientLevel ambient: Double,
                          floor: Double, ceiling: Double) -> Double {
        let span = ceiling - floor
        guard span > 0 else { return 0 }
        return min(max((ambient - floor) / span, 0), 1)
    }

    /// The offsets that survive a reload. Offsets belong to one physical
    /// monitor on one Mac port, so anything that is not a finite value inside
    /// the legal range is dropped rather than trusted.
    static func sanitizedOffsets(_ raw: [Double]) -> [Double] {
        raw.filter { $0.isFinite }.map { min(max($0, -1), 1) }
    }

    /// Values are stored per physical monitor (fingerprint), not per display
    /// number: a reconnection hands out IDs again and a level saved for one
    /// monitor must never follow whatever inherits its number.
    static func fingerprint(vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        "\(vendor):\(model):\(serial)"
    }
}