// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AppKit
import CoreText
import Foundation
import PDFKit

enum TextRenderer {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 54

    static func attributed(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ])
    }

    static func paginate(_ text: String) -> [CFRange] {
        let attributed = attributed(text)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let box = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        var ranges: [CFRange] = []
        var start = 0
        let length = attributed.length
        while start < length {
            let path = CGPath(rect: box, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            ranges.append(visible)
            start = visible.location + visible.length
        }
        if ranges.isEmpty { ranges.append(CFRange(location: 0, length: 0)) }
        return ranges
    }

    static func draw(_ text: String, range: CFRange, in context: CGContext, scale: CGFloat = 1) {
        let attributed = attributed(text)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let box = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let path = CGPath(rect: box, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    static func writePDF(_ text: String, to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
        for range in paginate(text) {
            context.beginPDFPage(nil)
            draw(text, range: range, in: context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    static func renderWholeDocument(_ text: String, dpi: CGFloat = 150) throws -> CGImage {
        let ranges = paginate(text)
        let scale = dpi / 72
        let width = Int(pageSize.width * scale)
        let pageHeight = Int(pageSize.height * scale)
        let totalHeight = pageHeight * ranges.count
        try ImageIOBridge.validateDimensions(width: width, height: totalHeight)
        guard let context = CGContext(
            data: nil, width: width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw OpenTangerineError.encodeFailed("image") }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))
        for (index, range) in ranges.enumerated() {
            context.saveGState()
            let offsetY = CGFloat(totalHeight - pageHeight * (index + 1))
            context.translateBy(x: 0, y: offsetY)
            draw(text, range: range, in: context, scale: scale)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { throw OpenTangerineError.encodeFailed("image") }
        return image
    }
}

enum PDFRenderer {
    static func writeImagesPDF(_ urls: [URL], pageSize: CGSize, margin: CGFloat = 36, to destination: URL, progress: @escaping (Double) -> Void) throws {
        guard !urls.isEmpty else { throw OpenTangerineError.invalidInput("No images to place in the PDF.") }
        guard let consumer = CGDataConsumer(url: destination as CFURL) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
        for (index, url) in urls.enumerated() {
            let image = try ImageIOBridge.load(url)
            let available = mediaBox.insetBy(dx: margin, dy: margin)
            let scale = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height))
            let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let rect = CGRect(x: available.midX - drawn.width / 2, y: available.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
            context.beginPDFPage(nil)
            context.interpolationQuality = .high
            context.draw(image, in: rect)
            context.endPDFPage()
            progress(Double(index + 1) / Double(urls.count))
        }
        context.closePDF()
    }

    static func render(page: PDFPage, dpi: CGFloat = 300) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let rotation = page.rotation
        let rotated = rotation % 180 != 0
        let pixelWidth = ((rotated ? bounds.height : bounds.width) * scale).rounded()
        let pixelHeight = ((rotated ? bounds.width : bounds.height) * scale).rounded()
        guard pixelWidth.isFinite, pixelHeight.isFinite, pixelWidth > 0, pixelHeight > 0,
              pixelWidth * pixelHeight <= 40_000_000 else { return nil }
        let width = Int(pixelWidth)
        let height = Int(pixelHeight)
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    static func thumbnail(page: PDFPage, maxSize: CGFloat) -> NSImage {
        page.thumbnail(of: CGSize(width: maxSize, height: maxSize), for: .mediaBox)
    }
}

struct DocumentEngine: ConversionEngine {
    func supports(from: FileFormat, to: FileFormat) -> Bool {
        switch (from, to) {
        case (.pdf, .docx), (.pdf, .jpg), (.pdf, .png), (.pdf, .txt): return true
        case (.txt, .pdf), (.txt, .jpg), (.txt, .png), (.txt, .srt), (.txt, .vtt): return true
        default: return false
        }
    }

    func convert(_ request: ConversionRequest) async throws {
        switch request.sourceFormat {
        case .pdf: try await convertPDF(request)
        case .txt: try await convertText(request)
        default: throw OpenTangerineError.unsupportedConversion(request.sourceFormat, request.target)
        }
    }

    private func convertPDF(_ request: ConversionRequest) async throws {
        let document = try PDFOps.document(request.source)
        let pageCount = document.pageCount
        switch request.target {
        case .txt:
            var text = ""
            for index in 0..<pageCount {
                if let page = document.page(at: index), let content = page.string { text += content + "\n\n" }
                request.progress(Double(index + 1) / Double(pageCount))
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // A scan: render each page and read it.
                for index in 0..<pageCount {
                    try Task.checkCancellation()
                    if let page = document.page(at: index), let image = PDFRenderer.render(page: page) {
                        text += try await OCR.recognize(image) + "\n\n"
                    }
                    request.progress(Double(index + 1) / Double(pageCount))
                }
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OpenTangerineError.invalidInput("No text was found in this PDF.")
            }
            try text.write(to: request.destination, atomically: true, encoding: .utf8)
        case .jpg, .png:
            if pageCount == 1, let page = document.page(at: 0) {
                guard let image = PDFRenderer.render(page: page) else { throw OpenTangerineError.encodeFailed(request.destination.lastPathComponent) }
                try ImageIOBridge.write(image, to: request.destination, format: request.target, quality: 0.92)
            } else {
                let folder = request.destination.deletingPathExtension()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let base = ConversionMatrix.strippedBaseName(request.source.lastPathComponent)
                for index in 0..<pageCount {
                    guard let page = document.page(at: index), let image = PDFRenderer.render(page: page) else { throw OpenTangerineError.encodeFailed("PDF page \(index + 1)") }
                    let pageURL = folder.appendingPathComponent("\(base) - page \(index + 1).\(request.target.fileExtension)")
                    try ImageIOBridge.write(image, to: pageURL, format: request.target, quality: 0.92)
                    request.progress(Double(index + 1) / Double(pageCount))
                }
                try? FileManager.default.removeItem(at: request.destination)
                try FileManager.default.moveItem(at: folder, to: request.destination)
            }
        case .docx:
            var blocks: [DocxWriter.Block] = []
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("opentangerine-pdfdocx-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            for index in 0..<pageCount {
                guard let page = document.page(at: index) else { throw OpenTangerineError.encodeFailed("PDF page \(index + 1)") }
                if index > 0 { blocks.append(.pageBreak) }
                let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty {
                    blocks += text.components(separatedBy: "\n").map { .paragraph($0.trimmingCharacters(in: .whitespaces)) }
                } else if let image = PDFRenderer.render(page: page, dpi: 150) {
                    let pageImage = temp.appendingPathComponent("page\(index + 1).png")
                    try ImageIOBridge.write(image, to: pageImage, format: .png)
                    blocks.append(.image(pageImage))
                }
                request.progress(Double(index + 1) / Double(pageCount) * 0.8)
            }
            try await DocxWriter.write(blocks: blocks, to: request.destination)
        default:
            throw OpenTangerineError.unsupportedConversion(.pdf, request.target)
        }
        request.progress(1)
    }

    private func convertText(_ request: ConversionRequest) async throws {
        let text = try TextFile.read(request.source)
        switch request.target {
        case .pdf:
            try TextRenderer.writePDF(text, to: request.destination)
        case .jpg, .png:
            let image = try TextRenderer.renderWholeDocument(text)
            try ImageIOBridge.write(image, to: request.destination, format: request.target, quality: 0.92)
        case .srt, .vtt:
            let cues = SubtitleParser.parse(text, hint: .txt)
            try SubtitleParser.serialize(cues, as: request.target).write(to: request.destination, atomically: true, encoding: .utf8)
        default:
            throw OpenTangerineError.unsupportedConversion(.txt, request.target)
        }
        request.progress(1)
    }
}

enum TextFile {
    static func read(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) { return text }
        throw OpenTangerineError.unreadable(url)
    }
}

