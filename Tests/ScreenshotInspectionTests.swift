// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The screenshot editor's inspection rules, on synthetic pixels.
enum ScreenshotInspectionTests {
    typealias Inspection = ScreenshotInspectionSupport
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
        tools(suite)
        rendering(suite)
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

    // MARK: - Tools

    static func tools(_ suite: TestSuite) {
        typealias Tool = ScreenshotSupport.Tool
        suite.expect(Tool.editorTools.contains(.ruler)
                     && !Tool.editorTools.contains(.guide) && !Tool.editorTools.contains(.image),
                     "the ruler is in the rail; guides and images are content only")
        let saved = "select,arrow,pixelate,crop,text,sticker,rect,highlight,freehand,line,ellipse,counter,redact,spotlight,expandCanvas"
        let ordered = Tool.ordered(from: saved)
        suite.expect(Array(ordered.prefix(15).map(\.rawValue)) == saved.split(separator: ",").map(String.init)
                     && ordered.last == .ruler,
                     "an order saved before the ruler keeps its keys and gains it at the end")
        suite.expect(Tool.ordered(from: "guide,ruler").first == .ruler
                     && Tool.startingTool(remembered: "guide") == .arrow
                     && Tool.startingTool(remembered: "ruler") == .ruler
                     && Tool.bindings(from: "guide=:1").isEmpty,
                     "a guide is never a rail tool, a starting tool or a binding")
        suite.expect(!Tool.ruler.dragsRect && !Tool.ruler.resizesWithHandles,
                     "a ruler is dragged as a line")
        let ruler = ScreenshotSupport.Annotation(tool: .ruler, color: .blue, stroke: .large)
        suite.expect(ScreenshotSupport.selectionStyle(for: ruler)
                     == ScreenshotSupport.SelectionStyle(color: .blue, stroke: .large, arrowStyle: nil),
                     "a picked ruler shows its color and thickness")
    }

    // MARK: - Rendering

    static func rendering(_ suite: TestSuite) {
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

    // MARK: - Preferences and strings

    static func preferencesAndStrings(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotMeasureUnit] as? String == ""
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenshotMeasureUnit),
                     "the ruler starts in points and its unit travels in backups")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshotInspector(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(!values.isEmpty && values.allSatisfy { !$0.isEmpty },
                         "every inspector string is translated (\(language.rawValue))")
            suite.expect(values.allSatisfy { !$0.contains("\u{2014}") && !$0.contains("\u{2013}") && !$0.contains("'") },
                         "inspector strings use no long dashes or straight apostrophes (\(language.rawValue))")
            suite.expect(strings.measureHint.contains("⌥S") && strings.measureHint.contains("⌥D"),
                         "the measuring hint names its guide keys (\(language.rawValue))")
        }
    }
}
