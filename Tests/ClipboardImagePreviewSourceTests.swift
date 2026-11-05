// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the UI's source selection with real file availability checks. The
/// thumbnail decoder is unnecessary: these decisions choose what it will read.
enum ClipboardImagePreviewSourceTests {
    enum ClipboardImageStore {
        enum ThumbnailSource: Hashable {
            case stored(name: String)
            case file(path: String, maxPixelSize: CGFloat = 480)
        }
    }

    struct Entry {
        typealias ClipboardImageStore = ClipboardImagePreviewSourceTests.ClipboardImageStore
        enum Kind { case text, image, files }
        var kind: Kind
        var filePaths: [String] = []
        var imageFile: String?
    }

    static func run(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("copied.JPG")
            try Data().write(to: file)
            let stored = ClipboardImageStore.ThumbnailSource.stored(name: "snapshot.png")
            let copied = Entry(kind: .files, filePaths: [file.path], imageFile: "snapshot.png")
            suite.expect(copied.imageThumbnailSource == stored,
                         "a copied image file prefers its durable snapshot over its available source")

            try FileManager.default.removeItem(at: file)
            suite.expect(copied.imageThumbnailSource == stored,
                         "a copied image keeps its preview when its original scoped or temporary file is unavailable")
            suite.expect(Entry(kind: .image, imageFile: "snapshot.png").imageThumbnailSource == stored,
                         "an ordinary captured image uses the stored thumbnail source")
            suite.expect(Entry(kind: .image).imageThumbnailSource == nil,
                         "an image without stored pixels cannot invent a thumbnail source")

            try Data().write(to: file)
            suite.expect(Entry(kind: .files, filePaths: [file.path]).imageThumbnailSource == .file(path: file.path),
                         "an older image-file entry without a snapshot still previews its accessible original")
            try FileManager.default.removeItem(at: file)
            suite.expect(Entry(kind: .files, filePaths: [file.path]).imageThumbnailSource == nil,
                         "an older entry whose image file disappeared has no readable preview source")

            for paths in [[], [directory.appendingPathComponent("notes.txt").path],
                          [file.path, directory.appendingPathComponent("second.png").path]] {
                suite.expect(Entry(kind: .files, filePaths: paths, imageFile: "snapshot.png").imageThumbnailSource == nil,
                             "empty, non-image and multiple-file entries do not masquerade as one captured image")
            }
            suite.expect(Entry(kind: .text, filePaths: [file.path], imageFile: "snapshot.png").imageThumbnailSource == nil,
                         "thumbnail metadata cannot turn copied text into an image")

            for name in ["", "../outside.png", "/tmp/outside.png", "nested/preview.png"] {
                suite.expect(Entry(kind: .image, imageFile: name).imageThumbnailSource == nil,
                             "a stored thumbnail name must be one nonempty filename within the image store")
                suite.expect(Entry(kind: .files, filePaths: [file.path], imageFile: name).imageThumbnailSource == nil,
                             "an invalid snapshot name cannot preview an unavailable source file")
            }
            try Data().write(to: file)
            suite.expect(Entry(kind: .files, filePaths: [file.path], imageFile: "../outside.png").imageThumbnailSource
                            == .file(path: file.path),
                         "rejecting malformed snapshot metadata preserves a legitimate accessible image-file preview")
        } catch {
            suite.expect(false, "clipboard preview source fixtures could be created: \(error)")
        }
    }
}
