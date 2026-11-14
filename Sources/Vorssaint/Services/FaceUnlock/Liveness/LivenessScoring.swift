// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.
//
//  `LivenessFrame` plus the two cross-frame confirm cues that read it directly:
//  `poseDepthConsistency` and `blinkDynamics`. No `import Vision`/AppKit, so it
//  compiles standalone for `tools/liveness_selftest.swift`.

import Foundation
import CoreGraphics

/// One frame's worth of liveness-relevant measurements — already normalized, no Vision needed.
/// Populated by `LivenessFeatureExtractor.extract(from:)` from a real camera frame, or built
/// directly from synthetic data by `tools/liveness_selftest.swift`.
struct LivenessFrame {
    let timestamp: Date
    /// Every landmark point Vision found this frame, tagged by region — see `LandmarkGeometry.allPoints`.
    let landmarks: [LandmarkPoint]
    /// Distance between the two eye centers — the normalization scale for every ratio below.
    let interocularDistance: CGFloat?
    let yaw: Float?
    let leftEyeAspectRatio: CGFloat?
    let rightEyeAspectRatio: CGFloat?
    /// `(noseCentroid.x - eyeMidpoint.x) / interocularDistance` — tracks `tan(yaw)` on a real
    /// 3D face but stays constant on any flat presentation. See `poseDepthConsistency` below.
    let noseOffsetRatio: CGFloat?
    /// Whether landmarks came from full 5-point detection rather than a degraded fallback;
    /// cues that need precision skip frames where this is false.
    let hasReliableLandmarks: Bool
    /// Fraction of the face bounding box covered by a detected device-shaped rectangle;
    /// `nil` when detection wasn't run or found nothing. Read by the `deviceDetected` deny cue.
    let deviceOverlapFraction: CGFloat?
    /// Specular-highlight measurements from a native-resolution face crop; `nil` when no crop
    /// was available, in which case the `glossGlare` deny cue abstains.
    let glare: GlareSample?

    /// Explicit init so `glare` can default to `nil` — a defaulted `let` property is otherwise
    /// excluded from Swift's synthesized memberwise init rather than becoming optional.
    init(
        timestamp: Date,
        landmarks: [LandmarkPoint],
        interocularDistance: CGFloat?,
        yaw: Float?,
        leftEyeAspectRatio: CGFloat?,
        rightEyeAspectRatio: CGFloat?,
        noseOffsetRatio: CGFloat?,
        hasReliableLandmarks: Bool,
        deviceOverlapFraction: CGFloat?,
        glare: GlareSample? = nil
    ) {
        self.timestamp = timestamp
        self.landmarks = landmarks
        self.interocularDistance = interocularDistance
        self.yaw = yaw
        self.leftEyeAspectRatio = leftEyeAspectRatio
        self.rightEyeAspectRatio = rightEyeAspectRatio
        self.noseOffsetRatio = noseOffsetRatio
        self.hasReliableLandmarks = hasReliableLandmarks
        self.deviceOverlapFraction = deviceOverlapFraction
        self.glare = glare
    }
}

nonisolated enum LivenessScoring {
    // MARK: - Depth/pose consistency (confirm cue)

    /// Correlates nose-offset-from-eye-midline against tan(yaw): tracks yaw on a real face,
    /// stays constant on a flat presentation. Abstains at small yaw ranges where the
    /// predicted displacement is below Vision's landmark noise floor.
    static func poseDepthConsistency(_ window: [LivenessFrame]) -> CueReading {
        let pairs = window.compactMap { frame -> (CGFloat, CGFloat)? in
            guard let offset = frame.noseOffsetRatio, let yaw = frame.yaw, frame.hasReliableLandmarks else { return nil }
            return (offset, CGFloat(tan(yaw)))
        }
        guard pairs.count >= 4 else { return .none }

        let yaws = pairs.map(\.1)
        guard let minYaw = yaws.min(), let maxYaw = yaws.max() else { return .none }
        let yawRange = abs(atan(maxYaw) - atan(minYaw))
        // Below ~12 degrees the predicted displacement is sub-pixel — matches
        // `GeometryTuning.minYawRangeDegrees`, which gates on the same underlying limit.
        let minMeasurableRange: CGFloat = 12 * .pi / 180
        guard yawRange > minMeasurableRange else { return .none }

        guard let correlation = pearsonCorrelation(pairs.map(\.0), pairs.map(\.1)) else { return .none }
        let level = Float(clamp((correlation + 1) / 2, 0, 1))
        // Confidence ramps in over the next ~15 degrees past the minimum —
        // more rotation observed, more trustworthy the correlation is.
        let confidence = Float(clamp((yawRange - minMeasurableRange) / (15 * .pi / 180), 0, 1))
        return CueReading(level: level, confidence: confidence)
    }

    private static func pearsonCorrelation(_ xs: [CGFloat], _ ys: [CGFloat]) -> CGFloat? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let n = CGFloat(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var covariance: CGFloat = 0, varX: CGFloat = 0, varY: CGFloat = 0
        for i in 0..<xs.count {
            let dx = xs[i] - meanX, dy = ys[i] - meanY
            covariance += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        guard varX > 0, varY > 0 else { return nil }
        return covariance / (varX.squareRoot() * varY.squareRoot())
    }

    // MARK: - Blink dynamics (confirm cue)

    /// Looks for a dip-and-recovery in eye-aspect-ratio. Never mandatory — a short window
    /// often contains no blink at all, which abstains rather than fails. Thresholds are loose
    /// because Vision's landmark model doesn't fully collapse the eyelid contour during a real
    /// blink; recovery is checked within a radius since a blink can span several frames at ~20fps.
    static func blinkDynamics(_ window: [LivenessFrame]) -> CueReading {
        let ears = window.compactMap { frame -> CGFloat? in
            guard let l = frame.leftEyeAspectRatio, let r = frame.rightEyeAspectRatio else { return nil }
            return (l + r) / 2
        }
        guard ears.count >= 4 else { return .none }

        let baseline = ears.max() ?? 0
        guard baseline > 0 else { return .none }
        guard let minEAR = ears.min(), let minIndex = ears.firstIndex(of: minEAR) else { return .none }

        let dipRatio = minEAR / baseline
        let recoveryRadius = 3
        let openBefore = ears[..<minIndex].suffix(recoveryRadius).contains { $0 / baseline > 0.7 }
        let openAfter = ears[(minIndex + 1)...].prefix(recoveryRadius).contains { $0 / baseline > 0.7 }
        let hasNeighborRecovery = minIndex > 0 && minIndex < ears.count - 1 && openBefore && openAfter

        guard dipRatio < 0.65, hasNeighborRecovery else { return .none }
        return CueReading(level: 1, confidence: 1)
    }

    private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
