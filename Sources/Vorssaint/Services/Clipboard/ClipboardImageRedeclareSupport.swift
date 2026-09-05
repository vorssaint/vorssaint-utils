// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

/// Detects the second capture produced when a source app re-declares the
/// pasteboard while resolving a promised image flavor. Chromium browsers post
/// image copies with lazy flavors; the history capture's immediate read makes
/// the browser render the promised PNG, and posting that render bumps the
/// change count again seconds after the copy. The picture is the same, but it
/// arrives from a different encoder — often converted from the page's Display
/// P3 profile to sRGB — so byte hashes never match and the history records a
/// twin. Compared here on a small colorspace-normalized thumbnail instead,
/// which absorbs the rounding that color conversion introduces while still
/// telling genuinely different images apart.
enum ClipboardImageRedeclare {
    /// A re-declare lands within a couple of seconds of the copy; anything
    /// later is treated as a deliberate new copy.
    static let window: TimeInterval = 3
    static let thumbnailSide = 16
    /// Mean absolute channel difference at or below this reads as the same
    /// picture. Color-managed re-encodes land near zero once downsampled;
    /// different images of the same size land far above it.
    static let tolerance: Double = 3

    struct Signature {
        let width: Int
        let height: Int
        let thumbnail: [UInt8]
        let capturedAt: Date
        let entryID: UUID
    }

    /// The entry the new image re-declares, or nil when it is a genuine new
    /// copy: same pixel size, inside the window, and matching thumbnails.
    static func redeclaredEntryID(previous: Signature?,
                                  width: Int,
                                  height: Int,
                                  thumbnail: [UInt8],
                                  at date: Date = Date()) -> UUID? {
        guard let previous,
              previous.width == width,
              previous.height == height,
              date.timeIntervalSince(previous.capturedAt) >= 0,
              date.timeIntervalSince(previous.capturedAt) <= window,
              matches(previous.thumbnail, thumbnail)
        else { return nil }
        return previous.entryID
    }

    static func matches(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var total = 0
        for index in a.indices {
            total += abs(Int(a[index]) - Int(b[index]))
        }
        return Double(total) / Double(a.count) <= tolerance
    }

    static func thumbnail(of data: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Ask ImageIO for a decode bounded at the comparison size instead of
        // decoding the full bitmap: this runs on the main queue for every
        // image copy, and a full decode of a 6K screenshot there is real,
        // visible latency. ImageIO subsamples during decode, so the cost
        // scales with the thumbnail, not the source.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return thumbnail(of: image)
    }

    /// Draws into a fixed sRGB RGBA8 canvas so images tagged with different
    /// profiles are compared in one colorspace.
    static func thumbnail(of image: CGImage) -> [UInt8]? {
        let side = thumbnailSide
        let bytesPerRow = side * 4
        var buffer = [UInt8](repeating: 0, count: side * bytesPerRow)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: side,
                                          height: side,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? buffer : nil
    }
}
