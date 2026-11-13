// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The screenshot editor's inspection rules, on synthetic pixels.
enum ScreenshotInspectionTests {
    typealias Inspection = ScreenshotInspectionSupport
    typealias Output = ScreenshotOutputSupport
    typealias RGBA = Inspection.RGBA

    static let white = RGBA(255, 255, 255)
    static let black = RGBA(0, 0, 0)

    /// An sRGB image whose pixel (x, y), top row first, is `color(x, y)`.
    static func image(width: Int, height: Int, color: (Int, Int) -> RGBA) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = color(x, y)
                let alpha = Int(pixel.alpha)
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(Int(pixel.red) * alpha / 255)
                bytes[offset + 1] = UInt8(Int(pixel.green) * alpha / 255)
                bytes[offset + 2] = UInt8(Int(pixel.blue) * alpha / 255)
                bytes[offset + 3] = pixel.alpha
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGBA {
        Inspection.pixelGrid(of: image, region: CGRect(x: x, y: y, width: 1, height: 1))!.pixels[0]
    }

    /// Draws `annotations` over `base` the way the exporter does.
    static func rendered(_ base: CGImage, _ annotations: [ScreenshotSupport.Annotation]) -> CGImage {
        ScreenshotRenderer.renderExport(
            baseImage: base, annotations: annotations,
            blurSources: ScreenshotRenderer.BlurSources(image: base),
            scale: 1, annotationShadowsEnabled: false,
            watermark: ScreenshotSupport.WatermarkStyle(), watermarkImage: nil,
            style: ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0),
            fill: .none, downscaleTo1x: false)!.image
    }

    static func run(_ suite: TestSuite) {
        pixels(suite)
        measuring(suite)
        colors(suite)
        smartCrop(suite)
        tools(suite)
        rendering(suite)
        resizing(suite)
        preferencesAndStrings(suite)
    }

    // MARK: - Pixels

    static func pixels(_ suite: TestSuite) {
        let picture = image(width: 4, height: 3) { x, y in RGBA(UInt8(x * 60), UInt8(y * 100), 7) }
        let grid = Inspection.pixelGrid(of: picture, region: CGRect(x: 1, y: 1, width: 2, height: 2))
        suite.expect(grid?.width == 2 && grid?.height == 2
                     && grid?[0, 0] == RGBA(60, 100, 7) && grid?[1, 1] == RGBA(120, 200, 7),
                     "a region reads top row first in image pixels")
        suite.expect(Inspection.pixelGrid(of: picture, region: CGRect(x: 3, y: 2, width: 9, height: 9))?.pixels
                     == [RGBA(180, 200, 7)],
                     "a region past the edge reads only what is on the image")
        suite.expect(Inspection.pixelGrid(of: picture, region: CGRect(x: 9, y: 9, width: 2, height: 2)) == nil,
                     "a region off the image reads nothing")
        let wide = image(width: 100, height: 2) { x, _ in x < 50 ? black : RGBA(250, 0, 0) }
        let sampled = Inspection.pixelGrid(of: wide, region: CGRect(x: 0, y: 0, width: 100, height: 2),
                                           maximumSide: 10)
        suite.expect(sampled?.width == 10 && sampled.map { Set($0.pixels) } == [black, RGBA(250, 0, 0)],
                     "sampling a large region keeps real colors instead of blending them")
        let translucent = image(width: 1, height: 1) { _, _ in RGBA(200, 100, 50, 128) }
        let read = pixel(translucent, 0, 0)
        suite.expect(read.alpha == 128 && abs(Int(read.red) - 200) <= 2 && abs(Int(read.green) - 100) <= 2,
                     "a translucent pixel reads its own color, not one darkened by its alpha")
    }

    // MARK: - Measuring

    static func measuring(_ suite: TestSuite) {
        let gap = [black] + Array(repeating: white, count: 10) + [black]
        suite.expect(Inspection.similarRun(in: gap, around: 5) == 1..<11,
                     "the run stops at the edge on each side")
        let horizontal = Inspection.measuredSpan(line: gap, axis: .horizontal, pointer: CGPoint(x: 5.4, y: 7.8))
        suite.expect(horizontal == Inspection.Span(start: CGPoint(x: 1, y: 7.5), end: CGPoint(x: 11, y: 7.5))
                     && horizontal?.length == 10,
                     "a ten pixel gap measures ten, drawn across the pointer's pixel row")
        let vertical = Inspection.measuredSpan(line: gap, axis: .vertical, pointer: CGPoint(x: 3.2, y: 2))
        suite.expect(vertical == Inspection.Span(start: CGPoint(x: 3.5, y: 1), end: CGPoint(x: 3.5, y: 11)),
                     "a vertical measurement runs down the pointer's column")
        let gradient = (0..<20).map { RGBA(UInt8(100 + $0 * 4), 100, 100) }
        suite.expect(Inspection.similarRun(in: gradient, around: 3) == 0..<20,
                     "a soft gradient is one surface, not a row of edges")
        let edge = Array(repeating: white, count: 4) + Array(repeating: RGBA(200, 200, 200), count: 4)
        suite.expect(Inspection.similarRun(in: edge, around: 1) == 0..<4,
                     "a step past the tolerance is an edge")
        suite.expect(Inspection.measuredSpan(line: gap, axis: .horizontal, pointer: CGPoint(x: 40, y: 0)) == nil,
                     "a pointer past the line measures nothing")
        suite.expect(Inspection.similarRun(in: [white, white], around: 0) == 0..<2,
                     "a gap reaching the edge of the capture ends there")

        let size = CGSize(width: 30, height: 20)
        suite.expect(Inspection.guideSpan(axis: .vertical, pointer: CGPoint(x: 7.6, y: 3), imageSize: size)
                     == Inspection.Span(start: CGPoint(x: 7.5, y: 0), end: CGPoint(x: 7.5, y: 20))
                     && Inspection.guideSpan(axis: .horizontal, pointer: CGPoint(x: 1, y: 99), imageSize: size)
                     == Inspection.Span(start: CGPoint(x: 0, y: 19.5), end: CGPoint(x: 30, y: 19.5)),
                     "a guide crosses the whole capture through the pointer's pixel, kept on it")

        let horizontalMode = Inspection.LiveMode.distance(.horizontal)
        suite.expect(Inspection.toggledMode(nil, pressing: horizontalMode) == horizontalMode
                     && Inspection.toggledMode(horizontalMode, pressing: horizontalMode) == nil
                     && Inspection.toggledMode(horizontalMode, pressing: .guide(.vertical)) == .guide(.vertical),
                     "the same key ends a measurement and another key switches to its own")

        suite.expect(Inspection.measureLabel(lengthPixels: 240, scale: 2, unit: .points) == "120 pt"
                     && Inspection.measureLabel(lengthPixels: 240, scale: 2, unit: .pixels) == "240 px"
                     && Inspection.measureLabel(lengthPixels: 121, scale: 2, unit: .points) == "60.5 pt"
                     && Inspection.measureLabel(lengthPixels: 120, scale: 1, unit: .points) == "120 px",
                     "Retina lengths read in points by default and a 1x capture reads in pixels")
        suite.expect(Inspection.MeasureUnit.sanitized(nil) == .points
                     && Inspection.MeasureUnit.sanitized("px") == .pixels
                     && Inspection.MeasureUnit.sanitized("cm") == .points
                     && Inspection.MeasureUnit.points.toggled == .pixels,
                     "the unit starts in points and P switches it")
        let start = CGPoint(x: 10, y: 10)
        suite.expect(Inspection.constrainedEnd(from: start, to: CGPoint(x: 40, y: 14), axisLocked: true)
                     == CGPoint(x: 40, y: 10)
                     && Inspection.constrainedEnd(from: start, to: CGPoint(x: 13, y: 50), axisLocked: true)
                     == CGPoint(x: 10, y: 50)
                     && Inspection.constrainedEnd(from: start, to: CGPoint(x: 13, y: 50), axisLocked: false)
                     == CGPoint(x: 13, y: 50),
                     "Shift keeps a hand-drawn ruler flat or upright")
    }

    // MARK: - Colors

    static func colors(_ suite: TestSuite) {
        suite.expectClose(Inspection.contrastRatio(black, white), 21, "black on white", tol: 0.001)
        suite.expectClose(Inspection.contrastRatio(RGBA(0x77, 0x77, 0x77), white), 4.478, "#777 on white", tol: 0.01)
        suite.expectClose(Inspection.contrastRatio(white, RGBA(0x77, 0x77, 0x77)), 4.478,
                          "the ratio reads the same either way", tol: 0.01)
        suite.expect(Inspection.ContrastLevel(ratio: 7) == .aaa && Inspection.ContrastLevel(ratio: 4.5) == .aa
                     && Inspection.ContrastLevel(ratio: 4.49) == .aaLarge && Inspection.ContrastLevel(ratio: 2.9) == .fail,
                     "the WCAG levels start at 7, 4.5 and 3")
        suite.expectClose(Inspection.apcaContrast(text: black, background: white), 106.04, "APCA black on white", tol: 0.01)
        suite.expectClose(Inspection.apcaContrast(text: white, background: black), -107.88, "APCA white on black", tol: 0.01)
        suite.expectClose(Inspection.apcaContrast(text: RGBA(0x88, 0x88, 0x88), background: white), 63.06,
                          "APCA #888 on white", tol: 0.01)
        suite.expect(Inspection.apcaContrast(text: white, background: white) == 0,
                     "APCA reads no contrast between equal colors")
        suite.expect(RGBA(10, 171, 255).hex == "#0AABFF", "a color reads as upper case hex")

        let text = Inspection.PixelGrid(width: 3, height: 1, pixels: [white, RGBA(120, 120, 130), RGBA(20, 20, 40)])
        suite.expect(Inspection.darkest(in: text) == RGBA(20, 20, 40), "the text color is the darkest pixel")
        let mixed = Inspection.PixelGrid(width: 2, height: 1, pixels: [RGBA(0, 100, 200), RGBA(100, 0, 50)])
        suite.expect(Inspection.average(of: mixed) == RGBA(50, 50, 125), "the average is the mean color")
        let clear = Inspection.PixelGrid(width: 2, height: 1, pixels: [RGBA(0, 0, 0, 0), RGBA(90, 90, 90)])
        suite.expect(Inspection.average(of: clear) == RGBA(90, 90, 90) && Inspection.darkest(in: clear) == RGBA(90, 90, 90),
                     "transparent pixels hold no color")

        // A word on a page: mostly background, some ink, a few smoothed pixels.
        var page = Array(repeating: RGBA(250, 250, 250), count: 900)
        for index in 0..<60 { page[index * 7] = RGBA(30, 30, 30) }
        page[1] = RGBA(140, 140, 140)
        page[2] = RGBA(200, 60, 60)
        let pair = Inspection.dominantPair(in: Inspection.PixelGrid(width: 30, height: 30, pixels: page))
        suite.expect(pair?.background == RGBA(250, 250, 250) && pair?.foreground == RGBA(30, 30, 30),
                     "the pair is the page and its ink, never a stray smoothed pixel")
        let plain = Inspection.PixelGrid(width: 4, height: 4, pixels: Array(repeating: white, count: 16))
        suite.expect(Inspection.dominantPair(in: plain) == nil, "a single color has no contrast to rate")
        suite.expect(Inspection.sizeLabel(CGSize(width: 240, height: 96), scale: 2, unit: .points) == "120 × 48 pt"
                     && Inspection.sizeLabel(CGSize(width: 240, height: 96), scale: 2, unit: .pixels) == "240 × 96 px",
                     "a selection's size reads with one unit")
    }

    // MARK: - Smart crop

    static func smartCrop(_ suite: TestSuite) {
        var pixels = Array(repeating: white, count: 100)
        for y in 5..<7 { for x in 4..<7 { pixels[y * 10 + x] = black } }
        let grid = Inspection.PixelGrid(width: 10, height: 10, pixels: pixels)
        suite.expect(Inspection.contentRect(in: grid) == CGRect(x: 4, y: 5, width: 3, height: 2),
                     "fitting trims every plain border row and column")
        suite.expect(Inspection.contentRect(in: Inspection.PixelGrid(width: 3, height: 3,
                                                                    pixels: Array(repeating: white, count: 9))) == nil,
                     "a selection with nothing in it keeps its size")
        var noisy = Array(repeating: white, count: 25)
        noisy[0] = RGBA(250, 250, 250)
        noisy[12] = black
        suite.expect(Inspection.contentRect(in: Inspection.PixelGrid(width: 5, height: 5, pixels: noisy))
                     == CGRect(x: 2, y: 2, width: 1, height: 1),
                     "a near match of the border color is still border")
        var framed = Array(repeating: white, count: 36)
        for index in 0..<6 { framed[index] = black }
        suite.expect(Inspection.contentRect(in: Inspection.PixelGrid(width: 6, height: 6, pixels: framed))
                     == CGRect(x: 0, y: 0, width: 6, height: 1),
                     "content reaching a corner is kept, and the border is the color around it")
    }

    // MARK: - Tools

    static func tools(_ suite: TestSuite) {
        typealias Tool = ScreenshotSupport.Tool
        suite.expect(Tool.editorTools.contains(.ruler) && Tool.editorTools.contains(.magnifier)
                     && !Tool.editorTools.contains(.guide) && !Tool.editorTools.contains(.image),
                     "the ruler and the magnifier are in the rail; guides and images are content only")
        let saved = "select,arrow,pixelate,crop,text,sticker,rect,highlight,freehand,line,ellipse,counter,redact,spotlight,expandCanvas"
        let ordered = Tool.ordered(from: saved)
        suite.expect(Array(ordered.prefix(15).map(\.rawValue)) == saved.split(separator: ",").map(String.init)
                     && Array(ordered.suffix(2)) == [.ruler, .magnifier],
                     "an order saved before the new tools keeps its keys and gains them at the end")
        suite.expect(Tool.ordered(from: "guide,ruler").first == .ruler
                     && Tool.startingTool(remembered: "guide") == .arrow
                     && Tool.startingTool(remembered: "ruler") == .ruler
                     && Tool.bindings(from: "guide=:1").isEmpty,
                     "a guide is never a rail tool, a starting tool or a binding")
        suite.expect(!Tool.ruler.dragsRect && !Tool.ruler.resizesWithHandles
                     && Tool.magnifier.dragsRect && Tool.magnifier.resizesWithHandles,
                     "a ruler is dragged as a line and a magnifier as an area")
        suite.expect(ScreenshotSupport.Annotation(tool: .magnifier).magnification == 2
                     && ScreenshotSupport.sanitizedMagnification(3) == 3
                     && ScreenshotSupport.sanitizedMagnification(0) == 2
                     && ScreenshotSupport.sanitizedMagnification(9) == 2,
                     "a magnifier starts at twice the size and an unknown magnification falls back to it")
        let ruler = ScreenshotSupport.Annotation(tool: .ruler, color: .blue, stroke: .large)
        suite.expect(ScreenshotSupport.selectionStyle(for: ruler)
                     == ScreenshotSupport.SelectionStyle(color: .blue, stroke: .large, arrowStyle: nil),
                     "a picked ruler shows its color and thickness")
    }

    // MARK: - Rendering

    static func rendering(_ suite: TestSuite) {
        // One black column at x = 20 on white.
        let base = image(width: 40, height: 40) { x, _ in x == 20 ? black : white }
        var lens = ScreenshotSupport.Annotation(tool: .magnifier, rect: CGRect(x: 10, y: 10, width: 20, height: 20),
                                                color: .red, stroke: .small)
        lens.magnification = 2
        let magnified = rendered(base, [lens])
        suite.expect(pixel(base, 21, 20) == white && pixel(magnified, 21, 20) == black
                     && pixel(magnified, 2, 2) == white,
                     "a magnifier shows what is under its centre twice as large, and only inside itself")
        let redaction = ScreenshotSupport.Annotation(tool: .redact, rect: CGRect(x: 16, y: 16, width: 8, height: 8),
                                                     color: .blue)
        let hidden = rendered(base, [redaction, lens])
        let inside = pixel(hidden, 21, 20)
        suite.expect(inside.blue > 200 && inside.red < 60,
                     "a magnifier over a covered area enlarges the cover, never what it hides")
        let above = rendered(base, [lens, redaction])
        suite.expect(pixel(above, 21, 20).blue > 200,
                     "a mark above the magnifier still draws over it")

        let ruler = ScreenshotSupport.Annotation(tool: .ruler, points: [CGPoint(x: 2, y: 30), CGPoint(x: 38, y: 30)],
                                                 color: .red, stroke: .large)
        let measured = rendered(image(width: 40, height: 40) { _, _ in white }, [ruler])
        let line = pixel(measured, 10, 30)
        suite.expect(line.red > 200 && line.green < 120, "a ruler draws its line in its color")
        let tag = (0..<40).contains { y in
            (0..<40).contains { x in
                let value = pixel(measured, x, y)
                return y < 26 && value.red > 200 && value.green < 120
            }
        }
        suite.expect(tag, "a flat ruler puts its length on a tag above the line")

        let guide = ScreenshotSupport.Annotation(tool: .guide, points: [CGPoint(x: 5.5, y: 0), CGPoint(x: 5.5, y: 40)],
                                                 color: .blue)
        let guided = rendered(image(width: 40, height: 40) { _, _ in white }, [guide])
        suite.expect(pixel(guided, 5, 1).blue > 200 && pixel(guided, 20, 20) == white,
                     "a guide draws a thin line across the capture and nothing else")
    }

    // MARK: - Resize

    static func resizing(_ suite: TestSuite) {
        let original = CGSize(width: 1000, height: 500)
        suite.expect(Output.resizedSize(original: original, width: 400) == CGSize(width: 400, height: 200)
                     && Output.resizedSize(original: original, height: 100) == CGSize(width: 200, height: 100)
                     && Output.resizedSize(original: original, percent: 150) == CGSize(width: 1500, height: 750),
                     "resizing keeps the proportions from a width, a height or a percentage")
        suite.expect(Output.resizedSize(original: original, width: 1000) == nil
                     && Output.resizedSize(original: original, width: 10) == nil
                     && Output.resizedSize(original: original, percent: 2000) == nil
                     && Output.resizedSize(original: original) == nil
                     && Output.resizedSize(original: original, width: -4) == nil,
                     "no change, a side outside the limits or nothing typed resizes nothing")
        suite.expect(Output.proportionalSide(400, of: 1000, other: 500) == 200
                     && Output.proportionalSide(3, of: 1000, other: 500) == 2,
                     "the other field follows in proportion")
        let base = image(width: 40, height: 20) { x, _ in x < 20 ? black : white }
        let smaller = ScreenshotRenderer.resized(base, to: CGSize(width: 20, height: 10))
        suite.expect(smaller?.width == 20 && smaller?.height == 10
                     && smaller.map { pixel($0, 2, 5).red < 40 && pixel($0, 17, 5).red > 215 } == true,
                     "resampling keeps what is where")
    }

    // MARK: - Preferences and strings

    static func preferencesAndStrings(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotMeasureUnit] as? String == ""
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenshotMeasureUnit),
                     "the ruler starts in points and its unit travels in backups")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastMagnification] as? Int == 2
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenshotLastMagnification),
                     "the magnifier starts at 2× and its choice travels in backups")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshotInspector(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(!values.isEmpty && values.allSatisfy { !$0.isEmpty },
                         "every inspector string is translated (\(language.rawValue))")
            suite.expect(values.allSatisfy { !$0.contains("\u{2014}") && !$0.contains("\u{2013}") && !$0.contains("'") },
                         "inspector strings use no long dashes or straight apostrophes (\(language.rawValue))")
            suite.expect(strings.measureHint.contains("⌥S") && strings.measureHint.contains("⌥D")
                         && strings.pointerColorHint.contains("⇧Tab"),
                         "the hints name their keys (\(language.rawValue))")
        }
    }
}
