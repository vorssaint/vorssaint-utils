// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Captures a selected region until scrolling no longer changes it, then joins
/// only overlaps that can be identified confidently. Nothing stays installed
/// between captures: each scroll event, image and sample belongs to this call.
enum ScreenshotScrollingCapture {
    enum Result {
        case success(ScreenshotSelectionController.Capture)
        case cancelled
        case tooLong
        case failed
    }

    private struct StitchSlice {
        let image: CGImage
        let topCrop: Int
    }

    static func capture(region: RecorderSupport.Region,
                        includePointer: Bool) async -> Result {
        do {
            try await Task.sleep(nanoseconds: 140_000_000)
            try Task.checkCancellation()

            guard let first = await capturedRegion(region, includePointer: includePointer),
                  let firstSample = sample(first)
            else { return .failed }

            let startedAt = ProcessInfo.processInfo.systemUptime
            let step = ScreenshotSupport.scrollingCaptureStepPoints(
                regionHeight: region.anchorRect.height)
            var slices = [StitchSlice(image: first, topCrop: 0)]
            var previousSample = firstSample
            var totalHeight = first.height

            while true {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime - startedAt
                        < ScreenshotSupport.scrollingCaptureMaximumDuration
                else { return .tooLong }
                guard postScrollDown(points: step, anchorRect: region.anchorRect) else {
                    return .failed
                }
                try await Task.sleep(nanoseconds: 360_000_000)
                try Task.checkCancellation()

                guard var current = await capturedRegion(region, includePointer: includePointer),
                      var currentSample = sample(current)
                else { return .failed }
                var transition = ScreenshotSupport.scrollingTransition(
                    previous: previousSample, current: currentSample)

                // A target with animated or inertial scrolling may still be
                // moving at the first capture. One settled retry avoids both a
                // false seam and another scroll event.
                if transition == .unmatched {
                    try await Task.sleep(nanoseconds: 180_000_000)
                    try Task.checkCancellation()
                    guard let settled = await capturedRegion(region,
                                                             includePointer: includePointer),
                          let settledSample = sample(settled)
                    else { return .failed }
                    current = settled
                    currentSample = settledSample
                    transition = ScreenshotSupport.scrollingTransition(
                        previous: previousSample, current: currentSample)
                }

                switch transition {
                case .end:
                    guard let image = stitch(slices) else { return .failed }
                    return .success(ScreenshotSelectionController.Capture(
                        image: image,
                        scale: region.scale,
                        anchorRect: region.anchorRect))

                case .advanced(let sampleOverlap):
                    let overlap = Int((CGFloat(sampleOverlap) / CGFloat(currentSample.height)
                        * CGFloat(current.height)).rounded())
                    guard overlap > 0, overlap < current.height else { return .failed }
                    let nextHeight = totalHeight + current.height - overlap
                    guard current.width > 0,
                          nextHeight <= ScreenshotSupport.scrollingCaptureMaximumPixels
                            / current.width
                    else { return .tooLong }
                    slices.append(StitchSlice(image: current, topCrop: overlap))
                    totalHeight = nextHeight
                    previousSample = currentSample

                case .unmatched:
                    return .failed
                }
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
    }

    private static func capturedRegion(_ region: RecorderSupport.Region,
                                       includePointer: Bool) async -> CGImage? {
        await ScreenshotCaptureEngine.captureDisplayRegion(
            displayID: region.displayID,
            pixelRect: region.pixelRect,
            includePointer: includePointer)
    }

    private static func postScrollDown(points: CGFloat, anchorRect: CGRect) -> Bool {
        let pixels = Int32(clamping: Int(points.rounded()))
        guard pixels > 0,
              let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 1,
                                  wheel1: -pixels,
                                  wheel2: 0,
                                  wheel3: 0)
        else { return false }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        event.location = CGPoint(x: anchorRect.midX,
                                 y: mainHeight - anchorRect.midY)
        event.setIntegerValueField(.eventSourceUserData,
                                   value: ScrollWheelSupport.syntheticTag)
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func sample(_ image: CGImage) -> ScreenshotSupport.ScrollingSample? {
        // Width can be reduced safely, but vertical rows stay one-for-one with
        // the source. Resizing both axes turns an integer scroll into a
        // fractional row offset and destroys an otherwise exact overlap.
        let width = min(32, image.width)
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ScreenshotSupport.ScrollingSample(width: width,
                                                 height: height,
                                                 pixels: pixels)
    }

    private static func stitch(_ slices: [StitchSlice]) -> CGImage? {
        guard let first = slices.first else { return nil }
        guard slices.count > 1 else { return first.image }
        let width = slices.map(\.image.width).min() ?? first.image.width
        guard let pieces = ScreenshotSupport.scrollingStitchPieces(
            frameHeights: slices.map(\.image.height),
            topCrops: slices.map(\.topCrop))
        else { return nil }
        let height = pieces.reduce(0) { $0 + $1.height }
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none

        for (slice, plan) in zip(slices, pieces) {
            guard plan.height > 0,
                  let piece = slice.image.cropping(to: CGRect(x: 0,
                                                              y: plan.sourceY,
                                                              width: width,
                                                              height: plan.height))
            else { return nil }
            context.draw(piece, in: CGRect(x: 0, y: plan.destinationY,
                                           width: piece.width, height: piece.height))
        }
        return context.makeImage()
    }
}
