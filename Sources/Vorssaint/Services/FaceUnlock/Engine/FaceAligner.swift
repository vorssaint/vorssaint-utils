// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.
//
//  ArcFace requires faces warped into a canonical pose (eyes level, fixed positions) — a loose crop tanks its accuracy.
//  Solves the 2D similarity transform mapping 5 detected landmarks onto the standard ArcFace template, then warps.

import Vision
import CoreGraphics

struct AlignedFace {
    let image: CGImage   // 112x112, canonically aligned
    let tier: AlignmentTier
}

enum AlignmentTier: String {
    case fivePoint = "5-point"
    case twoPoint = "2-point (eyes only)"
    case paddedCrop = "padded crop (no alignment)"
}

nonisolated enum FaceAligner {
    static let outputSize = 112

    /// Standard ArcFace 112x112 template: left eye, right eye, nose, left mouth, right mouth. "Left"/"right" are
    /// on-screen, not anatomical — see the ordering fix in `fivePoints(from:imageSize:)`.
    private static let referencePoints: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]
    private static let eyeReferencePoints = Array(referencePoints[0...1])

    /// Best-effort: 5-point landmarks, falling back to 2-point (eyes only), falling back to a padded crop.
    static func align(_ face: DetectedFace, from image: CGImage) -> AlignedFace? {
        let imageSize = CGSize(width: image.width, height: image.height)

        if let landmarks = face.landmarks,
           let points = fivePoints(from: landmarks, imageSize: imageSize),
           let warped = warp(image, sourcePoints: points, destinationPoints: referencePoints) {
            return AlignedFace(image: warped, tier: .fivePoint)
        }

        if let landmarks = face.landmarks,
           let eyes = twoPoints(from: landmarks, imageSize: imageSize),
           let warped = warp(image, sourcePoints: eyes, destinationPoints: eyeReferencePoints) {
            return AlignedFace(image: warped, tier: .twoPoint)
        }

        guard let cropped = FaceDetector.crop(face, from: image),
              let resized = resize(cropped, to: outputSize) else { return nil }
        return AlignedFace(image: resized, tier: .paddedCrop)
    }

    // MARK: - Landmark extraction
    //
    // Point/centroid/eye-center/transform math lives in `LandmarkGeometry`, shared with the liveness analyzer.

    private static func fivePoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [CGPoint]? {
        guard let eyeA = LandmarkGeometry.eyeCenter(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize),
              let eyeB = LandmarkGeometry.eyeCenter(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize),
              let nose = landmarks.nose, let noseCenter = LandmarkGeometry.centroid(of: nose, imageSize: imageSize),
              let outerLips = landmarks.outerLips else { return nil }

        // Vision's leftEye/rightEye are anatomical, not on-screen — sort by x instead of trusting either label.
        let imageLeftEye = eyeA.x <= eyeB.x ? eyeA : eyeB
        let imageRightEye = eyeA.x <= eyeB.x ? eyeB : eyeA

        let lipPoints = LandmarkGeometry.imagePoints(of: outerLips, imageSize: imageSize)
        guard let imageLeftMouth = lipPoints.min(by: { $0.x < $1.x }),
              let imageRightMouth = lipPoints.max(by: { $0.x < $1.x }) else { return nil }

        return [imageLeftEye, imageRightEye, noseCenter, imageLeftMouth, imageRightMouth]
    }

    private static func twoPoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [CGPoint]? {
        guard let eyeA = LandmarkGeometry.eyeCenter(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize),
              let eyeB = LandmarkGeometry.eyeCenter(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize) else { return nil }
        return eyeA.x <= eyeB.x ? [eyeA, eyeB] : [eyeB, eyeA]
    }

    // MARK: - Warp

    /// Points are given in top-left/y-down space but flipped before solving since CGContext is bottom-left/y-up;
    /// the image itself needs no flip since `CGContext.draw(_:in:)` already handles a CGImage's row order.
    private static func warp(_ image: CGImage, sourcePoints: [CGPoint], destinationPoints: [CGPoint]) -> CGImage? {
        let imageHeight = CGFloat(image.height)
        let sourceFlipped = sourcePoints.map { CGPoint(x: $0.x, y: imageHeight - $0.y) }
        let destinationFlipped = destinationPoints.map { CGPoint(x: $0.x, y: CGFloat(outputSize) - $0.y) }

        guard let transform = LandmarkGeometry.solveSimilarityTransform(from: sourceFlipped, to: destinationFlipped) else { return nil }

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: outputSize, height: outputSize,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return context.makeImage()
    }

    private static func resize(_ image: CGImage, to size: Int) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }
}
