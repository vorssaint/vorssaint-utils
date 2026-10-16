// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Services supplies a dedicated pasteboard. Never consult the general clipboard
/// or infer paths from plain text: a selected URL must identify a local file.
enum FinderToolsPasteboardSelection {
    static func request(from pasteboard: NSPasteboard) -> FinderToolsRequest? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let request = FinderToolsRequest(selection: urls, directory: nil)
        guard request.url != nil else { return nil }
        return request
    }
}
