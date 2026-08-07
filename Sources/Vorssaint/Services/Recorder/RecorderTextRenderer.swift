// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreText

/// Turns a line of overlay text into pixels, once.
///
/// Rasterized rather than drawn per frame: the same words at the same size
/// come out identical every time, so a two-minute export draws each caption
/// exactly once and composites a texture for the rest of it.
enum RecorderTextRenderer {

    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    static func image(for overlay: RecorderTextOverlay, canvasHeight: CGFloat) -> CGImage? {
        let pointSize = max(8, (canvasHeight * CGFloat(overlay.size)).rounded())
        let key = "\(overlay.text)|\(Int(pointSize))|\(overlay.palette.rawValue)"
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let image = render(overlay.text, pointSize: pointSize, palette: overlay.palette)
        else { return nil }
        lock.lock()
        if cache.count > 48 { cache.removeAll() }
        cache[key] = image
        lock.unlock()
        return image
    }

    static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private static func render(_ text: String,
                               pointSize: CGFloat,
                               palette: RecorderTextOverlay.Palette) -> CGImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = palette.components
        let color = NSColor(srgbRed: components.red,
                            green: components.green,
                            blue: components.blue,
                            alpha: 1)
        // A shadow rather than an outline: text over a screen recording lands
        // on anything, and a soft drop is what keeps it readable without
        // looking like a sticker.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = pointSize * 0.18
        shadow.shadowOffset = CGSize(width: 0, height: -pointSize * 0.04)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pointSize, weight: .semibold),
            .foregroundColor: color,
            .shadow: shadow,
        ]
        let attributed = NSAttributedString(string: trimmed, attributes: attributes)
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)
        let bounds = attributed.boundingRect(with: unbounded,
                                             options: [.usesLineFragmentOrigin])
        let padding = pointSize * 0.5
        let width = Int((bounds.width + padding * 2).rounded(.up))
        let height = Int((bounds.height + padding * 2).rounded(.up))
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        attributed.draw(with: CGRect(x: padding, y: padding,
                                     width: bounds.width, height: bounds.height),
                        options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Where the rasterized line sits on the canvas, in Core Image's
    /// bottom-left space, with a margin off every edge it touches.
    static func origin(for overlay: RecorderTextOverlay,
                       textSize: CGSize,
                       canvas: CGSize) -> CGPoint {
        let margin = min(canvas.width, canvas.height) * 0.05
        let point = overlay.anchor.unitPoint
        let x = margin + (canvas.width - textSize.width - margin * 2) * point.x
        // The anchor counts down from the top, the way the screen does.
        let topY = margin + (canvas.height - textSize.height - margin * 2) * point.y
        return CGPoint(x: x, y: canvas.height - topY - textSize.height)
    }
}
