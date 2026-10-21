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

        for (draftSize, displayScale) in [(CGSize(width: 680, height: 460), CGFloat(2)),
                                          (CGSize(width: 600, height: 400), CGFloat(1)),
                                          (CGSize(width: 9, height: 6), CGFloat(0.37))] {
            let layout = ExpansionPreview.Layout(draftSize: draftSize, displayScale: displayScale)
            let bounds = CGRect(origin: .zero, size: layout.size)
            let halfLine = layout.gripLineWidth / 2
            suite.expect(layout.draft.size == draftSize && layout.grips.count == 8
                    && layout.grips.allSatisfy { bounds.contains($0.insetBy(dx: -halfLine, dy: -halfLine)) },
                         "every expansion grip shows whole inside the preview, ring line included")
            suite.expect(layout.draft.minX > 0 && layout.draft.minX.truncatingRemainder(dividingBy: 8) == 0
                    && layout.draft.minY == layout.draft.minX,
                         "the preview's extra room is whole checker tiles, so a transparent fill continues the card's checkerboard")
            suite.expect(zip(ScreenshotSupport.Handle.allCases, layout.grips).allSatisfy { handle, grip in
                let point = handle.position(in: layout.draft)
                return abs(grip.midX - point.x) < 0.001 && abs(grip.midY - point.y) < 0.001
            }, "each expansion grip is centered on the draft edge a press picks up")
        }
        func corners(_ rect: CGRect) -> [CGPoint] {
            [CGPoint(x: rect.minX + 0.5, y: rect.minY + 0.5), CGPoint(x: rect.minX + 0.5, y: rect.maxY - 0.5),
             CGPoint(x: rect.maxX - 0.5, y: rect.minY + 0.5), CGPoint(x: rect.maxX - 0.5, y: rect.maxY - 0.5)]
        }
        let card = CGRect(x: 10, y: 10, width: 100, height: 60)
        suite.expect(corners(card).allSatisfy { ExpansionPreview.cardHole(card, in: card, cornerRadius: 4).contains($0) },
                     "before a drag the expansion fill leaves the whole card open, so its rounded corners show as they are")
        let wider = CGRect(x: 10, y: 10, width: 140, height: 60)
        let hole = ExpansionPreview.cardHole(card, in: wider, cornerRadius: 4)
        let open = corners(card).map { hole.contains($0) }
        suite.expect(open == [true, true, false, false] && !hole.contains(CGPoint(x: 108.7, y: 11.3))
                && hole.contains(CGPoint(x: 60, y: 10.5)) && hole.contains(CGPoint(x: 60, y: 40))
                && ExpansionPreview.cardHole(card, in: wider, cornerRadius: 0).contains(CGPoint(x: 109.5, y: 10.5)),
                     "the expansion fill covers the card's rounded corners the new margin meets, just past their edge, and no others")
        // A 7 px left expansion of a 601 px capture at 60%, scaled as the
        // preview does: the right edges then differ only by rounding.
        let layout = ExpansionPreview.Layout(draftSize: CGSize(width: 608 * 0.6, height: 400 * 0.6),
                                             displayScale: 1.2)
        let shifted = CGRect(x: layout.draft.minX - -7 * 0.6, y: layout.draft.minY - 0 * 0.6,
                             width: 601 * 0.6, height: 400 * 0.6)
        let leftHole = ExpansionPreview.cardHole(shifted, in: layout.draft, cornerRadius: 4)
        suite.expect(corners(shifted).map { leftHole.contains($0) } == [false, false, true, true],
                     "an edge the expansion did not move keeps the card's corners open despite rounding in the scaled rects")
        suite.expect(ScreenshotCanvasSupport.expansionHandle(at: CGPoint(x: -8, y: -8), rect: bounds,
                         tolerance: ScreenshotCanvasSupport.expansionGripReach) == .topLeft
                && ScreenshotCanvasSupport.expansionHandle(at: CGPoint(x: 48, y: 20), rect: bounds,
                         tolerance: ScreenshotCanvasSupport.expansionGripReach) == .right,
                     "a press on a grip's outer half, past the capture's edge, picks it up")
    }
}
