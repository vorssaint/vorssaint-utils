// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

/// The editor's production copy methods, with an isolated pasteboard and
/// defaults domain. Image bytes still go through the real renderer and AppKit.
enum ScreenshotClipboardTests {
    static let defaultsDomain = "com.vorssaint.tests.screenshot-clipboard.\(UUID().uuidString)"
    static var copyDirectory: URL?

    enum UserDefaults {
        static let standard = Foundation.UserDefaults(suiteName: defaultsDomain)!
    }

    enum NSPasteboard {
        static let general = Pasteboard()
    }

    final class Pasteboard {
        let contents = AppKit.NSPasteboard(name: .init("Vorssaint.ScreenshotClipboardTests.\(UUID().uuidString)"))
        var acceptsWrites = true
        func clearContents() { contents.clearContents() }
        func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
            acceptsWrites && contents.writeObjects(objects)
        }
        func declareVorssaintSource() { contents.declareVorssaintSource() }
    }

    enum NSSound {
        static var beeps = 0
        static func beep() { beeps += 1 }
    }

    enum QuickToolHUD {
        static var messages: [String] = []
        static func show(icon: String, message: String) { messages.append(message) }
    }

    final class Model {
        var output: ScreenshotRenderer.Export?
        var exports = 0
        func exportImage() -> ScreenshotRenderer.Export? { output }
        func markExported() { exports += 1 }
    }

    final class Window {
        var closes = 0
        func close() { closes += 1 }
    }

    class State {
        let model = Model()
        let strings = ScreenshotFeatureStrings.enUS
        var window: Window? = Window()
    }

    static func run(_ suite: TestSuite) {
        let pasteboard = NSPasteboard.general
        defer {
            pasteboard.contents.releaseGlobally()
            UserDefaults.standard.removePersistentDomain(forName: defaultsDomain)
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotCopyImageOnly] as? Bool == false,
                     "screenshot copying preserves file paths by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenshotCopyImageOnly),
                     "the image-only copy choice travels in a settings backup")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshot(language)
            suite.expect(!strings.copyImageOnlyToggle.isEmpty && !strings.copyImageOnlyCaption.isEmpty,
                         "image-only copy controls are localized in \(language.rawValue)")
            let keywords = SettingsSearchSupport.screenCaptureKeywords(
                Strings.localized(language), language: language)
            suite.expect(keywords.contains(strings.copyImageOnlyToggle),
                         "image-only copying is searchable in \(language.rawValue)")
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotClipboardTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            copyDirectory = nil
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            copyDirectory = folder
            for scale: CGFloat in [1, 2] {
                guard let export = editedImage(scale: scale) else {
                    suite.expect(false, "the edited screenshot renders at \(scale)x")
                    continue
                }
                let payload = Editor.clipboardPayload(from: export)
                guard let png = payload.png else {
                    suite.expect(false, "the edited screenshot encodes as PNG")
                    continue
                }
                let url = folder.appendingPathComponent("Edited-\(Int(scale)).png")
                try png.write(to: url)

                UserDefaults.standard.set(false, forKey: DefaultsKey.screenshotCopyImageOnly)
                suite.expect(Editor.copyFile(url, payload: payload), "file copy publishes the edited capture")
                suite.expect(pasteboard.contents.string(forType: .fileURL) == url.absoluteString
                    && (try? Data(contentsOf: url)) == png,
                             "file copy keeps a readable path containing the edited PNG")
                checkImage(suite, type: .png, scale: scale)
                checkImage(suite, type: .tiff, scale: scale)

                let fileEditor = Editor()
                fileEditor.model.output = export
                fileEditor.copyToClipboard()
                let copiedURL = pasteboard.contents.string(forType: .fileURL).flatMap { URL(string: $0) }
                suite.expect(fileEditor.model.exports == 1 && fileEditor.window?.closes == 1
                    && copiedURL?.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
                    && copiedURL.flatMap { try? Data(contentsOf: $0) } == pasteboard.contents.data(forType: .png),
                             "the editor's default copy creates the file it publishes and closes on success")
                checkImage(suite, type: .png, scale: scale)
                checkImage(suite, type: .tiff, scale: scale)

                UserDefaults.standard.set(true, forKey: DefaultsKey.screenshotCopyImageOnly)
                suite.expect(Editor.copyFile(url, payload: payload),
                             "copying a saved capture honors the image-only preference")
                checkImageOnly(suite)
                checkImage(suite, type: .png, scale: scale)
                checkImage(suite, type: .tiff, scale: scale)

                let editor = Editor()
                editor.model.output = export
                let oldCount = pasteboard.contents.changeCount
                let filesBefore = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
                editor.copyToClipboard()
                suite.expect(editor.model.exports == 1 && editor.window?.closes == 1
                    && pasteboard.contents.changeCount != oldCount,
                             "copying an edited image publishes it before marking it exported and closing")
                suite.expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == filesBefore,
                             "copying an edited image in image-only mode creates no cached file")
                checkImageOnly(suite)
                checkImage(suite, type: .png, scale: scale)
                checkImage(suite, type: .tiff, scale: scale)

                pasteboard.acceptsWrites = false
                let failed = Editor()
                failed.model.output = export
                let messagesBefore = QuickToolHUD.messages.count
                let beepsBefore = NSSound.beeps
                failed.copyToClipboard()
                suite.expect(failed.model.exports == 0 && failed.window?.closes == 0
                    && QuickToolHUD.messages.count == messagesBefore && NSSound.beeps == beepsBefore + 1,
                             "a rejected edited-image copy stays open without claiming success")
                pasteboard.acceptsWrites = true
            }
        } catch {
            suite.expect(false, "screenshot clipboard fixture can be written: \(error)")
        }

        pasteboard.contents.clearContents()
        pasteboard.contents.setString("keep this copy", forType: .string)
        suite.expect(!Editor.copyClipboardPayload(.init(png: nil, tiff: nil))
            && pasteboard.contents.string(forType: .string) == "keep this copy",
                     "an empty image payload fails without destroying the current clipboard")
    }

    private static func editedImage(scale: CGFloat) -> ScreenshotRenderer.Export? {
        guard let context = CGContext(data: nil, width: 64, height: 64,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let base = context.makeImage() else { return nil }
        let rectangle = ScreenshotSupport.Annotation(tool: .rect,
            rect: CGRect(x: 16, y: 16, width: 32, height: 32), color: .red, stroke: .medium)
        return ScreenshotRenderer.renderExport(baseImage: base, annotations: [rectangle],
            blurSources: .none, scale: scale, annotationShadowsEnabled: false,
            watermark: ScreenshotSupport.WatermarkStyle(), watermarkImage: nil,
            style: ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0),
            fill: .none, downscaleTo1x: false)
    }

    private static func checkImageOnly(_ suite: TestSuite) {
        let pasteboard = NSPasteboard.general.contents
        suite.expect(pasteboard.pasteboardItems?.count == 1
            && pasteboard.data(forType: .png) != nil && pasteboard.data(forType: .tiff) != nil
            && pasteboard.string(forType: .fileURL) == nil
            && pasteboard.string(forType: .URL) == nil,
                     "image-only copy publishes one PNG/TIFF item with no URL representation")
    }

    private static func checkImage(_ suite: TestSuite, type: AppKit.NSPasteboard.PasteboardType,
                                   scale: CGFloat) {
        guard let data = NSPasteboard.general.contents.data(forType: type),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let bitmap = NSBitmapImageRep(data: data) else {
            suite.expect(false, "the clipboard \(type.rawValue) decodes as an image")
            return
        }
        let border = ScreenshotCanvasSupportTests.pixel(image, x: 16, y: 32)
        let center = ScreenshotCanvasSupportTests.pixel(image, x: 32, y: 32)
        suite.expect(image.width == 64 && image.height == 64
            && border[0] > 180 && border[1] < 130 && border[2] < 130
            && center[0] > 240 && center[1] > 240 && center[2] > 240,
                     "the clipboard \(type.rawValue) contains the rectangle and the original pixels")
        suite.expect(bitmap.pixelsWide == 64 && bitmap.pixelsHigh == 64
            && bitmap.size.width == 64 / scale && bitmap.size.height == 64 / scale,
                     "the clipboard \(type.rawValue) decodes at the \(scale)x point size in both axes")
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
        let dpiWidth = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        let dpiHeight = (properties?[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue
        let expectedDPI = Double(72 * scale)
        // AppKit omits TIFF's default 72 DPI. The decoded point size above
        // must still be exact; other scales and PNG require explicit density.
        let permitsImplicitDPI = type == .tiff && scale == 1
        suite.expect((dpiWidth == expectedDPI || (dpiWidth == nil && permitsImplicitDPI))
            && (dpiHeight == expectedDPI || (dpiHeight == nil && permitsImplicitDPI)),
                     "the clipboard \(type.rawValue) preserves the \(scale)x image density in both axes")
    }
}
