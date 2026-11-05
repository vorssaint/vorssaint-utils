// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How Save writes a capture. Copying, dragging, sharing links and the
/// recent captures stay PNG everywhere, since that is what other apps paste
/// best and what those paths read back.
enum ScreenshotSaveFormat: String, CaseIterable {
    case png = ""
    case jpeg
    case automatic

    static func sanitized(_ raw: String?) -> ScreenshotSaveFormat {
        ScreenshotSaveFormat(rawValue: raw ?? "") ?? .png
    }

    enum FileType: Equatable {
        case png, jpeg

        var fileExtension: String {
            self == .png ? "png" : "jpg"
        }

        var contentType: UTType {
            self == .png ? .png : .jpeg
        }

        /// What a typed file name asks for; anything but a JPEG name is PNG.
        init(fileExtension: String) {
            self = ["jpg", "jpeg"].contains(fileExtension.lowercased()) ? .jpeg : .png
        }
    }

    /// What Automatic decides from: how many pixels it read, how many
    /// different colors they hold, and whether any of them is see-through.
    struct Sample: Equatable {
        let pixels: Int
        let distinctColors: Int
        let opaque: Bool
    }

    /// Pixels a side Automatic reads at most. Nearest neighbour keeps every
    /// value a color that is really in the picture.
    static let sampleSide = 128

    static func sample(of image: CGImage, maximumSide: Int = sampleSide) -> Sample? {
        guard image.width > 0, image.height > 0 else { return nil }
        let factor = min(1, CGFloat(maximumSide) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let words = data.bindMemory(to: UInt32.self, capacity: width * height)
        var colors = Set<UInt32>()
        var opaque = true
        for index in 0..<(width * height) {
            let word = words[index]
            colors.insert(word)
            // The alpha byte is the last one in memory whatever the order.
            if withUnsafeBytes(of: word, { $0[3] }) != 255 { opaque = false }
        }
        return Sample(pixels: width * height, distinctColors: colors.count, opaque: opaque)
    }

    /// The file type a save gets. A screen of text and controls uses few
    /// distinct colors and stays sharp as PNG; a photo or a rich gradient
    /// uses almost as many colors as it has pixels and is far smaller as
    /// JPEG. Anything see-through stays PNG, which keeps it.
    func fileType(for sample: Sample?) -> FileType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .automatic:
            guard let sample, sample.opaque, sample.pixels >= 256 else { return .png }
            return Double(sample.distinctColors) / Double(sample.pixels) > 0.35 ? .jpeg : .png
        }
    }

    /// JPEG has no transparency, so what is see-through lands on white, the
    /// way Preview exports it. The pixels per point travel as DPI, as they
    /// do in the PNG.
    static func jpegData(from image: CGImage, scale: CGFloat, quality: Double = 0.9) -> Data? {
        let width = image.width
        let height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flattened = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let properties = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyDPIWidth: Double(scale) * 72,
            kCGImagePropertyDPIHeight: Double(scale) * 72,
        ] as CFDictionary
        CGImageDestinationAddImage(destination, flattened, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
