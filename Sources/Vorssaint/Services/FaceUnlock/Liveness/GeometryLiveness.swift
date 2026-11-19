// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.
//
//  Planar-vs-3D liveness (the `flatVs3D` cue). No `import Vision`, so this
//  compiles into `tools/liveness_selftest.swift`. Higher `planarResidualScore` = more like a live face.

import Foundation
import CoreGraphics

struct GeometryTuning {
    /// Excess (`probeResidual / fitResidual`) at which the planar signal starts ramping off 0; ~1 means a plane.
    var excessFloor: CGFloat = 1.15
    /// Excess at which the planar signal saturates at 1.
    var excessCeiling: CGFloat = 2.0
    /// `|mean residual| / mean(|residual|)` below this reads as landmark noise, not 3D parallax.
    var coherenceFloor: CGFloat = 0.35
    /// Minimum mean fit-set displacement (in interocular-distance units) before geometry votes at all.
    var motionGate: CGFloat = 0.008
    /// Minimum yaw range (degrees) before geometry votes — closes the "smooth phone wobble" case where
    /// pure translation (no rotation) clears `motionGate` with zero real parallax.
    var minYawRangeDegrees: CGFloat = 12

    nonisolated static let `default` = GeometryTuning()
}

struct GeometryLivenessResult: Equatable {
    let planarResidualScore: Float
    let planarConfidence: Float

    let validLandmarkCount: Int
    let pairsAnalyzed: Int
    let rejectedPairCount: Int
    let medianFitResidual: CGFloat?
    let medianProbeResidual: CGFloat?
    let excessRatio: CGFloat?
    let coherence: CGFloat?
    let motionMagnitude: CGFloat?
    /// Normalized distance ratios for Face Lab — diagnostic only, do not vote.
    let diagnosticRatios: [String: CGFloat]

    static let empty = GeometryLivenessResult(
        planarResidualScore: 0, planarConfidence: 0,
        validLandmarkCount: 0, pairsAnalyzed: 0, rejectedPairCount: 0,
        medianFitResidual: nil, medianProbeResidual: nil,
        excessRatio: nil, coherence: nil, motionMagnitude: nil,
        diagnosticRatios: [:]
    )

    /// Adapter into the shared cue vocabulary — see `LivenessCues.readings`.
    nonisolated var planarReading: CueReading {
        CueReading(level: planarResidualScore, confidence: planarConfidence)
    }
}

/// Regions that sit on roughly one shallow surface, with enough spatial
/// spread to constrain an 8-DOF homography. The nose is held out.
nonisolated private let geometryFitRegions: Set<LandmarkRegion> = [
    .leftEye, .rightEye, .leftEyebrow, .rightEyebrow, .outerLips,
]

/// Protruding landmarks geometrically *inside* the fit hull, so leftover
/// error is depth, not extrapolation. `faceContour` is excluded on purpose.
nonisolated private let geometryProbeRegions: Set<LandmarkRegion> = [
    .nose, .noseCrest, .medianLine,
]

