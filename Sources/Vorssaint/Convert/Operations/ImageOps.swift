// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

struct PhotoAdjustments: Equatable {
    var exposure: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var highlights: Double = 1
    var shadows: Double = 0
    var saturation: Double = 1
    var vibrance: Double = 0
    var temperature: Double = 6500
    var tint: Double = 0
    var sharpness: Double = 0
    var clarity: Double = 0
    var dehaze: Double = 0
    var noiseReduction: Double = 0
    var grain: Double = 0
    var vignette: Double = 0
    var sepia: Double = 0
    var monochrome: Bool = false

    static let neutral = PhotoAdjustments()
}

enum RedactionStyle: String, CaseIterable, Identifiable {
    case solid
    case blur
    case pixelate

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Redaction: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect
    var style: RedactionStyle = .solid
    var color: CGColor = CGColor(gray: 0, alpha: 1)
    var start: Double = 0
    var end: Double = .infinity

    static func == (lhs: Redaction, rhs: Redaction) -> Bool {
        lhs.id == rhs.id && lhs.rect == rhs.rect && lhs.style == rhs.style && lhs.start == rhs.start && lhs.end == rhs.end
    }
}

enum ImageOps {
    static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    private static let softwareContext = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

    static func ciImage(_ image: CGImage) -> CIImage { CIImage(cgImage: image) }

