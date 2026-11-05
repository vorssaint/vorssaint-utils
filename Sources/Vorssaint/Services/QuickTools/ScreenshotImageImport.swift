// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Reads encoded dimensions before decoding, so declining a large file allocates no bitmap.
struct ScreenshotImageImport {
    static let maximumDimension = 6_000
    private let source: CGImageSource
    private let sourceIndex: Int
    let pixelSize: CGSize
    let sourceFormat: MediaImageFormat
    private let scale: CGFloat

    var requiresSizeChoice: Bool {
        max(pixelSize.width, pixelSize.height) > CGFloat(Self.maximumDimension)
    }

    var reducedMaximumDimension: Int {
        let size = MediaImageResizeMode.maxDimension(Self.maximumDimension).targetSize(for: pixelSize)
        return Int(max(size.width, size.height))
    }

    private init?(source: CGImageSource) {
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?,
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { return nil }
        self.source = source
        sourceIndex = index
        let type = CGImageSourceGetType(source) as String?
        sourceFormat = CGImageSourceGetCount(source) == 1
            ? [MediaImageFormat.jpeg, .png, .heic].first(where: { $0.contentType.identifier == type }) ?? .png : .png
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        pixelSize = CGSize(width: rotated ? height.doubleValue : width.doubleValue,
                           height: rotated ? width.doubleValue : height.doubleValue)
        let dpiX = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let dpiY = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
        scale = ScreenshotSupport.clipboardImageScale(
            pixelSize: CGSize(width: width.doubleValue, height: height.doubleValue),
            pointSize: CGSize(width: width.doubleValue * 72 / dpiX,
                              height: height.doubleValue * 72 / dpiY))
    }

    init?(url: URL) {
        if let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
           let input = Self(source: source) {
            self = input
        } else {
            guard let data = NSImage(contentsOf: url)?.tiffRepresentation else { return nil }
            self.init(data: data)
        }
    }

    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        self.init(source: source)
    }

    init?(pasteboard: NSPasteboard) {
        if let url = Self.fileURL(from: pasteboard), let input = Self(url: url) {
            self = input
            return
        }
        // AppKit may synthesize TIFF by decoding the full JPEG or HEIC.
        // Read encoded formats first so the size choice precedes that work.
        let types: [NSPasteboard.PasteboardType] = [
            .png, .init(UTType.jpeg.identifier), .init(UTType.heic.identifier), .tiff
        ]
        for type in types {
            if let data = pasteboard.data(forType: type), let input = Self(data: data) {
                self = input
                return
            }
        }
        guard let data = NSImage(pasteboard: pasteboard)?.tiffRepresentation else { return nil }
        self.init(data: data)
    }

    static func fileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL])?.first as URL?
    }

    func decode() -> (image: CGImage, scale: CGFloat)? {
        guard let image = MediaImageProcessing.decode(source, at: sourceIndex,
                                                      maximumDimension: reducedMaximumDimension) else { return nil }
        return (image, scale)
    }
}
