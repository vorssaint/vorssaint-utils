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

    static func capture(region: RecorderSupport.Region,
                        includePointer: Bool,
                        hideVorssaintWindows: Bool,
                        protectedWindowIDs: Set<CGWindowID>,
                        finishSignal: FinishSignal,
                        targetPID: pid_t,
                        onProgress: @escaping @MainActor (Int) -> Void) async -> Result {
        do {
            guard let targetApplication = NSRunningApplication(
                processIdentifier: targetPID) else { return .failed }
            _ = await MainActor.run { targetApplication.activate(options: []) }
            try await Task.sleep(nanoseconds: 140_000_000)
            try Task.checkCancellation()

            guard let first = await capturedRegion(region,
                                                   includePointer: includePointer,
                                                   hideVorssaintWindows: hideVorssaintWindows,
                                                   protectedWindowIDs: protectedWindowIDs)
            else { return .failed }
            try Task.checkCancellation()
            guard let firstSample = sample(first) else { return .failed }

            let startedAt = ProcessInfo.processInfo.systemUptime
            let step = ScreenshotSupport.scrollingCaptureStepPoints(
                regionHeight: region.anchorRect.height)
            var slices = [first]
            var previousSample = firstSample
            var totalHeight = first.height
            var retainedPixels = first.width * first.height
            await onProgress(totalHeight)

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
                guard try await postScrollDown(points: step,
                                               anchorRect: region.anchorRect) else {
                    return .failed
                }
                guard let settled = try await capturedAfterScroll(
                    region: region,
                    includePointer: includePointer,
                    hideVorssaintWindows: hideVorssaintWindows,
                    protectedWindowIDs: protectedWindowIDs,
                    previousSample: previousSample)
                else { return .failed }
                let current = settled.image
                let currentSample = settled.sample
                let transition = settled.transition

                switch transition {
                case .end:
                    return completed(slices: slices, region: region, result: .success)

                case .advanced(let sampleOverlap):
                    let overlap = Int((CGFloat(sampleOverlap) / CGFloat(currentSample.height)
                        * CGFloat(current.height)).rounded())
                    guard overlap > 0, overlap < current.height else { return .failed }
                    let stripHeight = current.height - overlap
                    let nextHeight = totalHeight + stripHeight
                    guard current.width > 0,
                          nextHeight <= ScreenshotSupport.scrollingCaptureMaximumPixels
                            / current.width
                    else {
                        return completed(slices: slices, region: region, result: .limited)
                    }
                    guard let strip = copiedStrip(from: current, topCrop: overlap)
                    else { return .failed }
                    let stripPixels = strip.width * strip.height
                    guard retainedPixels
                            <= ScreenshotSupport.scrollingCaptureMaximumRetainedPixels
                                - stripPixels else {
                        return completed(slices: slices, region: region, result: .limited)
                    }
                    // Keep only new pixels. Retaining every full frame made a
                    // common Retina selection hit the memory guard after about
                    // eleven scrolls even though the final image was still safe.
                    slices.append(strip)
                    totalHeight = nextHeight
                    retainedPixels += stripPixels
                    previousSample = currentSample
                    await onProgress(totalHeight)

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

    private static func completed(slices: [CGImage],
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
                                       includePointer: Bool,
                                       hideVorssaintWindows: Bool,
                                       protectedWindowIDs: Set<CGWindowID>) async -> CGImage? {
        await ScreenshotCaptureEngine.captureDisplayRegion(
            displayID: region.displayID,
            pixelRect: region.pixelRect,
            includePointer: includePointer,
            hideVorssaintWindows: hideVorssaintWindows,
            protectedWindowIDs: protectedWindowIDs)
    }

    private struct SettledFrame {
        let image: CGImage
        let sample: ScreenshotSupport.ScrollingSample
        let transition: ScreenshotSupport.ScrollingTransition
    }

    /// Captures until two consecutive views agree, while remembering the best
    /// usable frame. This adapts to inertial scrolling and content that arrives
    /// a little late without imposing the same fixed pause on every target.
    private static func capturedAfterScroll(
        region: RecorderSupport.Region,
        includePointer: Bool,
        hideVorssaintWindows: Bool,
        protectedWindowIDs: Set<CGWindowID>,
        previousSample: ScreenshotSupport.ScrollingSample
    ) async throws -> SettledFrame? {
        var lastSample: ScreenshotSupport.ScrollingSample?
        var best: SettledFrame?

        for attempt in 0..<7 {
            try await Task.sleep(nanoseconds: attempt == 0 ? 120_000_000 : 90_000_000)
            try Task.checkCancellation()
            guard let image = await capturedRegion(
                region,
                includePointer: includePointer,
                hideVorssaintWindows: hideVorssaintWindows,
                protectedWindowIDs: protectedWindowIDs),
                  let currentSample = sample(image)
            else { return nil }
            try Task.checkCancellation()

            let transition = ScreenshotSupport.scrollingTransition(
                previous: previousSample, current: currentSample)
            let frame = SettledFrame(image: image,
                                     sample: currentSample,
                                     transition: transition)
            if transition != .unmatched {
                best = frame
            }
            if let lastSample,
               ScreenshotSupport.scrollingSamplesAreStable(lastSample, currentSample) {
                return transition == .unmatched ? best : frame
            }
            lastSample = currentSample
        }
        return best
    }

    /// Resolve the app beneath the chosen area before our progress HUD appears.
    /// Keeping that app in front lets marked global scroll events reach the
    /// chosen content without moving the real pointer.
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
                                       anchorRect: CGRect) async throws -> Bool {
        let deltas = ScreenshotSupport.scrollingCaptureScrollDeltas(points: points)
        guard !deltas.isEmpty else { return false }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let location = CGPoint(x: anchorRect.midX,
                               y: mainHeight - anchorRect.midY)
        for delta in deltas {
            try Task.checkCancellation()
            guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                      units: .line,
                                      wheelCount: 1,
                                      wheel1: delta,
                                      wheel2: 0,
                                      wheel3: 0)
            else { return false }
            event.location = location
            event.setIntegerValueField(.eventSourceUserData,
                                       value: ScrollWheelSupport.syntheticTag)
            event.post(tap: .cghidEventTap)
            try await Task.sleep(nanoseconds: 4_000_000)
        }
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

    /// A cropped CGImage may keep its full source storage alive. Drawing the
    /// new strip into its own bitmap makes the retained-pixel guard truthful.
    private static func copiedStrip(from image: CGImage, topCrop: Int) -> CGImage? {
        let height = image.height - topCrop
        guard image.width > 0, height > 0,
              let source = image.cropping(to: CGRect(x: 0,
                                                     y: topCrop,
                                                     width: image.width,
                                                     height: height)),
              let context = CGContext(data: nil,
                                      width: image.width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: image.width, height: height))
        return context.makeImage()
    }

    private static func stitch(_ slices: [CGImage]) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        guard let first = slices.first else { return nil }
        guard slices.count > 1 else { return first }
        let width = slices.map(\.width).min() ?? first.width
        let height = slices.reduce(0) { $0 + $1.height }
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none

        var destinationY = height
        for slice in slices {
            guard !Task.isCancelled else { return nil }
            destinationY -= slice.height
            guard let piece = slice.cropping(to: CGRect(x: 0,
                                                        y: 0,
                                                        width: width,
                                                        height: slice.height))
            else { return nil }
            context.draw(piece, in: CGRect(x: 0, y: destinationY,
                                           width: piece.width, height: piece.height))
        }
        guard !Task.isCancelled, destinationY == 0 else { return nil }
        return context.makeImage()
    }
}
