// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

/// Draws annotations into a CGContext. The editor canvas and the exporter
/// share this code, so what is on screen is exactly what leaves the app.
/// All geometry is in image pixels with a top-left origin; `scale` is the
/// capture's pixels per point, keeping stroke weights and text sizes visually
/// constant across 1x and Retina captures.
enum ScreenshotRenderer {

    static func color(_ id: ScreenshotSupport.ColorID, alpha: CGFloat = 1) -> CGColor {
        let c = id.components
        return CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: alpha)
    }

    static func nsColor(_ id: ScreenshotSupport.ColorID) -> NSColor {
        let c = id.components
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    static func fontSize(for stroke: ScreenshotSupport.StrokeID, scale: CGFloat) -> CGFloat {
        switch stroke {
        case .small: return 13 * scale
        case .medium: return 19 * scale
        case .large: return 27 * scale
        }
    }

    /// Measures a text annotation's box for hit-testing and the inline editor.
    static func textBounds(_ text: String,
                           at origin: CGPoint,
                           stroke: ScreenshotSupport.StrokeID,
                           scale: CGFloat) -> CGRect {
        let font = NSFont.systemFont(ofSize: fontSize(for: stroke, scale: scale), weight: .semibold)
        let measured = (text.isEmpty ? " " : text).size(withAttributes: [.font: font])
        return CGRect(origin: origin,
                      size: CGSize(width: ceil(measured.width) + 4, height: ceil(measured.height)))
    }

    // MARK: - Annotation pass

    /// Draws every annotation over the base content. `pixelated` is the
    /// redaction source for pixelate rectangles; text being edited inline is
    /// skipped so the live field is the only visible copy.
    static func drawAnnotations(_ annotations: [ScreenshotSupport.Annotation],
                                in context: CGContext,
                                pixelated: CGImage?,
                                imageSize: CGSize,
                                scale: CGFloat,
                                annotationShadowsEnabled: Bool,
                                skippingText editingID: UUID? = nil) {
        for annotation in annotations {
            switch annotation.tool {
            case .pixelate:
                drawPixelate(annotation, in: context, pixelated: pixelated, imageSize: imageSize)
            case .redact:
                context.setFillColor(color(annotation.color))
                context.fill(annotation.rect)
            case .highlight:
                context.saveGState()
                context.setBlendMode(.multiply)
                context.setFillColor(color(annotation.color, alpha: 0.42))
                context.fill(annotation.rect)
                context.restoreGState()
            case .rect:
                strokeShape(in: context, annotation: annotation, scale: scale,
                            shadowsEnabled: annotationShadowsEnabled) {
                    context.stroke(annotation.rect)
                }
            case .ellipse:
                strokeShape(in: context, annotation: annotation, scale: scale,
                            shadowsEnabled: annotationShadowsEnabled) {
                    context.strokeEllipse(in: annotation.rect)
                }
            case .line:
                drawLine(annotation, in: context, scale: scale, arrow: false,
                         shadowsEnabled: annotationShadowsEnabled)
            case .arrow:
                drawLine(annotation, in: context, scale: scale, arrow: true,
                         shadowsEnabled: annotationShadowsEnabled)
            case .freehand:
                drawFreehand(annotation, in: context, scale: scale,
                             shadowsEnabled: annotationShadowsEnabled)
            case .text:
                if annotation.id != editingID {
                    drawText(annotation, in: context, scale: scale,
                             shadowsEnabled: annotationShadowsEnabled)
                }
            case .sticker:
                drawSticker(annotation, in: context, scale: scale,
                            shadowsEnabled: annotationShadowsEnabled)
            case .counter:
                drawCounter(annotation, in: context, imageSize: imageSize, scale: scale,
                            shadowsEnabled: annotationShadowsEnabled)
            case .select, .crop:
                break
            }
        }
    }

    private static func strokeShape(in context: CGContext,
                                    annotation: ScreenshotSupport.Annotation,
                                    scale: CGFloat,
                                    shadowsEnabled: Bool,
                                    stroke: () -> Void) {
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(color(annotation.color))
        context.setLineWidth(annotation.stroke.width * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        stroke()
        context.restoreGState()
    }

    private static func drawLine(_ annotation: ScreenshotSupport.Annotation,
                                 in context: CGContext,
                                 scale: CGFloat,
                                 arrow: Bool,
                                 shadowsEnabled: Bool) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points[0]
        let end = annotation.points[1]
        let width = annotation.stroke.width * scale
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)

        guard arrow else {
            context.setStrokeColor(color(annotation.color))
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            context.restoreGState()
            return
        }

        context.setFillColor(color(annotation.color))
        context.addPath(ScreenshotSupport.arrowSilhouette(from: start,
                                                          to: end,
                                                          strokeWidth: width))
        context.fillPath()
        context.restoreGState()
    }

    private static func drawFreehand(_ annotation: ScreenshotSupport.Annotation,
                                     in context: CGContext,
                                     scale: CGFloat,
                                     shadowsEnabled: Bool) {
        guard annotation.points.count > 1 else { return }
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(color(annotation.color))
        context.setLineWidth(annotation.stroke.width * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: annotation.points[0])
        // Quadratic curves through midpoints smooth hand jitter without
        // drifting from the stroke.
        for index in 1..<annotation.points.count {
            let current = annotation.points[index]
            let previous = annotation.points[index - 1]
            let mid = CGPoint(x: (current.x + previous.x) / 2, y: (current.y + previous.y) / 2)
            context.addQuadCurve(to: mid, control: previous)
        }
        if let last = annotation.points.last {
            context.addLine(to: last)
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawText(_ annotation: ScreenshotSupport.Annotation,
                                 in context: CGContext,
                                 scale: CGFloat,
                                 shadowsEnabled: Bool) {
        guard !annotation.text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: fontSize(for: annotation.stroke, scale: scale),
                                     weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor(annotation.color),
        ]
        if shadowsEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 2.5 * scale
            shadow.shadowOffset = NSSize(width: 0, height: -1 * scale)
            attributes[.shadow] = shadow
        }
        context.saveGState()
        // NSAttributedString draws in an unflipped space; flip locally.
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        annotation.text.draw(at: CGPoint(x: annotation.rect.minX + 2, y: annotation.rect.minY),
                             withAttributes: attributes)
        NSGraphicsContext.current = previous
        context.restoreGState()
    }

    private static func drawCounter(_ annotation: ScreenshotSupport.Annotation,
                                    in context: CGContext,
                                    imageSize: CGSize,
                                    scale: CGFloat,
                                    shadowsEnabled: Bool) {
        let diameter = ScreenshotSupport.counterDiameter(for: imageSize, scale: 1)
        let rect = CGRect(x: annotation.rect.midX - diameter / 2,
                          y: annotation.rect.midY - diameter / 2,
                          width: diameter,
                          height: diameter)
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setFillColor(color(annotation.color))
        context.fillEllipse(in: rect)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(max(1.5, diameter * 0.05))
        context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
        context.restoreGState()

        let label = "\(annotation.number)"
        let font = NSFont.systemFont(ofSize: diameter * 0.52, weight: .bold)
        let textColor: NSColor = annotation.color == .white
            ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1) : .white
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = label.size(withAttributes: attributes)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                   withAttributes: attributes)
        NSGraphicsContext.current = previous
    }

    private static func drawSticker(_ annotation: ScreenshotSupport.Annotation,
                                    in context: CGContext,
                                    scale: CGFloat,
                                    shadowsEnabled: Bool) {
        let sticker = ScreenshotSupport.StickerID.sanitized(annotation.text)
        let fontSize = max(10 * scale, min(annotation.rect.width, annotation.rect.height) * 0.82)
        let font = NSFont(name: "Apple Color Emoji", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if shadowsEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 3 * scale
            shadow.shadowOffset = NSSize(width: 0, height: -1 * scale)
            attributes[.shadow] = shadow
        }
        let glyph = sticker.glyph
        let size = glyph.size(withAttributes: attributes)
        let origin = CGPoint(x: annotation.rect.midX - size.width / 2,
                             y: annotation.rect.midY - size.height / 2)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        glyph.draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.current = previous
    }

    private static func drawPixelate(_ annotation: ScreenshotSupport.Annotation,
                                     in context: CGContext,
                                     pixelated: CGImage?,
                                     imageSize: CGSize) {
        guard let pixelated else { return }
        context.saveGState()
        context.clip(to: annotation.rect)
        // The pixelated twin is drawn full-size under the clip; flip locally
        // because CGContext.draw expects an unflipped space.
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(pixelated, in: CGRect(origin: .zero, size: imageSize))
        context.restoreGState()
    }

    private static func applyShadow(_ context: CGContext,
                                    scale: CGFloat,
                                    enabled: Bool) {
        guard enabled else { return }
        context.setShadow(offset: CGSize(width: 0, height: -1 * scale),
                          blur: 3 * scale,
                          color: CGColor(gray: 0, alpha: 0.38))
    }

    // MARK: - Pixelation source

    /// A low-resolution mosaic with per-block color variation.
    static func pixelatedImage(from image: CGImage) -> CGImage? {
        let block = ScreenshotSupport.pixelBlockSize(
            for: CGSize(width: image.width, height: image.height))
        let smallWidth = max(1, image.width / block)
        let smallHeight = max(1, image.height / block)
        guard let small = CGContext(data: nil,
                                    width: smallWidth,
                                    height: smallHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))

        if let data = small.data {
            var generator = SystemRandomNumberGenerator()
            let bytes = data.bindMemory(to: UInt8.self,
                                        capacity: small.bytesPerRow * smallHeight)
            for row in 0..<smallHeight {
                for column in 0..<smallWidth {
                    let offset = row * small.bytesPerRow + column * 4
                    let noise = Int.random(in: -9...9, using: &generator)
                    for channel in 0..<3 {
                        let value = Int(bytes[offset + channel]) + noise
                        bytes[offset + channel] = UInt8(max(0, min(255, value)))
                    }
                }
            }
        }
        guard let mosaic = small.makeImage() else { return nil }

        guard let full = CGContext(data: nil,
                                   width: image.width,
                                   height: image.height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        full.interpolationQuality = .none
        full.draw(mosaic, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return full.makeImage()
    }

    // MARK: - Export

    /// What actually paints behind the capture, resolved by the editor from
    /// the persisted style (image files loaded and cached there).
    enum BackdropFill {
        case none
        /// 1 color = solid, 2 colors = gradient.
        case colors([(red: Double, green: Double, blue: Double)])
        case image(CGImage)
    }

    /// Flattens the base image and annotations, rounds the card's corners,
    /// optionally composes the padded backdrop fill behind it, optionally
    /// downscaled to 1x.
    static func renderExport(baseImage: CGImage,
                             annotations: [ScreenshotSupport.Annotation],
                             pixelated: CGImage?,
                             scale: CGFloat,
                             annotationShadowsEnabled: Bool,
                             style: ScreenshotSupport.BackdropStyle,
                             fill: BackdropFill,
                             downscaleTo1x: Bool) -> CGImage? {
        let imageSize = CGSize(width: baseImage.width, height: baseImage.height)
        guard let flattened = renderFlattened(baseImage: baseImage,
                                              annotations: annotations,
                                              pixelated: pixelated,
                                              scale: scale,
                                              annotationShadowsEnabled: annotationShadowsEnabled)
        else { return nil }
        let corner = ScreenshotSupport.cardCornerRadius(for: imageSize,
                                                        factor: style.cornerRadius)

        var result = flattened
        if case .none = fill {
            // Rounded corners without a backdrop become transparency.
            if corner > 0, let rounded = roundedAlpha(flattened, corner: corner) {
                result = rounded
            }
        } else if let composed = renderBackdrop(fill,
                                                behind: flattened,
                                                imageSize: imageSize,
                                                paddingFactor: CGFloat(style.padding),
                                                corner: corner,
                                                scale: scale) {
            result = composed
        }
        if downscaleTo1x, scale > 1 {
            let target = ScreenshotSupport.downscaledSize(
                pixelSize: CGSize(width: result.width, height: result.height), scale: scale)
            if let smaller = resized(result, to: target) {
                result = smaller
            }
        }
        return result
    }

    private static func roundedAlpha(_ image: CGImage, corner: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil,
                                      width: image.width,
                                      height: image.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.addPath(CGPath(roundedRect: rect,
                               cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.clip()
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private static func renderFlattened(baseImage: CGImage,
                                        annotations: [ScreenshotSupport.Annotation],
                                        pixelated: CGImage?,
                                        scale: CGFloat,
                                        annotationShadowsEnabled: Bool) -> CGImage? {
        let width = baseImage.width
        let height = baseImage.height
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Flip to the annotations' top-left space.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        drawAnnotations(annotations,
                        in: context,
                        pixelated: pixelated,
                        imageSize: CGSize(width: width, height: height),
                        scale: scale,
                        annotationShadowsEnabled: annotationShadowsEnabled)
        return context.makeImage()
    }

    private static func renderBackdrop(_ fill: BackdropFill,
                                       behind image: CGImage,
                                       imageSize: CGSize,
                                       paddingFactor: CGFloat,
                                       corner: CGFloat,
                                       scale: CGFloat) -> CGImage? {
        let padding = ScreenshotSupport.backdropPadding(for: imageSize, factor: paddingFactor)
        let width = Int(imageSize.width + padding * 2)
        let height = Int(imageSize.height + padding * 2)
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        drawFill(fill, in: context, size: CGSize(width: width, height: height))

        let imageRect = CGRect(x: padding, y: padding,
                               width: imageSize.width, height: imageSize.height)
        context.setShadow(offset: CGSize(width: 0, height: -6 * scale),
                          blur: 22 * scale,
                          color: CGColor(gray: 0, alpha: 0.4))
        let path = CGPath(roundedRect: imageRect,
                          cornerWidth: corner, cornerHeight: corner, transform: nil)
        // Fill under the shadow, then clip the image to the same rounding.
        context.addPath(path)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()
        return context.makeImage()
    }

    private static func drawFill(_ fill: BackdropFill, in context: CGContext, size: CGSize) {
        switch fill {
        case .none:
            break
        case .colors(let components):
            if components.count == 1, let single = components.first {
                context.setFillColor(CGColor(srgbRed: single.red, green: single.green,
                                             blue: single.blue, alpha: 1))
                context.fill(CGRect(origin: .zero, size: size))
            } else if components.count >= 2 {
                let colors = components.map {
                    CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
                } as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: colors,
                                             locations: [0, 1]) {
                    context.drawLinearGradient(gradient,
                                               start: CGPoint(x: 0, y: size.height),
                                               end: CGPoint(x: size.width, y: 0),
                                               options: [])
                }
            }
        case .image(let backdropImage):
            // Aspect fill, centered, like a wallpaper on a desktop.
            let imageWidth = CGFloat(backdropImage.width)
            let imageHeight = CGFloat(backdropImage.height)
            guard imageWidth > 0, imageHeight > 0 else { break }
            let scale = max(size.width / imageWidth, size.height / imageHeight)
            let drawSize = CGSize(width: imageWidth * scale, height: imageHeight * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2,
                                 y: (size.height - drawSize.height) / 2)
            context.saveGState()
            context.clip(to: CGRect(origin: .zero, size: size))
            context.interpolationQuality = .high
            context.draw(backdropImage, in: CGRect(origin: origin, size: drawSize))
            context.restoreGState()
        }
    }

    private static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    // MARK: - Encoding

    static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
