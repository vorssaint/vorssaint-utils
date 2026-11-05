// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Rulers and guides. Like every mark, they draw in image pixels with a
/// top-left origin, and the canvas, the live measurement and the exporter
/// share this code.
extension ScreenshotRenderer {
    /// The ruler's own line is thinner than a shape's at the same setting:
    /// it marks a distance, and a heavy stroke would cover the edges it
    /// measures between.
    static func rulerLineWidth(_ stroke: ScreenshotSupport.StrokeID, scale: CGFloat) -> CGFloat {
        max(1, stroke.width / 2) * scale
    }

    /// A line with a short tick at each end and its length on a tag beside
    /// the middle. The tag moves to the other side when it would leave the
    /// capture, so a measurement along an edge still reads.
    static func drawRuler(_ annotation: ScreenshotSupport.Annotation,
                          in context: CGContext,
                          imageSize: CGSize,
                          scale: CGFloat,
                          shadowsEnabled: Bool) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points[0]
        let end = annotation.points[1]
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return }
        let normal = CGPoint(x: -(end.y - start.y) / length, y: (end.x - start.x) / length)
        let tick = 5 * scale
        let ink = color(annotation.color)

        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(ink)
        context.setLineWidth(rulerLineWidth(annotation.stroke, scale: scale))
        context.setLineCap(.butt)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        for point in [start, end] {
            context.move(to: CGPoint(x: point.x - normal.x * tick, y: point.y - normal.y * tick))
            context.addLine(to: CGPoint(x: point.x + normal.x * tick, y: point.y + normal.y * tick))
        }
        context.strokePath()
        context.restoreGState()

        // The text holds the unit; the length always follows the ends.
        let label = ScreenshotInspectionSupport.measureLabel(
            lengthPixels: length, scale: scale,
            unit: ScreenshotInspectionSupport.MeasureUnit.sanitized(annotation.text))
        drawMeasureTag(label, color: annotation.color,
                       middle: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                       normal: normal, imageSize: imageSize, scale: scale, in: context)
    }

    /// The tag that names a length, shared with the live measurement.
    static func drawMeasureTag(_ text: String,
                               color colorID: ScreenshotSupport.ColorID,
                               middle: CGPoint,
                               normal: CGPoint,
                               imageSize: CGSize,
                               scale: CGFloat,
                               in context: CGContext) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11 * scale, weight: .semibold)
        let light = colorID == .white || colorID == .yellow
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: light ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1) : NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let size = CGSize(width: ceil(textSize.width) + 10 * scale, height: ceil(textSize.height) + 4 * scale)
        let gap = 5 * scale
        // Above a flat line and to the right of an upright one, read the way
        // the editor's other labels sit.
        var direction = normal
        if direction.y > 0 || (abs(direction.y) < 0.001 && direction.x < 0) {
            direction = CGPoint(x: -direction.x, y: -direction.y)
        }
        func tagRect(_ direction: CGPoint) -> CGRect {
            let reach = abs(direction.x) * size.width / 2 + abs(direction.y) * size.height / 2 + gap
            let center = CGPoint(x: middle.x + direction.x * reach, y: middle.y + direction.y * reach)
            return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        }
        var rect = tagRect(direction)
        let bounds = CGRect(origin: .zero, size: imageSize)
        if !bounds.contains(rect) {
            let flipped = tagRect(CGPoint(x: -direction.x, y: -direction.y))
            if bounds.contains(flipped) { rect = flipped }
        }
        context.saveGState()
        context.setFillColor(color(colorID, alpha: 0.95))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: size.height / 2,
                               cornerHeight: size.height / 2, transform: nil))
        context.fillPath()
        context.restoreGState()
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                  withAttributes: attributes)
        NSGraphicsContext.current = previous
    }

    /// A thin dashed line across the capture, for checking that things line up.
    static func drawGuide(_ annotation: ScreenshotSupport.Annotation,
                          in context: CGContext,
                          scale: CGFloat) {
        guard annotation.points.count >= 2 else { return }
        context.saveGState()
        context.setStrokeColor(color(annotation.color))
        context.setLineWidth(max(1, scale))
        context.setLineDash(phase: 0, lengths: [6 * scale, 4 * scale])
        context.beginPath()
        context.move(to: annotation.points[0])
        context.addLine(to: annotation.points[1])
        context.strokePath()
        context.restoreGState()
    }
}
