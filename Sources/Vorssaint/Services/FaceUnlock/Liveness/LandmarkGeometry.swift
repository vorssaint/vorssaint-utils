// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.
//
//  Shared landmark math used by `FaceAligner` and the liveness analyzer —
//  moved out of `FaceAligner` so the two call sites can't drift apart.

import Vision
import CoreGraphics

/// Every landmark region this app reads from `VNFaceLandmarks2D`. Includes several regions
/// `FaceAligner` never needed — liveness samples more of them for its residual-coherence check.
enum LandmarkRegion: String, CaseIterable, Hashable {
    case leftEye, rightEye
    case leftEyebrow, rightEyebrow
    case nose, noseCrest
    case outerLips, innerLips
    case faceContour, medianLine
}

/// One landmark point, tagged with where it came from. `indexInRegion` lets two frames'
/// points be paired up for cross-frame comparison.
struct LandmarkPoint {
    let point: CGPoint
    let region: LandmarkRegion
    let indexInRegion: Int
}

/// Pure geometry — `nonisolated` so it's callable from the same background
/// tasks `FaceAligner`/`FaceDetector` already run on.
nonisolated enum LandmarkGeometry {
    /// Vision returns points in bottom-left-origin, y-up; flipped here to top-left/y-down
    /// to match `DetectedFace.boundingBox`.
    static func imagePoints(of region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> [CGPoint] {
        region.pointsInImage(imageSize: imageSize).map { CGPoint(x: $0.x, y: imageSize.height - $0.y) }
    }

    static func centroid(of region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> CGPoint? {
        let points = imagePoints(of: region, imageSize: imageSize)
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Prefers the pupil landmark (a precise point) over the eye outline's
    /// centroid (an approximation from eyelid boundary points) when Vision
    /// provides one.
    static func eyeCenter(pupil: VNFaceLandmarkRegion2D?, eye: VNFaceLandmarkRegion2D?, imageSize: CGSize) -> CGPoint? {
        if let pupil, let center = centroid(of: pupil, imageSize: imageSize) { return center }
        if let eye { return centroid(of: eye, imageSize: imageSize) }
        return nil
    }

    /// Distance between the two eye centers — the normalization scale used throughout
    /// liveness scoring so scores stay comparable regardless of camera distance.
    static func interocularDistance(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> CGFloat? {
        guard let left = eyeCenter(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize),
              let right = eyeCenter(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize)
        else { return nil }
        return hypot(left.x - right.x, left.y - right.y)
    }

    /// Height/width of a landmark region's bounding box — a stand-in for the classic
    /// 6-point eye-aspect-ratio (Vision's point count isn't the fixed 6 that assumes).
    private static func boundingBoxAspectRatio(of region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> CGFloat? {
        let points = imagePoints(of: region, imageSize: imageSize)
        guard points.count >= 3, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }
        let width = maxX - minX
        guard width > 0 else { return nil }
        return (maxY - minY) / width
    }

    static func eyeAspectRatio(of eyeRegion: VNFaceLandmarkRegion2D, imageSize: CGSize) -> CGFloat? {
        boundingBoxAspectRatio(of: eyeRegion, imageSize: imageSize)
    }

    static func region(_ region: LandmarkRegion, of landmarks: VNFaceLandmarks2D) -> VNFaceLandmarkRegion2D? {
        switch region {
        case .leftEye: return landmarks.leftEye
        case .rightEye: return landmarks.rightEye
        case .leftEyebrow: return landmarks.leftEyebrow
        case .rightEyebrow: return landmarks.rightEyebrow
        case .nose: return landmarks.nose
        case .noseCrest: return landmarks.noseCrest
        case .outerLips: return landmarks.outerLips
        case .innerLips: return landmarks.innerLips
        case .faceContour: return landmarks.faceContour
        case .medianLine: return landmarks.medianLine
        }
    }

    /// Every point Vision detected, tagged by region and position so a later frame's
    /// points can be matched back up; a region missing this frame just contributes nothing.
    static func allPoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [LandmarkPoint] {
        var result: [LandmarkPoint] = []
        for regionCase in LandmarkRegion.allCases {
            guard let vnRegion = region(regionCase, of: landmarks) else { continue }
            let points = imagePoints(of: vnRegion, imageSize: imageSize)
            for (index, point) in points.enumerated() {
                result.append(LandmarkPoint(point: point, region: regionCase, indexInRegion: index))
            }
        }
        return result
    }

    // MARK: - Homography (projective) transform

    /// 3×3 homography — the model a flat photograph (or phone screen) is limited to,
    /// including perspective tilt; strictly more general than `solveSimilarityTransform`.
    struct Homography {
        let h11, h12, h13, h21, h22, h23, h31, h32, h33: CGFloat

        func apply(_ point: CGPoint) -> CGPoint {
            let w = h31 * point.x + h32 * point.y + h33
            guard abs(w) > 1e-12 else { return point }
            return CGPoint(
                x: (h11 * point.x + h12 * point.y + h13) / w,
                y: (h21 * point.x + h22 * point.y + h23) / w
            )
        }
    }

    /// Hartley-normalized DLT homography with `h33 = 1`, solved as an 8×8
    /// normal-equation system. Needs at least 4 correspondences; 6+ is
    /// the practical floor used by callers so the fit is overdetermined.
    static func solveHomography(from sourcePoints: [CGPoint], to destinationPoints: [CGPoint], weights: [CGFloat]? = nil) -> Homography? {
        guard sourcePoints.count == destinationPoints.count, sourcePoints.count >= 4 else { return nil }
        if let weights {
            guard weights.count == sourcePoints.count else { return nil }
        }

        guard let srcT = normalizingTransform(sourcePoints),
              let dstT = normalizingTransform(destinationPoints)
        else { return nil }

        let n = sourcePoints.count
        var ata = Array(repeating: Array(repeating: CGFloat(0), count: 8), count: 8)
        var atb = Array(repeating: CGFloat(0), count: 8)

        for i in 0..<n {
            let src = applyNormalization(sourcePoints[i], srcT)
            let dst = applyNormalization(destinationPoints[i], dstT)
            let w = (weights?[i] ?? 1).squareRoot()
            guard w > 0 else { continue }
            let x = src.x, y = src.y, u = dst.x, v = dst.y
            // Two DLT rows, h33 fixed at 1:
            // [x y 1 0 0 0 -u x -u y] · h = u
            // [0 0 0 x y 1 -v x -v y] · h = v
            let row0: [CGFloat] = [x * w, y * w, w, 0, 0, 0, -u * x * w, -u * y * w]
            let row1: [CGFloat] = [0, 0, 0, x * w, y * w, w, -v * x * w, -v * y * w]
            let b0 = u * w
            let b1 = v * w
            accumulateNormalEquations(row0, b0, into: &ata, atb: &atb)
            accumulateNormalEquations(row1, b1, into: &ata, atb: &atb)
        }

        guard let h = solveLinearSystem(ata, atb) else { return nil }
        let hNorm = Homography(
            h11: h[0], h12: h[1], h13: h[2],
            h21: h[3], h22: h[4], h23: h[5],
            h31: h[6], h32: h[7], h33: 1
        )
        return denormalizeHomography(hNorm, source: srcT, destination: dstT)
    }

    /// Two-pass IRLS around `solveHomography`, Tukey biweight, so one wildly jittered
    /// landmark can't pull the plane around. Cutoff uses the full-set median so a smiling
    /// mouth stays in the fit rather than letting an underconstrained homography absorb parallax.
    static func solveRobustHomography(from sourcePoints: [CGPoint], to destinationPoints: [CGPoint]) -> Homography? {
        guard var current = solveHomography(from: sourcePoints, to: destinationPoints) else { return nil }
        for _ in 0..<2 {
            let residuals = zip(sourcePoints, destinationPoints).map { hypot($1.x - current.apply($0).x, $1.y - current.apply($0).y) }
            let scale = max(medianValue(residuals), 1e-4)
            let cutoff = 4.685 * 1.4826 * scale
            var weights: [CGFloat] = residuals.map { r in
                let u = r / cutoff
                if u >= 1 { return 0 }
                let t = 1 - u * u
                return t * t
            }
            let inliers = weights.filter { $0 > 0 }.count
            if inliers < 6 {
                weights = Array(repeating: 1, count: sourcePoints.count)
            }
            if let refined = solveHomography(from: sourcePoints, to: destinationPoints, weights: weights) {
                current = refined
            }
        }
        return current
    }

    private struct SimilarityNorm {
        let scale: CGFloat
        let centerX: CGFloat
        let centerY: CGFloat
    }

    /// Translate to centroid, scale so mean distance from origin is √2.
    private static func normalizingTransform(_ points: [CGPoint]) -> SimilarityNorm? {
        let n = CGFloat(points.count)
        guard n > 0 else { return nil }
        let cx = points.reduce(CGFloat(0)) { $0 + $1.x } / n
        let cy = points.reduce(CGFloat(0)) { $0 + $1.y } / n
        let meanDist = points.reduce(CGFloat(0)) { $0 + hypot($1.x - cx, $1.y - cy) } / n
        guard meanDist > 1e-8 else { return nil }
        return SimilarityNorm(scale: CGFloat(2).squareRoot() / meanDist, centerX: cx, centerY: cy)
    }

    private static func applyNormalization(_ point: CGPoint, _ t: SimilarityNorm) -> CGPoint {
        CGPoint(x: t.scale * (point.x - t.centerX), y: t.scale * (point.y - t.centerY))
    }

    /// `H = Tdst⁻¹ · Hn · Tsrc`.
    private static func denormalizeHomography(_ h: Homography, source: SimilarityNorm, destination: SimilarityNorm) -> Homography {
        let s1 = source.scale, cx1 = source.centerX, cy1 = source.centerY
        let s2 = destination.scale, cx2 = destination.centerX, cy2 = destination.centerY
        // Tsrc
        let ts = (s1, CGFloat(0), -s1 * cx1, CGFloat(0), s1, -s1 * cy1, CGFloat(0), CGFloat(0), CGFloat(1))
        // Hn · Tsrc
        let hn = (h.h11, h.h12, h.h13, h.h21, h.h22, h.h23, h.h31, h.h32, h.h33)
        let m = multiply3x3(hn, ts)
        // Tdst⁻¹
        let ti = (1 / s2, CGFloat(0), cx2, CGFloat(0), 1 / s2, cy2, CGFloat(0), CGFloat(0), CGFloat(1))
        let r = multiply3x3(ti, m)
        return Homography(h11: r.0, h12: r.1, h13: r.2, h21: r.3, h22: r.4, h23: r.5, h31: r.6, h32: r.7, h33: r.8)
    }

    private static func multiply3x3(
        _ a: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat),
        _ b: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) {
        (
            a.0 * b.0 + a.1 * b.3 + a.2 * b.6,
            a.0 * b.1 + a.1 * b.4 + a.2 * b.7,
            a.0 * b.2 + a.1 * b.5 + a.2 * b.8,
            a.3 * b.0 + a.4 * b.3 + a.5 * b.6,
            a.3 * b.1 + a.4 * b.4 + a.5 * b.7,
            a.3 * b.2 + a.4 * b.5 + a.5 * b.8,
            a.6 * b.0 + a.7 * b.3 + a.8 * b.6,
            a.6 * b.1 + a.7 * b.4 + a.8 * b.7,
            a.6 * b.2 + a.7 * b.5 + a.8 * b.8
        )
    }

    private static func accumulateNormalEquations(_ row: [CGFloat], _ b: CGFloat, into ata: inout [[CGFloat]], atb: inout [CGFloat]) {
        for i in 0..<8 {
            atb[i] += row[i] * b
            for j in 0..<8 {
                ata[i][j] += row[i] * row[j]
            }
        }
    }

    /// Gaussian elimination with partial pivoting. `nil` if singular.
    static func solveLinearSystem(_ matrix: [[CGFloat]], _ rhs: [CGFloat]) -> [CGFloat]? {
        let n = rhs.count
        guard matrix.count == n, matrix.allSatisfy({ $0.count == n }) else { return nil }
        var a = matrix
        var b = rhs
        for k in 0..<n {
            var pivot = k
            var maxVal = abs(a[k][k])
            if k + 1 < n {
                for i in (k + 1)..<n {
                    let v = abs(a[i][k])
                    if v > maxVal {
                        maxVal = v
                        pivot = i
                    }
                }
            }
            if maxVal < 1e-12 { return nil }
            if pivot != k {
                a.swapAt(k, pivot)
                b.swapAt(k, pivot)
            }
            let diag = a[k][k]
            if k + 1 < n {
                for i in (k + 1)..<n {
                    let factor = a[i][k] / diag
                    for j in k..<n {
                        a[i][j] -= factor * a[k][j]
                    }
                    b[i] -= factor * b[k]
                }
            }
        }
        var x = [CGFloat](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[i]
            if i + 1 < n {
                for j in (i + 1)..<n {
                    sum -= a[i][j] * x[j]
                }
            }
            guard abs(a[i][i]) > 1e-12 else { return nil }
            x[i] = sum / a[i][i]
        }
        return x
    }

    static func medianValue(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    // MARK: - Similarity transform

    /// Closed-form least-squares similarity transform (rotation + uniform scale + translation),
    /// via 2D Procrustes in complex-number form — no SVD needed. This is exactly the model a flat
    /// presentation is limited to; motion it can't explain is the non-rigid residual `LivenessScoring` measures.
    static func solveSimilarityTransform(from sourcePoints: [CGPoint], to destinationPoints: [CGPoint]) -> CGAffineTransform? {
        guard sourcePoints.count == destinationPoints.count, sourcePoints.count >= 2 else { return nil }

        let n = CGFloat(sourcePoints.count)
        let srcSum = sourcePoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let srcMean = CGPoint(x: srcSum.x / n, y: srcSum.y / n)
        let dstSum = destinationPoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let dstMean = CGPoint(x: dstSum.x / n, y: dstSum.y / n)

        var numeratorReal: CGFloat = 0
        var numeratorImag: CGFloat = 0
        var denominator: CGFloat = 0
        for i in 0..<sourcePoints.count {
            let p = CGPoint(x: sourcePoints[i].x - srcMean.x, y: sourcePoints[i].y - srcMean.y)
            let q = CGPoint(x: destinationPoints[i].x - dstMean.x, y: destinationPoints[i].y - dstMean.y)
            // q * conj(p) = (qx + i*qy)(px - i*py) = (qx*px + qy*py) + i(qy*px - qx*py)
            numeratorReal += q.x * p.x + q.y * p.y
            numeratorImag += q.y * p.x - q.x * p.y
            denominator += p.x * p.x + p.y * p.y
        }
        guard denominator > 0 else { return nil }

        // scale*cos(theta), scale*sin(theta)
        let sc = numeratorReal / denominator
        let ss = numeratorImag / denominator

        // dst = R * scale * (src - srcMean) + dstMean, expanded into
        // CGAffineTransform's convention: x' = a*x + c*y + tx, y' = b*x + d*y + ty
        let a = sc, b = ss, c = -ss, d = sc
        let tx = dstMean.x - (a * srcMean.x + c * srcMean.y)
        let ty = dstMean.y - (b * srcMean.x + d * srcMean.y)
        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}
