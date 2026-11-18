// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum MediaPDFMergeTests {
    static func run(_ suite: TestSuite) {
        ordering(suite)
        toolRules(suite)
        merging(suite)
        strings(suite)
    }

    private static func ordering(_ suite: TestSuite) {
        let urls = ["page 10.pdf", "page 2.pdf", "Page 1.pdf", "appendix.pdf"]
            .map { URL(fileURLWithPath: "/tmp/\($0)") }
        suite.expect(MediaPDFMerger.defaultOrder(urls).map(\.lastPathComponent)
               == ["appendix.pdf", "Page 1.pdf", "page 2.pdf", "page 10.pdf"],
               "PDF merge starts in Finder's natural filename order, not plain string order")
    }

    private static func toolRules(_ suite: TestSuite) {
        suite.expect(MediaTool.pdfMerger.acceptsMultipleInputs && MediaTool.imageCompressor.acceptsMultipleInputs,
               "PDF merge and image conversion take several inputs")
        suite.expect(!MediaTool.videoCompressor.acceptsMultipleInputs && !MediaTool.gifMaker.acceptsMultipleInputs
               && !MediaTool.textExtractor.acceptsMultipleInputs,
               "Single-input tools keep taking one input")
        suite.expect(MediaSupport.sanitizedTool("pdfMerger") == .pdfMerger,
               "The PDF merge tool persists as the last-used tool")
        suite.expect(MediaTool.pdfMerger.minimumInputs == 2
               && MediaTool.allCases.filter { $0 != .pdfMerger }.allSatisfy { $0.minimumInputs == 1 },
               "Only the PDF merge tool needs two inputs before it can run")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintPDFMergeRules-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = makePDF(in: dir, name: "doc.pdf", pages: 1, width: 100)
        let otherPDF = makePDF(in: dir, name: "other.pdf", pages: 1, width: 100)
        let png = makePNG(in: dir, name: "shot.png", width: 10, height: 10)
        let text = dir.appendingPathComponent("notes.txt")
        try? Data("x".utf8).write(to: text)

        suite.expect(MediaTool.imageCompressor.usableInputs([pdf, png, otherPDF]) == [png],
               "Switching from PDF merge to the image tool drops PDFs instead of rasterizing their first page")
        suite.expect(MediaTool.pdfMerger.usableInputs([png, pdf, text]) == [png, pdf],
               "Switching to PDF merge keeps PDFs and images in their order and drops other files")
        suite.expect(MediaTool.videoCompressor.usableInputs([png, pdf]).isEmpty,
               "Switching to a video tool keeps no image or PDF inputs")

        let photos = (1...3).map { makePNG(in: dir, name: "photo\($0).png", width: 4, height: 4) }
        // Image (3 photos) → Video → Image: the photos come back.
        var all = MediaTool.imageCompressor.updatingAllInputs([], current: photos)
        let videoInputs = MediaTool.videoCompressor.usableInputs(all)
        all = MediaTool.videoCompressor.updatingAllInputs(all, current: videoInputs)
        suite.expect(videoInputs.isEmpty && MediaTool.imageCompressor.usableInputs(all) == photos,
               "Switching away from the image tool and back restores its files")
        // PDF [pdf, png, otherPDF] → Image (sees png only) → PDF: the PDFs return in their places.
        all = MediaTool.pdfMerger.updatingAllInputs([], current: [pdf, png, otherPDF])
        let imageInputs = MediaTool.imageCompressor.usableInputs(all)
        all = MediaTool.imageCompressor.updatingAllInputs(all, current: imageInputs)
        suite.expect(imageInputs == [png] && MediaTool.pdfMerger.usableInputs(all) == [pdf, png, otherPDF],
               "Switching from PDF merge to the image tool and back keeps the merge list and its order")
        // A reorder in the merge tool is what the next switch remembers.
        all = MediaTool.pdfMerger.updatingAllInputs(all, current: [otherPDF, pdf, png])
        suite.expect(all == [otherPDF, pdf, png],
               "The merge order the person set is kept across tool switches")
        suite.expect(MediaTool.imageCompressor.updatingAllInputs([pdf, png], current: [png, photos[0]])
               == [pdf, png, photos[0]],
               "Files added under one tool join the list without dropping set-aside files")

        suite.expect(MediaPDFMerger.appending([png, pdf], to: [otherPDF, pdf]) == [otherPDF, pdf, png],
               "Adding files to a merge appends new ones in drop order and never duplicates an existing one")
        suite.expect(MediaPDFMerger.appending([], to: [pdf]) == [pdf],
               "Adding nothing leaves the merge list unchanged")

        suite.expect(NotchFileToolsSupport.accepts([pdf, png], for: .pdfMerger)
               && !NotchFileToolsSupport.accepts([pdf], for: .pdfMerger)
               && !NotchFileToolsSupport.accepts([pdf, text], for: .pdfMerger),
               "The Notch offers PDF merge only for two or more PDFs and images")
        suite.expect(!NotchFileToolsSupport.accepts([pdf, otherPDF], for: .imageCompressor)
               && NotchFileToolsSupport.accepts([png], for: .imageCompressor),
               "The Notch image tool still accepts images only")
    }

    private static func merging(_ suite: TestSuite) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintPDFMerge-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = makePDF(in: dir, name: "first.pdf", pages: 2, width: 200)
        let image = makePNG(in: dir, name: "photo.png", width: 40, height: 20)
        let last = makePDF(in: dir, name: "last.pdf", pages: 1, width: 300)
        let output = dir.appendingPathComponent("merged.pdf")
        let pages = try? MediaPDFMerger.merge([first, image, last], to: output)
        let merged = PDFDocument(url: output)
        suite.expect(pages == 4 && merged?.pageCount == 4,
               "PDF merge keeps every page of each PDF and adds one page per image")
        suite.expect(merged?.page(at: 0)?.bounds(for: .mediaBox).width == 200
               && merged?.page(at: 2)?.bounds(for: .mediaBox).size == CGSize(width: 40, height: 20)
               && merged?.page(at: 3)?.bounds(for: .mediaBox).width == 300,
               "PDF merge follows the given order, with images at their pixel size like the image tool's PDFs")

        // A camera photo stored landscape with "rotate 90°" metadata must come out upright.
        let rotated = makeJPEG(in: dir, name: "portrait.jpg", width: 40, height: 20, orientation: 6)
        let rotatedOutput = dir.appendingPathComponent("rotated.pdf")
        _ = try? MediaPDFMerger.merge([first, rotated], to: rotatedOutput)
        suite.expect(PDFDocument(url: rotatedOutput)?.page(at: 2)?.bounds(for: .mediaBox).size
               == CGSize(width: 20, height: 40),
               "Image pages follow EXIF orientation, so portrait photos are not merged sideways")

        let reordered = dir.appendingPathComponent("reordered.pdf")
        _ = try? MediaPDFMerger.merge([last, first], to: reordered)
        suite.expect(PDFDocument(url: reordered)?.page(at: 0)?.bounds(for: .mediaBox).width == 300,
               "A reordered merge starts with the file the user moved to the front")

        suite.expect(MediaPDFMerger.pageCount(of: first) == 2 && MediaPDFMerger.pageCount(of: image) == 1,
               "Merge rows report PDF page counts and one page per image")
        suite.expect(MediaPDFMerger.canMerge([first, image]) && !MediaPDFMerger.canMerge([first]),
               "Merging needs at least two inputs")

        let text = dir.appendingPathComponent("notes.txt")
        try? Data("x".utf8).write(to: text)
        suite.expect(!MediaPDFMerger.canMerge([first, text]),
               "Merging rejects inputs that are neither PDFs nor images")

        var cancelledError: MediaPDFMerger.Failure?
        let cancelledOutput = dir.appendingPathComponent("cancelled.pdf")
        do {
            try MediaPDFMerger.merge([first, last], to: cancelledOutput, isCancelled: { true })
        } catch let failure as MediaPDFMerger.Failure {
            cancelledError = failure
        } catch {}
        suite.expect(cancelledError == .cancelled && !FileManager.default.fileExists(atPath: cancelledOutput.path),
               "A cancelled merge writes nothing")

        let locked = makeLockedPDF(in: dir, name: "locked.pdf")
        var lockedError: MediaPDFMerger.Failure?
        do {
            try MediaPDFMerger.merge([first, locked], to: dir.appendingPathComponent("locked-out.pdf"))
        } catch let failure as MediaPDFMerger.Failure {
            lockedError = failure
        } catch {}
        suite.expect(lockedError == .passwordProtected(locked),
               "A password-protected PDF stops the merge with an error naming that file")

        let restricted = makeRestrictedPDF(in: dir, name: "no-copy.pdf")
        var restrictedError: MediaPDFMerger.Failure?
        do {
            try MediaPDFMerger.merge([first, restricted], to: dir.appendingPathComponent("restricted-out.pdf"))
        } catch let failure as MediaPDFMerger.Failure {
            restrictedError = failure
        } catch {}
        suite.expect(restrictedError == .restricted(restricted),
               "A PDF whose owner disallowed copying is refused instead of having its restrictions stripped")

        // Copying allowed, printing not: merging would still lift the print restriction.
        let noPrint = makeRestrictedPDF(in: dir, name: "no-print.pdf", allowsCopying: true, allowsPrinting: false)
        var noPrintError: MediaPDFMerger.Failure?
        do {
            try MediaPDFMerger.merge([first, noPrint], to: dir.appendingPathComponent("no-print-out.pdf"))
        } catch let failure as MediaPDFMerger.Failure {
            noPrintError = failure
        } catch {}
        suite.expect(noPrintError == .restricted(noPrint),
               "A PDF with any owner restriction, not only copying, is refused")

        let broken = dir.appendingPathComponent("broken.png")
        try? Data("not an image".utf8).write(to: broken)
        var brokenError: MediaPDFMerger.Failure?
        do {
            try MediaPDFMerger.merge([first, broken], to: dir.appendingPathComponent("broken-out.pdf"))
        } catch let failure as MediaPDFMerger.Failure {
            brokenError = failure
        } catch {}
        suite.expect(brokenError == .unreadable(broken),
               "An unreadable input stops the merge with an error naming that file")
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let s = Strings.localized(language)
            suite.expect(s.mediaErrorPasswordProtectedFormat.contains("%@")
                   && s.mediaErrorRestrictedPDFFormat.contains("%@")
                   && s.mediaErrorUnreadableFormat.contains("%@"),
                   "PDF merge errors keep their file-name argument in \(language.rawValue)")
            suite.expect(!s.mediaStartMergePDF.isEmpty && !s.mediaMergeOrderCaption.isEmpty
                   && !s.mediaMergeNeedsTwo.isEmpty && !s.mediaToolPDF.isEmpty,
                   "PDF merge labels exist in \(language.rawValue)")
        }
    }

    // MARK: - Fixtures

    private static func makePDF(in dir: URL, name: String, pages: Int, width: CGFloat) -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: width, height: 100)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
        for _ in 0..<pages { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        return url
    }

    private static func makeLockedPDF(in dir: URL, name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let options: [CFString: Any] = [kCGPDFContextUserPassword: "secret", kCGPDFContextOwnerPassword: "owner"]
        guard let context = CGContext(url as CFURL, mediaBox: &box, options as CFDictionary) else { return url }
        context.beginPDFPage(nil); context.endPDFPage()
        context.closePDF()
        return url
    }

    private static func makeRestrictedPDF(in dir: URL, name: String,
                                          allowsCopying: Bool = false, allowsPrinting: Bool = true) -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        // Opens without a password, but the owner restricted it.
        let options: [CFString: Any] = [kCGPDFContextUserPassword: "", kCGPDFContextOwnerPassword: "owner",
                                        kCGPDFContextAllowsCopying: allowsCopying,
                                        kCGPDFContextAllowsPrinting: allowsPrinting]
        guard let context = CGContext(url as CFURL, mediaBox: &box, options as CFDictionary) else { return url }
        context.beginPDFPage(nil); context.endPDFPage()
        context.closePDF()
        return url
    }

    private static func makeJPEG(in dir: URL, name: String, width: Int, height: Int, orientation: Int) -> URL {
        let url = dir.appendingPathComponent(name)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return url }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return url
    }

    private static func makePNG(in dir: URL, name: String, width: Int, height: Int) -> URL {
        let url = dir.appendingPathComponent(name)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return url }
        // 72 dpi so the image's point size equals its pixel size.
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return url
    }
}
