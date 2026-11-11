// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// One display in a frozen frame.
struct ShotDisplay {
    let id: CGDirectDisplayID
    /// Where the display sits, in the overlay's shared points.
    let bounds: ShotRect
    /// Pixels per point.
    let scale: CGFloat
    let image: CGImage
}

/// A frozen copy of every display. Positions are whole points in one space
/// shared by all displays, with the main display's top-left corner at the
/// origin and y growing downwards.
final class ShotFrame {
    let displays: [ShotDisplay]
    /// Every display together.
    let bounds: ShotRect

    init(displays: [ShotDisplay]) {
        self.displays = displays
        bounds = displays.reduce(ShotRect.zero) { $0.union($1.bounds) }
    }

    /// Photographs every display. Nil when nothing could be captured.
    static func grab(includeCursor: Bool) async -> ShotFrame? {
        let images = await ScreenRegionCapture.captureAllDisplays(includePointer: includeCursor)
        let displays = await MainActor.run { () -> [ShotDisplay] in
            NSScreen.screens.compactMap { screen in
                guard let image = images[screen.displayID] else { return nil }
                return ShotDisplay(id: screen.displayID, bounds: ShotFrame.shotRect(fromCocoa: screen.frame),
                                   scale: screen.backingScaleFactor, image: image)
            }
        }
        return displays.isEmpty ? nil : ShotFrame(displays: displays)
    }

    /// The height of the main display, which the shared space is flipped around.
    static var mainHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func shotRect(fromCocoa rect: CGRect) -> ShotRect {
        ShotRect(x: Int(rect.minX.rounded()), y: Int((mainHeight - rect.maxY).rounded()),
                 width: Int(rect.width.rounded()), height: Int(rect.height.rounded()))
    }

    static func cocoaRect(from rect: ShotRect) -> CGRect {
        CGRect(x: CGFloat(rect.x), y: mainHeight - CGFloat(rect.bottom),
               width: CGFloat(rect.width), height: CGFloat(rect.height))
    }

    /// The pointer in the shared space.
    static func pointer() -> (x: Int, y: Int) {
        let location = NSEvent.mouseLocation
        return (Int(location.x.rounded(.down)), Int((mainHeight - location.y).rounded(.down)))
    }

    /// The display holding the point, or the nearest one.
    func display(atX x: Double, y: Double) -> ShotDisplay {
        if let hit = displays.first(where: { $0.bounds.contains(x, y) }) { return hit }
        return displays.min { Self.distance($0.bounds, x, y) < Self.distance($1.bounds, x, y) } ?? displays[0]
    }

    private static func distance(_ r: ShotRect, _ x: Double, _ y: Double) -> Double {
        let dx = max(max(Double(r.x) - x, 0), x - Double(r.right))
        let dy = max(max(Double(r.y) - y, 0), y - Double(r.bottom))
        return dx * dx + dy * dy
    }

    /// The finest scale among the displays the rectangle touches.
    func scale(for rect: ShotRect) -> CGFloat {
        displays.filter { !$0.bounds.intersection(rect).isEmpty }.map(\.scale).max()
            ?? displays.map(\.scale).max() ?? 2
    }

    /// The pixel of a display under a point of the shared space.
    func pixel(atX x: Int, y: Int) -> (display: ShotDisplay, px: Int, py: Int)? {
        guard let display = displays.first(where: { $0.bounds.contains(Double(x), Double(y)) }) else { return nil }
        let px = Int((CGFloat(x - display.bounds.x) * display.scale).rounded(.down))
        let py = Int((CGFloat(y - display.bounds.y) * display.scale).rounded(.down))
        return (display, min(max(px, 0), display.image.width - 1), min(max(py, 0), display.image.height - 1))
    }

