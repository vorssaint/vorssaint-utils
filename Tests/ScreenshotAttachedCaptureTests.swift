// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ScreenCaptureKit

/// Runs the production compositor with real pixel buffers and stream
/// configurations. Window acquisition and display scales are isolated doubles;
/// these checks do not replace a capture across physical displays.
enum ScreenshotAttachedCaptureTests {
    enum NSScreen {
        struct Screen {
            let backingScaleFactor: CGFloat
            var frame: CGRect = .zero
            let displayID: CGDirectDisplayID = 1
            var width: Int { Int(frame.width) }
            var height: Int { Int(frame.height) }
        }
        static var screens = [Screen(backingScaleFactor: 1), Screen(backingScaleFactor: 2)]
    }
    enum WindowPreviewProvider {
        static var images: [CGWindowID: CGImage] = [:]
        static var calls: [CGWindowID] = []
        static func captureViaWindowServer(_ id: CGWindowID) async -> CGImage? {
            calls.append(id)
            return images[id]
        }
    }
    struct Window {
        let windowID: CGWindowID
        var frame: CGRect { ScreenshotAttachedCaptureTests.frames[windowID] ?? .zero }
    }
    struct SCShareableContent {
        let windows: [Window]
        var displays: [NSScreen.Screen] { NSScreen.screens }
        static var ids: [CGWindowID] = [1, 2, 3]
        static var calls = 0
        static func excludingDesktopWindows(_ excluded: Bool,
                                             onScreenWindowsOnly: Bool) async throws -> Self {
            calls += 1
            return Self(windows: ids.map { Window(windowID: $0) })
        }
    }
    struct SCContentFilter {
        let windowIDs: [CGWindowID]
        let pointPixelScale: CGFloat
        init(desktopIndependentWindow window: Window) {
            windowIDs = [window.windowID]
            pointPixelScale = 1
        }
        init(display: NSScreen.Screen, including windows: [Window]) {
            windowIDs = windows.map(\.windowID)
            pointPixelScale = display.backingScaleFactor
        }
    }
    enum SCScreenshotManager {
        struct Request {
            let windowIDs: [CGWindowID]
            let configuration: SCStreamConfiguration
            var id: CGWindowID { windowIDs[0] }
        }
        enum Failure: Error { case missing }
        static var images: [CGWindowID: CGImage] = [:]
        static var requests: [Request] = []
        static func captureImage(contentFilter: SCContentFilter,
                                  configuration: SCStreamConfiguration) async throws -> CGImage {
            requests.append(Request(windowIDs: contentFilter.windowIDs, configuration: configuration))
            guard let id = contentFilter.windowIDs.first, let image = images[id] else { throw Failure.missing }
            return image
        }
    }

    private static let bounds = CGRect(x: 1200, y: 100, width: 80, height: 60)
    private static let frames: [CGWindowID: CGRect] = [
        1: bounds,
        2: CGRect(x: 1210, y: 108, width: 40, height: 24),
        3: CGRect(x: 1220, y: 116, width: 20, height: 8)
    ]
    private static let plan = ScreenshotCapturePolicy.AttachedCapturePlan(
        windowIDs: [1, 2, 3], bounds: bounds)

