// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Combines PDFs and images into one PDF, in the order given. Kept free of UI and of
/// `MediaService` state so ordering and merging can be tested directly.
enum MediaPDFMerger {
    /// Image pages use the same quality as the image tool's PDF output.
    static let imageQuality = 0.9

    enum Failure: Error, Equatable {
        case unreadable(URL)
        case passwordProtected(URL)
        /// Opens without a password, but its owner restricted it (copying, printing, changes…).
        case restricted(URL)
        case imageTooLarge(URL)
        case cancelled
        case writeFailed
    }

    /// Finder-style natural order ("page 2" before "page 10"), for files picked in the open
    /// panel, which reports no meaningful order. Dropped files keep their drag order.
    static func defaultOrder(_ urls: [URL]) -> [URL] {
        urls.sorted { a, b in
            let result = a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
            if result != .orderedSame { return result == .orderedAscending }
            return a.path < b.path
        }
    }

    /// A merge list grows: new files go after the existing ones, and a file already in the
    /// list keeps its place instead of appearing twice.
    static func appending(_ newURLs: [URL], to existing: [URL]) -> [URL] {
        var seen = Set(existing.map(\.standardizedFileURL))
        var result = existing
        for url in newURLs where seen.insert(url.standardizedFileURL).inserted {
            result.append(url)
        }
        return result
    }

    static func canMerge(_ urls: [URL]) -> Bool {
        let tool = MediaTool.pdfMerger
        return urls.count >= tool.minimumInputs && tool.usableInputs(urls).count == urls.count
    }

    /// Page count for a PDF input, 1 for an image, nil if unreadable.
    static func pageCount(of url: URL) -> Int? {
        if isPDF(url) { return CGPDFDocument(url as CFURL)?.numberOfPages }
        return CGImageSourceCreateWithURL(url as CFURL, nil) == nil ? nil : 1
    }

    /// Writes the merged document to `outputURL` (a staged path; the caller installs it).
    /// Each image becomes one page the size of its pixels, upright, as the image tool's PDF
    /// output does. Returns the merged page count.
    @discardableResult
    static func merge(_ urls: [URL], to outputURL: URL,
                      isCancelled: () -> Bool = { false },
                      progress: (Double) -> Void = { _ in }) throws -> Int {
        let merged = PDFDocument()
        var sources: [PDFDocument] = []  // pages reference their document until written
        for (index, url) in urls.enumerated() {
            guard !isCancelled() else { throw Failure.cancelled }
            let document: PDFDocument
            if isPDF(url) {
                guard let pdf = PDFDocument(url: url) else { throw Failure.unreadable(url) }
                guard !pdf.isLocked else { throw Failure.passwordProtected(url) }
                // The merged file carries no permissions, so merging a restricted PDF would
                // quietly lift every restriction its owner set. Refuse it instead.
                guard !isRestricted(pdf) else { throw Failure.restricted(url) }
                document = pdf
            } else {
                document = try imagePage(url)
            }
            sources.append(document)
            for pageIndex in 0..<document.pageCount {
                if pageIndex % 64 == 0, isCancelled() { throw Failure.cancelled }
                if let page = document.page(at: pageIndex)?.copy() as? PDFPage {
                    merged.insert(page, at: merged.pageCount)
                }
            }
            progress(Double(index + 1) / Double(urls.count) * 0.95)
        }
        guard !isCancelled() else { throw Failure.cancelled }
        // Image pages are already compressed, so this mostly copies existing data.
        guard merged.write(to: outputURL) else { throw Failure.writeFailed }
        withExtendedLifetime(sources) {}
        progress(1)
        return merged.pageCount
    }

    /// One image as a one-page PDF: decoded with its orientation applied (as the image tool
    /// does) and embedded as JPEG, so a merge of photos stays close to the photos' size and
    /// only compressed data is held in memory.
    private static func imagePage(_ url: URL) throws -> PDFDocument {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let size = MediaSupport.imageDisplaySize(properties: properties) else {
            throw Failure.unreadable(url)
        }
        guard MediaSupport.imageRenderSizeIsSafe(size) else { throw Failure.imageTooLarge(url) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(size.width, size.height).rounded(.up)),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let image = MediaSupport.jpegBackedImage(decoded, quality: imageQuality) else {
            throw Failure.unreadable(url)
        }
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw Failure.unreadable(url)
        }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        guard let page = PDFDocument(data: data as Data), page.pageCount == 1 else {
            throw Failure.unreadable(url)
        }
        return page
    }

    static func isRestricted(_ pdf: PDFDocument) -> Bool {
        pdf.isEncrypted && !(pdf.allowsCopying && pdf.allowsPrinting && pdf.allowsDocumentChanges
                             && pdf.allowsDocumentAssembly && pdf.allowsCommenting && pdf.allowsFormFieldEntry)
    }

    private static func isPDF(_ url: URL) -> Bool {
        MediaSupport.contentType(of: url)?.conforms(to: .pdf) ?? false
    }
}
