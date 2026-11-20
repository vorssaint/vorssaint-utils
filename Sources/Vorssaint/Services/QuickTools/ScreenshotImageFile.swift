// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

/// One payload and extension for every editor file output; clipboard images stay PNG/TIFF.
struct ScreenshotImageFile {
    let data: Data
    let format: MediaImageFormat

    static func encode(_ export: ScreenshotRenderer.Export,
                       preferredFormat: MediaImageFormat) -> ScreenshotImageFile? {
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        if [.jpeg, .heic].contains(preferredFormat),
           supported.contains(preferredFormat.contentType.identifier),
           !hasTransparency(export.image) {
            let data = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(
                data, preferredFormat.contentType.identifier as CFString, 1, nil) {
                let properties = [
                    kCGImageDestinationLossyCompressionQuality: 1.0,
                    kCGImagePropertyDPIWidth: Double(export.scale) * 72,
                    kCGImagePropertyDPIHeight: Double(export.scale) * 72
                ] as CFDictionary
                CGImageDestinationAddImage(destination, export.image, properties)
                if CGImageDestinationFinalize(destination) {
                    return ScreenshotImageFile(data: data as Data, format: preferredFormat)
                }
            }
        }
        guard let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale) else { return nil }
        return ScreenshotImageFile(data: data, format: .png)
    }

    private static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              image.bytesPerRow <= CFDataGetLength(data) / image.height else { return true }
        var offset: Int
        switch image.alphaInfo {
        case .first, .premultipliedFirst: offset = 0
        case .last, .premultipliedLast: offset = 3
        default: return true
        }
        let order = image.bitmapInfo.intersection(.byteOrderMask)
        if order == .byteOrder32Little { offset = 3 - offset }
        else if order != .byteOrderDefault && order != .byteOrder32Big { return true }
        for row in 0..<image.height {
            for column in 0..<image.width {
                if bytes[row * image.bytesPerRow + column * 4 + offset] != 255 { return true }
            }
        }
        return false
    }
}
