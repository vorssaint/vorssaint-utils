// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import ImageIO

/// Rich capture uses a private pasteboard and generated production readers.
/// Its files can disappear after capture, as a chat app's temporary files do.
enum ClipboardImageCaptureTests {
    enum Board { static let general = AppKit.NSPasteboard.withUniqueName() }
    enum ClipboardImageStore {
        static var stored: [Data] = []
        static var fails = false
        static func store(_ data: Data) -> String? {
            guard !fails else { return nil }
            stored.append(data)
            return "\(stored.count).png"
        }
    }
    class Fixture {
        typealias NSPasteboard = Board
        var entries: [ClipboardHistoryEntry] = []
        var saves = 0
        var latestPasteboardEntry: ClipboardHistoryEntry?
        var capturedEntries: [ClipboardHistoryEntry] = []
        func insertPromoted(_ entry: ClipboardHistoryEntry, source: String?) {
            var entry = entry
            entry.sourceBundleID = source
            entries.insert(entry, at: 0)
            latestPasteboardEntry = entry
            capturedEntries.append(entry)
        }
        func normalizeEntryOrder() {}
        func trimToLimit() {}
        func save() { saves += 1 }
        static func sha256Hex(_ data: Data) -> String { data.base64EncodedString() }
    }

    static func run(_ suite: TestSuite) {
        let board = Board.general
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
            ClipboardImageStore.stored = []
            ClipboardImageStore.fails = false
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 64,
                                      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
            rep.setColor(.red, atX: 0, y: 0)
            let png = rep.representation(using: .png, properties: [:])!
            let jpeg = rep.representation(using: .jpeg, properties: [:])!
            for orientation in [6, 8] {
                let data = NSMutableData()
                let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
                CGImageDestinationAddImage(destination, rep.cgImage!,
                                          [kCGImagePropertyOrientation: orientation] as CFDictionary)
                CGImageDestinationFinalize(destination)
                let preview = Reader.normalizedPNGImage(data as Data)
                suite.expect(preview?.width == 64 && preview?.height == 32,
                             "JPEG orientation \(orientation) is applied to the captured PNG pixels")
            }
            var snapshot: (data: Data, width: Int, height: Int)?
            for (name, data) in [("wechat.jpg", jpeg), ("qq.jpeg", jpeg), ("finder.png", png)] {
                let url = directory.appendingPathComponent(name)
                try data.write(to: url)
                board.clearContents()
                board.writeObjects([url as NSURL])
                guard case .files(let paths, let preview)? = Reader.readPasteboard(includeImagesFiles: true) else {
                    suite.expect(false, "a copied chat/Finder image remains a file entry")
                    continue
                }
                suite.expect(paths == [url.path] && preview?.width == 32 && preview?.height == 64,
                             "URL-only \(name) captures its image while preserving the original file path")
                suite.expect(preview.flatMap { NSBitmapImageRep(data: $0.data) } != nil,
                             "the copied file snapshot is a decodable stored image")
                snapshot = preview
                suite.expect(Reader.readPasteboard(includeImagesFiles: false) == nil,
                             "images/files disabled never captures file pixels")
                try FileManager.default.removeItem(at: url)
                suite.expect(preview.flatMap { NSBitmapImageRep(data: $0.data) } != nil,
                             "captured pixels survive removal of the source app's temporary image")
            }

            let a = directory.appendingPathComponent("a.png")
            let b = directory.appendingPathComponent("b.png")
            try png.write(to: a)
            try png.write(to: b)
            board.clearContents()
            board.writeObjects([a as NSURL, b as NSURL])
            if case .files(let paths, let preview)? = Reader.readPasteboard(includeImagesFiles: true) {
                suite.expect(paths == [a.path, b.path] && preview == nil,
                             "multiple files keep their order and never become one image")
            } else { suite.expect(false, "a multiple-file copy remains files") }

            let invalid = directory.appendingPathComponent("not-an-image.jpg")
            try Data("plain text".utf8).write(to: invalid)
            board.clearContents()
            board.writeObjects([invalid as NSURL])
            if case .files(_, let preview)? = Reader.readPasteboard(includeImagesFiles: true) {
                suite.expect(preview == nil, "a misleading image extension does not create a corrupt preview")
            } else { suite.expect(false, "an invalid image file remains a file") }

            board.clearContents()
            board.setData(jpeg, forType: .init("public.jpeg"))
            if case .image(let preview)? = Reader.readPasteboard(includeImagesFiles: true) {
                suite.expect(preview.width == 32 && preview.height == 64,
                             "native JPEG-only clipboard images are normalized and captured")
            } else { suite.expect(false, "native JPEG clipboard image is recognized") }

            board.clearContents()
            board.writeObjects([invalid as NSURL])
            board.setData(png, forType: .png)
            if case .files(_, let preview)? = Reader.readPasteboard(includeImagesFiles: true) {
                suite.expect(preview?.width == 32 && preview?.height == 64,
                             "embedded image bytes provide a preview if the original file cannot decode")
            } else { suite.expect(false, "file plus image data still retains file copy semantics") }

            board.setString("1", forType: .init("org.nspasteboard.ConcealedType"))
            suite.expect(Reader.readPasteboard(includeImagesFiles: true) == nil,
                         "concealed file/image copies remain unread and unrecorded")
            suite.expect(Reader.normalizedPNGImage(Data(repeating: 0, count: 64 * 1024 * 1024 + 1)) == nil,
                         "raw image bytes are bounded before decoding")

            let history = Reader()
            var original = ClipboardHistoryEntry(text: "", copiedAt: .distantPast, pinnedAt: .distantPast,
                                                   kind: .files, filePaths: [a.path])
            original.sourceBundleID = "com.tencent.xinWeChat"
            let repaired = history.cachingFilePreview(snapshot, in: original)
            suite.expect(repaired.id == original.id && repaired.copiedAt == original.copiedAt
                         && repaired.pinnedAt == original.pinnedAt && repaired.sourceBundleID == original.sourceBundleID
                         && repaired.filePaths == original.filePaths && repaired.imageFile != nil,
                         "adding a preview preserves the saved file's identity, ordering metadata, source and copy payload")
            let writeCount = ClipboardImageStore.stored.count
            suite.expect(history.cachingFilePreview(snapshot, in: repaired) == repaired
                         && ClipboardImageStore.stored.count == writeCount,
                         "identical pixels reuse the stored snapshot")
            history.entries = [repaired]
            history.promoteFiles([a.path], preview: snapshot, source: "com.example.history", keepsSource: true)
            suite.expect(history.entries.count == 1 && history.entries[0].id == original.id
                         && history.entries[0].imageFile == repaired.imageFile
                         && history.entries[0].sourceBundleID == original.sourceBundleID
                         && history.entries[0].pinnedAt == original.pinnedAt,
                         "recopying a pinned file reuses its preview and preserves its source")
            history.promoteFiles([a.path], preview: nil, source: "com.tencent.qq", keepsSource: false)
            suite.expect(history.entries[0].imageFile == repaired.imageFile
                         && history.entries[0].sourceBundleID == "com.tencent.qq",
                         "a later unreadable copy retains its durable image while updating attribution")
            ClipboardImageStore.fails = true
            suite.expect(history.cachingFilePreview((Data("changed".utf8), 2, 3), in: repaired) == repaired,
                         "failed preview writes preserve the previous pixels and metadata")
        } catch {
            suite.expect(false, "clipboard image capture fixture: \(error)")
        }
    }
}