    /// The colour of the pixel under a point as #RRGGBB.
    func hex(atX x: Int, y: Int) -> String {
        guard let hit = pixel(atX: x, y: y),
              let crop = hit.display.image.cropping(to: CGRect(x: hit.px, y: hit.py, width: 1, height: 1))
        else { return "" }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: Self.colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2]) : ""
    }

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Draws every display's picture. The context's space is the shared one:
    /// points, y growing downwards.
    func draw(in context: CGContext) {
        for display in displays {
            Self.draw(display.image, in: display.bounds, context: context)
        }
    }

    /// Draws an image upright into a rectangle of a context whose y grows downwards.
    static func draw(_ image: CGImage, in rect: ShotRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: CGFloat(rect.x), y: CGFloat(rect.bottom))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(rect.width), height: CGFloat(rect.height)))
        context.restoreGState()
    }

    /// A bitmap of `region` at `scale` pixels per point, whose drawing space
    /// is the shared one. `draw` paints into it.
    static func bitmap(of region: ShotRect, scale: CGFloat, draw: (CGContext) -> Void) -> CGContext? {
        let width = max(1, Int((CGFloat(region.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(region.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -CGFloat(region.x), y: -CGFloat(region.y))
        draw(context)
        return context
    }

    /// The selection with its drawings, at the finest scale it touches.
    func render(_ selection: ShotRect, shapes: [ShotShape], renderer: ShotRenderer) -> (image: CGImage, scale: CGFloat)? {
        let scale = scale(for: selection)
        guard let context = Self.bitmap(of: selection, scale: scale, draw: { context in
            context.interpolationQuality = .high
            self.draw(in: context)
            for shape in shapes { renderer.draw(shape, in: context) }
        }), let image = context.makeImage() else { return nil }
        return (image, scale)
    }
}

/// Draws annotations. The context's space is the overlay's shared one.
final class ShotRenderer {
    private let frame: ShotFrame
    private var blurCache: [ObjectIdentifier: (rect: ShotRect, image: CGImage)] = [:]

    init(frame: ShotFrame) {
        self.frame = frame
    }

    static func cgColor(_ rgb: UInt32, opacity: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: CGFloat(opacity))
    }

    static func textFont(size: Double) -> NSFont {
        NSFont.systemFont(ofSize: CGFloat(max(1, size)))
    }

    func draw(_ shape: ShotShape, in context: CGContext) {
        guard !shape.points.isEmpty else { return }
        let color = Self.cgColor(shape.color, opacity: shape.opacity)
        let a = CGPoint(x: shape.start.x, y: shape.start.y)
        let b = CGPoint(x: shape.end.x, y: shape.end.y)
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(CGFloat(shape.width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch shape.tool {
        case .pen, .marker:
            if shape.tool == .marker { context.setLineCap(.square) }
            if shape.points.count == 1 || shape.points.allSatisfy({ $0 == shape.start }) {
                let radius = CGFloat(shape.width) / 2
                context.fillEllipse(in: CGRect(x: a.x - radius, y: a.y - radius, width: radius * 2, height: radius * 2))
                return
            }
            context.beginPath()
            context.move(to: a)
            for point in shape.points.dropFirst() { context.addLine(to: CGPoint(x: point.x, y: point.y)) }
            context.strokePath()
        case .line:
            context.beginPath()
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()
        case .arrow:
            drawArrow(from: a, to: b, width: CGFloat(shape.width), in: context)
        case .rectangle:
            context.setLineJoin(.miter)
            context.stroke(cgRect(shape.bounds))
        case .circle:
            context.strokeEllipse(in: cgRect(shape.bounds))
        case .text:
            drawText(shape, at: a, in: context)
        case .blur:
            if let blur = blurred(shape) { ShotFrame.draw(blur.image, in: blur.rect, context: context) }
        case .none:
            break
        }
    }

    private func cgRect(_ rect: ShotRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private func drawArrow(from a: CGPoint, to b: CGPoint, width: CGFloat, in context: CGContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length >= 1 else { return }
        let vx = dx / length, vy = dy / length
        let head = max(10, width * 4)
        let base = CGPoint(x: b.x - vx * head, y: b.y - vy * head)
        let nx = -vy * head * 0.5, ny = vx * head * 0.5
        let shaft = min(head * 0.3, length / 2)
        context.beginPath()
        context.move(to: a)
        context.addLine(to: CGPoint(x: base.x + vx * shaft, y: base.y + vy * shaft))
        context.strokePath()
        context.beginPath()
        context.move(to: b)
        context.addLine(to: CGPoint(x: base.x + nx, y: base.y + ny))
        context.addLine(to: CGPoint(x: base.x - nx, y: base.y - ny))
        context.closePath()
        context.setLineWidth(1)
        context.drawPath(using: .fillStroke)
    }

    private func drawText(_ shape: ShotShape, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.textFont(size: shape.fontSize),
            .foregroundColor: NSColor(cgColor: Self.cgColor(shape.color)) ?? .red,
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (shape.text as NSString).draw(at: point, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The frame under a blur rectangle, pixelated. Kept until the rectangle changes.
    private func blurred(_ shape: ShotShape) -> (rect: ShotRect, image: CGImage)? {
        let rect = shape.bounds.intersection(frame.bounds)
        guard !rect.isEmpty else { return nil }
        let key = ObjectIdentifier(shape)
        if let cached = blurCache[key], cached.rect == rect { return cached }
        let scale = frame.scale(for: rect)
        guard let context = ShotFrame.bitmap(of: rect, scale: scale, draw: { frame.draw(in: $0) }),
              let data = context.data else { return nil }
        let width = context.width, height = context.height, stride = context.bytesPerRow
        let source = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                                 count: stride * height))
        let block = max(4, Int((shape.width * Double(scale) * 3).rounded()))
        let pixels = ShotImage.pixelate(source, stride: stride,
                                        region: ShotRect(x: 0, y: 0, width: width, height: height), block: block)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: ShotFrame.colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent)
        else { return nil }
        blurCache[key] = (rect, image)
        return (rect, image)
    }
}
