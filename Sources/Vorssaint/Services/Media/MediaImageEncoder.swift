// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stateless ImageIO helpers shared by the media tools and the clipboard
/// image optimizer. Nothing here draws with AppKit, so it runs on any queue.
enum MediaImageEncoder {
    struct Info: Equatable {
        let width: Int
        let height: Int
        let hasAlpha: Bool
        /// Horizontal resolution, nil when the file does not say.
        let dpi: Double?
    }

    static func typeIdentifier(for format: MediaImageFormat) -> String {
        switch format {
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .png: return UTType.png.identifier
        case .pdf: return UTType.pdf.identifier
        }
    }

    static func sanitizedImageProperties(_ properties: [CFString: Any], image: CGImage) -> [CFString: Any] {
        var clean = properties
        clean.removeValue(forKey: kCGImagePropertyOrientation)
        clean[kCGImagePropertyPixelWidth] = image.width
        clean[kCGImagePropertyPixelHeight] = image.height
        return clean
    }

    /// Adds one image and finalizes. Without `properties` no metadata is
    /// written, which is what stripping means here.
    static func write(_ image: CGImage,
                      to destination: CGImageDestination,
                      quality: Double?,
                      properties: [CFString: Any] = [:]) -> Bool {
        var outputProperties = properties
        if let quality {
            outputProperties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    static func encode(_ image: CGImage, type: String, quality: Double?,
                       properties: [CFString: Any] = [:]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil),
              write(image, to: destination, quality: quality, properties: properties) else { return nil }
        return data as Data
    }

    static func imageInfo(_ data: Data) -> Info? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return Info(width: width, height: height,
                    hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
                    dpi: (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue)
    }

    /// Decodes at full size, or as a thumbnail whose long edge is `maxPixel`,
    /// which never materializes the full bitmap first.
    static func decode(_ data: Data, maxPixel: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let maxPixel else {
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }
}
