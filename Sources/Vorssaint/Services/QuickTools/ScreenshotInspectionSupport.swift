// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The decisions behind the editor's inspection tools, starting with
/// measuring the gap between edges. Everything works on plain pixel values in
/// image pixels with a top-left origin, the annotations' space, so each rule
/// is testable on a handful of synthetic pixels.
enum ScreenshotInspectionSupport {
    // MARK: - Pixels

    /// One sRGB pixel, alpha not premultiplied.
    struct RGBA: Hashable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8 = 255

        init(_ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8 = 255) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    /// A region of an image read into memory, top row first.
    struct PixelGrid: Equatable {
        let width: Int
        let height: Int
        let pixels: [RGBA]

        subscript(x: Int, y: Int) -> RGBA {
            pixels[y * width + x]
        }
    }

    /// Reads `region` of `image` as sRGB pixels. With `maximumSide`, a larger
    /// region is sampled down by nearest neighbour, so every value is still a
    /// color that is really on screen rather than a blend of several.
    static func pixelGrid(of image: CGImage, region: CGRect, maximumSide: Int? = nil) -> PixelGrid? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let crop = region.integral.intersection(bounds)
        guard !crop.isNull, crop.width >= 1, crop.height >= 1,
              let source = image.cropping(to: crop) else { return nil }
        var width = Int(crop.width)
        var height = Int(crop.height)
        if let maximumSide, max(width, height) > maximumSide {
            let factor = CGFloat(maximumSide) / CGFloat(max(width, height))
            width = max(1, Int((CGFloat(width) * factor).rounded()))
            height = max(1, Int((CGFloat(height) * factor).rounded()))
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for index in 0..<(width * height) {
            let offset = index * 4
            let alpha = bytes[offset + 3]
            func straight(_ value: UInt8) -> UInt8 {
                guard alpha < 255 else { return value }
                guard alpha > 0 else { return 0 }
                return UInt8(min(255, (Int(value) * 255 + Int(alpha) / 2) / Int(alpha)))
            }
            pixels.append(RGBA(straight(bytes[offset]), straight(bytes[offset + 1]),
                               straight(bytes[offset + 2]), alpha))
        }
        return PixelGrid(width: width, height: height, pixels: pixels)
    }

    /// How far apart two colors are: the largest difference of any channel.
    static func distance(_ a: RGBA, _ b: RGBA) -> Int {
        max(abs(Int(a.red) - Int(b.red)), abs(Int(a.green) - Int(b.green)),
            abs(Int(a.blue) - Int(b.blue)), abs(Int(a.alpha) - Int(b.alpha)))
    }

    // MARK: - Measuring

    enum Axis: Equatable {
        case horizontal, vertical
    }

    /// What the editor measures while the pointer moves: the gap between the
    /// edges on either side of it, or a guide across the whole capture.
    enum LiveMode: Equatable {
        case distance(Axis)
        case guide(Axis)
    }

    /// The same key again ends the mode; any other starts its own.
    static func toggledMode(_ current: LiveMode?, pressing mode: LiveMode) -> LiveMode? {
        current == mode ? nil : mode
    }

    /// Lengths read in points on a Retina capture by default, the way the
    /// interface was laid out; pixels are one switch away.
    enum MeasureUnit: String, CaseIterable {
        case points = ""
        case pixels = "px"

        static func sanitized(_ raw: String?) -> MeasureUnit {
            MeasureUnit(rawValue: raw ?? "") ?? .points
        }

        var toggled: MeasureUnit {
            self == .points ? .pixels : .points
        }
    }

    /// Neighbouring pixels closer than this belong to the same surface, so a
    /// soft gradient or a little compression noise does not stop the ruler.
    static let edgeTolerance = 18

    /// The stretch of `line` around `index` with no edge in it: it grows
    /// while each next pixel stays within `tolerance` of the one before.
    static func similarRun(in line: [RGBA], around index: Int,
                           tolerance: Int = edgeTolerance) -> Range<Int> {
        guard line.indices.contains(index) else { return index..<index }
        var lower = index
        while lower > 0, distance(line[lower - 1], line[lower]) <= tolerance {
            lower -= 1
        }
        var upper = index + 1
        while upper < line.count, distance(line[upper], line[upper - 1]) <= tolerance {
            upper += 1
        }
        return lower..<upper
    }

    /// A measured span in image pixels, drawn across pixel centres.
    struct Span: Equatable {
        var start: CGPoint
        var end: CGPoint

        var length: CGFloat {
            hypot(end.x - start.x, end.y - start.y)
        }
    }

    /// The gap around the pointer along one axis. `line` is the row (or
    /// column) under the pointer; the span covers whole pixels, so a ten
    /// pixel gap measures ten.
    static func measuredSpan(line: [RGBA], axis: Axis, pointer: CGPoint,
                             tolerance: Int = edgeTolerance) -> Span? {
        let along = Int((axis == .horizontal ? pointer.x : pointer.y).rounded(.down))
        guard line.indices.contains(along) else { return nil }
        let run = similarRun(in: line, around: along, tolerance: tolerance)
        let across = (axis == .horizontal ? pointer.y : pointer.x).rounded(.down) + 0.5
        let lower = CGFloat(run.lowerBound)
        let upper = CGFloat(run.upperBound)
        switch axis {
        case .horizontal:
            return Span(start: CGPoint(x: lower, y: across), end: CGPoint(x: upper, y: across))
        case .vertical:
            return Span(start: CGPoint(x: across, y: lower), end: CGPoint(x: across, y: upper))
        }
    }

    /// A guide runs the whole capture through the pointer's pixel.
    static func guideSpan(axis: Axis, pointer: CGPoint, imageSize: CGSize) -> Span {
        switch axis {
        case .horizontal:
            let y = min(max(pointer.y.rounded(.down), 0), max(imageSize.height - 1, 0)) + 0.5
            return Span(start: CGPoint(x: 0, y: y), end: CGPoint(x: imageSize.width, y: y))
        case .vertical:
            let x = min(max(pointer.x.rounded(.down), 0), max(imageSize.width - 1, 0)) + 0.5
            return Span(start: CGPoint(x: x, y: 0), end: CGPoint(x: x, y: imageSize.height))
        }
    }

    /// A ruler drawn by hand snaps flat or upright with Shift, like the
    /// system's own drawing tools.
    static func constrainedEnd(from start: CGPoint, to end: CGPoint, axisLocked: Bool) -> CGPoint {
        guard axisLocked else { return end }
        return abs(end.x - start.x) >= abs(end.y - start.y)
            ? CGPoint(x: end.x, y: start.y)
            : CGPoint(x: start.x, y: end.y)
    }

    /// Lengths read the way design tools print them, with a decimal point
    /// in every language.
    static let technicalLocale = Locale(identifier: "en_US_POSIX")

    /// "120 pt", "240 px" or "60.5 pt". A 1x capture has nothing to convert,
    /// so it always reads in pixels.
    static func measureLabel(lengthPixels: CGFloat, scale: CGFloat, unit: MeasureUnit) -> String {
        let usesPoints = unit == .points && scale > 1
        let value = usesPoints ? lengthPixels / scale : lengthPixels
        let rounded = (value * 10).rounded() / 10
        let number = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", locale: technicalLocale, Double(rounded))
        return number + (usesPoints ? " pt" : " px")
    }
}
