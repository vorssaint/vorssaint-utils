// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageIOBridge {
    static let nativeEncoders: Set<String> = {
        let ids = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return Set(ids)
    }()

    static func canEncodeNatively(_ format: FileFormat) -> Bool {
        guard let type = format.utType else { return false }
        return nativeEncoders.contains(type.identifier)
    }

    static func load(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        guard url.isFileURL else { throw OpenTangerineError.invalidInput("Only local files are accepted.") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 100_000_000 else {
            throw OpenTangerineError.invalidInput("Use a regular image file smaller than 100 MB.")
        }
        if FileFormat.detect(url) == .svg {
            return try rasterizeSVG(url, maxPixelSize: maxPixelSize)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw OpenTangerineError.unreadable(url) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        DiagnosticLog.log("image load \(url.lastPathComponent) type=\((CGImageSourceGetType(source) as String?) ?? "?") \(width)x\(height) max=\(maxPixelSize.map(String.init) ?? "none")")
        try validateDimensions(width: width, height: height)
        let longest = max(width, height, 1)
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize.map { min($0, longest) } ?? longest,
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            DiagnosticLog.log("thumbnail decoded \(image.width)x\(image.height) alpha=\(image.alphaInfo.rawValue)")
            return image
        }
        options[kCGImageSourceCreateThumbnailWithTransform] = false
        DiagnosticLog.log("thumbnail failed, falling back to full decode")
        if let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { return image }
        if let ns = NSImage(contentsOf: url), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) { return cg }
        throw OpenTangerineError.unreadable(url)
    }

    static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw OpenTangerineError.invalidInput("Cannot read image dimensions. Re-export this image as PNG or JPEG and retry.")
        }
        guard Double(width) * Double(height) <= 40_000_000 else {
            throw OpenTangerineError.invalidInput("Image is \(width) × \(height) pixels; the limit is 40 megapixels. Resize it first, then retry.")
        }
    }

    static func rasterizeSVG(_ url: URL, maxPixelSize: Int?) throws -> CGImage {
        guard let image = NSImage(contentsOf: url) else { throw OpenTangerineError.unreadable(url) }
        var size = image.size
        if size.width <= 0 || size.height <= 0 { size = CGSize(width: 1024, height: 1024) }
        let target = CGFloat(maxPixelSize ?? 2048)
        let scale = target / max(size.width, size.height)
        let pixelSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw OpenTangerineError.unreadable(url) }
        rep.size = pixelSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: pixelSize), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = rep.cgImage else { throw OpenTangerineError.unreadable(url) }
        return cg
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func pixelSize(_ url: URL) -> CGSize {
        let props = properties(url)
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation >= 5 { return CGSize(width: height, height: width) }
        return CGSize(width: width, height: height)
    }

    static func write(_ image: CGImage, to url: URL, format: FileFormat, quality: Double = 0.9, metadata: [CFString: Any]? = nil, allowRasterFallback: Bool = true) throws {
        guard let type = format.utType, nativeEncoders.contains(type.identifier) else {
            throw OpenTangerineError.encodeFailed("\(format.displayName) natively")
        }
        DiagnosticLog.log("image write \(url.lastPathComponent) as \(type.identifier) quality=\(quality) metadata=\(metadata?.count ?? 0)")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw OpenTangerineError.encodeFailed(url.lastPathComponent)
        }
        var options: [CFString: Any] = metadata ?? [:]
        if format == .jpg || format == .heic || format == .webp || format == .avif {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        var output = image
        if format == .jpg || format == .bmp, image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst {
            output = flatten(image, background: .white)
            DiagnosticLog.log("flattened alpha \(output.width)x\(output.height)")
        }
        CGImageDestinationAddImage(destination, output, options as CFDictionary)
        DiagnosticLog.log("image added, finalizing")
        guard CGImageDestinationFinalize(destination) else {
            // Decoded AVIF/HEIC images can carry a pixel layout the PNG writer cannot consume.
            if allowRasterFallback, format != .heic,
               let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                if let raster = context.makeImage() {
                    try write(raster, to: url, format: format, quality: quality, metadata: metadata, allowRasterFallback: false)
                    return
                }
            }
            throw OpenTangerineError.encodeFailed(url.lastPathComponent)
        }
        DiagnosticLog.log("image finalized \(url.lastPathComponent)")
    }

    static func writeAnyFormat(_ image: CGImage, to url: URL, format: FileFormat, quality: Double = 0.9) async throws {
        if canEncodeNatively(format) {
            try write(image, to: url, format: format, quality: quality)
            return
        }
        if format == .webp, !(await FFmpeg.availableEncoders()).contains("libwebp") {
            try WebPLossless.write(image, to: url)
            return
        }
        DiagnosticLog.log("no native encoder for \(format.rawValue), using ffmpeg")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("opentangerine-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temp) }
        try write(image, to: temp, format: .png)
        try await encodeWithFFmpeg(png: temp, to: url, format: format, quality: quality)
    }

    static func encodeWithFFmpeg(png: URL, to url: URL, format: FileFormat, quality: Double) async throws {
        var args = ["-i", png.path, "-frames:v", "1"]
        switch format {
        case .webp:
            args += ["-c:v", "libwebp", "-quality", String(Int(quality * 100)), "-f", "webp"]
        case .avif:
            let crf = Int((1 - quality) * 50 + 10)
            let encoders = await FFmpeg.availableEncoders()
            if encoders.contains("libaom-av1") {
                args += ["-c:v", "libaom-av1", "-still-picture", "1"]
            } else if encoders.contains("libsvtav1") {
                args += ["-c:v", "libsvtav1", "-preset", "8"]
            } else {
                throw OpenTangerineError.invalidInput("AVIF needs an FFmpeg build with libaom-av1 or libsvtav1 encoding support.")
            }
            args += ["-crf", String(crf), "-b:v", "0", "-pix_fmt", "yuv420p", "-f", "avif"]
        case .heic:
            throw OpenTangerineError.invalidInput("HEIC requires the native macOS encoder.")
        case .bmp:
            args += ["-f", "image2", "-c:v", "bmp"]
        case .tiff:
            args += ["-f", "image2", "-c:v", "tiff"]
        case .jpg:
            args += ["-f", "image2", "-c:v", "mjpeg", "-q:v", String(Int((1 - quality) * 30 + 2))]
        default:
            throw OpenTangerineError.unsupportedConversion(.png, format)
        }
        args.append(url.path)
        try await FFmpeg.run(args, purpose: "Encoding \(format.displayName)")
    }

    static func flatten(_ image: CGImage, background: NSColor) -> CGImage {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func resized(_ image: CGImage, longEdge: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longEdge > 0, longest > longEdge else { return image }
        let scale = CGFloat(longEdge) / CGFloat(longest)
        return scaled(image, to: CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale))
    }

    static func scaled(_ image: CGImage, to size: CGSize) -> CGImage {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func cropped(_ image: CGImage, to rect: CGRect) -> CGImage {
        let bounded = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return image.cropping(to: bounded) ?? image
    }

    static func writePDF(images: [CGImage], to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
        for image in images {
            let pointsWidth = CGFloat(image.width) * 72 / 150
            let pointsHeight = CGFloat(image.height) * 72 / 150
            var box = CGRect(x: 0, y: 0, width: pointsWidth, height: pointsHeight)
            let info = [kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(info)
            context.draw(image, in: box)
            context.endPDFPage()
        }
        context.closePDF()
    }
}

struct ImageEngine: ConversionEngine {
    func supports(from: FileFormat, to: FileFormat) -> Bool {
        guard from.category == .image else { return false }
        return to.category == .image || to == .pdf || to == .docx
    }

    func convert(_ request: ConversionRequest) async throws {
        let image = try ImageIOBridge.load(request.source, maxPixelSize: request.options.maxLongEdge)
        request.progress(0.3)
        switch request.target {
        case .pdf:
            try ImageIOBridge.writePDF(images: [image], to: request.destination)
        case .docx:
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("opentangerine-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: temp) }
            try ImageIOBridge.write(image, to: temp, format: .png)
            try await DocxWriter.write(paragraphs: [], images: [temp], to: request.destination)
        default:
            let quality = request.options.quality ?? AppSettings.shared.jpegQuality
            try await ImageIOBridge.writeAnyFormat(image, to: request.destination, format: request.target, quality: quality)
        }
        request.progress(1)
    }
}

