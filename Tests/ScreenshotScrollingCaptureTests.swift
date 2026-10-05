// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Runs the production capture loop and pixel stitching with an isolated image
/// source. No screen permissions, global input or application windows are used.
enum ScreenshotScrollingCaptureTests {
    enum RecorderSupport {
        struct Region {
            let displayID: CGDirectDisplayID = 1
            let pixelRect = CGRect(x: 0, y: 0, width: 32, height: 120)
            let anchorRect = CGRect(x: 10, y: 20, width: 16, height: 60)
            let scale: CGFloat = 2
        }
    }
    enum ScreenshotSelectionController {
        struct Capture {
            let image: CGImage
            let scale: CGFloat
            let anchorRect: CGRect
        }
    }
    @MainActor enum ScreenshotCaptureEngine {
        static var source: Source!
        static var preparations = 0
        static func prepareDisplayRegion(displayID: CGDirectDisplayID, pixelRect: CGRect,
                                         includePointer: Bool, hideVorssaintWindows: Bool,
                                         protectedWindowIDs: Set<CGWindowID>) async -> Source? {
            preparations += 1
            return source
        }
        final class Source {
            let images: [CGImage?]
            let finish: ScreenshotScrollingCapture.FinishSignal
            var calls = 0
            init(_ images: [CGImage?], finish: ScreenshotScrollingCapture.FinishSignal) {
                self.images = images
                self.finish = finish
            }
            func image() async -> CGImage? {
                let index = min(calls, images.count - 1)
                calls += 1
                if calls >= images.count { finish.request() }
                return images[index]
            }
        }
    }

    static func run(_ suite: TestSuite) {
        var completed = false
        let task = Task { @MainActor in
            await checks(suite)
            completed = true
        }
        let deadline = Date().addingTimeInterval(12)
        while !completed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        if !completed { task.cancel() }
        suite.expect(completed, "scrolling capture completes without wheel events or desktop access")
    }

