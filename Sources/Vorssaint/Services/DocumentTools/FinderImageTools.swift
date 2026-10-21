// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Bounded raster operations; results are new PNG files with normalized orientation.
enum FinderImageTools {
    static let maximumPixels = 64_000_000
    static let maximumDimension = 16_384

    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = values[kCGImagePropertyPixelWidth] as? Int,
              let height = values[kCGImagePropertyPixelHeight] as? Int else {
            throw FinderFileActionError.unsupported(url, "The file is not a readable image")
        }
        try validateDimensions(width: width, height: height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    static func rotate(_ image: CGImage, clockwise: Bool = true) throws -> CGImage {
        let transformed = CIImage(cgImage: image).oriented(clockwise ? .right : .left)
        guard let output = CIContext().createCGImage(transformed, from: transformed.extent) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return output
    }

    static func stitch(_ images: [CGImage], horizontal: Bool,
                       cancellation: FinderToolsCancellation) throws -> CGImage {
        guard !images.isEmpty, images.count <= 32 else {
            throw FinderFileActionError.invalidRequest("Choose between 1 and 32 images to stitch.")
        }
        let width = horizontal ? images.reduce(0) { $0 + $1.width } : images.map(\.width).max()!
        let height = horizontal ? images.map(\.height).max()! : images.reduce(0) { $0 + $1.height }
        let context = try canvas(width: width, height: height)
        var offset = 0
        for image in images {
            try cancellation.check()
            let rect: CGRect
            if horizontal {
                rect = CGRect(x: offset, y: (height - image.height) / 2, width: image.width, height: image.height)
                offset += image.width
            } else {
                rect = CGRect(x: (width - image.width) / 2, y: height - offset - image.height,
                              width: image.width, height: image.height)
                offset += image.height
            }
            context.draw(image, in: rect)
        }
        guard let output = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return output
    }

    static func recolor(_ image: CGImage, red: Double, green: Double, blue: Double) throws -> CGImage {
        guard [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw FinderFileActionError.invalidRequest("Color components must be between zero and one.")
        }
        let context = try canvas(width: image.width, height: image.height)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        context.setBlendMode(.sourceIn)
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(bounds)
        guard let output = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return output
    }

    static func removeBackground(_ image: CGImage, replacement: CGImage? = nil,
                                 cancellation: FinderToolsCancellation) throws -> CGImage {
        try cancellation.check()
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        try cancellation.check()
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw FinderFileActionError.invalidRequest("No foreground subject was detected in the image.")
        }
        let pixels = try observation.generateMaskedImage(ofInstances: observation.allInstances,
            from: handler, croppedToInstancesExtent: false)
        var foreground = CIImage(cvPixelBuffer: pixels)
        if let replacement {
            let background = CIImage(cgImage: replacement)
            let scale = max(foreground.extent.width / background.extent.width,
                            foreground.extent.height / background.extent.height)
            let resized = background.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let aligned = resized.transformed(by: CGAffineTransform(
                translationX: foreground.extent.midX - resized.extent.midX,
                y: foreground.extent.midY - resized.extent.midY))
            foreground = foreground.composited(over: aligned.cropped(to: foreground.extent))
        }
        guard let output = CIContext().createCGImage(foreground, from: foreground.extent) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return output
    }

    static func savePNG(_ image: CGImage, in directory: URL, named name: String,
                        cancellation: FinderToolsCancellation) throws -> URL {
        try cancellation.check()
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw CocoaError(.fileWriteUnknown) }
        try cancellation.check()
        let outputName = name.lowercased().hasSuffix(".png") ? name : name + ".png"
        return try FinderFileActions.createFile(in: directory, named: outputName, contents: data as Data,
                                                collisionPolicy: .makeUnique)
    }

    private static func canvas(width: Int, height: Int) throws -> CGContext {
        try validateDimensions(width: width, height: height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return context
    }

    private static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension,
              width * height <= maximumPixels else {
            throw FinderFileActionError.invalidRequest("The image exceeds 64 megapixels or 16,384 pixels on one side.")
        }
    }
}
