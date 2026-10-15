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
        sampleReuse(suite)
        sampleBounds(suite)
        textOnlyAreasOverImages(suite)
        eraseOverImages(suite)
        areasBesideImages(suite)
        startingTool(suite)
        editorViewContracts(suite)
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
        render(base, annotations, sources: ScreenshotRenderer.BlurSources(image: base, imageLayerCache: cache))
    }

    static func render(_ base: CGImage, _ annotations: [ScreenshotSupport.Annotation],
                       sources: ScreenshotRenderer.BlurSources) -> CGImage? {
        ScreenshotRenderer.renderExport(
            baseImage: base, annotations: annotations, blurSources: sources, scale: 1,
            annotationShadowsEnabled: false, watermark: ScreenshotSupport.WatermarkStyle(),
            watermarkImage: nil, style: ScreenshotSupport.BackdropStyle(),
            fill: .none, downscaleTo1x: false)?.image
    }

    /// The RGBA bytes of `rect`, top row first.
    static func bytes(_ image: CGImage, in rect: CGRect) -> [UInt8] {
        let width = Int(rect.width), height = Int(rect.height)
        guard let crop = image.cropping(to: rect) else { return [] }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    static func layer(_ color: NSColor, _ rect: CGRect) -> ScreenshotSupport.Annotation {
        ScreenshotSupport.Annotation(tool: .image, rect: rect, imageAsset: ScreenshotSupport.ImageAsset(
            image: solid(color, width: Int(rect.width), height: Int(rect.height))))
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
            // The moved image still lies in the area, away from the hole.
            var moved = green
            moved.rect.origin.x = 75
            guard let movedResult = renderLayers(base, [moved, blur, blue], cache: cache),
                  let uncovered = renderLayers(base, [moved, blur], cache: cache) else {
                suite.expect(false, "moved image exports")
                continue
            }
            let exposed = ScreenshotCanvasSupportTests.pixel(movedResult, x: 40, y: 40)
            // Next to the moved image's edge, a drawn area mixes red and green.
            let edge = ScreenshotCanvasSupportTests.pixel(uncovered, x: 73, y: 40)
            suite.expect(Int(exposed[0]) > Int(exposed[1]) + 100 && edge[0] > 40 && edge[1] > 40,
                         "moving the lower image makes blur sample the exposed red base: \(exposed), \(edge)")
        }
    }

    private static func textRunsAfterSampling(_ suite: TestSuite) {
        let base = solid(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), width: 120, height: 80)
        let area = ScreenshotSupport.Annotation(tool: .pixelate,
            rect: CGRect(x: 20, y: 20, width: 80, height: 40), blurTextOnly: true,
            renderReferenceSize: CGSize(width: 120, height: 80))
        let cache = ScreenshotRenderer.ImageLayerCache()
        cache.beginPass(base: base)
        var original = ScreenshotRenderer.BlurSources(image: base)
        let pending = cache.sources(for: area, images: [], original: original)
        original.textRuns = [CGRect(x: 30, y: 30, width: 20, height: 10)]
        let recognized = cache.sources(for: area, images: [], original: original)
        suite.expect(pending?.textRuns == nil && recognized?.textRuns == original.textRuns,
                     "text-only blur uses recognition results arriving after sample creation")
    }

    /// Samples carry random noise, so an area that got a new one on every
    /// redraw would flicker while the user draws elsewhere.
    private static func sampleReuse(_ suite: TestSuite) {
        // Wide enough for an image to sit past what a blur reads around the area.
        let base = solid(NSColor(deviceRed: 0.45, green: 0.5, blue: 0.55, alpha: 1), width: 200, height: 80)
        let pasted = layer(NSColor(deviceRed: 0.3, green: 0.6, blue: 0.4, alpha: 1),
                           CGRect(x: 20, y: 20, width: 60, height: 40))
        let far = layer(NSColor(deviceRed: 0.7, green: 0.3, blue: 0.5, alpha: 1),
                        CGRect(x: 170, y: 0, width: 10, height: 10))
        let arrow = ScreenshotSupport.Annotation(tool: .arrow,
            points: [CGPoint(x: 90, y: 72), CGPoint(x: 115, y: 76)])
        for style in [ScreenshotSupport.BlurStyleID.pixelate, .blur] {
            let area = ScreenshotSupport.Annotation(tool: .pixelate,
                rect: CGRect(x: 10, y: 10, width: 70, height: 50), blurStyle: style)
            let cache = ScreenshotRenderer.ImageLayerCache()
            let original = ScreenshotRenderer.BlurSources(image: base, imageLayerCache: cache)
            func sample() -> CGImage? {
                let sources = cache.sources(for: area, images: [pasted], original: original)
                return style == .pixelate ? sources?.mosaics[area.blurLevel] : sources?.softBlurs[area.blurLevel]
            }
            var moved = far
            moved.rect.origin.y = 60
            guard let first = renderLayers(base, [far, pasted, area], cache: cache) else {
                suite.expect(false, "\(style): an area over an image renders")
                continue
            }
            let firstSample = sample()
            guard let marked = renderLayers(base, [far, pasted, area, arrow], cache: cache) else { continue }
            let markedSample = sample()
            guard let shifted = renderLayers(base, [moved, pasted, area, arrow], cache: cache) else { continue }
            let pixels = bytes(first, in: area.rect)
            suite.expect(firstSample != nil && markedSample === firstSample
                         && bytes(marked, in: area.rect) == pixels,
                         "\(style): a mark added elsewhere keeps the sample and noise of an area over an image")
            suite.expect(sample() === firstSample && bytes(shifted, in: area.rect) == pixels,
                         "\(style): moving an image outside the area keeps its sample and noise")
            var dragged = area
            dragged.rect.origin.x += 6
            _ = renderLayers(base, [moved, pasted, dragged, arrow], cache: cache)
            suite.expect(sample() === firstSample,
                         "\(style): moving the area over the same image keeps its sample")
            var newer = pasted
            newer.rect.origin.x += 4
            _ = renderLayers(base, [moved, newer, area, arrow], cache: cache)
            let newerSources = cache.sources(for: area, images: [newer], original: original)
            let newerSample = style == .pixelate
                ? newerSources?.mosaics[area.blurLevel] : newerSources?.softBlurs[area.blurLevel]
            suite.expect(newerSample != nil && newerSample !== firstSample,
                         "\(style): moving the image below the area makes a new sample")
        }
    }

    /// A long drag must not keep a sample for every position it passed.
    private static func sampleBounds(_ suite: TestSuite) {
        let base = solid(NSColor(deviceRed: 0.45, green: 0.5, blue: 0.55, alpha: 1), width: 120, height: 80)
        let pasted = layer(NSColor(deviceRed: 0.3, green: 0.6, blue: 0.4, alpha: 1),
                           CGRect(x: 20, y: 20, width: 60, height: 40))
        for style in [ScreenshotSupport.BlurStyleID.pixelate, .erase] {
            let area = ScreenshotSupport.Annotation(tool: .pixelate,
                rect: CGRect(x: 10, y: 10, width: 90, height: 60), blurStyle: style)
            let cache = ScreenshotRenderer.ImageLayerCache()
            let original = ScreenshotRenderer.BlurSources(image: base, imageLayerCache: cache)
            func held() -> CGImage? {
                let sources = cache.sources(for: area, images: [pasted], original: original)
                return style == .pixelate ? sources?.mosaics[area.blurLevel] : sources?.image
            }
            _ = renderLayers(base, [pasted, area], cache: cache)
            let start = held()
            // An erase sample keeps a copy of what its area reads and goes
            // after one redraw without it; mosaics go once there are many.
            let steps = style == .erase ? 2 : ScreenshotRenderer.ImageLayerCache.entryLimit + 2
            for step in 1...steps {
                var moved = pasted
                moved.rect.origin.x += CGFloat(step)
                _ = renderLayers(base, [moved, area], cache: cache)
            }
            _ = renderLayers(base, [pasted, area], cache: cache)
            suite.expect(start != nil && held() !== start,
                         "\(style): samples a drag no longer uses are dropped")
        }
    }

    private static func textOnlyAreasOverImages(_ suite: TestSuite) {
        // A white image pasted over dark text in the capture: covering that
        // text must paint what shows there, not the capture below the image.
        let dark = solid(NSColor(deviceRed: 0.1, green: 0.1, blue: 0.1, alpha: 1), width: 120, height: 80)
        let white = layer(NSColor(deviceRed: 0.95, green: 0.95, blue: 0.95, alpha: 1),
                          CGRect(x: 10, y: 10, width: 100, height: 60))
        let strip = CGRect(x: 30, y: 30, width: 60, height: 12)
        let covering = ScreenshotSupport.Annotation(tool: .pixelate,
            rect: CGRect(x: 20, y: 20, width: 80, height: 40), blurTextOnly: true)
        var sources = ScreenshotRenderer.BlurSources(image: dark, textRuns: [strip],
                                                     imageLayerCache: ScreenshotRenderer.ImageLayerCache())
        if let mosaic = ScreenshotRenderer.pixelatedImage(from: dark) {
            sources.mosaics = [ScreenshotSupport.BlurStrength.defaultLevel: mosaic]
        }
        if let result = render(dark, [white, covering], sources: sources) {
            let inside = ScreenshotCanvasSupportTests.pixel(result, x: 60, y: 36)
            suite.expect(inside[0] > 180 && inside[1] > 180 && inside[2] > 180,
                         "a text only area over a pasted image paints the image, not the capture under it: \(inside)")
        } else {
            suite.expect(false, "a text only area over an image renders")
        }

        // Recognition never reads pasted pixels, so their part inside a text
        // only area is covered as unread text, and nothing outside the area.
        let gray = solid(NSColor(deviceRed: 0.5, green: 0.5, blue: 0.5, alpha: 1), width: 120, height: 80)
        let pasted = layer(NSColor(deviceRed: 0.35, green: 0.55, blue: 0.75, alpha: 1),
                           CGRect(x: 20, y: 20, width: 60, height: 40))
        let area = ScreenshotSupport.Annotation(tool: .pixelate,
            rect: CGRect(x: 40, y: 10, width: 70, height: 60), blurTextOnly: true)
        let read = ScreenshotRenderer.BlurSources(image: gray, textRuns: [],
                                                  imageLayerCache: ScreenshotRenderer.ImageLayerCache())
        guard let plain = render(gray, [pasted], sources: .none),
              let covered = render(gray, [pasted, area], sources: read) else {
            suite.expect(false, "a text only area over an image renders")
            return
        }
        let inside = CGRect(x: 40, y: 20, width: 40, height: 40)
        let outside = CGRect(x: 20, y: 20, width: 20, height: 40)
        suite.expect(bytes(covered, in: inside) != bytes(plain, in: inside),
                     "a text only area covers the pasted image inside it")
        suite.expect(bytes(covered, in: outside) == bytes(plain, in: outside)
                     && bytes(covered, in: CGRect(x: 80, y: 10, width: 30, height: 60))
                        == bytes(plain, in: CGRect(x: 80, y: 10, width: 30, height: 60)),
                     "the image outside the area and the capture without text stay as they are")
    }

    private static func eraseOverImages(_ suite: TestSuite) {
        let base = solid(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), width: 120, height: 80)
        let green = layer(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1),
                          CGRect(x: 20, y: 20, width: 80, height: 40))
        // A mark on the image that erasing has to remove.
        let mark = layer(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1),
                         CGRect(x: 45, y: 35, width: 10, height: 10))
        let erase = ScreenshotSupport.Annotation(tool: .pixelate,
            rect: CGRect(x: 40, y: 30, width: 20, height: 20), blurStyle: .erase)
        let cache = ScreenshotRenderer.ImageLayerCache()
        guard let result = renderLayers(base, [green, mark, erase], cache: cache) else {
            suite.expect(false, "an erased area over an image renders")
            return
        }
        let center = ScreenshotCanvasSupportTests.pixel(result, x: 50, y: 40)
        suite.expect(Int(center[1]) > Int(center[0]) + 100 && Int(center[1]) > Int(center[2]) + 100,
                     "erasing over a pasted image fills from the image around the area: \(center)")
        // The area and the 8 px a fill can read around it, not the canvas.
        let held = cache.sources(for: erase, images: [green, mark],
                                 original: ScreenshotRenderer.BlurSources(image: base, imageLayerCache: cache))
        suite.expect(held?.image?.width == 36 && held?.image?.height == 36
                     && held?.imageOrigin == CGPoint(x: 32, y: 22),
                     "an erase sample over images keeps only what its area reads, not a copy of the canvas")

        // A text only area covers the image inside it as unread text, filled
        // from what lies around the whole image, well past the area.
        let textOnly = ScreenshotSupport.Annotation(tool: .pixelate,
            rect: CGRect(x: 40, y: 30, width: 20, height: 20), blurStyle: .erase, blurTextOnly: true)
        let read = ScreenshotRenderer.BlurSources(image: base, textRuns: [],
                                                  imageLayerCache: ScreenshotRenderer.ImageLayerCache())
        guard let covered = render(base, [green, textOnly], sources: read) else {
            suite.expect(false, "a text only erased area over an image renders")
            return
        }
        let filled = ScreenshotCanvasSupportTests.pixel(covered, x: 50, y: 40)
        suite.expect(filled[0] > 200 && filled[1] < 50,
                     "a text only erase reads around the whole image it covers: \(filled)")
    }

    /// Every style reads a little past the area's edge, so an image just
    /// outside it shows there too, as on the canvas.
    private static func areasBesideImages(_ suite: TestSuite) {
        let base = solid(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), width: 120, height: 80)
        let green = layer(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1),
                          CGRect(x: 20, y: 20, width: 80, height: 48))
        let level = ScreenshotSupport.BlurStrength.defaultLevel
        var capture = ScreenshotRenderer.BlurSources(image: base,
                                                     imageLayerCache: ScreenshotRenderer.ImageLayerCache())
        if let mosaic = ScreenshotRenderer.pixelatedImage(from: base),
           let blurred = ScreenshotRenderer.softBlurredImage(from: base) {
            capture.mosaics = [level: mosaic]
            capture.softBlurs = [level: blurred]
        }
        // Each area starts on the image's bottom edge without overlapping it.
        for style in ScreenshotSupport.BlurStyleID.allCases {
            let area = ScreenshotSupport.Annotation(tool: .pixelate,
                rect: CGRect(x: 40, y: 68, width: 20, height: 10), blurStyle: style)
            guard let result = render(base, [green, area], sources: capture) else {
                suite.expect(false, "\(style): an area beside an image renders")
                continue
            }
            let edge = ScreenshotCanvasSupportTests.pixel(result, x: 50, y: style == .erase ? 68 : 69)
            suite.expect(edge[1] > (style == .erase ? 100 : 40),
                         "\(style): an area takes in the image just past its edge: \(edge)")
        }
    }

    private static func startingTool(_ suite: TestSuite) {
        typealias Tool = ScreenshotSupport.Tool
        for raw in [nil, "", "missing", "select", "crop", "expandCanvas", "image"] {
            suite.expect(Tool.startingTool(remembered: raw) == .arrow,
                         "a new editor opens with arrow instead of \(raw ?? "nothing")")
        }
        suite.expect(Tool.startingTool(remembered: "pixelate") == .pixelate
                     && Tool.startingTool(remembered: "text") == .text,
                     "a new editor opens with the drawing tool used last")
    }

    private static func editorViewContracts(_ suite: TestSuite) {
        let source = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift",
                                  encoding: .utf8)) ?? ""
        func section(_ start: String, _ end: String) -> String {
            guard let lower = source.range(of: start),
                  let upper = source.range(of: end, range: lower.upperBound..<source.endIndex)
            else { return "" }
            return String(source[lower.lowerBound..<upper.lowerBound])
        }
        // The expansion preview and its grip hit area are two layers of one
        // overlay; without their own top-left stack the overlay centers them on
        // each other, which moves the preview off the card on a backdrop.
        suite.expect(source.contains("            if model.tool == .expandCanvas {\n                // Both layers place themselves from the canvas's top left;\n                // the overlay's own stack would center them on each other.\n                ZStack(alignment: .topLeading) {"),
                     "the expansion preview and its grip area share one top-left stack over the canvas")
        let content = section("    private func drawContent(", "    /// Highlight for recognized words")
        let checker = content.range(of: "let showsChecker = !model.showsBackdrop\n        if showsChecker {\n            cg.setFillColor(ScreenshotCanvasExpansionPreview.checker)\n            cg.fill(imageRect)\n        }")
        let layer = content.range(of: "if isolatesContent { cg.beginTransparencyLayer(auxiliaryInfo: nil) }")
        suite.expect(checker != nil && layer != nil && checker!.upperBound <= layer!.lowerBound,
                     "the canvas shows the checkerboard only without a backdrop, as the export does, below the content layer")
        suite.expect(content.contains("$0.tool == .pixelate || (showsChecker && $0.tool == .spotlight)"),
                     "a spotlight over the checkerboard draws in its own layer, so transparent parts the export keeps stay undimmed")
        let controls = section("    private var expansionControls: some View {", "    private func updateExpansionFill()")
        suite.expect(controls.contains(".padding(.horizontal, 12)\n        .padding(.vertical, 8)\n        .background(.regularMaterial, in: Capsule(style: .continuous))\n        .shadow(color: .black.opacity(0.16), radius: 12, y: 3)"),
                     "the fill controls sit in the same capsule as the crop and style bars")
        suite.expect(controls.contains("supportsOpacity: false)\n                    .labelsHidden()"),
                     "the custom fill well does not repeat the name its picker already shows")
        suite.expect(controls.contains("Picker(strings.colorLabel, selection: $expansionFillChoice)")
                && controls.contains("            .labelsHidden()\n            .fixedSize()\n            .onChange(of: expansionFillChoice)"),
                     "the fill picker shows only its choices and keeps its name for VoiceOver")
        let canvas = section("    private func canvas(zoom: CGFloat, canvasSize: CGSize, available: CGSize)",
                             "    /// The live backdrop layer")
        let gripArea = canvas.range(of: "Color.clear\n                        .frame(width: canvasSize.width + reach * 2, height: canvasSize.height + reach * 2)\n                        .contentShape(Rectangle())\n                        .offset(x: -reach, y: -reach)")
        let gesture = canvas.range(of: ".gesture(canvasGesture(zoom: zoom, available: available))")
        suite.expect(canvas.contains("let reach = ScreenshotCanvasSupport.expansionGripReach")
                && gripArea != nil && gesture != nil && gripArea!.upperBound <= gesture!.lowerBound,
                     "the canvas takes presses on the expansion grips' outer half, past its edge")
        suite.expect(canvas.contains("cardCornerRadius: model.showsBackdrop\n                                                         ? model.cardCornerPixels * zoom\n                                                         : outerRadius)"),
                     "the expansion preview fills around the card's corners with the rounding they are drawn with")
        let preview = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Screenshot/ScreenshotCanvasExpansionPreview.swift",
                                   encoding: .utf8)) ?? ""
        suite.expect(preview.contains("cg.addRect(outer)\n                cg.addPath(Self.cardHole(old, in: outer, cornerRadius: cardCornerRadius))\n                cg.clip(using: .evenOdd)"),
                     "the expansion preview fills the wedges at the card's corners the margin meets")
        suite.expect(preview.contains("for dot in layout.grips {")
                && preview.contains("let outer = layout.draft\n")
                && preview.contains(".frame(width: layout.size.width, height: layout.size.height)\n        .offset(x: -layout.draft.minX, y: -layout.draft.minY)"),
                     "the expansion preview draws its grips whole, in the room around the draft")
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