nonisolated enum GeometryLiveness {
    static func evaluate(_ window: [LivenessFrame], tuning: GeometryTuning = .default) -> GeometryLivenessResult {
        let lastLandmarks = window.last?.landmarks.count ?? 0
        var diagnostics = diagnosticRatios(from: window.last)

        guard window.count >= 3 else {
            return GeometryLivenessResult(
                planarResidualScore: 0, planarConfidence: 0,
                validLandmarkCount: lastLandmarks, pairsAnalyzed: 0, rejectedPairCount: 0,
                medianFitResidual: nil, medianProbeResidual: nil,
                excessRatio: nil, coherence: nil, motionMagnitude: nil,
                diagnosticRatios: diagnostics
            )
        }

        let yawRange = yawRangeDegrees(window)
        let yawGateOK = (yawRange ?? 0) >= tuning.minYawRangeDegrees
        if let yawRange { diagnostics["yaw range (deg)"] = yawRange }

        var excesses: [CGFloat] = []
        var coherences: [CGFloat] = []
        var motions: [CGFloat] = []
        var fitResiduals: [CGFloat] = []
        var probeResiduals: [CGFloat] = []
        var weights: [CGFloat] = []
        var rejected = 0
        var skippedForMotion = 0

        for (i, j, weight) in pairIndices(count: window.count) {
            guard let sample = pairGeometry(from: window[i], to: window[j]) else {
                rejected += 1
                continue
            }
            if sample.motion < tuning.motionGate {
                skippedForMotion += 1
                continue
            }
            excesses.append(sample.excess)
            coherences.append(sample.coherence)
            motions.append(sample.motion)
            fitResiduals.append(sample.fitResidual)
            probeResiduals.append(sample.probeResidual)
            weights.append(weight)
        }

        let pairsAnalyzed = excesses.count
        let medianFit = fitResiduals.isEmpty ? nil : LandmarkGeometry.medianValue(fitResiduals)
        let medianProbe = probeResiduals.isEmpty ? nil : LandmarkGeometry.medianValue(probeResiduals)
        let excess = weightedMedian(excesses, weights: weights)
        let coherence = weightedMedian(coherences, weights: weights)
        let motion = motions.isEmpty ? nil : (motions.reduce(0, +) / CGFloat(motions.count))

        // Abstention is (level 0, confidence 0); level is never read when confidence is 0.
        var planarScore: Float = 0
        var planarConf: Float = 0
        if yawGateOK, let excess, let coherence, pairsAnalyzed >= 2 {
            // Unstructured leftover (landmark jitter) is not 3D evidence.
            let coherenceFactor = Float(clamp((coherence - tuning.coherenceFloor) / max(1 - tuning.coherenceFloor, 0.01), 0, 1))
            let excessScore = Float(clamp((excess - tuning.excessFloor) / max(tuning.excessCeiling - tuning.excessFloor, 0.01), 0, 1))
            planarScore = excessScore * (0.35 + 0.65 * coherenceFactor)
            planarConf = Float(clamp(Double(pairsAnalyzed) / 6.0, 0, 1)) * (0.5 + 0.5 * coherenceFactor)
        } else if !yawGateOK {
            // Not enough head rotation to tell flat from 3D — see `minYawRangeDegrees`.
            planarScore = 0
            planarConf = 0
        } else if skippedForMotion > 0, pairsAnalyzed == 0 {
            // Motion never cleared the gate — abstain rather than call it a photo.
            planarScore = 0
            planarConf = 0
        }

        return GeometryLivenessResult(
            planarResidualScore: planarScore,
            planarConfidence: planarConf,
            validLandmarkCount: lastLandmarks,
            pairsAnalyzed: pairsAnalyzed,
            rejectedPairCount: rejected,
            medianFitResidual: medianFit,
            medianProbeResidual: medianProbe,
            excessRatio: excess,
            coherence: coherence,
            motionMagnitude: motion,
            diagnosticRatios: diagnostics
        )
    }

    /// Yaw range (degrees) across frames that report one; `nil` if too few do.
    private static func yawRangeDegrees(_ window: [LivenessFrame]) -> CGFloat? {
        let yawsDegrees = window.compactMap { $0.yaw }.map { CGFloat($0) * 180 / .pi }
        guard yawsDegrees.count >= 3, let lo = yawsDegrees.min(), let hi = yawsDegrees.max() else { return nil }
        return hi - lo
    }

    // MARK: - Pair geometry

    private struct PairSample {
        let fitResidual: CGFloat
        let probeResidual: CGFloat
        let excess: CGFloat
        let coherence: CGFloat
        let motion: CGFloat
    }

    private static func pairGeometry(from a: LivenessFrame, to b: LivenessFrame) -> PairSample? {
        guard b.hasReliableLandmarks, a.hasReliableLandmarks else { return nil }
        guard let iod = b.interocularDistance, iod > 0 else { return nil }
        let matched = correspondingPoints(a.landmarks, b.landmarks)
        let (fitSrc, fitDst) = flatten(matched, in: geometryFitRegions)
        let (probeSrc, probeDst) = flatten(matched, in: geometryProbeRegions)
        let (eyeSrc, eyeDst) = flatten(matched, in: [.leftEye, .rightEye])
        guard fitSrc.count >= 6, probeSrc.count >= 2 else { return nil }
        guard let homography = LandmarkGeometry.solveRobustHomography(from: fitSrc, to: fitDst) else { return nil }

        let eyeMags = zip(eyeSrc, eyeDst).map { hypot($1.x - homography.apply($0).x, $1.y - homography.apply($0).y) / iod }
        let probeVecs: [(CGFloat, CGFloat)] = zip(probeSrc, probeDst).map { src, dst in
            let predicted = homography.apply(src)
            return ((dst.x - predicted.x) / iod, (dst.y - predicted.y) / iod)
        }
        let probeMags = probeVecs.map { hypot($0.0, $0.1) }
        // Eyes are the rigid anchors — expression in the fit set must not set the noise scale.
        let noiseMags: [CGFloat]
        if eyeMags.count >= 2 {
            noiseMags = eyeMags
        } else {
            noiseMags = zip(fitSrc, fitDst).map { hypot($1.x - homography.apply($0).x, $1.y - homography.apply($0).y) / iod }
        }
        let fitResidual = LandmarkGeometry.medianValue(noiseMags)
        let probeResidual = LandmarkGeometry.medianValue(probeMags)
        let noiseFloor: CGFloat = 0.002
        let excess = probeResidual / max(fitResidual, noiseFloor)

        let meanX = probeVecs.reduce(CGFloat(0)) { $0 + $1.0 } / CGFloat(probeVecs.count)
        let meanY = probeVecs.reduce(CGFloat(0)) { $0 + $1.1 } / CGFloat(probeVecs.count)
        let meanMag = probeMags.reduce(0, +) / CGFloat(probeMags.count)
        let coherence = meanMag > 1e-8 ? hypot(meanX, meanY) / meanMag : 0

        let motion = zip(fitSrc, fitDst).map { hypot($1.x - $0.x, $1.y - $0.y) }.reduce(0, +)
            / (CGFloat(fitSrc.count) * iod)

        return PairSample(
            fitResidual: fitResidual,
            probeResidual: probeResidual,
            excess: excess,
            coherence: coherence,
            motion: motion
        )
    }

    /// Points present, with matching per-region counts, in both frames — avoids silently pairing unrelated points.
    private static func correspondingPoints(
        _ a: [LandmarkPoint], _ b: [LandmarkPoint]
    ) -> [LandmarkRegion: (source: [CGPoint], destination: [CGPoint])] {
        let aByRegion = Dictionary(grouping: a, by: \.region)
        let bByRegion = Dictionary(grouping: b, by: \.region)
        var result: [LandmarkRegion: (source: [CGPoint], destination: [CGPoint])] = [:]
        for region in LandmarkRegion.allCases {
            guard let aPoints = aByRegion[region], let bPoints = bByRegion[region],
                  aPoints.count == bPoints.count, !aPoints.isEmpty else { continue }
            let aSorted = aPoints.sorted { $0.indexInRegion < $1.indexInRegion }
            let bSorted = bPoints.sorted { $0.indexInRegion < $1.indexInRegion }
            result[region] = (aSorted.map(\.point), bSorted.map(\.point))
        }
        return result
    }

    private static func flatten(
        _ byRegion: [LandmarkRegion: (source: [CGPoint], destination: [CGPoint])],
        in regions: Set<LandmarkRegion>
    ) -> (source: [CGPoint], destination: [CGPoint]) {
        var source: [CGPoint] = []
        var destination: [CGPoint] = []
        for region in LandmarkRegion.allCases where regions.contains(region) {
            guard let points = byRegion[region] else { continue }
            source += points.source
            destination += points.destination
        }
        return (source, destination)
    }

    private static func pairIndices(count: Int) -> [(Int, Int, CGFloat)] {
        guard count >= 2 else { return [] }
        var pairs: [(Int, Int, CGFloat)] = []
        for i in 0..<(count - 1) {
            pairs.append((i, i + 1, 1))
        }
        let half = max(count / 2, 2)
        if count > 4 {
            for i in 0..<(count - half) {
                pairs.append((i, i + half, 2))
            }
        }
        if count > 2 {
            pairs.append((0, count - 1, 3))
        }
        return pairs
    }

    // MARK: - Diagnostic ratios (display only)

    private static func centroid(_ points: [LandmarkPoint]?) -> CGPoint? {
        guard let points, !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.point.x, y: $0.y + $1.point.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func diagnosticRatios(from frame: LivenessFrame?) -> [String: CGFloat] {
        guard let frame else { return [:] }
        let grouped = Dictionary(grouping: frame.landmarks, by: \.region)
        var ratios: [String: CGFloat] = [:]
        if let iod = frame.interocularDistance, iod > 0 { ratios["interocular"] = iod }
        let xs = frame.landmarks.map(\.point.x)
        let ys = frame.landmarks.map(\.point.y)
        let faceWidth = (xs.max() ?? 0) - (xs.min() ?? 0)
        let faceHeight = (ys.max() ?? 0) - (ys.min() ?? 0)
        if faceWidth > 0, let iod = frame.interocularDistance, iod > 0 {
            ratios["eye / faceW"] = iod / faceWidth
        }
        if let left = centroid(grouped[.leftEye]), let right = centroid(grouped[.rightEye]),
           let nose = centroid(grouped[.nose]), faceHeight > 0 {
            let eyeMid = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
            ratios["nose-eye / faceH"] = hypot(nose.x - eyeMid.x, nose.y - eyeMid.y) / faceHeight
            if let lips = grouped[.outerLips], !lips.isEmpty {
                let mouth = CGPoint(
                    x: lips.reduce(CGFloat(0)) { $0 + $1.point.x } / CGFloat(lips.count),
                    y: lips.reduce(CGFloat(0)) { $0 + $1.point.y } / CGFloat(lips.count)
                )
                ratios["nose-mouth / faceH"] = hypot(mouth.x - nose.x, mouth.y - nose.y) / faceHeight
                if faceWidth > 0 {
                    let mouthW = (lips.map(\.point.x).max() ?? 0) - (lips.map(\.point.x).min() ?? 0)
                    ratios["mouthW / faceW"] = mouthW / faceWidth
                }
                let noseMouth = hypot(mouth.x - nose.x, mouth.y - nose.y)
                if noseMouth > 0, let iod = frame.interocularDistance {
                    ratios["eye / nose-mouth"] = iod / noseMouth
                }
            }
        }
        return ratios
    }

    // MARK: - Stats

    private static func weightedMedian(_ values: [CGFloat], weights: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty, values.count == weights.count else { return nil }
        let sorted = zip(values, weights).sorted { $0.0 < $1.0 }
        let total = sorted.reduce(CGFloat(0)) { $0 + $1.1 }
        guard total > 0 else { return LandmarkGeometry.medianValue(values) }
        var acc: CGFloat = 0
        for (value, weight) in sorted {
            acc += weight
            if acc >= total / 2 { return value }
        }
        return sorted.last?.0
    }

    private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
