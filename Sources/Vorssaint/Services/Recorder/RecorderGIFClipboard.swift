// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Publishes an exported recording as animated GIF data. The file is read and
/// recognized as a GIF before the general pasteboard is cleared, so an export
/// that is missing or is not really a GIF cannot destroy what was copied before.
enum RecorderGIFClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType(UTType.gif.identifier)

    static func publish(fileURL: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetCount(source) > 0 else { return false }

        let item = NSPasteboardItem()
        guard item.setData(data, forType: pasteboardType) else { return false }
        // A file URL lets attachment-oriented apps keep the original name,
        // while the native GIF flavor above remains the primary image payload.
        _ = item.setString(fileURL.absoluteString, forType: .fileURL)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return false }
        pasteboard.declareVorssaintSource()
        return true
    }
}
