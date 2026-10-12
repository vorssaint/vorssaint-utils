// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

enum ScreenshotImageLayerTests {
    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshot(language)
            suite.expect([strings.toolExpandCanvas, strings.pastedImage,
                          strings.canvasFillWhite, strings.canvasFillTransparent,
                          strings.canvasFillCustom].allSatisfy { !$0.isEmpty },
                         "canvas controls are localized in \(language.rawValue)")
        }
        suite.expect(ScreenshotSupport.Tool.ordered(from: "crop,image,arrow").prefix(2)
                     .elementsEqual([.crop, .arrow]), "stored internal content id cannot become a tool")
        imagePixels(suite)
        blurLayers(suite)
        textRunsAfterSampling(suite)
        clipboardInput(suite)
        let origin = CGRect(x: 10, y: 20, width: 40, height: 20)
        let resized = ScreenshotCanvasSupport.resizedImageRect(
            origin, handle: .bottomRight, point: CGPoint(x: 90, y: 60))
        suite.expect(resized == CGRect(x: 10, y: 20, width: 80, height: 40),
                     "image resize fixes the opposite corner and aspect ratio")
        suite.expect(ScreenshotCanvasSupport.imageHandle(at: CGPoint(x: 30, y: 30),
            rect: origin, tolerance: 12) == nil, "image interior drags move instead of resize")
        for handle in ScreenshotSupport.Handle.allCases {
            suite.expect(ScreenshotCanvasSupport.imageHandle(at: handle.position(in: origin),
                rect: origin, tolerance: 12) == handle,
                         "all eight image grips can be selected without overlapping hits")
        }
        let edgeResizes: [(ScreenshotSupport.Handle, CGPoint, CGRect)] = [
            (.left, CGPoint(x: -10, y: 999), CGRect(x: -10, y: 20, width: 60, height: 20)),
            (.right, CGPoint(x: 90, y: -999), CGRect(x: 10, y: 20, width: 80, height: 20)),
            (.top, CGPoint(x: -999, y: 10), CGRect(x: 10, y: 10, width: 40, height: 30)),
            (.bottom, CGPoint(x: 999, y: 60), CGRect(x: 10, y: 20, width: 40, height: 40))
        ]
        for (handle, point, expected) in edgeResizes {
            suite.expect(ScreenshotCanvasSupport.resizedImageRect(
                origin, handle: handle, point: point) == expected,
                         "image edge grip stretches only its axis and fixes the opposite edge")
        }
        let cornerResizes: [(ScreenshotSupport.Handle, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: -30, y: 0), CGRect(x: -30, y: 0, width: 80, height: 40)),
            (.topRight, CGPoint(x: 90, y: 0), CGRect(x: 10, y: 0, width: 80, height: 40)),
            (.bottomLeft, CGPoint(x: -30, y: 60), CGRect(x: -30, y: 20, width: 80, height: 40))
        ]
        for (handle, point, expected) in cornerResizes {
            suite.expect(ScreenshotCanvasSupport.resizedImageRect(
                origin, handle: handle, point: point) == expected,
                         "image corner grip retains proportional resize and the opposite corner")
        }
        for handle in [ScreenshotSupport.Handle.left, .right, .top, .bottom] {
            let point = handle == .left || handle == .top
                ? CGPoint(x: 90, y: 60) : CGPoint(x: -10, y: 0)
            let rect = ScreenshotCanvasSupport.resizedImageRect(origin, handle: handle, point: point)
            suite.expect(rect.width >= 1 && rect.height >= 1,
                         "image edge grip cannot collapse or invert the image")
        }
        suite.expect(ScreenshotSupport.Tool.isReservedEditorKey(
            .init(keyCode: Int64(kVK_ANSI_V), modifiers: .command)),
                     "image paste belongs to the editor rather than a tool shortcut")
        let image = ScreenshotCanvasSupportTests.image(width: 100, height: 50)
        let rect = ScreenshotCanvasSupport.fittedImageRect(image, canvas: CGSize(width: 40, height: 40))
        suite.expect(rect == CGRect(x: 0, y: 10, width: 40, height: 20),
                     "large image fits the canvas without stretching")
        let asset = ScreenshotSupport.ImageAsset(image: image)
        let annotation = ScreenshotSupport.Annotation(tool: .image, rect: rect, imageAsset: asset)
        var moved = annotation
        moved.rect.origin.x += 5
        suite.expect(moved.imageAsset === annotation.imageAsset, "geometry edits retain immutable image data")
        suite.expect(!ScreenshotSupport.Tool.editorTools.contains(.image), "image content is not a rail tool")
        suite.expect(Array(ScreenshotSupport.Tool.editorTools.prefix(9))
                     == [.select, .arrow, .pixelate, .crop, .text, .sticker, .rect, .highlight, .freehand],
                     "existing default digit shortcuts retain their tools")
        let rendered = ScreenshotImageLayerRendering.composite(base: image, images: [])
        suite.expect(rendered != nil && rendered?.width == 100, "image-only composition keeps native dimensions")
    }

    private static func imagePixels(_ suite: TestSuite) {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1), atX: 0, y: 0)
        bitmap.setColor(NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 1), atX: 1, y: 0)
        bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: 0, y: 1)
        bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: 1, y: 1)
        let base = ScreenshotCanvasSupportTests.image(width: 40, height: 40)
        let rect = CGRect(x: 10, y: 10, width: 2, height: 2)
        let image = ScreenshotSupport.Annotation(tool: .image, rect: rect,
            imageAsset: ScreenshotSupport.ImageAsset(image: bitmap.cgImage!))
        func render(_ annotations: [ScreenshotSupport.Annotation]) -> CGImage? {
            ScreenshotRenderer.renderExport(baseImage: base, annotations: annotations,
                blurSources: .none, scale: 1, annotationShadowsEnabled: false,
                watermark: ScreenshotSupport.WatermarkStyle(), watermarkImage: nil,
                style: ScreenshotSupport.BackdropStyle(), fill: .none, downscaleTo1x: false)?.image
        }
        guard let result = render([image]) else {
            suite.expect(false, "pasted image exports through the shared renderer")
            return
        }
        suite.expect(ScreenshotCanvasSupportTests.pixel(result, x: 10, y: 10) == [0, 255, 0, 255],
                     "pasted image retains its top-left orientation")
        suite.expect(ScreenshotCanvasSupportTests.pixel(result, x: 10, y: 11) == [0, 0, 255, 255],
                     "pasted image retains its bottom-left orientation")
        suite.expect(ScreenshotCanvasSupportTests.pixel(result, x: 11, y: 11) == [255, 0, 0, 255],
                     "transparent image pixels reveal the base")
        let red = ScreenshotSupport.Annotation(tool: .image, rect: rect,
            imageAsset: ScreenshotSupport.ImageAsset(image: base.cropping(to: CGRect(x: 20, y: 20, width: 2, height: 2))!))
        guard let top = render([image, red]), let reversed = render([red, image]) else {
            suite.expect(false, "both image layer orders export")
            return
        }
        suite.expect(ScreenshotCanvasSupportTests.pixel(top, x: 10, y: 10)[0] > 200
                     && ScreenshotCanvasSupportTests.pixel(reversed, x: 10, y: 10)[1] == 255,
                     "annotation order determines the top image: \(ScreenshotCanvasSupportTests.pixel(top, x: 10, y: 10)), \(ScreenshotCanvasSupportTests.pixel(reversed, x: 10, y: 10))")
    }
    static func solid(_ color: NSColor, width: Int, height: Int, hole: CGPoint? = nil) -> CGImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<height {
            for x in 0..<width { bitmap.setColor(color, atX: x, y: y) }
        }
        if let hole { bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: Int(hole.x), y: Int(hole.y)) }
        return bitmap.cgImage!
    }

    static func renderLayers(_ base: CGImage, _ annotations: [ScreenshotSupport.Annotation],
                             cache: ScreenshotRenderer.ImageLayerCache) -> CGImage? {
        let sources = ScreenshotRenderer.BlurSources(image: base, imageLayerCache: cache)
        return ScreenshotRenderer.renderExport(
            baseImage: base, annotations: annotations, blurSources: sources, scale: 1,
            annotationShadowsEnabled: false, watermark: ScreenshotSupport.WatermarkStyle(),
            watermarkImage: nil, style: ScreenshotSupport.BackdropStyle(),
            fill: .none, downscaleTo1x: false)?.image
    }

    static func blurLayers(_ suite: TestSuite) {
        let base = solid(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), width: 120, height: 80)
        let green = ScreenshotSupport.Annotation(
            tool: .image, rect: CGRect(x: 20, y: 20, width: 80, height: 40),
            imageAsset: ScreenshotSupport.ImageAsset(image: solid(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1), width: 80, height: 40)))
        let blue = ScreenshotSupport.Annotation(
            tool: .image, rect: CGRect(x: 20, y: 20, width: 80, height: 40),
            imageAsset: ScreenshotSupport.ImageAsset(
                image: solid(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), width: 80, height: 40, hole: CGPoint(x: 20, y: 20))))
        let cache = ScreenshotRenderer.ImageLayerCache()
        for style in [ScreenshotSupport.BlurStyleID.pixelate, .blur] {
            let blur = ScreenshotSupport.Annotation(
                tool: .pixelate, rect: CGRect(x: 20, y: 20, width: 80, height: 40), blurStyle: style)
            guard let result = renderLayers(base, [green, blur, blue], cache: cache) else {
                suite.expect(false, "layered blur exports")
                continue
            }
            let blurred = ScreenshotCanvasSupportTests.pixel(result, x: 40, y: 40)
            let foreground = ScreenshotCanvasSupportTests.pixel(result, x: 30, y: 30)
            suite.expect(Int(blurred[1]) > Int(blurred[0]) + 100
                      && Int(blurred[1]) > Int(blurred[2]) + 100,
                         "blur samples green below the transparent point, without the upper blue image")
            suite.expect(Int(foreground[2]) > Int(foreground[1]) + 100,
                         "upper blue image remains crisp")
            guard let reordered = renderLayers(base, [green, blue, blur], cache: cache) else {
                suite.expect(false, "reordered layers export")
                continue
            }
            let changed = ScreenshotCanvasSupportTests.pixel(reordered, x: 40, y: 40)
            suite.expect(Int(changed[2]) > Int(changed[1]) + 100,
                         "moving blue below blur changes sampling and invalidates the cache")
            var moved = green
            moved.rect.origin.x = 100
            guard let movedResult = renderLayers(base, [moved, blur, blue], cache: cache) else {
                suite.expect(false, "moved image exports")
                continue
            }
            let exposed = ScreenshotCanvasSupportTests.pixel(movedResult, x: 40, y: 40)
            suite.expect(Int(exposed[0]) > Int(exposed[1]) + 100,
                         "moving the lower image makes blur sample the exposed red base")
        }
    }

    private static func textRunsAfterSampling(_ suite: TestSuite) {
        let base = solid(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), width: 120, height: 80)
        let area = ScreenshotSupport.Annotation(tool: .pixelate,
            rect: CGRect(x: 20, y: 20, width: 80, height: 40), blurTextOnly: true,
            renderReferenceSize: CGSize(width: 120, height: 80))
        let cache = ScreenshotRenderer.ImageLayerCache()
        cache.beginPass(base: base, annotations: [area])
        var original = ScreenshotRenderer.BlurSources(image: base)
        let pending = cache.sources(for: area, images: [], original: original)
        original.textRuns = [CGRect(x: 30, y: 30, width: 20, height: 10)]
        let recognized = cache.sources(for: area, images: [], original: original)
        suite.expect(pending?.textRuns == nil && recognized?.textRuns == original.textRuns,
                     "text-only blur uses recognition results arriving after sample creation")
    }

    private static func clipboardInput(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer {
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let original = ScreenshotCanvasSupportTests.image(width: 40, height: 40)
            let url = directory.appendingPathComponent("source.png")
            try NSBitmapImageRep(cgImage: original).representation(using: .png, properties: [:])!.write(to: url)
            board.writeObjects([url as NSURL])
            let reader = ClipboardHistoryImageEditorTests.ScreenshotService.self
            let fileImage = reader.clipboardImage(from: board)
            let capture = fileImage.flatMap { reader.imageCapture(from: $0) }
            suite.expect(capture?.image.width == 40 && capture?.image.height == 40,
                         "Finder-style clipboard image URLs load full image pixels")
            let host = ScreenshotCanvasModelTests.Host(image: original)
            if let capture { _ = host.pasteImage(capture.image) }
            try FileManager.default.removeItem(at: url)
            suite.expect(host.annotations.first?.imageAsset?.image.width == 40,
                         "pasted pixels remain available after removing the source file")
            board.clearContents()
            board.setData(NSBitmapImageRep(cgImage: original).representation(using: .png, properties: [:]),
                          forType: .png)
            suite.expect(reader.clipboardImage(from: board) != nil, "clipboard PNG data is accepted")
            board.clearContents()
            board.setString("plain text", forType: .string)
            suite.expect(reader.clipboardImage(from: board) == nil, "plain clipboard text is not an image")
        } catch {
            suite.expect(false, "clipboard image input fixture: \(error)")
        }
    }
}