    static func frame(offset: Int, height: Int = 120, seed: Int = 0) -> CGImage {
        let width = 32
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let r = row + offset
                if seed == 0 {
                    pixels[row * width + column] = UInt8(
                        (r * 17 + column * 31 + (r / 7) * 13) % 251)
                } else {
                    var value = UInt32(r * width + column + seed)
                    value = (value ^ (value >> 16)) &* 0x45d9f3b
                    value = (value ^ (value >> 16)) &* 0x45d9f3b
                    pixels[row * width + column] = UInt8(truncatingIfNeeded: value ^ (value >> 16))
                }
            }
        }
        let data = Data(pixels) as CFData
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func paddedFrame(offset: Int) -> CGImage {
        let image = frame(offset: offset)
        let context = CGContext(data: nil, width: image.width + 1, height: image.height + 1,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // A transparent bottom row and right column, as a padded region capture.
        context.draw(image, in: CGRect(x: 0, y: 1, width: image.width, height: image.height))
        return context.makeImage()!
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    @MainActor static func checks(_ suite: TestSuite) async {
        // Match the reported output dimensions. Small synthetic images miss
        // rounding at the edges of strips drawn far down a tall bitmap.
        let sliceHeights = [1522, 160, 240, 320, 720, 400, 80, 1120, 400, 400, 78]
        let slices = sliceHeights.map { height -> CGImage in
            let context = CGContext(data: nil, width: 2876, height: height,
                                    bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2876, height: height))
            return context.makeImage()!
        }
        if let joined = ScreenshotScrollingCapture.stitch(slices) {
            var alpha = [UInt8](repeating: 0, count: joined.height)
            let context = CGContext(data: &alpha, width: 1, height: joined.height,
                                    bitsPerComponent: 8, bytesPerRow: 1,
                                    space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            context.draw(joined, in: CGRect(x: 0, y: 0, width: 1, height: joined.height))
            suite.expect(joined.height == 5440 && alpha.allSatisfy { $0 == 255 },
                         "tall Retina bitmap stitching never creates transparent seam rows")
        } else { suite.expect(false, "tall screenshot strips can be joined") }

        let retinaStart = frame(offset: 0, height: 1340, seed: 91)
        let retinaNext = frame(offset: 83, height: 1340, seed: 91)
        func sample(_ image: CGImage) -> ScreenshotSupport.ScrollingSample {
            .init(width: image.width, height: image.height,
                  pixels: Array(image.dataProvider!.data! as Data))
        }
        let matchingStarted = ProcessInfo.processInfo.systemUptime
        let transition = ScreenshotSupport.scrollingTransition(
            previous: sample(retinaStart), current: sample(retinaNext))
        let matchingDuration = ProcessInfo.processInfo.systemUptime - matchingStarted
        suite.expect(transition == .advanced(overlap: 1257, direction: .forward,
                                             contentColumns: 0..<32),
                     "Retina-height matching preserves the exact native-pixel overlap")
        // A generous bound for a ~0.1 s operation; the original unoptimized
        // nested loops took ~7 s, missing whole viewports during normal input.
        suite.expect(matchingDuration < 1,
                     "Retina matching must not stall the capture for a second (\(matchingDuration)s)")

        let region = RecorderSupport.Region()
        defer { ScreenshotCaptureEngine.source = nil }
        func capture(_ frames: [CGImage?]) async -> ScreenshotScrollingCapture.Result {
            let signal = ScreenshotScrollingCapture.FinishSignal()
            ScreenshotCaptureEngine.source = .init(frames, finish: signal)
            ScreenshotCaptureEngine.preparations = 0
            let result = await ScreenshotScrollingCapture.capture(
                region: region, includePointer: false, hideVorssaintWindows: true,
                protectedWindowIDs: [], finishSignal: signal, onProgress: { _ in })
            suite.expect(ScreenshotCaptureEngine.preparations == 1,
                         "scrolling session resolves its capture configuration only once")
            return result
        }
        if case .success(let capture) = await capture([frame(offset: 0), frame(offset: 42)]) {
            suite.expect(capture.image.height == 162 && capture.scale == 2
                         && capture.anchorRect == region.anchorRect,
                         "Done includes the last frame without a wheel event and preserves geometry")
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 162)),
                         "stitched pixels follow the document without duplicated or inverted strips")
        } else { suite.expect(false, "pixel polling must capture scrolling without mouse events") }

        if case .success(let capture) = await capture([
            paddedFrame(offset: 0), paddedFrame(offset: 42), paddedFrame(offset: 72)
        ]) {
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 192)),
                         "transparent capture-edge padding never becomes a seam or loses content rows")
        } else { suite.expect(false, "padded screen captures must still join") }

        if case .success(let capture) = await capture([frame(offset: 0)]) {
            suite.expect(capture.image.height == 120, "Done without scrolling returns the initial capture")
        } else { suite.expect(false, "Done must also work without any scroll movement") }

        if case .partial(let capture) = await capture([frame(offset: 0), frame(offset: 0, seed: 91)]) {
            suite.expect(capture.image.height == 120, "unmatched scrolling preserves the first frame")
        } else { suite.expect(false, "Done preserves a partial image when no overlap is found") }

        if case .partial(let capture) = await capture([
            frame(offset: 0), frame(offset: 42), frame(offset: 0, seed: 91)
        ]) {
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 162)),
                         "a later mismatch preserves all successfully stitched content")
        } else { suite.expect(false, "unmatched movement must return the completed portion") }

        if case .partial(let capture) = await capture([frame(offset: 0), nil]) {
            suite.expect(capture.image.height == 120, "a later capture failure keeps existing pixels")
        } else { suite.expect(false, "a later source failure must not discard the capture") }

        if case .success(let capture) = await capture([
            frame(offset: 0), frame(offset: 42), frame(offset: 12), frame(offset: 72)
        ]) {
            suite.expect(pixels(capture.image) == pixels(frame(offset: 0, height: 192)),
                         "backtracking and resuming never duplicates already captured content")
        } else { suite.expect(false, "scrolling back then forward still completes") }

        if case .failed = await capture([nil]) {} else {
            suite.expect(false, "failure before any frame is reported as failed")
        }

        let signal = ScreenshotScrollingCapture.FinishSignal()
        ScreenshotCaptureEngine.source = .init([frame(offset: 0)], finish: signal)
        let cancelled = Task {
            await ScreenshotScrollingCapture.capture(
                region: region, includePointer: false, hideVorssaintWindows: true,
                protectedWindowIDs: [], finishSignal: signal, onProgress: { _ in })
        }
        cancelled.cancel()
        if case .cancelled = await cancelled.value {} else {
            suite.expect(false, "Cancel must not deliver a screenshot")
        }
    }
}
