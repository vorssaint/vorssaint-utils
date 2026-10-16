// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import PDFKit

enum FinderPDFToolsTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder PDF tools") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let first = try fixture(in: root, name: "first.pdf", width: 200)
                let second = try fixture(in: root, name: "second.pdf", width: 300)
                let firstBytes = try Data(contentsOf: first)
                let token = FinderToolsCancellation()
                let merged = try FinderPDFTools.merge([first, second], in: root, named: "merged", cancellation: token)
                let document = PDFDocument(url: merged)
                suite.expect(document?.pageCount == 2
                    && document?.page(at: 0)?.bounds(for: .mediaBox).width == 200
                    && document?.page(at: 1)?.bounds(for: .mediaBox).width == 300,
                    "PDF merge retains selected order and page dimensions")
                let outputs = try FinderPDFTools.split(merged, in: root, named: "pages", cancellation: token)
                suite.expect(outputs.count == 2 && outputs.allSatisfy { PDFDocument(url: $0)?.pageCount == 1 },
                             "splitting creates one valid PDF per page")
                let watermarked = try FinderPDFTools.watermark(first, text: "Review", in: root,
                    named: "first.pdf", cancellation: token)
                let result = PDFDocument(url: watermarked)
                suite.expect(watermarked != first && result?.page(at: 0)?.annotations.contains { $0.contents == "Review" } == true,
                             "watermark creates a separately named PDF with the requested annotation")
                let after = try Data(contentsOf: first)
                suite.expect(after == firstBytes, "merge, split and watermark leave the original bytes unchanged")
                let invalid = try FinderFileActions.createFile(in: root, named: "invalid.pdf", contents: Data("invalid".utf8))
                do {
                    _ = try FinderPDFTools.merge([first, invalid], in: root, named: "invalid-merged.pdf", cancellation: token)
                    suite.expect(false, "invalid input should reject the merge")
                } catch {
                    suite.expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("invalid-merged.pdf").path),
                                 "invalid input publishes no partial merge")
                }
            } catch { suite.expect(false, "PDF fixture failed: \(error)") }
        }
    }

    private static func fixture(in directory: URL, name: String, width: CGFloat) throws -> URL {
        let bytes = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: width, height: 400)
        guard let consumer = CGDataConsumer(data: bytes), let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 40, height: 40))
        context.endPDFPage()
        context.closePDF()
        return try FinderFileActions.createFile(in: directory, named: name, contents: bytes as Data)
    }
}
