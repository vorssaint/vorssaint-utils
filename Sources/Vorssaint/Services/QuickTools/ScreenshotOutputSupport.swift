// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The decisions behind changing what a capture becomes and how the editor
/// shows it: resizing it, making a before and after animation of it, and
/// zooming to a part of it. Pure geometry and encoding, so each rule is
/// testable without a window.
enum ScreenshotOutputSupport {
    // MARK: - Resize

    /// Neither side may end up below this or above the largest bitmap the
    /// renderer is asked to draw.
    static let resizeSideLimits: ClosedRange<CGFloat> = 8...16_384

    /// The new pixel size for a typed width or height, keeping the capture's
    /// proportions. Nil when nothing usable was typed, when the size would
    /// not change, or when either side would leave the limits.
    static func resizedSize(original: CGSize, width: Int? = nil, height: Int? = nil) -> CGSize? {
        guard original.width > 0, original.height > 0 else { return nil }
        let factor: CGFloat
        if let width, width > 0 {
            factor = CGFloat(width) / original.width
        } else if let height, height > 0 {
            factor = CGFloat(height) / original.height
        } else {
            return nil
        }
        return resizedSize(original: original, factor: factor)
    }

    static func resizedSize(original: CGSize, percent: Int) -> CGSize? {
        guard percent > 0 else { return nil }
        return resizedSize(original: original, factor: CGFloat(percent) / 100)
    }

    private static func resizedSize(original: CGSize, factor: CGFloat) -> CGSize? {
        guard factor.isFinite, factor > 0 else { return nil }
        let size = CGSize(width: max(1, (original.width * factor).rounded()),
                          height: max(1, (original.height * factor).rounded()))
        guard size != original,
              resizeSideLimits.contains(size.width), resizeSideLimits.contains(size.height)
        else { return nil }
        return size
    }

    /// The other side of a typed one, for the field that follows along.
    static func proportionalSide(_ typed: Int, of original: CGFloat, other: CGFloat) -> Int {
        guard original > 0 else { return 0 }
        return max(1, Int((CGFloat(typed) * other / original).rounded()))
    }

    // MARK: - Zoom

    /// The zoom (view points per image pixel) that shows `rect` whole inside
    /// `viewport` with `margin` around it.
    static func zoomToFit(_ rect: CGRect, viewport: CGSize, margin: CGFloat,
                          range: ClosedRange<CGFloat>) -> CGFloat? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let width = max(viewport.width - margin * 2, 1)
        let height = max(viewport.height - margin * 2, 1)
        let zoom = min(width / rect.width, height / rect.height)
        guard zoom.isFinite else { return nil }
        return min(max(zoom, range.lowerBound), range.upperBound)
    }

    /// Where a scroll view's visible area starts so `target` (content points)
    /// sits in its middle, kept within the scrollable range.
    static func scrollOrigin(centering target: CGRect, viewport: CGSize, content: CGSize) -> CGPoint {
        func clamped(_ value: CGFloat, _ limit: CGFloat) -> CGFloat {
            min(max(value, 0), max(limit, 0))
        }
        return CGPoint(x: clamped(target.midX - viewport.width / 2, content.width - viewport.width),
                       y: clamped(target.midY - viewport.height / 2, content.height - viewport.height))
    }

    // MARK: - Before and after

    /// The two frames of a comparison: the capture without the pasted images,
    /// then with them at full strength. A pasted image is often made see
    /// through only to line it up, which is not how it should end up.
    static func comparisonFrames(_ annotations: [ScreenshotSupport.Annotation])
        -> (before: [ScreenshotSupport.Annotation], after: [ScreenshotSupport.Annotation])? {
        guard annotations.contains(where: { $0.tool == .image }) else { return nil }
        let before = annotations.filter { $0.tool != .image }
        let after = annotations.map { annotation -> ScreenshotSupport.Annotation in
            guard annotation.tool == .image else { return annotation }
            var opaque = annotation
            opaque.opacity = 1
            return opaque
        }
        return (before, after)
    }

    /// Seconds each frame of the comparison stays up.
    static let comparisonFrameDelay = 1.0

    /// An endlessly looping animated GIF of `frames`.
    static func gifData(frames: [CGImage], delay: Double = comparisonFrameDelay) -> Data? {
        guard !frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frames.count, nil)
        else { return nil }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
