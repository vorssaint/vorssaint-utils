// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum MediaImageProcessing {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    // Native decoders may use full source buffers; this bounds output pixels,
    // not peak memory. Use tiled decoding if a hard peak bound is required.
    static func decode(_ source: CGImageSource, at index: Int = 0,
                       maximumDimension: Int) -> CGImage? {
        if index != 0 {
            // Image I/O's HEIC thumbnail path can read the first image even
            // when a different index is requested. Core Image keeps that index.
            let image = CIImage(cgImageSource: source, index: index,
                                options: [.applyOrientationProperty: true])
            let extent = image.extent
            guard !extent.isEmpty, extent.width.isFinite, extent.height.isFinite,
                  maximumDimension > 0 else { return nil }
            let factor = min(1, CGFloat(maximumDimension) / max(extent.width, extent.height))
            let size = MediaSupport.integralImageSize(width: extent.width * factor,
                                                     height: extent.height * factor)
            let resized = image
                .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            return context.createCGImage(resized, from: CGRect(origin: .zero, size: size))
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, index, options)
    }
}
