// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScreenshotCanvasSupportTests {
    static func image(width: Int, height: Int) -> CGImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<height {
            for x in 0..<width { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) }
        }
        bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: 0, y: 0)
        return bitmap.cgImage!
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let context = CGContext(data: nil, width: 1, height: 1,
                                bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: bytes, count: 4))
    }

    static func run(_ suite: TestSuite) {
        let size = CGSize(width: 40, height: 40)
        let bounds = CGRect(origin: .zero, size: size)
        for handle in ScreenshotSupport.Handle.allCases {
            suite.expect(ScreenshotCanvasSupport.expansionHandle(
                at: handle.position(in: bounds), rect: bounds, tolerance: 28) == handle,
                "small Retina canvas picks the intended expansion handle")
        }
        suite.expect(ScreenshotCanvasSupport.expansionHandle(
            at: CGPoint(x: 20, y: 36), rect: bounds, tolerance: 28) == .bottom,
            "inset bottom grip does not resolve to the right edge")
        suite.expect(ScreenshotCanvasSupport.expansionHandle(
            at: CGPoint(x: 20, y: 20), rect: bounds, tolerance: 28) == nil,
            "canvas interior does not start expansion")
        suite.expect(ScreenshotCanvasSupport.expansionHandle(
            at: CGPoint(x: 40, y: 40), rect: CGRect(x: 0, y: 0, width: 4000, height: 4000),
            tolerance: 10 / 0.1) == .topLeft,
            "zoomed-out canvas accepts the displayed inset grip")
        let down = ScreenshotCanvasSupport.expandedRect(
            size: size, handle: .bottom, point: CGPoint(x: 20, y: 60))
        suite.expect(down == CGRect(x: 0, y: 0, width: 40, height: 60),
                     "bottom expansion preserves width and adds 20 rows")
        let upLeft = ScreenshotCanvasSupport.expandedRect(
            size: size, handle: .topLeft, point: CGPoint(x: -10, y: -20))
        suite.expect(upLeft == CGRect(x: -10, y: -20, width: 50, height: 60),
                     "top-left expansion retains the old origin in draft space")
        suite.expect(ScreenshotCanvasSupport.expandedRect(
            size: size, handle: .bottom, point: CGPoint(x: 20, y: 10))
            == CGRect(origin: .zero, size: size), "inward drag cannot crop")
        suite.expect(!ScreenshotCanvasSupport.validSize(CGSize(width: 60_000_001, height: 1)),
                     "canvas rejects pixel overflow before allocation")
        let base = image(width: 40, height: 40)
        for fill in [ScreenshotCanvasSupport.Fill.white, .transparent,
                     .color(red: 0, green: 0, blue: 1)] {
            guard let result = ScreenshotCanvasSupport.expandedImage(
                base, to: down!, fill: fill) else {
                suite.expect(false, "valid canvas expansion produces an image")
                continue
            }
            suite.expect(result.width == 40 && result.height == 60, "exact export dimensions")
            suite.expect(pixel(result, x: 0, y: 0)[3] == 0,
                         "white padding does not flatten source transparency")
            suite.expect(pixel(result, x: 20, y: 20) == [255, 0, 0, 255],
                         "original pixels remain unchanged")
            let blank = pixel(result, x: 20, y: 50)
            suite.expect(blank[3] == (fill == .transparent ? 0 : 255),
                         "new region has the chosen alpha")
            if fill == .white { suite.expect(blank == [255, 255, 255, 255], "white region") }
            if fill == .color(red: 0, green: 0, blue: 1) {
                suite.expect(blank == [0, 0, 255, 255], "custom region")
            }
        }
    }
}
