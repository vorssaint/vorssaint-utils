// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

enum ImageThumbnailer {
    static let defaultPointSize: CGFloat = 20

    static func thumbnail(for url: URL, pointSize: CGFloat = defaultPointSize) -> NSImage? {
        thumbnail(for: url, pointSize: pointSize, scale: backingScale)
    }

    /// The same decode, off the main thread. Decoding is synchronous work
    /// that scales with the source file, so a caller with many files to get
    /// through (the shelf restoring a saved list) would otherwise hold the
    /// main thread for the sum of all of them. NSScreen is main-thread-only,
    /// so the scale is read there and the decode runs off the main actor,
    /// the same split VideoThumbnailer uses.
    static func thumbnail(for url: URL, pointSize: CGFloat = defaultPointSize) async -> NSImage? {
        let scale = await MainActor.run { backingScale }
        return thumbnail(for: url, pointSize: pointSize, scale: scale)
    }

    private static func thumbnail(for url: URL, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let maxPixelSize = pixelSize(for: pointSize, scale: scale)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let size = NSSize(width: CGFloat(cgImage.width) / scale,
                          height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    static func thumbnail(for image: NSImage, pointSize: CGFloat = defaultPointSize) -> NSImage? {
        let pixels = pixelSize(for: pointSize, scale: backingScale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixels,
                                         pixelsHigh: pixels,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            return nil
        }

        // The rep's point size MUST be set before the context is created: the
        // context takes its user-space scale from the rep at creation time.
        // Created first, it maps one point to one pixel, and drawing into the
        // pointSize rect fills only a quarter of a retina bitmap, which is why
        // icons used to render at half their intended size.
        let logicalSize = NSSize(width: pointSize, height: pointSize)
        rep.size = logicalSize
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: logicalSize).fill()
        image.draw(in: NSRect(origin: .zero, size: logicalSize),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1,
                   respectFlipped: false,
                   hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: logicalSize)
        result.addRepresentation(rep)
        return result
    }

    static func estimatedBitmapCost(pointSize: CGFloat = defaultPointSize) -> Int {
        let pixels = pixelSize(for: pointSize, scale: backingScale)
        return pixels * pixels * 4
    }

    static var backingScale: CGFloat {
        max(1, NSScreen.main?.backingScaleFactor ?? 2)
    }

    /// Takes `scale` rather than defaulting to `backingScale` so that every
    /// caller's dependency on an `NSScreen` read is visible where it happens.
    /// It does not move the read: the two callers that used the default now
    /// pass `backingScale` themselves, on the same thread as before.
    private static func pixelSize(for pointSize: CGFloat, scale: CGFloat) -> Int {
        max(16, Int((pointSize * scale).rounded(.up)))
    }
}
