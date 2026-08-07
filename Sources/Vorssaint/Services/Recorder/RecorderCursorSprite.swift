// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// The pointer the recorder draws, and the ring a click leaves behind.
///
/// Drawn by us rather than read from the system: the recording is captured
/// with the real pointer switched off so the eased one can take its place, and
/// the system's own cursor image is a deprecated read that Apple says will
/// stop working. A vector arrow also stays crisp at any zoom.
enum RecorderCursorSprite {

    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    /// The last-resort pointer, for a recording where the system never gave
    /// up a real one. Black fill with a white outline and a soft shadow, which
    /// is what the macOS arrow actually looks like; a white-filled arrow is
    /// the single most obvious way to get this wrong.
    ///
    /// Drawn into a 28 by 40 box, the size of the real one, with its point at
    /// (4.5, 4.0) so the hot spot lands where a click did.
    static let fallbackSize = CGSize(width: 28, height: 40)
    static let fallbackHotSpot = CGPoint(x: 4.5, y: 4.0)

    static func arrow(pixelSize: CGFloat) -> CGImage? {
        let width = max(8, pixelSize.rounded())
        return cached("arrow-\(Int(width))") {
            let pixels = Int(width)
            let height = Int((width * fallbackSize.height / fallbackSize.width).rounded())
            guard let context = context(width: pixels, height: height) else { return nil }
            let unit = width / fallbackSize.width

            // The outline of the pointer in its own 28x40 box, measured down
            // and right from the top-left, with the point inset so the white
            // outline is never clipped by the edge of the bitmap.
            let outline: [CGPoint] = [
                CGPoint(x: 4.5, y: 4.0),
                CGPoint(x: 4.5, y: 31.5),
                CGPoint(x: 10.5, y: 25.5),
                CGPoint(x: 14.5, y: 35.5),
                CGPoint(x: 18.5, y: 33.8),
                CGPoint(x: 14.6, y: 24.0),
                CGPoint(x: 22.5, y: 23.5),
            ]
            let path = CGMutablePath()
            for (index, point) in outline.enumerated() {
                let mapped = CGPoint(x: point.x * unit,
                                     y: CGFloat(height) - point.y * unit)
                if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
            }
            path.closeSubpath()

            context.setShadow(offset: CGSize(width: 0, height: -unit * 0.8),
                              blur: unit * 2.2,
                              color: CGColor(gray: 0, alpha: 0.35))
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(unit * 2.4)
            context.setLineJoin(.round)
            context.strokePath()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.addPath(path)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath()
            return context.makeImage()
        }
    }

    /// One thin stroked circle, transparent everywhere else.
    static func ring(radius: CGFloat, lineWidth: CGFloat, alpha: Double) -> CGImage? {
        let side = max(4, ((radius + lineWidth) * 2).rounded())
        let key = "ring-\(Int(side))-\(Int(lineWidth * 4))-\(Int(alpha * 100))"
        return cached(key) {
            let size = Int(side)
            guard let context = context(width: size, height: size) else { return nil }
            context.setStrokeColor(CGColor(gray: 1, alpha: alpha))
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: CGRect(x: lineWidth / 2 + (side / 2 - radius),
                                             y: lineWidth / 2 + (side / 2 - radius),
                                             width: radius * 2 - lineWidth,
                                             height: radius * 2 - lineWidth))
            return context.makeImage()
        }
    }

    static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private static func cached(_ key: String, _ make: () -> CGImage?) -> CGImage? {
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        guard let image = make() else { return nil }
        lock.lock()
        // The cache exists to keep a per-frame draw from re-rasterizing the
        // same sprite, not to grow forever: a handful of sizes is all a
        // recording ever asks for.
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        lock.unlock()
        return image
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let context = CGContext(data: nil,
                                width: max(1, width),
                                height: max(1, height),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setAllowsAntialiasing(true)
        context?.interpolationQuality = .high
        return context
    }
}
