// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import PDFKit
import Quartz

/// PDF operations produce new documents and never edit the selected originals.
enum FinderPDFTools {
    static let maximumPages = 2_000
    static let maximumInputBytes = 256 * 1024 * 1024

    static func merge(_ inputs: [URL], in directory: URL, named name: String,
                      cancellation: FinderToolsCancellation) throws -> URL {
        guard !inputs.isEmpty else { throw FinderFileActionError.invalidRequest("Select PDF files or images to merge.") }
        let output = PDFDocument()
        for input in inputs {
            try cancellation.check()
            try validateSize(input)
            let source: PDFDocument
            if let pdf = PDFDocument(url: input) {
                guard !pdf.isLocked, pdf.allowsCopying else {
                    throw FinderFileActionError.unsupported(input, "The PDF is locked or does not allow copying")
                }
                source = pdf
            } else if let image = try? FinderImageTools.load(input),
                      let page = PDFPage(image: NSImage(cgImage: image, size: .zero)) {
                source = PDFDocument()
                source.insert(page, at: 0)
            } else {
                throw FinderFileActionError.unsupported(input, "Choose a PDF document or readable image")
            }
            guard output.pageCount + source.pageCount <= maximumPages else {
                throw FinderFileActionError.invalidRequest("A document may contain at most 2,000 pages.")
            }
            for index in 0..<source.pageCount {
                try cancellation.check()
                guard let page = source.page(at: index)?.copy() as? PDFPage else {
                    throw FinderFileActionError.unsupported(input, "A PDF page could not be read")
                }
                output.insert(page, at: output.pageCount)
            }
        }
        return try save(output, in: directory, named: name, cancellation: cancellation)
    }

    static func split(_ input: URL, in directory: URL, named name: String,
                      cancellation: FinderToolsCancellation) throws -> [URL] {
        let source = try document(input)
        try cancellation.check()
        let folder = try FinderFileActions.createFolder(in: directory, named: name, collisionPolicy: .makeUnique)
        var outputs: [URL] = []
        for index in 0..<source.pageCount {
            do {
                try cancellation.check()
                guard let page = source.page(at: index)?.copy() as? PDFPage else {
                    throw FinderFileActionError.unsupported(input, "A PDF page could not be read")
                }
                let output = PDFDocument()
                output.insert(page, at: 0)
                outputs.append(try save(output, in: folder, named: String(format: "%04d.pdf", locale: Locale(identifier: "en_US_POSIX"), index + 1),
                                        cancellation: cancellation))
            } catch {
                throw FinderFileActionError.partialFailure(operation: "split PDF", completed: outputs,
                    failures: [.init(url: folder, reason: error.localizedDescription)])
            }
        }
        return outputs
    }

    static func watermark(_ input: URL, text: String, in directory: URL, named name: String,
                          cancellation: FinderToolsCancellation) throws -> URL {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 500 else {
            throw FinderFileActionError.invalidRequest("Enter a watermark between 1 and 500 characters.")
        }
        let source = try document(input)
        for index in 0..<source.pageCount {
            try cancellation.check()
            guard let page = source.page(at: index) else { throw CocoaError(.fileReadCorruptFile) }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let height = min(100, bounds.height / 3)
            let annotation = PDFAnnotation(bounds: CGRect(x: bounds.minX + 12, y: bounds.midY - height / 2,
                width: max(1, bounds.width - 24), height: height), forType: .freeText, withProperties: nil)
            annotation.contents = text
            annotation.font = NSFont.systemFont(ofSize: min(36, bounds.width / 15))
            annotation.fontColor = NSColor.gray.withAlphaComponent(0.25)
            annotation.color = .clear
            annotation.alignment = .center
            annotation.shouldPrint = true
            page.addAnnotation(annotation)
        }
        return try save(source, in: directory, named: name, cancellation: cancellation)
    }

    static func compress(_ input: URL, in directory: URL, named name: String,
                         cancellation: FinderToolsCancellation) throws -> URL {
        let source = try document(input)
        let filterURL = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
        guard let filter = QuartzFilter(url: filterURL),
              let data = source.dataRepresentation(options: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]) else {
            throw FinderFileActionError.unsupported(input, "The system PDF size-reduction filter is unavailable")
        }
        try cancellation.check()
        let originalSize = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard data.count < originalSize else {
            throw FinderFileActionError.unsupported(input, "The PDF could not be reduced further with the system filter")
        }
        return try FinderFileActions.createFile(in: directory, named: pdfName(name), contents: data,
                                                collisionPolicy: .makeUnique)
    }

    private static func document(_ input: URL) throws -> PDFDocument {
        try validateSize(input)
        guard let document = PDFDocument(url: input), !document.isLocked, document.allowsCopying,
              document.pageCount > 0, document.pageCount <= maximumPages else {
            throw FinderFileActionError.unsupported(input, "Choose an unlocked PDF with 1 to 2,000 pages that allows copying")
        }
        return document
    }

    private static func validateSize(_ input: URL) throws {
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= maximumInputBytes else {
            throw FinderFileActionError.unsupported(input, "Choose a regular document smaller than 256 MB")
        }
    }

    private static func save(_ document: PDFDocument, in directory: URL, named name: String,
                             cancellation: FinderToolsCancellation) throws -> URL {
        guard document.pageCount > 0, let data = document.dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try cancellation.check()
        return try FinderFileActions.createFile(in: directory, named: pdfName(name), contents: data,
                                                collisionPolicy: .makeUnique)
    }

    private static func pdfName(_ name: String) -> String {
        name.lowercased().hasSuffix(".pdf") ? name : name + ".pdf"
    }
}
