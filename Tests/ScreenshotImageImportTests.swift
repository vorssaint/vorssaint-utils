// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

enum ScreenshotImageImportTests {
    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshot(language)
            suite.expect([strings.largeImageTitle, strings.largeImageMessageFormat,
                          strings.editReducedImage,
                          strings.imageImportFailed].allSatisfy { !$0.isEmpty },
                         "large-image choices and failures are localized in \(language.rawValue)")
        }
        let resize = MediaImageResizeMode.maxDimension(ScreenshotImageImport.maximumDimension)
        suite.expect(resize.targetSize(for: CGSize(width: 11479, height: 8199)) == CGSize(width: 6000, height: 4286),
                     "editor reduction uses the media longest-side sizing policy")
        suite.expect(resize.targetSize(for: CGSize(width: 40, height: 20)) == CGSize(width: 40, height: 20),
                     "the longest-side policy never enlarges a small image")
        for edge in [6000, 6001] {
            let image = ScreenshotCanvasSupportTests.image(width: edge, height: 1)
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            let input = ScreenshotImageImport(data: data)
            suite.expect(input?.requiresSizeChoice == (edge > 6000)
                && input?.reducedMaximumDimension == 6000,
                         "the size prompt starts above the 6000-pixel longest side, regardless of area")
            suite.expect(input?.decode()?.image.width == 6000,
                         "the import decoder never bypasses the 6000-pixel limit")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer {
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let bitmap = NSBitmapImageRep(cgImage: ScreenshotCanvasSupportTests.image(width: 40, height: 20))
            bitmap.size = CGSize(width: 20, height: 10)
            let data = bitmap.representation(using: .png, properties: [:])!
            let url = folder.appendingPathComponent("source.png")
            try data.write(to: url)
            board.writeObjects([url as NSURL])
            board.setData(NSBitmapImageRep(cgImage: ScreenshotCanvasSupportTests.image(width: 2, height: 2))
                .representation(using: .tiff, properties: [:]), forType: .tiff)
            let input = ScreenshotImageImport(pasteboard: board)
            suite.expect(input?.pixelSize == CGSize(width: 40, height: 20)
                && input?.requiresSizeChoice == false,
                         "a copied file wins over its small clipboard preview without decoding it")
            let original = input?.decode()
            suite.expect(original?.image.width == 40 && original?.image.height == 20 && original?.scale == 2,
                         "small-image import preserves full pixels and DPI scale")
            let smaller = CGImageSourceCreateWithData(data as CFData, nil)
                .flatMap { MediaImageProcessing.decode($0, maximumDimension: 10) }
            suite.expect(smaller?.width == 10 && smaller?.height == 5,
                         "Image I/O reduces pixels proportionally rather than only compressing file bytes")
            suite.expect(try Data(contentsOf: url) == data, "image import leaves the source file unchanged")
            board.clearContents()
            board.setData(data, forType: .png)
            suite.expect(ScreenshotImageImport(pasteboard: board)?.decode()?.image.width == 40,
                         "plain clipboard PNG data still opens without a file URL")
            board.clearContents()
            board.setData(bitmap.representation(using: .tiff, properties: [:]), forType: .tiff)
            suite.expect(ScreenshotImageImport(pasteboard: board)?.decode()?.scale == 2,
                         "plain clipboard TIFF data retains its image density")
            let jpeg = NSMutableData()
            let destination = CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, bitmap.cgImage!,
                                      [kCGImagePropertyOrientation: 6] as CFDictionary)
            suite.expect(CGImageDestinationFinalize(destination), "the oriented image fixture can be encoded")
            let rotated = ScreenshotImageImport(data: jpeg as Data)
            suite.expect(rotated?.sourceFormat == .jpeg, "the input format survives oriented image import")
            suite.expect(rotated?.pixelSize == CGSize(width: 20, height: 40)
                && rotated?.decode()?.image.width == 20 && rotated?.decode()?.image.height == 40,
                         "metadata and image import honor EXIF orientation")
            let pdf = NSMutableData()
            var page = CGRect(x: 0, y: 0, width: 40, height: 20)
            let context = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &page, nil)!
            context.beginPDFPage(nil)
            context.fill(page)
            context.endPDFPage()
            context.closePDF()
            let pdfURL = folder.appendingPathComponent("source.pdf")
            try (pdf as Data).write(to: pdfURL)
            suite.expect(ScreenshotImageImport(url: pdfURL)?.decode() != nil,
                         "file editing retains the AppKit fallback for images Image I/O cannot decode")
            board.clearContents()
            board.setString("plain text", forType: .string)
            suite.expect(ScreenshotImageImport(pasteboard: board) == nil
                && ScreenshotImageImport(data: Data("broken image".utf8)) == nil,
                         "text and malformed images are rejected")
        } catch {
            suite.expect(false, "image import fixtures: \(error)")
        }
        choices(suite)
    }

    enum Flow {
        typealias ScreenshotSelectionController = ClipboardHistoryImageEditorTests.ScreenshotSelectionController
        typealias GeneralPasteboardAccess = ScreenshotCanvasModelTests.Paste.GeneralPasteboardAccess
        enum AppFeature {
            static var screenshot = Availability()
            struct Availability { var isAvailable = true }
        }
        enum QuickToolHUD {
            static var messages: [String] = []
            static func show(icon: String, message: String) { messages.append(message) }
        }
        enum NSApp { static func activate(ignoringOtherApps: Bool) {} }
        enum WindowActivationPolicy {
            static var retained = 0
            static func retain() { retained += 1 }
            static func release() { retained -= 1 }
        }
        final class NSAlert {
            static var response: NSApplication.ModalResponse = .alertSecondButtonReturn
            static var shown = 0
            static var buttons: [String] = []
            init() { Self.buttons = [] }
            var alertStyle: AppKit.NSAlert.Style = .warning
            var messageText = "", informativeText = ""
            @discardableResult func addButton(withTitle title: String) -> NSButton {
                Self.buttons.append(title)
                return NSButton()
            }
            func runModal() -> NSApplication.ModalResponse {
                Self.shown += 1
                return Self.response
            }
        }
        final class ScreenshotImageImport {
            let sourceFormat = MediaImageFormat.jpeg
            var requiresSizeChoice = true
            var decodes = 0
            var decodedOnMain = false
            var fails = false
            func decode() -> (image: CGImage, scale: CGFloat)? {
                decodes += 1
                decodedOnMain = Thread.isMainThread
                return fails ? nil : (ScreenshotCanvasSupportTests.image(width: 40, height: 20), 1)
            }
        }
        class State {
            var imageImportsInProgress: Set<ImageImportSource> = []
            let strings = FeatureStrings.screenshot(.enUS)
        }
    }

    private static func choices(_ suite: TestSuite) {
        let lane = Flow.GeneralPasteboardAccess.shared
        for response in [NSApplication.ModalResponse.alertFirstButtonReturn,
                         .alertSecondButtonReturn] {
            let host = Flow.Host()
            let input = Flow.ScreenshotImageImport()
            Flow.NSAlert.response = response
            var captures = 0
            var sourceFormat: MediaImageFormat?
            host.importImage({ input }, from: .clipboard) { capture in
                captures += 1
                sourceFormat = capture.sourceFormat
            }
            host.importImage({ input }, from: .clipboard) { capture in
                captures += 1
                sourceFormat = capture.sourceFormat
            }
            suite.expect(lane.queued == 1, "repeated import requests cannot queue concurrent large decodes")
            lane.run()
            let deadline = Date(timeIntervalSinceNow: 2)
            while !host.imageImportsInProgress.isEmpty, Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
            }
            suite.expect(host.imageImportsInProgress.isEmpty && Flow.WindowActivationPolicy.retained == 0,
                         "every large-image choice releases admission and window activation")
            suite.expect(Flow.NSAlert.buttons == [host.strings.editReducedImage, host.strings.cancel],
                         "large images offer only resize-and-edit or cancel")
            if response == .alertSecondButtonReturn {
                suite.expect(input.decodes == 0 && captures == 0,
                             "cancel never decodes pixels or opens an editor")
            } else {
                suite.expect(input.decodes == 1 && captures == 1 && !input.decodedOnMain
                    && sourceFormat == .jpeg,
                             "a confirmed import decodes once off the main thread and delivers one capture")

            }
        }
        let host = Flow.Host()
        let input = Flow.ScreenshotImageImport()
        input.requiresSizeChoice = false
        input.fails = true
        let alerts = Flow.NSAlert.shown
        let errors = Flow.QuickToolHUD.messages.count
        host.importImage({ input }, from: .clipboard) { _ in suite.expect(false, "failed decode cannot open an editor") }
        lane.run()
        let deadline = Date(timeIntervalSinceNow: 2)
        while !host.imageImportsInProgress.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        suite.expect(Flow.NSAlert.shown == alerts && Flow.QuickToolHUD.messages.count == errors + 1
            && host.imageImportsInProgress.isEmpty,
                     "small images skip the dialog and decode failure reports an error without blocking later imports")
        input.fails = false
        var clipboardCaptures = 0
        var fileCaptures = 0
        var fileReadOnMain = true
        host.importImage({ input }, from: .clipboard) { _ in clipboardCaptures += 1 }
        let file = Flow.ScreenshotImageImport()
        file.requiresSizeChoice = false
        host.importImage({
            fileReadOnMain = Thread.isMainThread
            return file
        }, from: .file) { _ in fileCaptures += 1 }
        host.importImage({ file }, from: .file) { _ in fileCaptures += 1 }
        let fileDeadline = Date(timeIntervalSinceNow: 2)
        while host.imageImportsInProgress.contains(.file), Date() < fileDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        suite.expect(fileCaptures == 1 && file.decodes == 1 && !fileReadOnMain && !file.decodedOnMain
            && clipboardCaptures == 0 && lane.queued == 1,
                     "a blocked clipboard import cannot stall local files; repeated file imports still decode once off main")
        lane.run()
        let clipboardDeadline = Date(timeIntervalSinceNow: 2)
        while !host.imageImportsInProgress.isEmpty, Date() < clipboardDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        suite.expect(clipboardCaptures == 1 && host.imageImportsInProgress.isEmpty,
                     "the clipboard import remains on its lane and completes when that lane resumes")
    }
}