    static func run(_ suite: TestSuite) {
        var completed = false
        let task = Task { @MainActor in
            await checks(suite)
            reset()
            completed = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !completed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        if !completed { task.cancel() }
        suite.expect(completed, "attached captures complete without desktop access")
    }

    private static func reset(scale: CGFloat = 1) {
        NSScreen.screens = [.init(backingScaleFactor: 1), .init(backingScaleFactor: 2)]
        WindowPreviewProvider.images = Dictionary(uniqueKeysWithValues: frames.map { id, frame in
            (id, solid(width: Int(frame.width * scale), height: Int(frame.height * scale), channel: Int(id - 1)))
        })
        WindowPreviewProvider.calls = []
        SCShareableContent.ids = [1, 2, 3]
        SCShareableContent.calls = 0
        SCScreenshotManager.images = [:]
        SCScreenshotManager.requests = []
    }

    @MainActor private static func checks(_ suite: TestSuite) async {
        await filteredDisplayCrops(suite)
        reset(scale: 2)
        let whole = WindowPreviewProvider.images[1]!
        SCScreenshotManager.images[1] = whole
        let isolated = await Engine.captureIndependentWindow(1, scale: 2, requireFullFrame: true)
        let request = SCScreenshotManager.requests.last
        suite.expect(isolated === whole && request?.id == 1
                     && request?.configuration.width == whole.width
                     && request?.configuration.height == whole.height
                     && request?.configuration.ignoreGlobalClipSingleWindow == true,
                     "a frozen window beyond one display requests the whole isolated surface")
        SCScreenshotManager.images[1] = solid(width: 120, height: 120, channel: 0)
        let partial = await Engine.captureIndependentWindow(1, scale: 2, requireFullFrame: true)
        SCScreenshotManager.images[1] = nil
        let unavailable = await Engine.captureIndependentWindow(1, scale: 2, requireFullFrame: true)
        suite.expect(partial == nil && unavailable == nil,
                     "a clipped or unavailable window cannot be saved as a complete frozen-mode capture")

        for scale: CGFloat in [1, 2] {
            reset(scale: scale)
            let capture = await Engine.composeAttached(plan, frames: frames)
            expectPixels(capture, scale: scale, suite)
            suite.expect(WindowPreviewProvider.calls == [1, 2, 3] && SCScreenshotManager.requests.isEmpty,
                         "whole layers keep their native scale and need no independent recapture")
        }

        reset(scale: 2)
        SCScreenshotManager.images = WindowPreviewProvider.images
        WindowPreviewProvider.images[1] = solid(width: 77, height: 60, channel: 0)
        WindowPreviewProvider.images[2] = solid(width: 40, height: 24, channel: 1)
        WindowPreviewProvider.images[3] = nil
        let recaptured = await Engine.composeAttached(plan, frames: frames)
        expectPixels(recaptured, scale: 2, suite)
        suite.expect(SCScreenshotManager.requests.map(\.id) == [1, 2, 3] && SCShareableContent.calls == 1,
                     "clipped, differently scaled and missing buffers share one content snapshot and are recaptured")
        suite.expect(SCScreenshotManager.requests.allSatisfy { request in
            let configuration = request.configuration
            let frame = frames[request.id]!
            return configuration.width == Int(frame.width * 2)
                && configuration.height == Int(frame.height * 2)
                && configuration.ignoreGlobalClipSingleWindow
                && configuration.captureResolution == .best && !configuration.showsCursor
        }, "each independent layer requests its full frame beyond display clipping at the reported scale")

        reset(scale: 2)
        WindowPreviewProvider.images[2] = nil
        SCScreenshotManager.images[2] = solid(width: 77, height: 48, channel: 1)
        let clipped = await Engine.composeAttached(plan, frames: frames)
        suite.expect(clipped == nil, "an independently recaptured layer that is still clipped never becomes a stretched composite")
        SCScreenshotManager.images[2] = nil
        let failed = await Engine.composeAttached(plan, frames: frames)
        suite.expect(failed == nil, "failed recapture leaves the single-window fallback to answer")

        reset(scale: 2)
        WindowPreviewProvider.images[1] = nil
        SCShareableContent.ids = []
        let closed = await Engine.composeAttached(plan, frames: frames)
        suite.expect(closed == nil && SCScreenshotManager.requests.isEmpty,
                     "a window that disappeared from shareable content is not captured under another identity")
        reset()
        var incompleteFrames = frames
        incompleteFrames[2] = nil
        let incomplete = await Engine.composeAttached(plan, frames: incompleteFrames)
        suite.expect(incomplete == nil, "missing attachment geometry never produces a partial composite")
        reset()
        NSScreen.screens = []
        let noDisplay = await Engine.composeAttached(plan, frames: frames)
        suite.expect(noDisplay == nil && WindowPreviewProvider.calls.isEmpty,
                     "unknown display scale declines the composite before acquiring pixels")
    }

    @MainActor private static func filteredDisplayCrops(_ suite: TestSuite) async {
        reset()
        let screen = CGRect(x: 0, y: 0, width: 64, height: 48)
        NSScreen.screens = [.init(backingScaleFactor: 2, frame: screen)]
        let width = 128, height = 96
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let offset = CGPoint(x: 31.5, y: 17.5)
        let size = CGSize(width: 16, height: 8)
        let samples: [(x: Int, y: Int, color: [UInt8])] = [
            (0, 0, [255, 0, 0, 255]), (1, 0, [0, 128, 0, 128]),
            (2, 0, [0, 0, 0, 0]), (31, 15, [0, 0, 255, 255])
        ]
        let cases: [(layout: String, origin: CGPoint, drawnAt: CGPoint, ids: [CGWindowID])] = [
            ("top-left", .zero, .zero, [1]), ("placed", offset, offset, [1]), ("packed", offset, .zero, [1, 2])
        ]
        for (layout, origin, drawnAt, ids) in cases {
            let plan = ScreenshotCapturePolicy.AttachedCapturePlan(windowIDs: ids,
                                                                   bounds: CGRect(origin: origin, size: size))
            weak var displayBytes: NSMutableData?
            autoreleasepool {
                let bytes = NSMutableData(length: width * height * 4)!
                displayBytes = bytes
                for (x, y, color) in samples {
                    let column = Int(drawnAt.x * 2) + x
                    let row = Int(drawnAt.y * 2) + y
                    color.withUnsafeBytes { source in
                        bytes.mutableBytes.advanced(by: (row * width + column) * 4)
                            .copyMemory(from: source.baseAddress!, byteCount: 4)
                    }
                }
                // The provider alone owns the display's bytes after this pool drains.
                let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(bytes).toOpaque(),
                                              data: bytes.bytes, size: bytes.length) { info, _, _ in
                    Unmanaged<NSMutableData>.fromOpaque(info!).release()
                }!
                SCScreenshotManager.images[1] = CGImage(
                    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            }
            suite.expect(displayBytes != nil, "the display provider owns the source before capture")
            let capture = await Engine.captureAttached(plan)
            SCScreenshotManager.images = [:]
            guard let capture, capture.image.width == 32, capture.image.height == 16 else {
                suite.expect(false, "the filtered display returns the complete \(layout) Retina crop")
                continue
            }
            suite.expect(displayBytes == nil, "the \(layout) crop releases the filtered display's backing storage")
            suite.expect(capture.scale == 2 && SCScreenshotManager.requests.last?.windowIDs == ids
                         && capture.image.colorSpace.map { CFEqual($0, space) } == true,
                         "the \(layout) crop keeps the filter's windows, scale and colour space")
            suite.expect(samples.allSatisfy { rgba(capture.image, x: $0.x, y: $0.y) == $0.color },
                         "the \(layout) crop keeps the top-left and bottom-right pixels, single-pixel detail and alpha")
        }

        let full = ScreenshotCapturePolicy.AttachedCapturePlan(windowIDs: [1], bounds: screen)
        let unavailable = await Engine.captureAttached(full)
        suite.expect(unavailable == nil, "an unavailable filtered display leaves the window fallback to answer")
        let whole = solid(width: width, height: height, channel: 0)
        SCScreenshotManager.images[1] = whole
        let fullCapture = await Engine.captureAttached(full)
        suite.expect(fullCapture?.image === whole && fullCapture?.scale == 2,
                     "a window covering the full display reuses the acquired image")

        // An indexed image can be cropped, though its colour space cannot back a bitmap context.
        let palette = CGColorSpace(indexedBaseSpace: space, last: 1, colorTable: [0, 0, 0, 255, 0, 0])!
        let indices = Data(repeating: 0xFF, count: width / 8 * height)
        SCScreenshotManager.images[1] = CGImage(
            width: width, height: height, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: width / 8,
            space: palette, bitmapInfo: [], provider: CGDataProvider(data: indices as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        let indexed = await Engine.captureAttached(.init(windowIDs: [1], bounds: CGRect(origin: .zero, size: size)))
        suite.expect(indexed?.image.colorSpace?.model == .indexed && indexed?.scale == 2
                     && indexed?.image.width == 32 && indexed?.image.height == 16
                     && indexed.map { rgba($0.image, x: 0, y: 0) } == [255, 0, 0, 255],
                     "an unavailable bitmap copy returns the window crop in its original indexed format")
    }

    private static func expectPixels(_ capture: (image: CGImage, scale: CGFloat)?,
                                     scale: CGFloat, _ suite: TestSuite) {
        guard let capture else {
            suite.expect(false, "a complete attached-window plan produces an image")
            return
        }
        suite.expect(capture.scale == scale && capture.image.width == Int(80 * scale)
                        && capture.image.height == Int(60 * scale),
                     "the composite reports the scale used for its canvas")
        for (x, y, channel) in [(2, 2, 0), (11, 9, 1), (21, 17, 2)] {
            let pixel = rgba(capture.image, x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))
            suite.expect(pixel[channel] > 240 && pixel[(channel + 1) % 3] < 10
                            && pixel[(channel + 2) % 3] < 10 && pixel[3] == 255,
                         "layer \(channel) at \(scale)x keeps its position and drawing order, found \(pixel)")
        }
    }

    private static func solid(width: Int, height: Int, channel: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: space,
                                     components: [channel == 0 ? 1 : 0, channel == 1 ? 1 : 0,
                                                  channel == 2 ? 1 : 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!,
                         in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }
}
