// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import CryptoKit
import Foundation

/// The PDF engine the media tools and the clipboard optimizer share.
enum MediaPDFCompressorTests {
    typealias Engine = MediaPDFCompressor

    static func run(_ suite: TestSuite) {
        settings(suite)
        protection(suite)
        filter(suite)
        rewrite(suite)
        workspace(suite)
    }

    static func workspace(_ suite: TestSuite) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaPDFWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("doc.pdf")
        makeImagePDF(pdf, pages: 1, info: [:])
        suite.expect(NotchFileToolsSupport.accepts([pdf], for: .pdfCompressor), "the PDF tool takes a PDF")
        suite.expect(!NotchFileToolsSupport.accepts([pdf], for: .imageCompressor),
                     "the image tool still refuses a PDF, which ImageIO would rasterize")
        suite.expect(!NotchFileToolsSupport.accepts([pdf, pdf], for: .pdfCompressor), "the PDF tool takes one file")
        suite.expect(NotchFileToolsSupport.optimizationTool(for: [pdf]) == nil,
                     "a PDF dropped straight on the notch still stays in the shelf")
        suite.expect(MediaTool.allCases.firstIndex(of: .pdfCompressor) == 3, "the PDF tool sits after the image tool")
        suite.expect(MediaSupport.sanitizedTool("pdfCompressor") == .pdfCompressor, "the last tool is remembered")
        suite.expect(MediaPDFOptions(dpi: 7, quality: 9, grayscale: true).settings
                     == Engine.Settings(dpi: Engine.Settings.defaultDPI, quality: 1, grayscale: true),
                     "stored options are sanitized before use")
        // A bare % in a format string is read as a specifier: "5% smaller"
        // made "% s" consume a Swift string as a C string and crash.
        for language in AppLanguage.allCases {
            let format = MediaPDFStrings.localized(language).notSmallerFormat
            let rest = format.replacingOccurrences(of: "%%", with: "").replacingOccurrences(of: "%@", with: "")
            suite.expect(!rest.contains("%") && format.components(separatedBy: "%@").count == 3,
                         "\(language) not-smaller message has exactly two %@ and no bare %")
        }
        for key in [DefaultsKey.mediaPDFDPI, DefaultsKey.mediaPDFQuality, DefaultsKey.mediaPDFGrayscale] {
            suite.expect(Defaults.registeredDefaults[key] != nil, "\(key) is registered, so backup includes it")
        }
        for language in AppLanguage.allCases {
            let text = MediaPDFStrings.localized(language)
            let all = [text.tool, text.start, text.resolution, text.dpiFormat, text.grayscale, text.caption,
                       text.notSmallerFormat, text.notDownloaded, text.notWritable, text.notEnoughSpace]
                + Engine.Protection.allCases.map(text.protectionMessage)
            suite.expect(all.allSatisfy { !$0.isEmpty }, "\(language) has every PDF string")
            suite.expect(text.notSmallerFormat.components(separatedBy: "%@").count == 3
                         && text.dpiFormat.contains("%d"), "\(language) PDF formats keep their placeholders")
            suite.expect(Set(Engine.Protection.allCases.map(text.protectionMessage)).count
                         == Engine.Protection.allCases.count, "\(language) names each skip reason differently")
        }
    }

    static func settings(_ suite: TestSuite) {
        let fallback = Engine.Settings.sanitized(dpi: 123, quality: .nan)
        suite.expect(fallback.dpi == Engine.Settings.defaultDPI && fallback.quality == Engine.Settings.defaultQuality,
                     "an unknown resolution or quality falls back to the defaults")
        suite.expect(Engine.Settings.sanitized(dpi: 72, quality: 5).quality == 1, "quality is capped at 1")
        suite.expect(Engine.Settings.sanitized(dpi: 72, quality: 0).quality == 0.1, "quality never reaches 0")
        suite.expect(Engine.Settings.sanitized(dpi: 300, quality: 0.5, grayscale: true)
                     == Engine.Settings(dpi: 300, quality: 0.5, grayscale: true), "valid settings are kept")
        suite.expect(!Engine.Settings.sanitized(dpi: nil, quality: nil).grayscale, "gray is off unless asked")
    }

    static func protection(_ suite: TestSuite) {
        suite.expect(Engine.Traits().protection == nil, "a plain PDF has nothing to protect")
        var traits = Engine.Traits()
        traits.javaScript = true
        traits.tagged = true
        traits.signed = true
        suite.expect(traits.protection == .signed, "the first reason in order is the one reported")
        let cases: [(WritableKeyPath<Engine.Traits, Bool>, Engine.Protection)] = [
            (\.encrypted, .encrypted), (\.signed, .signed), (\.permissions, .permissions),
            (\.tagged, .tagged), (\.xfa, .forms), (\.embeddedFiles, .attachments), (\.javaScript, .scripted),
        ]
        for (flag, reason) in cases {
            var one = Engine.Traits()
            one[keyPath: flag] = true
            suite.expect(one.protection == reason && one.leavesAlone, "\(reason) is reported as the reason")
        }
        suite.expect(ClipboardOptimizerFileSupport.PDFTraits.self == Engine.Traits.self,
                     "the clipboard reads the same traits as the media tools")
    }

    static func filter(_ suite: TestSuite) {
        let color = Engine.filter(Engine.Settings(dpi: 100, quality: 0.55), name: "Test") as NSDictionary
        suite.expect(color.value(forKeyPath: "FilterData.ColorSettings.ImageSettings.ImageScaleSettings.ImageResolution")
                     as? Int == 100, "the filter resamples images to the chosen DPI")
        suite.expect(color["Name"] as? String == "Test", "the filter carries the caller's name")
        suite.expect(color.value(forKeyPath: "FilterData.ColorSettings.DocumentColorSettings") == nil
                     && color.value(forKeyPath: "FilterData.FilterProfileArray") == nil,
                     "a color filter never converts colors")
        let gray = Engine.filter(Engine.Settings(dpi: 100, quality: 0.55, grayscale: true), name: "Test") as NSDictionary
        suite.expect(gray.value(forKeyPath: "FilterData.ColorSettings.DocumentColorSettings.IntermediateColorSpace")
                     as? Int == 0, "gray matches colors through the first profile")
        suite.expect((gray.value(forKeyPath: "FilterData.FilterProfileArray") as? [Data])?.first?.isEmpty == false,
                     "gray embeds a gray profile")
        suite.expect(gray.value(forKeyPath: "FilterData.ColorSettings.ImageSettings.Compression Quality")
                     as? Double == 0.55, "gray still resamples images")
        suite.expect(PropertyListSerialization.propertyList(gray, isValidFor: .xml), "the gray filter is a property list")
        let clipboard = ClipboardOptimizerFileSupport.pdfFilter(
            ClipboardOptimizerFileSupport.PDFOptions(dpi: 100, quality: 0.55, maxMB: 100)) as NSDictionary
        suite.expect(clipboard == (Engine.filter(Engine.Settings(dpi: 100, quality: 0.55),
                                                 name: "Vorssaint clipboard optimizer") as NSDictionary),
                     "the clipboard filter is the shared color filter")
    }

    static func rewrite(_ suite: TestSuite) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaPDFCompressorTests-\(UUID().uuidString)", isDirectory: true)
        let scratch = dir.appendingPathComponent("scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("photos.pdf")
        makeImagePDF(source, pages: 3, info: [:])
        let before = digest(source)
        let settings = Engine.Settings(dpi: 72, quality: 0.5)

        let output = dir.appendingPathComponent("out.pdf")
        let pages = try? Engine.rewrite(source: source, to: output, settings: settings, filterName: "Test",
                                        scratchDirectory: scratch, isCancelled: { false })
        suite.expect(pages == 3, "a rewrite keeps every page")
        suite.expect(size(output) > 0 && size(output) < size(source),
                     "resampled images make the PDF smaller: \(size(source)) -> \(size(output))")
        suite.expect(digest(source) == before, "the source is never changed")
        suite.expect(leftovers(scratch).isEmpty, "the filter file is removed")

        let gray = dir.appendingPathComponent("gray.pdf")
        _ = try? Engine.rewrite(source: source, to: gray, settings: Engine.Settings(dpi: 72, quality: 0.5, grayscale: true),
                                filterName: "Test", scratchDirectory: scratch, isCancelled: { false })
        suite.expect(maxChannelSpread(gray) <= 4, "gray output has no color left: \(maxChannelSpread(gray))")
        suite.expect(maxChannelSpread(output) > 64, "color output keeps its color")

        let cancelled = dir.appendingPathComponent("cancelled.pdf")
        suite.expect(failure { try Engine.rewrite(source: source, to: cancelled, settings: settings, filterName: "Test",
                                                  scratchDirectory: scratch, isCancelled: { true }) } == .cancelled,
                     "a cancelled rewrite stops before writing")
        var calls = 0
        suite.expect(failure { try Engine.rewrite(source: source, to: cancelled, settings: settings, filterName: "Test",
                                                  scratchDirectory: scratch,
                                                  isCancelled: { calls += 1; return calls > 1 }) } == .cancelled,
                     "a cancel during the write is honored after it")
        suite.expect(!FileManager.default.fileExists(atPath: cancelled.path) && leftovers(scratch).isEmpty,
                     "a cancelled rewrite leaves no output and no filter behind")

        let locked = dir.appendingPathComponent("locked.pdf")
        makeImagePDF(locked, pages: 1, info: [kCGPDFContextOwnerPassword as String: "owner",
                                              kCGPDFContextAllowsCopying as String: false])
        suite.expect(failure { try Engine.rewrite(source: locked, to: output, settings: settings, filterName: "Test",
                                                  scratchDirectory: scratch, isCancelled: { false }) }
                     == .protected(.encrypted), "an encrypted PDF is refused with its reason")
        let junk = dir.appendingPathComponent("junk.pdf")
        try? Data("not a pdf".utf8).write(to: junk)
        suite.expect(failure { try Engine.rewrite(source: junk, to: output, settings: settings, filterName: "Test",
                                                  scratchDirectory: scratch, isCancelled: { false }) }
                     == .unreadable, "a file that is not a PDF is unreadable")
    }

    static func failure(_ body: () throws -> Int) -> Engine.Failure? {
        do { _ = try body(); return nil } catch let failure as Engine.Failure { return failure } catch { return nil }
    }

    static func makeImagePDF(_ url: URL, pages: Int, info: [String: Any]) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary),
              let bitmap = CGContext(data: nil, width: 1200, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        var seed: UInt64 = 42
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 56) / 255
        }
        for y in stride(from: 0, to: 1200, by: 6) {
            for x in stride(from: 0, to: 1200, by: 6) {
                bitmap.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: 1))
                bitmap.fill(CGRect(x: x, y: y, width: 6, height: 6))
            }
        }
        guard let image = bitmap.makeImage() else { return }
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.draw(image, in: CGRect(x: 56, y: 196, width: 500, height: 500))
            context.endPDFPage()
        }
        context.closePDF()
    }

    static func size(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    static func digest(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func leftovers(_ dir: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    static func maxChannelSpread(_ url: URL) -> Int {
        guard let page = CGPDFDocument(url as CFURL)?.page(at: 1),
              let context = CGContext(data: nil, width: 306, height: 396, bitsPerComponent: 8, bytesPerRow: 306 * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return -1 }
        context.scaleBy(x: 0.5, y: 0.5)
        context.drawPDFPage(page)
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return -1 }
        var spread = 0
        for index in stride(from: 0, to: 306 * 396 * 4, by: 4 * 13) {
            let r = Int(data[index]), g = Int(data[index + 1]), b = Int(data[index + 2])
            spread = max(spread, max(r, g, b) - min(r, g, b))
        }
        return spread
    }
}
