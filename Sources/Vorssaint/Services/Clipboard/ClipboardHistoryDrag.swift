// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Payloads for a native drag session. Preparing a drag leaves both the
/// general pasteboard and the saved history untouched.
enum ClipboardHistoryDrag {
    struct Payload {
        let writers: [NSPasteboardWriting]
        /// Bookmark access must stay open until the destination finishes
        /// receiving the drag, rather than just while its URLs are prepared.
        var fileLeases: [ClipboardHistoryFileLease] = []
    }

    static func writers(for entry: ClipboardHistoryEntry,
                        imageDirectory: URL?) -> [NSPasteboardWriting] {
        prepare(for: entry, imageDirectory: imageDirectory).writers
    }

    static func prepare(for entry: ClipboardHistoryEntry,
                        imageDirectory: URL?,
                        fileDirectory: URL? = ClipboardFileStore.directory) -> Payload {
        switch entry.kind {
        case .text:
            guard !entry.text.isEmpty else { return Payload(writers: []) }
            let item = NSPasteboardItem()
            item.setString(entry.text, forType: .string)
            // Keep the exact saved text as the fallback, while browsers and
            // link-aware editors receive a URL when the entire copy is a link.
            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains(where: \.isWhitespace),
               let url = URL(string: trimmed),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https",
               let host = url.host, !host.isEmpty {
                item.setString(url.absoluteString, forType: .URL)
            }
            return Payload(writers: [item])
        case .image:
            return Payload(writers: imageWriters(named: entry.imageFile, directory: imageDirectory))
        case .files:
            // Each file needs its own dragging item for native multi-file drops.
            let leases = ClipboardHistoryFileResolver.resolveAll(entry, storeDirectory: fileDirectory,
                                                                  imageDirectory: imageDirectory)
            if !leases.isEmpty {
                // Legacy copied images retained only a PNG preview. Preserve
                // its pixel representations as well as the copyable file URL;
                // exact-byte ClipboardFiles snapshots keep their native URLs.
                if leases.count == 1, entry.filePaths.count == 1,
                   ClipboardHistoryImageSupport.isImageFileName(entry.filePaths[0]),
                   let imageDirectory, let name = entry.imageFile,
                   leases[0].url.standardizedFileURL == imageDirectory.appendingPathComponent(name).standardizedFileURL,
                   leases[0].url.path != entry.filePaths[0] {
                    let images = imageWriters(named: name, directory: imageDirectory)
                    return Payload(writers: images, fileLeases: images.isEmpty ? [] : leases)
                }
                return Payload(writers: leases.map { $0.url as NSURL }, fileLeases: leases)
            }
            // A copied picture can retain a full PNG snapshot after its app's
            // temporary or scoped original expires. Prefer the original while
            // readable, preserving its format and metadata; only that single
            // image can fall back to its saved pixels.
            guard entry.filePaths.count == 1, let path = entry.filePaths.first,
                  (path as NSString).isAbsolutePath,
                  ClipboardHistoryImageSupport.isImageFileName(path) else { return Payload(writers: []) }
            return Payload(writers: imageWriters(named: entry.imageFile, directory: imageDirectory))
        }
    }

    private static func imageWriters(named name: String?, directory: URL?) -> [NSPasteboardWriting] {
        guard let directory,
              let name, !name.isEmpty,
              (name as NSString).lastPathComponent == name,
              name != ".", name != ".." else { return [] }
        let url = directory.appendingPathComponent(name)
        guard let png = try? Data(contentsOf: url),
              let bitmap = NSBitmapImageRep(data: png) else { return [] }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = bitmap.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        // Finder needs a file URL, while editors can consume the pixels.
        // The source only offers copy, so the private stored image stays put.
        item.setString(url.absoluteString, forType: .fileURL)
        return [item]
    }
}
