// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import PDFKit
import Quartz

/// Stateless PDF rewriting shared by the media tools and the clipboard
/// optimizer: a Quartz filter resamples embedded images and stores them as
/// JPEG, and PDFs a rewrite could break are refused before anything is read
/// past the catalog. It never touches the source file and never decides
/// whether a result is worth keeping; callers own sizes, caps and staging.
enum MediaPDFCompressor {
    struct Settings: Equatable {
        static let dpiChoices = [72, 100, 150, 200, 300]
        static let defaultDPI = 150
        static let defaultQuality = 0.7

        /// Embedded images are resampled down to this resolution on the page.
        var dpi: Int
        /// JPEG quality for the resampled images.
        var quality: Double
        /// Converts the whole document, text and drawings included, to gray.
        var grayscale = false

        static func sanitized(dpi: Int?, quality: Double?, grayscale: Bool? = nil) -> Settings {
            let quality = quality.flatMap { $0.isFinite ? $0 : nil } ?? defaultQuality
            let dpi = dpi.flatMap { dpiChoices.contains($0) ? $0 : nil } ?? defaultDPI
            return Settings(dpi: dpi, quality: min(1, max(0.1, quality)), grayscale: grayscale ?? false)
        }
    }

    /// Why a PDF is left alone, in the order a message reports them.
    enum Protection: String, CaseIterable, Equatable {
        case encrypted, signed, permissions, tagged, forms, attachments, scripted
    }

    /// What a rewrite could break in a PDF. Any of it leaves the file alone.
    struct Traits: Equatable {
        var encrypted = false
        var signed = false
        var permissions = false
        var tagged = false
        var xfa = false
        var embeddedFiles = false
        var javaScript = false

        var leavesAlone: Bool { protection != nil }

        var protection: Protection? {
            if encrypted { return .encrypted }
            if signed { return .signed }
            if permissions { return .permissions }
            if tagged { return .tagged }
            if xfa { return .forms }
            if embeddedFiles { return .attachments }
            if javaScript { return .scripted }
            return nil
        }

        static func read(_ document: CGPDFDocument) -> Traits {
            var traits = Traits()
            traits.encrypted = document.isEncrypted || !document.isUnlocked
            guard let catalog = document.catalog else { return traits }
            traits.permissions = has(catalog, "Perms")
            traits.javaScript = has(catalog, "OpenAction") || has(catalog, "AA")
            if let marks = dictionary(catalog, "MarkInfo") {
                var marked = false
                _ = CGPDFDictionaryGetBoolean(marks, "Marked", &marked)
                traits.tagged = marked
            }
            traits.tagged = traits.tagged || has(catalog, "StructTreeRoot")
            if let names = dictionary(catalog, "Names") {
                traits.embeddedFiles = has(names, "EmbeddedFiles")
                traits.javaScript = traits.javaScript || has(names, "JavaScript")
            }
            if let form = dictionary(catalog, "AcroForm") {
                traits.xfa = has(form, "XFA")
                var flags: CGPDFInteger = 0
                if CGPDFDictionaryGetInteger(form, "SigFlags", &flags), flags != 0 { traits.signed = true }
                var fields: CGPDFArrayRef?
                if !traits.signed, CGPDFDictionaryGetArray(form, "Fields", &fields), let fields {
                    traits.signed = containsSignature(fields, depth: 0)
                }
            }
            return traits
        }

        private static func has(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Bool {
            var object: CGPDFObjectRef?
            return CGPDFDictionaryGetObject(dictionary, key, &object)
        }

        private static func dictionary(_ parent: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
            var child: CGPDFDictionaryRef?
            return CGPDFDictionaryGetDictionary(parent, key, &child) ? child : nil
        }

        /// Signature fields can sit at any depth of the form's field tree.
        private static func containsSignature(_ fields: CGPDFArrayRef, depth: Int) -> Bool {
            guard depth < 8 else { return false }
            for index in 0..<CGPDFArrayGetCount(fields) {
                var field: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(fields, index, &field), let field else { continue }
                var type: UnsafePointer<Int8>?
                if CGPDFDictionaryGetName(field, "FT", &type), let type, String(cString: type) == "Sig" {
                    return true
                }
                var kids: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(field, "Kids", &kids), let kids,
                   containsSignature(kids, depth: depth + 1) {
                    return true
                }
            }
            return false
        }
    }

    enum Failure: Error, Equatable {
        case unreadable, empty, protected(Protection), filter, incompleteOutput, cancelled
    }

    /// A Quartz filter that resamples embedded images to `dpi` on the page
    /// and stores them as JPEG. Text, links and form fields are left as they
    /// are; only image streams change, unless `grayscale` asks for gray.
    static func filter(_ settings: Settings, name: String) -> [String: Any] {
        var colorSettings: [String: Any] = [
            "ImageSettings": [
                "Compression Quality": settings.quality,
                "ImageCompression": "ImageJPEGCompress",
                "ImageScaleSettings": [
                    "ImageResolution": settings.dpi,
                    "ImageScaleInterpolate": true,
                    "ImageSizeMin": 0,
                ] as [String: Any],
            ] as [String: Any],
        ]
        var filterData: [String: Any] = [:]
        if settings.grayscale, let gray = grayProfile {
            // The system "Gray Tone" filter's shape: match every color
            // through the first profile of FilterProfileArray.
            colorSettings["DocumentColorSettings"] = ["IntermediateColorSpace": 0]
            filterData["FilterProfileArray"] = [gray]
        }
        filterData["ColorSettings"] = colorSettings
        return [
            "Domains": ["Applications": true, "Printing": true],
            "FilterType": 1,
            "Name": name,
            "FilterData": filterData,
        ]
    }

    static var grayProfile: Data? {
        CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)?.copyICCData() as Data?
    }

    /// Reads only the catalog and page count, never the page contents.
    static func inspect(_ source: URL) throws -> Int {
        guard let reader = CGPDFDocument(source as CFURL) else { throw Failure.unreadable }
        if let protection = Traits.read(reader).protection { throw Failure.protected(protection) }
        guard reader.numberOfPages > 0 else { throw Failure.empty }
        return reader.numberOfPages
    }

    /// Writes a rewritten copy of `source` to `destination` and returns its
    /// page count. The filter file lives in `scratchDirectory` under a unique
    /// name, so concurrent callers never share one. PDFKit's write cannot be
    /// interrupted, so cancellation is checked on both sides of it; a write
    /// finished after a cancel is removed here.
    @discardableResult
    static func rewrite(source: URL, to destination: URL, settings: Settings, filterName: String,
                        scratchDirectory: URL, isCancelled: () -> Bool) throws -> Int {
        let pages = try inspect(source)
        guard !isCancelled() else { throw Failure.cancelled }
        let filterURL = scratchDirectory.appendingPathComponent(".\(UUID().uuidString).qfilter")
        defer { try? FileManager.default.removeItem(at: filterURL) }
        guard (filter(settings, name: filterName) as NSDictionary).write(to: filterURL, atomically: true),
              let quartzFilter = QuartzFilter(url: filterURL)
        else { throw Failure.filter }
        let written: Bool = try autoreleasepool {
            guard let document = PDFDocument(url: source) else { throw Failure.filter }
            return document.write(to: destination,
                                  withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): quartzFilter])
        }
        guard !isCancelled() else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.cancelled
        }
        guard written, let check = CGPDFDocument(destination as CFURL), check.numberOfPages == pages else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.incompleteOutput
        }
        return pages
    }
}
