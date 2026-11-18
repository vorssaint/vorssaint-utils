// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ClipboardHistoryDragTests {
    static func run(_ suite: TestSuite) {
        let fullText = "  Saved text\twith line breaks\n" + String(repeating: "long text ", count: 300)
        let text = ClipboardHistoryEntry(text: fullText)
        let textItems = ClipboardHistoryDrag.writers(for: text, imageDirectory: nil)
        let textItem = textItems.first as? NSPasteboardItem
        suite.expect(textItems.count == 1 && textItem?.string(forType: .string) == fullText,
                     "a text drag preserves the complete saved text, whitespace and line breaks")
        suite.expect(textItem?.string(forType: .URL) == nil,
                     "ordinary text does not advertise a URL representation")

        for saved in ["https://example.com/a?x=1", " \nHTTPS://example.com/a%20b\n "] {
            let entry = ClipboardHistoryEntry(text: saved)
            let item = ClipboardHistoryDrag.writers(for: entry, imageDirectory: nil).first as? NSPasteboardItem
            suite.expect(item?.string(forType: .string) == saved,
                         "a link drag keeps its exact saved plain-text fallback")
            suite.expect(item?.string(forType: .URL)
                            == URL(string: saved.trimmingCharacters(in: .whitespacesAndNewlines))?.absoluteString,
                         "a single web link also advertises its native URL representation")
        }
        for saved in ["https://example.com/a\nhttps://example.com/b", "https://example.com/a additional text",
                      "file:///tmp/saved-file", "notes.txt", "https://"] {
            let item = ClipboardHistoryDrag.writers(for: ClipboardHistoryEntry(text: saved), imageDirectory: nil)
                .first as? NSPasteboardItem
            suite.expect(item?.string(forType: .string) == saved && item?.string(forType: .URL) == nil,
                         "multiple links, prose, paths and incomplete URLs stay exact plain text")
        }
        suite.expect(ClipboardHistoryDrag.writers(for: ClipboardHistoryEntry(text: ""), imageDirectory: nil).isEmpty,
                     "an empty text entry cannot begin an empty drag")

        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("vorss-clipboard-drag-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: directory) }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try filePayloads(suite, in: directory)
            try imagePayloads(suite, in: directory)
        } catch {
            suite.expect(false, "clipboard drag fixtures could be created: \(error)")
        }
    }

    private static func filePayloads(_ suite: TestSuite, in directory: URL) throws {
        let first = directory.appendingPathComponent("first file.txt")
        let second = directory.appendingPathComponent("second.txt")
        let folder = directory.appendingPathComponent("folder", isDirectory: true)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let missing = directory.appendingPathComponent("missing.txt")
        let entry = ClipboardHistoryEntry(text: "", kind: .files,
                                          filePaths: [second.path, missing.path, first.path, folder.path, "", "relative.txt"])
        let writers = ClipboardHistoryDrag.writers(for: entry, imageDirectory: nil)
        let expected = [second, first, folder]
        suite.expect(writers.compactMap { ($0 as? NSURL).map { $0 as URL } } == expected,
                     "a file drag preserves every available file and directory in copy order, omitting stale and invalid paths")
        let payload = ClipboardHistoryDrag.prepare(for: entry, imageDirectory: nil)
        suite.expect(payload.fileLeases.map(\.url) == expected
                        && payload.writers.compactMap { ($0 as? NSURL).map { $0 as URL } } == expected,
                     "a prepared native drag retains access to every resolved file for the entire session")
        var sessionPayload: ClipboardHistoryDrag.Payload? = ClipboardHistoryDrag.prepare(for: entry, imageDirectory: nil)
        let hasSessionFileAccess = { [weak lease = sessionPayload?.fileLeases.first] in lease != nil }
        suite.expect(hasSessionFileAccess(), "a prepared file drag keeps its file access alive")
        sessionPayload = nil
        suite.expect(!hasSessionFileAccess(), "ending a file drag releases its scoped file access")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        suite.expect(pasteboard.writeObjects(writers), "native file drag writers can be published together")
        let received = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        suite.expect(received == expected, "a native drop reads multiple files as separate file URLs in order")
        suite.expect(ClipboardHistoryDrag.writers(for: ClipboardHistoryEntry(text: "", kind: .files,
                                                                            filePaths: [missing.path, ""]),
                                                  imageDirectory: nil).isEmpty,
                     "a file entry whose original files are gone cannot begin an empty drag")
        suite.expect(try Data(contentsOf: first) == Data("first".utf8)
                        && Data(contentsOf: second) == Data("second".utf8),
                     "preparing and reading the drag leaves its source files intact")
    }

    private static func imagePayloads(_ suite: TestSuite, in directory: URL) throws {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            suite.expect(false, "a PNG drag fixture can be encoded")
            return
        }
        let imageURL = directory.appendingPathComponent("stored.png")
        try png.write(to: imageURL)
        let entry = ClipboardHistoryEntry(text: "", kind: .image, imageFile: imageURL.lastPathComponent)
        let writers = ClipboardHistoryDrag.writers(for: entry, imageDirectory: directory)
        let item = writers.first as? NSPasteboardItem
        suite.expect(writers.count == 1 && item?.data(forType: .png) == png,
                     "an image drag offers the full stored PNG rather than a thumbnail")
        suite.expect(item?.data(forType: .tiff).flatMap { NSBitmapImageRep(data: $0) }?.pixelsWide == 2,
                     "an image drag also offers TIFF pixels to native editors")
        suite.expect(item?.string(forType: .fileURL) == imageURL.absoluteString,
                     "an image drag offers its stored PNG as a copyable file for Finder")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        suite.expect(pasteboard.writeObjects(writers), "an image drag writer can be published")
        let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage]
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        suite.expect(images?.count == 1 && files == [imageURL],
                     "native drop consumers can read the same image as pixels or as a file")
        suite.expect(try Data(contentsOf: imageURL) == png,
                     "preparing and reading an image drag leaves the stored image intact")
        try savedFileImagePayloads(suite, png: png, snapshot: imageURL)

        for name in ["missing.png", "", ".", "..", "../stored.png", imageURL.path, "nested/stored.png"] {
            let stale = ClipboardHistoryEntry(text: "", kind: .image, imageFile: name)
            suite.expect(ClipboardHistoryDrag.writers(for: stale, imageDirectory: directory).isEmpty,
                         "an unavailable image or a name outside the image store cannot become a drag payload")
        }
        suite.expect(ClipboardHistoryDrag.writers(for: entry, imageDirectory: nil).isEmpty,
                     "an image drag requires its image store")
        let broken = directory.appendingPathComponent("broken.png")
        try Data("invalid pixels".utf8).write(to: broken)
        suite.expect(ClipboardHistoryDrag.writers(for: ClipboardHistoryEntry(text: "", kind: .image,
                                                                            imageFile: broken.lastPathComponent),
                                                  imageDirectory: directory).isEmpty,
                     "an unreadable image does not advertise invalid pixel data")
    }

    private static func savedFileImagePayloads(_ suite: TestSuite, png: Data, snapshot: URL) throws {
        let fm = FileManager.default
        let directory = snapshot.deletingLastPathComponent()
        let original = directory.appendingPathComponent("temporary-original.JPG")
        try png.write(to: original)
        let entry = ClipboardHistoryEntry(text: "", kind: .files, filePaths: [original.path],
                                          imageFile: snapshot.lastPathComponent)
        let available = ClipboardHistoryDrag.writers(for: entry, imageDirectory: directory)
        suite.expect(available.count == 1 && (available.first as? NSURL).map { $0 as URL } == original,
                     "a readable copied image keeps its original file URL, format and metadata ahead of its snapshot")

        func hasSnapshot(_ writers: [NSPasteboardWriting]) -> Bool {
            guard writers.count == 1, let item = writers.first as? NSPasteboardItem else { return false }
            return item.data(forType: .png) == png && item.data(forType: .tiff) != nil
                && item.string(forType: .fileURL) == snapshot.absoluteString
        }
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: original.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path) }
        suite.expect(!fm.isReadableFile(atPath: original.path)
                        && hasSnapshot(ClipboardHistoryDrag.writers(for: entry, imageDirectory: directory)),
                     "an unreadable copied image falls back to its full saved PNG, TIFF and copyable snapshot URL")
        try fm.removeItem(at: original)
        suite.expect(hasSnapshot(ClipboardHistoryDrag.writers(for: entry, imageDirectory: directory)),
                     "a copied image whose temporary original expired can still drag its full saved snapshot")

        for paths in [[original.path, directory.appendingPathComponent("second.png").path],
                      [directory.appendingPathComponent("missing.txt").path], ["relative.png"]] {
            let excluded = ClipboardHistoryEntry(text: "", kind: .files, filePaths: paths,
                                                 imageFile: snapshot.lastPathComponent)
            suite.expect(ClipboardHistoryDrag.writers(for: excluded, imageDirectory: directory).isEmpty,
                         "multiple files, non-image files and invalid paths cannot invent a single-image snapshot payload")
        }
        let broken = directory.appendingPathComponent("broken-snapshot.png")
        try Data("invalid saved pixels".utf8).write(to: broken)
        for name in [nil, "missing.png", "../stored.png", broken.lastPathComponent] as [String?] {
            let stale = ClipboardHistoryEntry(text: "", kind: .files, filePaths: [original.path], imageFile: name)
            suite.expect(ClipboardHistoryDrag.writers(for: stale, imageDirectory: directory).isEmpty,
                         "an expired copied image without a valid saved snapshot cannot begin an empty drag")
        }
    }
}
