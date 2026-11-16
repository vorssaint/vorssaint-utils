// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Payloads for a native drag session. Preparing a drag leaves both the
/// general pasteboard and the saved history untouched.
enum ClipboardHistoryDrag {
    static func writers(for entry: ClipboardHistoryEntry,
                        imageDirectory: URL?) -> [NSPasteboardWriting] {
        switch entry.kind {
        case .text:
            guard !entry.text.isEmpty else { return [] }
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
            return [item]
        case .image:
            return imageWriters(named: entry.imageFile, directory: imageDirectory)
        case .files:
            // Each file needs its own dragging item for native multi-file drops.
            let files = entry.filePaths.compactMap { path -> NSPasteboardWriting? in
                var isDirectory: ObjCBool = false
                guard (path as NSString).isAbsolutePath,
                      FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                      isDirectory.boolValue || FileManager.default.isReadableFile(atPath: path) else { return nil }
                return NSURL(fileURLWithPath: path)
            }
            if !files.isEmpty { return files }
            // A copied picture can retain a full PNG snapshot after its app's
            // temporary or scoped original expires. Prefer the original while
            // readable, preserving its format and metadata; only that single
            // image can fall back to its saved pixels.
            guard entry.filePaths.count == 1, let path = entry.filePaths.first,
                  (path as NSString).isAbsolutePath,
                  ClipboardHistoryImageSupport.isImageFileName(path) else { return [] }
            return imageWriters(named: entry.imageFile, directory: imageDirectory)
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
