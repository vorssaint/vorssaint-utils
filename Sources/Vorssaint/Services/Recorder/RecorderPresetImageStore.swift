// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Presets own their pictures independently of the disposable recording.
/// Applying one makes fresh copies in the destination take, including for undo.
struct RecorderPresetImageStore {
    let directory: URL?

    init(directory: URL? = PrivateFileStore.containerURL?
        .appendingPathComponent("RecorderPresetImages", isDirectory: true)) {
        self.directory = directory?.resolvingSymlinksInPath().standardizedFileURL
    }

    func capture(_ images: [RecorderImageOverlay]) -> [RecorderImageOverlay]? {
        guard !images.isEmpty else { return [] }
        guard let directory, PrivateFileStore.createDirectory(at: directory) else { return nil }
        return copy(images, into: directory)
    }

    func restore(_ images: [RecorderImageOverlay], into take: RecorderTakeStore.Take,
                 duration: Double) -> [RecorderImageOverlay]? {
        guard duration.isFinite, duration > 0,
              images.allSatisfy({ owns(URL(fileURLWithPath: $0.path)) }),
              let restored = copy(images, into: take.folder) else { return nil }
        return restored.map { image in
            var image = image
            image.start = 0
            image.end = duration
            return image
        }
    }

    /// Only retired preset files are passed here. Active edits have their own
    /// copies, so deleting a preset cannot invalidate the document or its undo.
    func remove(_ images: [RecorderImageOverlay]) {
        for image in images {
            let url = URL(fileURLWithPath: image.path)
            guard owns(url) else { continue }
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    private func owns(_ url: URL) -> Bool {
        guard let directory else { return false }
        let folder = url.deletingLastPathComponent().standardizedFileURL
        return folder.deletingLastPathComponent().path == directory.path
            && UUID(uuidString: folder.lastPathComponent) != nil
            && folder.resolvingSymlinksInPath() == folder
    }

    private func copy(_ images: [RecorderImageOverlay], into directory: URL)
        -> [RecorderImageOverlay]? {
        var copied: [RecorderImageOverlay] = []
        for image in images {
            guard let url = RecorderTakeStore.shared.copyImage(
                at: URL(fileURLWithPath: image.path), into: directory) else {
                // Roll back only the fresh copies from this attempt.
                for copy in copied {
                    try? FileManager.default.removeItem(
                        at: URL(fileURLWithPath: copy.path).deletingLastPathComponent())
                }
                return nil
            }
            var copy = image
            copy.id = UUID()
            copy.path = url.path
            copied.append(copy)
        }
        return copied
    }
}
