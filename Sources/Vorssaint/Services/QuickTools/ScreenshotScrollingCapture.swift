// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Watches a selected region while the person scrolls it, then joins only
/// overlaps that can be identified confidently. Pixel polling also handles
/// scrollbar drags and keyboard scrolling without global event permissions.
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

    private static let sampleInterval: TimeInterval = 0.09
    private static let settleInterval: TimeInterval = 0.22
    private static let finishGraceInterval: TimeInterval = 0.85

    static func capture(region: RecorderSupport.Region,
                        includePointer: Bool,
                        hideVorssaintWindows: Bool,
                        protectedWindowIDs: Set<CGWindowID>,
                        finishSignal: FinishSignal,
                        onProgress: @escaping @MainActor (Int) -> Void) async -> Result {
        do {
            guard let source = await ScreenshotCaptureEngine.prepareDisplayRegion(
                displayID: region.displayID, pixelRect: region.pixelRect,
                includePointer: includePointer, hideVorssaintWindows: hideVorssaintWindows,
                protectedWindowIDs: protectedWindowIDs),
                  let firstFrame = await source.image(),
                  let first = contentFrame(firstFrame)
            else { return Task.isCancelled ? .cancelled : .failed }
            try Task.checkCancellation()
            guard let firstSample = sample(first) else { return .failed }

            let startedAt = ProcessInfo.processInfo.systemUptime
            var slices = [first]
            var previousSample = firstSample
            var lastObservedSample = firstSample
            var totalHeight = first.height
            var retainedPixels = first.width * first.height
            var contentSampleColumns: Range<Int>?
            var contentPixelColumns: Range<Int>?
            var fixedBottomPixels = 0
            var footerSlice: CGImage?
            var hasUnmatchedContent = false
            var lastChangedAt = startedAt
            var lastCaptureAt = ProcessInfo.processInfo.systemUptime
            var scrollPending = false
            var finishRequestedAt: TimeInterval?
            await onProgress(totalHeight)

            while true {
                try Task.checkCancellation()

                let now = ProcessInfo.processInfo.systemUptime
                if finishSignal.isRequested, finishRequestedAt == nil {
                    finishRequestedAt = now
                    // Take one final frame even if no wheel event was delivered.
                    scrollPending = true
                }
                if let finishRequestedAt,
                   !scrollPending || now - finishRequestedAt >= finishGraceInterval {
                    return completedByUser(
                        slices: slices,
                        footerSlice: footerSlice,
                        region: region,
                        hasUnmatchedContent: hasUnmatchedContent)
                }
                if now - startedAt
                    >= ScreenshotSupport.scrollingCaptureMaximumDuration
                    || slices.count >= ScreenshotSupport.scrollingCaptureMaximumFrames {
                    return completed(slices: slices,
                                     footerSlice: footerSlice,
                                     region: region,
                                     result: .limited)
                }

                // Observe pixels throughout the session. Wheel monitors miss
                // scrollbar drags, keyboard scrolling and some other apps.
                let sinceLastCapture = now - lastCaptureAt
                if sinceLastCapture < sampleInterval {
                    try await Task.sleep(nanoseconds: UInt64(
                        (sampleInterval - sinceLastCapture) * 1_000_000_000))
                    continue
                }

                guard let frame = await source.image(),
                      let current = contentFrame(frame),
                      let currentSample = sample(current)
                else {
                    return completed(slices: slices, footerSlice: footerSlice,
                                     region: region, result: .partial)
                }
                try Task.checkCancellation()
                lastCaptureAt = ProcessInfo.processInfo.systemUptime
                let frameIsStable = ScreenshotSupport.scrollingSamplesAreStable(
                    lastObservedSample,
                    currentSample,
                    contentColumns: contentSampleColumns)
                lastObservedSample = currentSample
                if !frameIsStable { lastChangedAt = lastCaptureAt }
                let transition = ScreenshotSupport.scrollingTransition(
                    previous: previousSample,
                    current: currentSample,
                    contentColumns: contentSampleColumns)

                switch transition {
                case .end:
                    hasUnmatchedContent = false

                case .advanced(let sampleOverlap, .forward, let matchedColumns):
                    let overlap = Int((CGFloat(sampleOverlap) / CGFloat(currentSample.height)
                        * CGFloat(current.height)).rounded())
                    guard overlap > 0, overlap < current.height else { return .failed }
                    let establishingContent = contentSampleColumns == nil
                    if establishingContent {
                        guard let pixelColumns = ScreenshotSupport.scrollingPixelRange(
                            sampleColumns: matchedColumns,
                            sampleWidth: currentSample.width,
                            imageWidth: current.width)
                        else { return .failed }
                        let fixedBottomRows = ScreenshotSupport.scrollingFixedBottomRows(
                            previous: previousSample,
                            current: currentSample,
                            overlap: sampleOverlap,
                            contentColumns: matchedColumns)
                        fixedBottomPixels = Int(
                            (CGFloat(fixedBottomRows) / CGFloat(currentSample.height)
                                * CGFloat(current.height)).rounded())
                        guard let newContentRows = ScreenshotSupport.scrollingNewContentRows(
                            imageHeight: current.height,
                            overlap: overlap,
                            fixedBottomRows: fixedBottomPixels),
                              let croppedFirst = copiedStrip(from: first,
                                                            columns: pixelColumns,
                                                            topCrop: 0,
                                                            bottomCrop: fixedBottomPixels)
                        else { return .failed }
                        contentSampleColumns = matchedColumns
                        contentPixelColumns = pixelColumns
                        slices[0] = croppedFirst
                        retainedPixels = croppedFirst.width * croppedFirst.height

                        if fixedBottomPixels > 0 {
                            guard let footer = copiedStrip(
                                from: current,
                                columns: pixelColumns,
                                topCrop: newContentRows.upperBound,
                                bottomCrop: 0)
                            else { return .failed }
                            footerSlice = footer
                            retainedPixels += footer.width * footer.height
                        }
                    }
                    guard let pixelColumns = contentPixelColumns else { return .failed }
                    guard let newContentRows = ScreenshotSupport.scrollingNewContentRows(
                        imageHeight: current.height,
                        overlap: overlap,
                        fixedBottomRows: fixedBottomPixels)
                    else { return .failed }
                    let stripHeight = newContentRows.count
                    let nextHeight = totalHeight + stripHeight
                    guard !pixelColumns.isEmpty,
                          nextHeight <= ScreenshotSupport.scrollingCaptureMaximumPixels
                            / pixelColumns.count
                    else {
                        return completed(slices: slices,
                                         footerSlice: footerSlice,
                                         region: region,
                                         result: .limited)
                    }
                    guard let strip = copiedStrip(from: current,
                                                  columns: pixelColumns,
                                                  topCrop: newContentRows.lowerBound,
                                                  bottomCrop: current.height
                                                    - newContentRows.upperBound)
                    else { return .failed }
                    let stripPixels = strip.width * strip.height
                    guard stripPixels <= ScreenshotSupport.scrollingCaptureMaximumRetainedPixels,
                          retainedPixels
                            <= ScreenshotSupport.scrollingCaptureMaximumRetainedPixels
                                - stripPixels else {
                        return completed(slices: slices,
                                         footerSlice: footerSlice,
                                         region: region,
                                         result: .limited)
                    }
                    if fixedBottomPixels > 0, !establishingContent {
                        guard let footer = copiedStrip(
                            from: current,
                            columns: pixelColumns,
                            topCrop: current.height - fixedBottomPixels,
                            bottomCrop: 0)
                        else { return .failed }
                        footerSlice = footer
                    }
                    // Keep only new pixels. Retaining every full frame made a
                    // common Retina selection hit the memory guard after about
                    // eleven scrolls even though the final image was still safe.
                    slices.append(strip)
                    totalHeight = nextHeight
                    retainedPixels += stripPixels
                    previousSample = currentSample
                    hasUnmatchedContent = false
                    await onProgress(totalHeight)

                case .advanced(_, .backward, _):
                    // Scrolling back never duplicates pixels already kept. A
                    // later forward movement can continue from the furthest
                    // accepted frame without inventing a seam.
                    hasUnmatchedContent = false

                case .unmatched:
                    hasUnmatchedContent = true
                }

                scrollPending = !frameIsStable || lastCaptureAt - lastChangedAt < settleInterval
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
    }

    private static func completedByUser(slices: [CGImage],
                                        footerSlice: CGImage?,
                                        region: RecorderSupport.Region,
                                        hasUnmatchedContent: Bool) -> Result {
        guard hasUnmatchedContent else {
            return completed(slices: slices,
                             footerSlice: footerSlice,
                             region: region,
                             result: .success)
        }
        return completed(slices: slices,
                         footerSlice: footerSlice,
                         region: region,
                         result: .partial)
    }

    private enum CompletedResult {
        case success
        case partial
        case limited
    }

    private static func completed(slices: [CGImage],
                                  footerSlice: CGImage?,
                                  region: RecorderSupport.Region,
                                  result: CompletedResult) -> Result {
        guard !Task.isCancelled else { return .cancelled }
        let completedSlices = footerSlice.map { slices + [$0] } ?? slices
        guard let image = stitch(completedSlices) else {
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

    /// ScreenCaptureKit can pad a region with a transparent edge row. Keeping
    /// that row in each appended strip produces a dark seam in image viewers.
    /// Remove only fully transparent outer rows/columns before matching, so the
    /// overlap and strip coordinates describe the same actual screen pixels.
    private static func contentFrame(_ image: CGImage) -> CGImage? {
        if [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) { return image }
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var top = 0, bottom = height, left = 0, right = width
        while top < bottom && alpha[(top * width)..<((top + 1) * width)].allSatisfy({ $0 == 0 }) {
            top += 1
        }
        while bottom > top && alpha[((bottom - 1) * width)..<(bottom * width)].allSatisfy({ $0 == 0 }) {
            bottom -= 1
        }
        guard top < bottom else { return nil }
        while left < right && (top..<bottom).allSatisfy({ alpha[$0 * width + left] == 0 }) {
            left += 1
        }
        while right > left && (top..<bottom).allSatisfy({ alpha[$0 * width + right - 1] == 0 }) {
            right -= 1
        }
        guard left < right else { return nil }
        if top == 0 && bottom == height && left == 0 && right == width { return image }
        return image.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top))
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
    private static func copiedStrip(from image: CGImage,
                                    columns: Range<Int>,
                                    topCrop: Int,
                                    bottomCrop: Int) -> CGImage? {
        let height = image.height - topCrop - bottomCrop
        guard image.width > 0, height > 0,
              topCrop >= 0, bottomCrop >= 0,
              columns.lowerBound >= 0,
              columns.upperBound <= image.width,
              !columns.isEmpty,
              let source = image.cropping(to: CGRect(x: columns.lowerBound,
                                                     y: topCrop,
                                                     width: columns.count,
                                                     height: height)),
              let context = CGContext(data: nil,
                                      width: columns.count,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0,
                                       width: columns.count, height: height))
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
