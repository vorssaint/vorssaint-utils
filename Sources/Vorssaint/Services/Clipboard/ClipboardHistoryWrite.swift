// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

protocol ClipboardHistoryPasteboard {
    func clearContents() -> Int
    var changeCount: Int { get }
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    func setData(_ data: Data?, forType type: NSPasteboard.PasteboardType) -> Bool
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: ClipboardHistoryPasteboard {}

struct ClipboardHistoryWriteResult {
    let succeeded: Bool
    let changeCount: Int
}

enum ClipboardHistoryWrite {
    case text(String)
    case image(png: Data, tiff: Data?)
    case files([NSURL])
    case rich(NSAttributedString, plain: String)

    /// The count from clearContents identifies our write, including on timeout.
    /// Setting the representations does not acquire pasteboard ownership again.
    /// If another app takes ownership, leave its generation for history to read.
    func write(to pasteboard: any ClipboardHistoryPasteboard,
               canStart: (() -> Bool)? = nil, isExpired: () -> Bool) -> ClipboardHistoryWriteResult? {
        // After admission this write runs to completion. A later cancellation
        // still suppresses the paste event, even if the clipboard has changed.
        guard !isExpired(), canStart?() != false else { return nil }
        let changeCount = pasteboard.clearContents()

        var succeeded = false
        if !isExpired() {
            switch self {
            case let .text(text):
                succeeded = pasteboard.setString(text, forType: .string)
            case let .image(png, tiff):
                succeeded = pasteboard.setData(png, forType: .png)
                if succeeded, let tiff, !isExpired() {
                    _ = pasteboard.setData(tiff, forType: .tiff)
                }
            case let .files(urls):
                succeeded = pasteboard.writeObjects(urls)
            case let .rich(rich, plain):
                succeeded = pasteboard.writeObjects([rich])
                if succeeded, !plain.isEmpty, !isExpired() {
                    _ = pasteboard.setString(plain, forType: .string)
                }
            }
        }

        let stillOwnsPasteboard = pasteboard.changeCount == changeCount
        return ClipboardHistoryWriteResult(succeeded: !isExpired() && succeeded && stillOwnsPasteboard,
                                           changeCount: changeCount)
    }
}
