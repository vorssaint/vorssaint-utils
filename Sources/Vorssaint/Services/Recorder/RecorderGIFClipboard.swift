// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Publishes an exported recording as an animated GIF. The file is recognized
/// as a GIF before the general pasteboard is cleared, so an export that is
/// missing or is not really a GIF cannot destroy what was copied before.
/// Checking the file reads every frame, so this runs off the main thread.
enum RecorderGIFClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType(UTType.gif.identifier)

    /// The largest GIF also handed over as data. A long recording makes
    /// hundreds of MB, which every app reading the clipboard would copy, and
    /// past about 256 MB macOS refuses the data after the clipboard was
    /// already cleared (measured on macOS 27.2). Larger GIFs go as the file
    /// alone, which apps that take attachments paste as it is.
    static let inlineByteLimit = 64 * 1024 * 1024

    static func publish(fileURL: URL,
                        to pasteboard: NSPasteboard = .general,
                        inlineByteLimit: Int = inlineByteLimit) -> Bool {
        guard let bytes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetCount(source) > 0 else { return false }

        let item = NSPasteboardItem()
        if bytes <= inlineByteLimit {
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                  item.setData(data, forType: pasteboardType) else { return false }
        }
        // A file URL lets attachment-oriented apps keep the original name,
        // while the native GIF flavor above remains the primary image payload.
        guard item.setString(fileURL.absoluteString, forType: .fileURL) else { return false }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return false }
        pasteboard.declareVorssaintSource()
        return true
    }
}
