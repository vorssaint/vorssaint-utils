// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct ClipboardHistoryImageEditorTests {
    class Fixture {
        var hidden = false
        func hideHistoryWindow() { hidden = true }
    }
    enum ClipboardImageStore { static var directory: URL? }
    enum AppFeature {
        static let screenshot = Availability()
        struct Availability { let isAvailable = true }
    }
    enum NSSound {
        static var failures = 0
        static func beep() { failures += 1 }
    }
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func closePopover() {}
    }
    final class NotchService {
        static let shared = NotchService()
        func perform(_ action: @escaping () -> Void) { action() }
    }
    enum ScreenshotSelectionController {
        struct Capture {
            let image: CGImage
            let scale: CGFloat
            let anchorRect: CGRect
        }
    }
    final class ScreenshotService {
        typealias ScreenshotSelectionController = ClipboardHistoryImageEditorTests.ScreenshotSelectionController
        static let shared = ScreenshotService()
        var capture: ScreenshotSelectionController.Capture?
        var openedOnMain = false
        func openEditor(with capture: ScreenshotSelectionController.Capture) {
            self.capture = capture
            openedOnMain = Thread.isMainThread
        }
    }
    private static func pump(until done: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !done(), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 640,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: directory.appendingPathComponent("older.png"))
            let entry = ClipboardHistoryEntry(text: "", copiedAt: .distantPast, kind: .image,
                                               imageFile: "older.png", imageWidth: 960, imageHeight: 640)
            ClipboardImageStore.directory = directory
            ScreenshotService.shared.capture = nil
            NSSound.failures = 0
            let host = Host()
            let changeCount = NSPasteboard.general.changeCount
            host.editImage(entry)
            pump { ScreenshotService.shared.capture != nil }
            let capture = ScreenshotService.shared.capture
            suite.expect(capture?.image.width == 960 && capture?.image.height == 640,
                         "history handoff opens the original image in the screenshot editor")
            suite.expect(capture?.scale == 1 && capture?.anchorRect == .zero,
                         "stored image uses the shared editor conversion and no screen anchor")
            suite.expect(host.hidden && ScreenshotService.shared.openedOnMain,
                         "history dismisses and presents the editor on the main thread")
            let image = ClipboardHistoryImageSupport.editorImage(for: entry, directory: directory)
            var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
            let original = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            suite.expect(original?.width == 960 && original?.height == 640,
                         "editing an older entry loads the stored original beyond thumbnail resolution")
            let pixel = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            if let corner = original?.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) {
                pixel.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            let bytes = pixel.data!.assumingMemoryBound(to: UInt8.self)
            suite.expect(bytes[0] == 255 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 255,
                         "the editor receives the selected historical image pixels")
            suite.expect(NSPasteboard.general.changeCount == changeCount,
                         "loading a historical image does not replace the current clipboard")
            try FileManager.default.removeItem(at: directory.appendingPathComponent("older.png"))
            ScreenshotService.shared.capture = nil
            host.hidden = false
            host.editImage(entry)
            pump { NSSound.failures > 0 }
            suite.expect(NSSound.failures == 1 && ScreenshotService.shared.capture == nil && !host.hidden,
                         "a missing image reports failure without dismissing history or opening an editor")
            suite.expect(ClipboardHistoryImageSupport.editorImage(for: entry, directory: directory) == nil,
                         "a removed historical image cannot fall back to the current clipboard")
            try Data("not an image".utf8).write(to: directory.appendingPathComponent("older.png"))
            suite.expect(ClipboardHistoryImageSupport.editorImage(for: entry, directory: directory) == nil,
                         "a corrupt stored image is rejected")
            for unsupported in [ClipboardHistoryEntry(text: "plain text"),
                                ClipboardHistoryEntry(text: "", kind: .files, filePaths: ["older.png"]),
                                ClipboardHistoryEntry(text: "", kind: .image),
                                ClipboardHistoryEntry(text: "", kind: .image, imageFile: "../older.png")] {
                suite.expect(ClipboardHistoryImageSupport.editorImage(for: unsupported, directory: directory) == nil,
                             "only a named image inside the history store can be edited")
            }
        } catch {
            suite.expect(false, "history image editor fixture: \(error)")
        }
    }
}
