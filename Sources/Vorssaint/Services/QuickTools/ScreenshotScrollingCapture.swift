// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin

/// Captures a selected region until scrolling no longer changes it, then joins
/// only overlaps that can be identified confidently. Nothing stays installed
/// between captures: each scroll event, image and sample belongs to this call.
enum ScreenshotScrollingCapture {
    final class FinishSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var requested = false

        func request() {
            lock.lock()
            requested = true
            lock.unlock()
        }

        var isRequested: Bool {
            lock.lock()
            defer { lock.unlock() }
            return requested
        }
    }

    enum Result {
        case success(ScreenshotSelectionController.Capture)
        case partial(ScreenshotSelectionController.Capture)
        case limited(ScreenshotSelectionController.Capture)
        case cancelled
        case failed
    }

    private struct StitchSlice {
        let image: CGImage
        let topCrop: Int
    }

    static func capture(region: RecorderSupport.Region,
                        includePointer: Bool,
                        finishSignal: FinishSignal,
                        targetPID: pid_t) async -> Result {
        do {
            try await Task.sleep(nanoseconds: 140_000_000)
            try Task.checkCancellation()

            guard let first = await capturedRegion(region, includePointer: includePointer)
            else { return .failed }
            try Task.checkCancellation()
            guard let firstSample = sample(first) else { return .failed }

            let startedAt = ProcessInfo.processInfo.systemUptime
            let step = ScreenshotSupport.scrollingCaptureStepPoints(
                regionHeight: region.anchorRect.height)
            var slices = [StitchSlice(image: first, topCrop: 0)]
            var previousSample = firstSample
            var totalHeight = first.height
            var retainedPixels = first.width * first.height

            while true {
                try Task.checkCancellation()
                if finishSignal.isRequested {
                    return completed(slices: slices, region: region, result: .success)
                }
                if ProcessInfo.processInfo.systemUptime - startedAt
                    >= ScreenshotSupport.scrollingCaptureMaximumDuration
                    || slices.count >= ScreenshotSupport.scrollingCaptureMaximumFrames {
                    return completed(slices: slices, region: region, result: .limited)
                }
                guard postScrollDown(points: step,
                                     anchorRect: region.anchorRect,
                                     targetPID: targetPID) else {
                    return .failed
                }
                try await Task.sleep(nanoseconds: 360_000_000)
                try Task.checkCancellation()

                guard var current = await capturedRegion(region, includePointer: includePointer)
                else { return .failed }
                try Task.checkCancellation()
                guard var currentSample = sample(current) else { return .failed }
                var transition = ScreenshotSupport.scrollingTransition(
                    previous: previousSample, current: currentSample)
                try Task.checkCancellation()

                // A target with animated or inertial scrolling may still be
                // moving at the first capture. One settled retry avoids both a
                // false seam and another scroll event.
                if transition == .unmatched {
                    try await Task.sleep(nanoseconds: 180_000_000)
                    try Task.checkCancellation()
                    guard let settled = await capturedRegion(region,
                                                             includePointer: includePointer)
                    else { return .failed }
                    try Task.checkCancellation()
                    guard let settledSample = sample(settled) else { return .failed }
                    current = settled
                    currentSample = settledSample
                    transition = ScreenshotSupport.scrollingTransition(
                        previous: previousSample, current: currentSample)
                    try Task.checkCancellation()
                }

                switch transition {
                case .end:
                    return completed(slices: slices, region: region, result: .success)

                case .advanced(let sampleOverlap):
                    let overlap = Int((CGFloat(sampleOverlap) / CGFloat(currentSample.height)
                        * CGFloat(current.height)).rounded())
                    guard overlap > 0, overlap < current.height else { return .failed }
                    let nextHeight = totalHeight + current.height - overlap
                    guard current.width > 0,
                          nextHeight <= ScreenshotSupport.scrollingCaptureMaximumPixels
                            / current.width
                    else {
                        return completed(slices: slices, region: region, result: .limited)
                    }
                    let currentPixels = current.width * current.height
                    guard retainedPixels <= ScreenshotSupport.scrollingCaptureMaximumRawPixels
                            - currentPixels else {
                        return completed(slices: slices, region: region, result: .limited)
                    }
                    slices.append(StitchSlice(image: current, topCrop: overlap))
                    totalHeight = nextHeight
                    retainedPixels += currentPixels
                    previousSample = currentSample

                case .unmatched:
                    guard slices.count > 1 else { return .failed }
                    return completed(slices: slices, region: region, result: .partial)
                }
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
    }

    private enum CompletedResult {
        case success
        case partial
        case limited
    }

    private static func completed(slices: [StitchSlice],
                                  region: RecorderSupport.Region,
                                  result: CompletedResult) -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard let image = stitch(slices) else {
            return Task.isCancelled ? .cancelled : .failed
        }
        guard !Task.isCancelled else { return .cancelled }
        let capture = ScreenshotSelectionController.Capture(
            image: image,
            scale: region.scale,
            anchorRect: region.anchorRect)
        switch result {
        case .success: return .success(capture)
        case .partial: return .partial(capture)
        case .limited: return .limited(capture)
        }
    }

    private static func capturedRegion(_ region: RecorderSupport.Region,
                                       includePointer: Bool) async -> CGImage? {
        await ScreenshotCaptureEngine.captureDisplayRegion(
            displayID: region.displayID,
            pixelRect: region.pixelRect,
            includePointer: includePointer)
    }

    /// Resolve the app beneath the chosen area before our progress HUD appears.
    /// Scroll events can then go straight to that app without moving the real
    /// pointer to the event's target coordinates.
    static func targetPID(for region: RecorderSupport.Region) -> pid_t? {
        let options: CGWindowListOption
        let relativeTo: CGWindowID
        if let windowID = region.windowID {
            options = [.optionIncludingWindow]
            relativeTo = windowID
        } else {
            options = [.optionOnScreenOnly, .excludeDesktopElements]
            relativeTo = kCGNullWindowID
        }
        guard let windows = CGWindowListCopyWindowInfo(options, relativeTo)
                as? [[String: Any]] else { return nil }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: region.anchorRect.midX,
                            y: mainHeight - region.anchorRect.midY)

        for window in windows {
            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid > 0,
                  let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (rawBounds["X"] as? NSNumber)?.doubleValue,
                  let y = (rawBounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (rawBounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (rawBounds["Height"] as? NSNumber)?.doubleValue,
                  CGRect(x: x, y: y, width: width, height: height).contains(point)
            else { continue }
            return pid_t(pid)
        }
        return nil
    }

    private static func postScrollDown(points: CGFloat,
                                       anchorRect: CGRect,
                                       targetPID: pid_t) -> Bool {
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
        event.postToPid(targetPID)
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
        guard !Task.isCancelled else { return nil }
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
            guard !Task.isCancelled else { return nil }
            guard plan.height > 0,
                  let piece = slice.image.cropping(to: CGRect(x: 0,
                                                              y: plan.sourceY,
                                                              width: width,
                                                              height: plan.height))
            else { return nil }
            context.draw(piece, in: CGRect(x: 0, y: plan.destinationY,
                                           width: piece.width, height: piece.height))
        }
        guard !Task.isCancelled else { return nil }
        return context.makeImage()
    }
}
