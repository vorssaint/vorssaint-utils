// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Turns an overlay's picture into the pixels a frame composites, once.
///
/// The same bargain the caption renderer makes: the file is read and resized
/// while the plan is built, so every frame after that is a composite of a
/// texture already at the size it is drawn. Sizes repeat as soon as anything
/// else about the edit changes, which is what the cache is for; it is held to
/// a budget in pixels rather than in entries, because one mark covering most
/// of a 4K frame is worth as much memory as a hundred captions.
enum RecorderImageRenderer {

    private static let pixelBudget = 24_000_000

    private static var cache: [String: CGImage] = [:]
    private static var cachedPixels = 0
    private static let lock = NSLock()

    static func image(for overlay: RecorderImageOverlay, canvas: CGSize) -> CGImage? {
        let url = URL(fileURLWithPath: overlay.path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey,
                                                             .fileSizeKey,
                                                             .contentModificationDateKey]),
              values.isRegularFile == true,
              let source = MediaSupport.imageDisplaySize(at: url),
              let drawn = RecorderImageOverlay.drawnSize(source: source,
                                                         size: overlay.size,
                                                         canvas: canvas),
              MediaSupport.imageRenderSizeIsSafe(drawn)
        else { return nil }

        // The file's own size and date are part of the key: a logo replaced on
        // disk while the editor is open is a different picture, not the same
        // one at the same size.
        let stamp = "\(values.fileSize ?? 0)|"
            + "\(values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)"
        let key = "\(overlay.path)|\(Int(drawn.width))x\(Int(drawn.height))|\(stamp)"
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let image = render(overlay.path, drawn: drawn) else { return nil }
        lock.lock()
        if cachedPixels > pixelBudget {
            cache.removeAll()
            cachedPixels = 0
        }
        cache[key] = image
        cachedPixels += image.width * image.height
        lock.unlock()
        return image
    }

    /// Decoded no larger than it is drawn, then drawn at exactly that size, so
    /// a photograph never arrives at full resolution and a small logo asked to
    /// fill half the frame is still resampled smoothly instead of blocking up.
    private static func render(_ path: String, drawn: CGSize) -> CGImage? {
        let width = Int(drawn.width)
        let height = Int(drawn.height)
        guard let picture = MediaSupport.imageThumbnail(at: URL(fileURLWithPath: path),
                                                        maxPixel: max(width, height)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(origin: .zero, size: drawn))
        return context.makeImage()
    }
}