    static func render(_ image: CIImage, extent: CGRect? = nil) -> CGImage? {
        let rect = extent ?? image.extent
        guard !rect.isInfinite, !rect.isEmpty else { return nil }
        return context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            ?? softwareContext.createCGImage(image, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    static func adjusted(_ input: CIImage, _ a: PhotoAdjustments) -> CIImage {
        var image = input
        if a.exposure != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = image; f.ev = Float(a.exposure); image = f.outputImage ?? image
        }
        if a.brightness != 0 || a.contrast != 1 || a.saturation != 1 {
            let f = CIFilter.colorControls(); f.inputImage = image
            f.brightness = Float(a.brightness); f.contrast = Float(a.contrast); f.saturation = Float(a.saturation)
            image = f.outputImage ?? image
        }
        if a.highlights != 1 || a.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = image
            f.highlightAmount = Float(a.highlights); f.shadowAmount = Float(a.shadows); f.radius = 8
            image = f.outputImage ?? image
        }
        if a.vibrance != 0 {
            let f = CIFilter.vibrance(); f.inputImage = image; f.amount = Float(a.vibrance); image = f.outputImage ?? image
        }
        if a.temperature != 6500 || a.tint != 0 {
            let f = CIFilter.temperatureAndTint(); f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: CGFloat(a.temperature), y: CGFloat(a.tint))
            image = f.outputImage ?? image
        }
        if a.dehaze != 0 {
            let contrast = CIFilter.colorControls(); contrast.inputImage = image
            contrast.contrast = Float(1 + a.dehaze * 0.35); contrast.saturation = Float(1 + a.dehaze * 0.2); contrast.brightness = Float(-a.dehaze * 0.05)
            let boosted = contrast.outputImage ?? image
            let curve = CIFilter.toneCurve(); curve.inputImage = boosted
            let k = CGFloat(a.dehaze) * 0.12
            curve.point0 = CGPoint(x: 0, y: 0); curve.point1 = CGPoint(x: 0.25, y: max(0, 0.25 - k)); curve.point2 = CGPoint(x: 0.5, y: 0.5)
            curve.point3 = CGPoint(x: 0.75, y: min(1, 0.75 + k * 0.5)); curve.point4 = CGPoint(x: 1, y: 1)
            image = curve.outputImage ?? boosted
        }
        if a.noiseReduction != 0 {
            let f = CIFilter.noiseReduction(); f.inputImage = image
            f.noiseLevel = Float(a.noiseReduction * 0.1); f.sharpness = 0.4
            image = f.outputImage ?? image
        }
        if a.clarity != 0 {
            let f = CIFilter.unsharpMask(); f.inputImage = image
            f.radius = 40; f.intensity = Float(a.clarity * 0.8)
            image = f.outputImage ?? image
        }
        if a.sharpness != 0 {
            let f = CIFilter.sharpenLuminance(); f.inputImage = image; f.sharpness = Float(a.sharpness); image = f.outputImage ?? image
        }
        if a.sepia != 0 {
            let f = CIFilter.sepiaTone(); f.inputImage = image; f.intensity = Float(a.sepia); image = f.outputImage ?? image
        }
        if a.monochrome {
            let f = CIFilter.photoEffectMono(); f.inputImage = image; image = f.outputImage ?? image
        }
        if a.vignette != 0 {
            let f = CIFilter.vignette(); f.inputImage = image; f.intensity = Float(a.vignette * 2); f.radius = Float(min(input.extent.width, input.extent.height) / 2); image = f.outputImage ?? image
        }
        if a.grain != 0 {
            let noise = CIFilter.randomGenerator().outputImage ?? CIImage.empty()
            let matrix = CIFilter.colorMatrix(); matrix.inputImage = noise
            let amount = CGFloat(a.grain) * 0.35
            matrix.rVector = CIVector(x: 0, y: amount, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: amount, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: amount, z: 0, w: 0)
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            matrix.biasVector = CIVector(x: 0.5 - amount / 2, y: 0.5 - amount / 2, z: 0.5 - amount / 2, w: 1)
            let grain = (matrix.outputImage ?? noise).cropped(to: input.extent)
            let blend = CIFilter.softLightBlendMode(); blend.inputImage = grain; blend.backgroundImage = image
            image = (blend.outputImage ?? image).cropped(to: input.extent)
        }
        return image.cropped(to: input.extent)
    }

    static func redact(_ input: CIImage, redactions: [Redaction], flipped: Bool = true) -> CIImage {
        var image = input
        let extent = input.extent
        for redaction in redactions {
            var rect = redaction.rect.intersection(extent)
            if flipped {
                rect = CGRect(x: rect.minX, y: extent.maxY - rect.maxY, width: rect.width, height: rect.height)
            }
            guard !rect.isEmpty else { continue }
            let patch: CIImage
            switch redaction.style {
            case .solid:
                patch = CIImage(color: CIColor(cgColor: redaction.color)).cropped(to: rect)
            case .blur:
                let blur = CIFilter.gaussianBlur(); blur.inputImage = image.clampedToExtent(); blur.radius = Float(max(12, min(rect.width, rect.height) / 8))
                patch = (blur.outputImage ?? image).cropped(to: rect)
            case .pixelate:
                let pixel = CIFilter.pixellate(); pixel.inputImage = image.clampedToExtent(); pixel.scale = Float(max(12, min(rect.width, rect.height) / 8))
                pixel.center = CGPoint(x: rect.midX, y: rect.midY)
                patch = (pixel.outputImage ?? image).cropped(to: rect)
            }
            image = patch.composited(over: image)
        }
        return image.cropped(to: extent)
    }

    static func rotated(_ image: CGImage, quarterTurns: Int, flipHorizontal: Bool, flipVertical: Bool) throws -> CGImage {
        var ci = CIImage(cgImage: image)
        let turns = ((quarterTurns % 4) + 4) % 4
        if turns != 0 {
            ci = ci.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2))
        }
        if flipHorizontal { ci = ci.transformed(by: CGAffineTransform(scaleX: -1, y: 1)) }
        if flipVertical { ci = ci.transformed(by: CGAffineTransform(scaleX: 1, y: -1)) }
        let extent = ci.extent
        ci = ci.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        if let result = render(ci) { return result }
        // Quarter turns and flips need no GPU. Preserve exact pixels with a bitmap transform.
        var transform = CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2)
        if flipHorizontal { transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1)) }
        if flipVertical { transform = transform.concatenating(CGAffineTransform(scaleX: 1, y: -1)) }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height).applying(transform)
        transform = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let width = turns % 2 == 0 ? image.width : image.height
        let height = turns % 2 == 0 ? image.height : image.width
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw OpenTangerineError.encodeFailed("Could not allocate the rotated image.")
        }
        bitmap.interpolationQuality = .none
        bitmap.setShouldAntialias(false)
        bitmap.concatenate(transform)
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = bitmap.makeImage() else { throw OpenTangerineError.encodeFailed("Could not render the rotated image.") }
        return result
    }

    enum Background {
        case color(NSColor)
        case gradient(NSColor, NSColor, angle: CGFloat)
        case image(CGImage, blur: CGFloat)
    }

    struct FrameOptions {
        var aspect: CGSize? = nil
        var padding: CGFloat = 0.08
        var cornerRadius: CGFloat = 24
        var shadow: CGFloat = 24
        var background: Background = .color(.white)
    }

    static func framed(_ image: CGImage, options: FrameOptions) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        var canvas = imageSize
        if let aspect = options.aspect, aspect.width > 0, aspect.height > 0 {
            let ratio = aspect.width / aspect.height
            if imageSize.width / imageSize.height > ratio {
                canvas = CGSize(width: imageSize.width, height: imageSize.width / ratio)
            } else {
                canvas = CGSize(width: imageSize.height * ratio, height: imageSize.height)
            }
        }
        let pad = options.padding * min(canvas.width, canvas.height)
        if let aspect = options.aspect, aspect.width > 0, aspect.height > 0 {
            // Expand uniformly so padding never changes the chosen output ratio.
            let factor = max((canvas.width + pad * 2) / canvas.width, (canvas.height + pad * 2) / canvas.height)
            canvas = CGSize(width: canvas.width * factor, height: canvas.height * factor)
        } else {
            canvas = CGSize(width: canvas.width + pad * 2, height: canvas.height + pad * 2)
        }
        let scale = min((canvas.width - pad * 2) / imageSize.width, (canvas.height - pad * 2) / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (canvas.width - drawn.width) / 2, y: (canvas.height - drawn.height) / 2)

        guard let ctx = CGContext(
            data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let full = CGRect(origin: .zero, size: canvas)
        switch options.background {
        case .color(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(full)
        case .gradient(let a, let b, let angle):
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1])!
            let radians = angle * .pi / 180
            let dx = cos(radians) * canvas.width / 2
            let dy = sin(radians) * canvas.height / 2
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            ctx.drawLinearGradient(gradient, start: CGPoint(x: center.x - dx, y: center.y - dy), end: CGPoint(x: center.x + dx, y: center.y + dy), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .image(let bg, let blur):
            var ci = CIImage(cgImage: bg)
            let bgScale = max(canvas.width / ci.extent.width, canvas.height / ci.extent.height)
            ci = ci.transformed(by: CGAffineTransform(scaleX: bgScale, y: bgScale))
            ci = ci.transformed(by: CGAffineTransform(translationX: (canvas.width - ci.extent.width) / 2 - ci.extent.minX, y: (canvas.height - ci.extent.height) / 2 - ci.extent.minY))
            if blur > 0 {
                let f = CIFilter.gaussianBlur(); f.inputImage = ci.clampedToExtent(); f.radius = Float(blur)
                ci = f.outputImage ?? ci
            }
            if let rendered = render(ci.cropped(to: full), extent: full) {
                ctx.draw(rendered, in: full)
            }
        }
        let target = CGRect(origin: origin, size: drawn)
        if options.shadow > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -options.shadow / 3), blur: options.shadow, color: CGColor(gray: 0, alpha: 0.35))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.addPath(CGPath(roundedRect: target, cornerWidth: options.cornerRadius, cornerHeight: options.cornerRadius, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: target, cornerWidth: min(options.cornerRadius, drawn.width / 2), cornerHeight: min(options.cornerRadius, drawn.height / 2), transform: nil))
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(image, in: target)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    enum CollageLayout: String, CaseIterable, Identifiable {
        case grid, row, column, featured
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    struct CollageOptions {
        var layout: CollageLayout = .grid
        var width: CGFloat = 2400
        var height: CGFloat = 2400
        var spacing: CGFloat = 24
        var cornerRadius: CGFloat = 16
        var background: NSColor = .white
    }

    static func collageFrames(count: Int, options: CollageOptions) -> [CGRect] {
        guard count > 0 else { return [] }
        let s = options.spacing
        let w = options.width, h = options.height
        var frames: [CGRect] = []
        switch options.layout {
        case .row:
            let cell = (w - s * CGFloat(count + 1)) / CGFloat(count)
            for i in 0..<count { frames.append(CGRect(x: s + CGFloat(i) * (cell + s), y: s, width: cell, height: h - 2 * s)) }
        case .column:
            let cell = (h - s * CGFloat(count + 1)) / CGFloat(count)
            for i in 0..<count { frames.append(CGRect(x: s, y: h - s - CGFloat(i + 1) * cell - CGFloat(i) * s, width: w - 2 * s, height: cell)) }
        case .grid:
            let columns = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(columns)))
            let cellW = (w - s * CGFloat(columns + 1)) / CGFloat(columns)
            let cellH = (h - s * CGFloat(rows + 1)) / CGFloat(rows)
            for i in 0..<count {
                let c = i % columns, r = i / columns
                frames.append(CGRect(x: s + CGFloat(c) * (cellW + s), y: h - s - CGFloat(r + 1) * cellH - CGFloat(r) * s, width: cellW, height: cellH))
            }
        case .featured:
            if count == 1 { return [CGRect(x: s, y: s, width: w - 2 * s, height: h - 2 * s)] }
            let featureH = (h - 3 * s) * 0.62
            frames.append(CGRect(x: s, y: h - s - featureH, width: w - 2 * s, height: featureH))
            let rest = count - 1
            let cell = (w - s * CGFloat(rest + 1)) / CGFloat(rest)
            let restH = h - 3 * s - featureH
            for i in 0..<rest { frames.append(CGRect(x: s + CGFloat(i) * (cell + s), y: s, width: cell, height: restH)) }
        }
        return frames
    }

    static func collage(_ images: [CGImage], options: CollageOptions) -> CGImage? {
        let frames = collageFrames(count: images.count, options: options)
        guard let ctx = CGContext(
            data: nil, width: Int(options.width), height: Int(options.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(options.background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: options.width, height: options.height))
        ctx.interpolationQuality = .high
        for (image, frame) in zip(images, frames) {
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: frame, cornerWidth: options.cornerRadius, cornerHeight: options.cornerRadius, transform: nil))
            ctx.clip()
            let scale = max(frame.width / CGFloat(image.width), frame.height / CGFloat(image.height))
            let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            ctx.draw(image, in: CGRect(x: frame.midX - drawn.width / 2, y: frame.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    static func nsImage(_ image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

