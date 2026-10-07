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

    /// Draws every annotation over the base content. `blurSources` holds what
    /// blur areas paint from. Text being edited inline is skipped so the live
    /// field is the only visible copy.
    static func drawAnnotations(_ annotations: [ScreenshotSupport.Annotation],
                                in context: CGContext,
                                blurSources: BlurSources,
                                imageSize: CGSize,
                                scale: CGFloat,
                                annotationShadowsEnabled: Bool,
                                skippingText editingID: UUID? = nil) {
        blurSources.eraseCache?.beginPass(image: blurSources.image, textRuns: blurSources.textRuns)
        for annotation in annotations {
            switch annotation.tool {
            case .pixelate:
                drawBlurArea(annotation, in: context, sources: blurSources, imageSize: imageSize)
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

    // MARK: - Blur areas

    /// What blur areas paint from. The editor keeps one sampled mosaic or soft
    /// blur per level in use, the capture and its finished fills for erasing,
    /// and the text runs recognition found. `textRuns` stays nil until
    /// recognition has read the capture, and text only areas cover all of
    /// themselves until then.
    struct BlurSources {
        var mosaics: [Int: CGImage] = [:]
        var softBlurs: [Int: CGImage] = [:]
        var image: CGImage?
        var eraseCache: EraseCache?
        var textRuns: [CGRect]?

        static let none = BlurSources()
    }

    private static func drawBlurArea(_ annotation: ScreenshotSupport.Annotation,
                                     in context: CGContext,
                                     sources: BlurSources,
                                     imageSize: CGSize) {
        let rect = annotation.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        // A whole area is a single run. A text only area covers each run of
        // recognized text inside it.
        let runs = annotation.blurTextOnly
            ? ScreenshotSupport.blurTextRuns(in: rect, from: sources.textRuns)
            : [rect]
        guard !runs.isEmpty else { return }
        switch annotation.blurStyle {
        case .pixelate:
            // Nearest-neighbor keeps the mosaic's blocks sharp.
            guard let mosaic = sources.mosaics[annotation.blurLevel] else { return }
            drawSample(mosaic, in: context, imageSize: imageSize,
                       clippedTo: runs.map { $0.intersection(rect) }, interpolation: .none)
        case .blur:
            guard let blurred = sources.softBlurs[annotation.blurLevel] else { return }
            drawSample(blurred, in: context, imageSize: imageSize,
                       clippedTo: runs.map { $0.intersection(rect) }, interpolation: .high)
        case .erase:
            guard let image = sources.image else { return }
            // The fill is read around the whole run, so an area that cuts
            // through a word never samples the word itself. Text runs are
            // skipped while reading, and a run's own never lies in what is
            // read around it, so one list serves every run.
            let text = annotation.blurTextOnly ? (sources.textRuns ?? []) : []
            let bounds = CGRect(origin: .zero, size: imageSize)
            for run in runs {
                guard let patch = sources.eraseCache?.patch(for: run, in: image, skipping: text)
                        ?? erasePatch(for: run, in: image, skipping: text) else { continue }
                context.saveGState()
                context.clip(to: run.intersection(rect).intersection(bounds))
                // Replace what is under the run. Blending would let text in a
                // translucent capture show through a fill with alpha.
                context.setBlendMode(.copy)
                // CGContext.draw expects an unflipped space, so flip around the patch.
                context.translateBy(x: 0, y: patch.rect.minY + patch.rect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.draw(patch.image, in: patch.rect)
                context.restoreGState()
            }
        }
    }

    /// Expands a capture-wide sample under the clip. Keeping samples small
    /// avoids one capture-sized bitmap per blur level.
    private static func drawSample(_ sample: CGImage,
                                   in context: CGContext,
                                   imageSize: CGSize,
                                   clippedTo regions: [CGRect],
                                   interpolation: CGInterpolationQuality) {
        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: imageSize))
        context.clip(to: regions)
        // Replace what is under the regions. Blending would let text in a
        // translucent capture show through a sample with alpha.
        context.setBlendMode(.copy)
        // Flip locally because CGContext.draw expects an unflipped space.
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = interpolation
        context.draw(sample, in: CGRect(origin: .zero, size: imageSize))
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

    // MARK: - Blur samples

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
        scrambleSamples(in: small)
        return small.makeImage()
    }

    /// A soft blur kept small: the capture is averaged into four samples per
    /// mosaic block, shaken by the same noise and blurred across about a
    /// block. That wipes out everything finer than the mosaic of the same
    /// level keeps, and neighboring samples end up close enough that the
    /// stretch back to full size stays smooth.
    static func softBlurredImage(from image: CGImage,
                                 level: Int = ScreenshotSupport.BlurStrength.defaultLevel) -> CGImage? {
        let block = ScreenshotSupport.pixelBlockSize(
            for: CGSize(width: image.width, height: image.height), level: level)
        let step = max(1, block / 4)
        let smallWidth = max(1, image.width / step)
        let smallHeight = max(1, image.height / step)
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
        scrambleSamples(in: small)
        guard let sampled = small.makeImage() else { return nil }
        let input = CIImage(cgImage: sampled)
        let radius = 0.8 * Double(block) / Double(step)
        let blurred = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return blurContext.createCGImage(blurred, from: input.extent)
    }

    /// Shifts every sampled pixel by a small random amount, so the same text
    /// never samples to the same values twice.
    private static func scrambleSamples(in context: CGContext) {
        guard let data = context.data else { return }
        let bytes = data.bindMemory(to: UInt8.self,
                                    capacity: context.bytesPerRow * context.height)
        // Random bytes come a row at a time. Asking a generator for every
        // sample is slow in unoptimized builds, and a soft blur sample can
        // hold over a million of them.
        var randomRow = [UInt8](repeating: 0, count: context.width)
        for row in 0..<context.height {
            arc4random_buf(&randomRow, randomRow.count)
            for column in 0..<context.width {
                let offset = row * context.bytesPerRow + column * 4
                let noise = Int(randomRow[column] % 19) - 9
                for channel in 0..<3 {
                    let value = Int(bytes[offset + channel]) + noise
                    bytes[offset + channel] = UInt8(max(0, min(255, value)))
                }
            }
        }
    }

    // MARK: - Erasing

    /// Erase fills already made, so a redraw does not read the pixels around
    /// every erased area again. Fills belong to one capture and its text
    /// runs, and are dropped when either changes.
    final class EraseCache {
        private struct Key: Hashable {
            let x, y, width, height: Int
            let skipsText: Bool
        }

        private struct Entry {
            let image: CGImage
            let rect: CGRect
            var pass: Int
        }

        private var image: CGImage?
        private var textRuns: [CGRect]?
        private var patches: [Key: Entry] = [:]
        private var pass = 0

        /// Starts a redraw. Dragging an area makes a new fill on every move,
        /// so once there are many, the fills the last redraw did not use are
        /// dropped. That happens only here, so a redraw with many erased runs
        /// keeps every fill it needs for the next one.
        func beginPass(image: CGImage?, textRuns: [CGRect]?) {
            if self.image !== image || self.textRuns != textRuns {
                // A fill skipped the text runs of its time, and new runs
                // can change what it should have read.
                self.image = image
                self.textRuns = textRuns
                patches.removeAll()
            } else if patches.count > 256 {
                patches = patches.filter { $0.value.pass == pass }
            }
            pass += 1
        }

        /// The runs skipped while reading are the ones `beginPass` was given,
        /// so whether any were skipped is all the key needs to know about them.
        func patch(for region: CGRect, in image: CGImage,
                   skipping text: [CGRect] = []) -> (image: CGImage, rect: CGRect)? {
            if self.image !== image {
                self.image = image
                patches.removeAll()
            }
            let area = region.integral
            let key = Key(x: Int(area.minX), y: Int(area.minY),
                          width: Int(area.width), height: Int(area.height),
                          skipsText: !text.isEmpty)
            if let entry = patches[key] {
                patches[key]?.pass = pass
                return (entry.image, entry.rect)
            }
            guard let patch = erasePatch(for: region, in: image, skipping: text) else { return nil }
            patches[key] = Entry(image: patch.image, rect: patch.rect, pass: pass)
            return patch
        }
    }

    /// A smooth fill for `region` made of the pixels just around it, with the
    /// rect to draw it in. Each side is read as medians along a thin strip
    /// past that edge, which ignores the odd glyph touching it, and every
    /// point blends the sides by how close it is to each. A flat background
    /// comes back exactly, and so does a straight gradient. Sides past the
    /// edge of the capture are left out, and an area as large as the capture
    /// reads its own border instead. Pixels inside `text`, the other runs of
    /// recognized text, are not background and are skipped while anything
    /// else is left to read.
    static func erasePatch(for region: CGRect, in image: CGImage,
                           skipping text: [CGRect] = []) -> (image: CGImage, rect: CGRect)? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = region.integral.intersection(bounds)
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
        let band = CGFloat(max(2, min(8, Int((min(area.width, area.height) * 0.12).rounded()))))
        let space = eraseColorSpace(for: image)

        var sides: [EraseSide.Edge: EraseSide] = [:]
        for (outside, skipped) in [(true, text), (true, []), (false, [])] where sides.isEmpty {
            for edge in EraseSide.Edge.allCases {
                sides[edge] = EraseSide(edge: edge, area: area, band: band, outside: outside,
                                        skipping: skipped, image: image, space: space)
            }
        }
        guard !sides.isEmpty else { return nil }

        // A node on each edge and every few pixels between: the fill then
        // meets its surroundings right at its border, and neighboring nodes
        // differ too little for the stretch to full size to show.
        let cell = max(4, max(area.width, area.height) / 128)
        let columns = Int((area.width / cell).rounded(.up)) + 1
        let rows = Int((area.height / cell).rounded(.up)) + 1
        let width = Float(area.width)
        let height = Float(area.height)
        let xs = (0..<columns).map { Float($0) / Float(columns - 1) * width }
        let ys = (0..<rows).map { Float($0) / Float(rows - 1) * height }
        // 1 / distance blends each pair of opposite sides linearly. A missing
        // side weighs nothing.
        func weights(_ edge: EraseSide.Edge, _ distances: [Float]) -> [Float] {
            guard let side = sides[edge] else { return [Float](repeating: 0, count: distances.count) }
            return distances.map { 1 / max(0.5, $0 + side.offset) }
        }
        func colors(_ edge: EraseSide.Edge, _ positions: [Float], _ length: Float) -> [Float] {
            sides[edge]?.colors(at: positions, along: length)
                ?? [Float](repeating: 0, count: positions.count * 4)
        }
        let top = colors(.top, xs, width)
        let bottom = colors(.bottom, xs, width)
        let left = colors(.left, ys, height)
        let right = colors(.right, ys, height)
        let topWeights = weights(.top, ys)
        let bottomWeights = weights(.bottom, ys.map { height - $0 })
        let leftWeights = weights(.left, xs)
        let rightWeights = weights(.right, xs.map { width - $0 })

        var bytes = [UInt8](repeating: 0, count: columns * rows * 4)
        for row in 0..<rows {
            for column in 0..<columns {
                let sum = topWeights[row] + bottomWeights[row] + leftWeights[column] + rightWeights[column]
                var color: [Float] = [0, 0, 0, 0]
                for channel in 0..<4 {
                    color[channel] = (topWeights[row] * top[column * 4 + channel]
                        + bottomWeights[row] * bottom[column * 4 + channel]
                        + leftWeights[column] * left[row * 4 + channel]
                        + rightWeights[column] * right[row * 4 + channel]) / sum
                }
                let offset = (row * columns + column) * 4
                let alpha = min(255, max(0, color[3].rounded()))
                bytes[offset + 3] = UInt8(alpha)
                for channel in 0..<3 {
                    bytes[offset + channel] = UInt8(min(alpha, max(0, color[channel].rounded())))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let patch = CGImage(width: columns, height: rows,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
                                  space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        // Each pixel of the patch is centered on its node, so it is drawn half
        // a cell past the area on every side and clipped back.
        let cellWidth = area.width / CGFloat(columns - 1)
        let cellHeight = area.height / CGFloat(rows - 1)
        return (patch, area.insetBy(dx: -cellWidth / 2, dy: -cellHeight / 2))
    }

    /// The capture's own color space when bitmaps can be drawn in it, so the
    /// fill matches the pixels it sits beside, and sRGB otherwise.
    private static func eraseColorSpace(for image: CGImage) -> CGColorSpace {
        if let own = image.colorSpace, own.model == .rgb, own.supportsOutput,
           CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                     space: own, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) != nil {
            return own
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// One side of an area being erased: the medians of a thin strip of pixels
    /// along that edge, RGBA in order, and how far the strip's middle sits
    /// from the edge.
    private struct EraseSide {
        enum Edge: CaseIterable {
            case top, bottom, left, right
        }

        let medians: [Float]
        let count: Int
        let offset: Float

        /// The strip's color across from each position, between the two
        /// nearest medians, RGBA in order.
        func colors(at positions: [Float], along length: Float) -> [Float] {
            var colors = [Float](repeating: 0, count: positions.count * 4)
            for (index, position) in positions.enumerated() {
                let place = min(max(position / length * Float(count) - 0.5, 0), Float(count - 1))
                let lower = Int(place)
                let fraction = place - Float(lower)
                let first = lower * 4
                let second = min(lower + 1, count - 1) * 4
                for channel in 0..<4 {
                    colors[index * 4 + channel] = medians[first + channel]
                        + (medians[second + channel] - medians[first + channel]) * fraction
                }
            }
            return colors
        }

        /// About one median per few strip widths: enough to follow a gradient,
        /// long enough for a stray glyph to stay a minority.
        static func segmentCount(along length: CGFloat, band: CGFloat) -> Int {
            max(1, min(48, Int(length / max(12, band * 4))))
        }

        init?(edge: Edge, area: CGRect, band: CGFloat, outside: Bool, skipping text: [CGRect],
              image: CGImage, space: CGColorSpace) {
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let thickness = outside ? band : min(band, area.width, area.height)
            let strip: CGRect
            switch (edge, outside) {
            case (.top, true): strip = CGRect(x: area.minX, y: area.minY - thickness,
                                              width: area.width, height: thickness)
            case (.bottom, true): strip = CGRect(x: area.minX, y: area.maxY,
                                                 width: area.width, height: thickness)
            case (.left, true): strip = CGRect(x: area.minX - thickness, y: area.minY,
                                               width: thickness, height: area.height)
            case (.right, true): strip = CGRect(x: area.maxX, y: area.minY,
                                                width: thickness, height: area.height)
            case (.top, false): strip = CGRect(x: area.minX, y: area.minY,
                                               width: area.width, height: thickness)
            case (.bottom, false): strip = CGRect(x: area.minX, y: area.maxY - thickness,
                                                  width: area.width, height: thickness)
            case (.left, false): strip = CGRect(x: area.minX, y: area.minY,
                                                width: thickness, height: area.height)
            case (.right, false): strip = CGRect(x: area.maxX - thickness, y: area.minY,
                                                 width: thickness, height: area.height)
            }
            let visible = strip.intersection(bounds)
            guard !visible.isNull, visible.width >= 1, visible.height >= 1,
                  let pixels = Self.pixels(of: visible, in: image, space: space)
            else { return nil }
            let alongX = edge == .top || edge == .bottom
            let width = Int(visible.width)
            let length = alongX ? width : Int(visible.height)
            let depth = alongX ? Int(visible.height) : width
            let count = Self.segmentCount(along: CGFloat(length), band: band)
            let skipped = text.filter { $0.intersects(visible) }
            // Up to 32 pixels per segment, spread along it and across the
            // strip, are plenty for a median.
            let limit = 32
            var medians = [Float](repeating: 0, count: count * 4)
            var found = [Bool](repeating: false, count: count)
            var samples = [UInt8](repeating: 0, count: 4 * limit)
            for segment in 0..<count {
                let start = segment * length / count
                let span = max(1, (segment + 1) * length / count - start)
                let attempts = min(limit, span * depth)
                var taken = 0
                var flat = true
                for attempt in 0..<attempts {
                    let along = start + attempt * span / attempts
                    let across = attempt % depth
                    let column = alongX ? along : across
                    let row = alongX ? across : along
                    if !skipped.isEmpty {
                        let point = CGPoint(x: visible.minX + CGFloat(column) + 0.5,
                                            y: visible.minY + CGFloat(row) + 0.5)
                        if skipped.contains(where: { $0.contains(point) }) { continue }
                    }
                    let pixel = (row * width + column) * 4
                    for channel in 0..<4 {
                        let value = pixels[pixel + channel]
                        samples[channel * limit + taken] = value
                        if value != samples[channel * limit] { flat = false }
                    }
                    taken += 1
                }
                guard taken > 0 else { continue }
                found[segment] = true
                for channel in 0..<4 {
                    let first = channel * limit
                    if flat {
                        medians[segment * 4 + channel] = Float(samples[first])
                    } else {
                        let sorted = samples[first..<(first + taken)].sorted()
                        medians[segment * 4 + channel] = Float(sorted[taken / 2])
                    }
                }
            }
            guard found.contains(true) else { return nil }
            // A segment covered by text takes the median of the nearest one
            // that was read.
            for segment in 0..<count where !found[segment] {
                let nearest = (0..<count).filter { found[$0] }
                    .min { abs($0 - segment) < abs($1 - segment) } ?? segment
                for channel in 0..<4 {
                    medians[segment * 4 + channel] = medians[nearest * 4 + channel]
                }
            }
            self.medians = medians
            self.count = count
            // Inside strips stand on the edge itself, outside ones half their
            // thickness past it.
            offset = outside ? Float(depth) / 2 : 0
        }

        /// RGBA bytes of `rect`, top row first, in the capture's color space so
        /// the fill matches the pixels it sits beside.
        private static func pixels(of rect: CGRect, in image: CGImage, space: CGColorSpace) -> [UInt8]? {
            guard let cropped = image.cropping(to: rect) else { return nil }
            let width = Int(rect.width)
            let height = Int(rect.height)
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            return drawn ? bytes : nil
        }
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
                             blurSources: BlurSources,
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
                                              blurSources: blurSources,
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
                                        blurSources: BlurSources,
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
                        blurSources: blurSources,
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
