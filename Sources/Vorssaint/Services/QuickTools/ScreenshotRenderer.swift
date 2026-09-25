// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Draws annotations into a CGContext. The editor canvas and the exporter
/// share this code, so what is on screen is exactly what leaves the app.
/// All geometry is in image pixels with a top-left origin; `scale` is the
/// capture's pixels per point, keeping stroke weights and text sizes visually
/// constant across 1x and Retina captures.
enum ScreenshotRenderer {
    private static let blurContext = CIContext(options: [.cacheIntermediates: false])

    static func color(_ id: ScreenshotSupport.ColorID, alpha: CGFloat = 1) -> CGColor {
        let c = id.components
        return CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: alpha)
    }

    static func nsColor(_ id: ScreenshotSupport.ColorID) -> NSColor {
        let c = id.components
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    static func fontSize(for textSize: Int, scale: CGFloat) -> CGFloat {
        CGFloat(textSize) * scale
    }

    /// Measures a text annotation's box for hit-testing and the inline editor.
    static func textBounds(_ text: String,
                           at origin: CGPoint,
                           textSize: Int,
                           scale: CGFloat) -> CGRect {
        let font = NSFont.systemFont(ofSize: fontSize(for: textSize, scale: scale), weight: .semibold)
        let measured = (text.isEmpty ? " " : text).size(withAttributes: [.font: font])
        return CGRect(origin: origin,
                      size: CGSize(width: ceil(measured.width) + 4, height: ceil(measured.height)))
    }

    // MARK: - Annotation pass

    /// Draws every annotation over the base content. `pixelated` holds the
    /// redaction source for pixelate rectangles, one per blur level; text being edited inline is
    /// skipped so the live field is the only visible copy.
    static func drawAnnotations(_ annotations: [ScreenshotSupport.Annotation],
                                in context: CGContext,
                                pixelated: [Int: CGImage],
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
                drawLine(annotation, in: context, scale: scale,
                         shadowsEnabled: annotationShadowsEnabled)
            case .arrow:
                drawArrow(annotation, in: context, scale: scale,
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
                                 shadowsEnabled: Bool) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points[0]
        let end = annotation.points[1]
        let width = annotation.stroke.width * scale
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(color(annotation.color))
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawArrow(_ annotation: ScreenshotSupport.Annotation,
                                  in context: CGContext,
                                  scale: CGFloat,
                                  shadowsEnabled: Bool) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points[0]
        let end = annotation.points[1]
        let width = annotation.stroke.width * scale

        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(color(annotation.color))
        context.setFillColor(color(annotation.color))
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        if let outline = ScreenshotSupport.arrowStrokePath(from: start,
                                                           to: end,
                                                           strokeWidth: width,
                                                           style: annotation.arrowStyle,
                                                           seed: annotation.scribbleSeed) {
            // Shaft and head in one stroke: the shadow falls on the whole arrow
            // once, instead of the head shading the shaft where they meet.
            context.addPath(outline)
            context.strokePath()
        } else {
            context.addPath(ScreenshotSupport.arrowSilhouette(from: start,
                                                              to: end,
                                                              strokeWidth: width))
            context.fillPath()
        }
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
        let font = NSFont.systemFont(ofSize: fontSize(for: annotation.textSize, scale: scale),
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
                                     pixelated: [Int: CGImage],
                                     imageSize: CGSize) {
        guard let pixelated = pixelated[annotation.blurLevel] else { return }
        context.saveGState()
        context.clip(to: annotation.rect)
        // Expand the sampled mosaic with nearest-neighbor filtering under the
        // clip. Keeping it small avoids one capture-sized bitmap per blur level.
        // Flip locally because CGContext.draw expects an unflipped space.
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
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

    // MARK: - Watermark

    /// Draws the mark over the finished annotations, so a redaction or an
    /// arrow can never erase it, and inside the capture, so a backdrop's
    /// margin stays clean. The picture of an image mark is loaded by the
    /// editor; nil draws nothing, the way a vanished backdrop file does.
    static func drawWatermark(_ style: ScreenshotSupport.WatermarkStyle,
                              image: CGImage?,
                              in context: CGContext,
                              imageSize: CGSize,
                              scale: CGFloat,
                              shadowsEnabled: Bool,
                              cornerRadius: CGFloat = 0) {
        let style = style.sanitized()
        let contentSize: CGSize
        let draw: (CGRect) -> Void
        switch style.kind {
        case .none:
            return
        case .text:
            let font = NSFont.systemFont(
                ofSize: ScreenshotSupport.watermarkFontSize(for: imageSize,
                                                            factor: CGFloat(style.size)),
                weight: .semibold)
            let color = ScreenshotSupport.ColorID(rawValue: style.color) ?? .white
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: nsColor(color),
            ]
            let measured = style.text.size(withAttributes: attributes)
            contentSize = CGSize(width: ceil(measured.width), height: ceil(measured.height))
            draw = { rect in
                // NSAttributedString draws in an unflipped space; flip locally.
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                style.text.draw(at: rect.origin, withAttributes: attributes)
                NSGraphicsContext.current = previous
            }
        case .image:
            guard let image, image.width > 0, image.height > 0 else { return }
            let width = ScreenshotSupport.watermarkImageWidth(for: imageSize,
                                                              factor: CGFloat(style.size))
            contentSize = CGSize(width: width,
                                 height: width * CGFloat(image.height) / CGFloat(image.width))
            draw = { rect in
                // CGContext.draw expects an unflipped space; flip around the
                // mark's center, which is the origin by now.
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.draw(image, in: rect)
            }
        }
        guard let placement = ScreenshotSupport.watermarkPlacement(contentSize: contentSize,
                                                                   rotation: style.rotation,
                                                                   anchor: style.anchor,
                                                                   in: imageSize,
                                                                   cornerRadius: cornerRadius)
        else { return }

        context.saveGState()
        // One layer for the whole mark: its opacity and shadow then apply to
        // the composite rather than to every glyph on its own.
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setAlpha(CGFloat(style.opacity))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: placement.center.x, y: placement.center.y)
        // The context is flipped, where a positive angle turns clockwise.
        context.rotate(by: -CGFloat(style.rotation) * .pi / 180)
        context.scaleBy(x: placement.fit, y: placement.fit)
        draw(CGRect(x: -contentSize.width / 2, y: -contentSize.height / 2,
                    width: contentSize.width, height: contentSize.height))
        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: - Pixelation source

    /// A low-resolution mosaic with per-block color variation.
    static func pixelatedImage(from image: CGImage,
                               level: Int = ScreenshotSupport.BlurStrength.defaultLevel) -> CGImage? {
        let block = ScreenshotSupport.pixelBlockSize(
            for: CGSize(width: image.width, height: image.height), level: level)
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
        return small.makeImage()
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

    /// A finished picture together with the pixels per point it was rendered
    /// at, so every file and pasteboard item it becomes can say how big it is
    /// on screen: a Retina capture then opens at its own size in Preview,
    /// Quick Look and documents, the way a system screenshot does, instead of
    /// twice as large and softened by the upscale.
    struct Export {
        let image: CGImage
        let scale: CGFloat
    }

    /// Flattens the base image, annotations and watermark, rounds the card's
    /// corners, optionally composes the padded backdrop fill behind it,
    /// optionally downscaled to 1x.
    static func renderExport(baseImage: CGImage,
                             annotations: [ScreenshotSupport.Annotation],
                             pixelated: [Int: CGImage],
                             scale: CGFloat,
                             annotationShadowsEnabled: Bool,
                             watermark: ScreenshotSupport.WatermarkStyle,
                             watermarkImage: CGImage?,
                             style: ScreenshotSupport.BackdropStyle,
                             fill: BackdropFill,
                             downscaleTo1x: Bool) -> Export? {
        let imageSize = CGSize(width: baseImage.width, height: baseImage.height)
        let corner = ScreenshotSupport.cardCornerRadius(for: imageSize,
                                                        factor: style.cornerRadius)
        guard let flattened = renderFlattened(baseImage: baseImage,
                                              annotations: annotations,
                                              pixelated: pixelated,
                                              scale: scale,
                                              annotationShadowsEnabled: annotationShadowsEnabled,
                                              watermark: watermark,
                                              watermarkImage: watermarkImage,
                                              cornerRadius: corner)
        else { return nil }

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
                                                blurFactor: CGFloat(style.blur),
                                                scale: scale) {
            result = composed
        }
        if downscaleTo1x, scale > 1 {
            let target = ScreenshotSupport.downscaledSize(
                pixelSize: CGSize(width: result.width, height: result.height), scale: scale)
            if let smaller = resized(result, to: target) {
                return Export(image: smaller, scale: 1)
            }
        }
        return Export(image: result, scale: scale)
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
                                        pixelated: [Int: CGImage],
                                        scale: CGFloat,
                                        annotationShadowsEnabled: Bool,
                                        watermark: ScreenshotSupport.WatermarkStyle,
                                        watermarkImage: CGImage?,
                                        cornerRadius: CGFloat) -> CGImage? {
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
        drawWatermark(watermark,
                      image: watermarkImage,
                      in: context,
                      imageSize: CGSize(width: width, height: height),
                      scale: scale,
                      shadowsEnabled: annotationShadowsEnabled,
                      cornerRadius: cornerRadius)
        return context.makeImage()
    }

    private static func renderBackdrop(_ fill: BackdropFill,
                                       behind image: CGImage,
                                       imageSize: CGSize,
                                       paddingFactor: CGFloat,
                                       corner: CGFloat,
                                       blurFactor: CGFloat,
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
        if blurFactor > 0, let background = context.makeImage() {
            let blurred = blurredBackdrop(background, factor: blurFactor)
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(blurred, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let imageRect = CGRect(x: padding, y: padding,
                               width: imageSize.width, height: imageSize.height)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6 * scale),
                          blur: 22 * scale,
                          color: CGColor(gray: 0, alpha: 0.4))
        let path = CGPath(roundedRect: imageRect,
                          cornerWidth: corner, cornerHeight: corner, transform: nil)
        // Keep the shadow outside the card without painting an opaque plate
        // behind translucent captures.
        context.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        context.addPath(path)
        context.clip(using: .evenOdd)
        context.addPath(path)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()
        return context.makeImage()
    }

    /// Blurs a finished background plate while extending its edge pixels, so
    /// the effect never creates a transparent seam around the canvas.
    static func blurredBackdrop(_ image: CGImage, factor: CGFloat) -> CGImage {
        let radius = ScreenshotSupport.backdropBlurRadius(
            for: CGSize(width: image.width, height: image.height),
            factor: factor)
        guard radius > 0 else { return image }
        let input = CIImage(cgImage: image)
        let filtered = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return blurContext.createCGImage(filtered, from: input.extent) ?? image
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

    /// PNG carrying the picture's pixels per point as standard DPI, the same
    /// convention the system screenshot tool writes and the store reads back.
    static func pngData(from image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let properties = [
            kCGImagePropertyDPIWidth: Double(scale) * 72,
            kCGImagePropertyDPIHeight: Double(scale) * 72,
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// TIFF for the pasteboard with the same density as the PNG: the point
    /// size is what the TIFF stores as its resolution, so a paste lands at
    /// the capture's on-screen size.
    static func tiffData(from image: CGImage, scale: CGFloat) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = NSSize(width: CGFloat(image.width) / scale,
                             height: CGFloat(image.height) / scale)
        return bitmap.tiffRepresentation
    }
}
