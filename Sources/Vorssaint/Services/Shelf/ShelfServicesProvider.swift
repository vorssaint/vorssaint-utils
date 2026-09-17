// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// "Add to Shelf" in the Services menu: a Finder selection, a stretch of
/// text or a link goes onto the shelf from any app without a drag. The
/// system hands over a pasteboard, and it takes the same road a drop does,
/// so files, images, links and text all land the way they would dragged.
/// Files opened with the app (`open -a Vorssaint report.pdf`, a drop on the
/// app icon) arrive through the app delegate and end up here as well.
///
/// No permissions required: the Services menu and open-with are the
/// system's own ways of handing an app what the user picked.
final class ShelfServicesProvider: NSObject {
    static let shared = ShelfServicesProvider()

    private override init() { super.init() }

    /// The selector `NSMessage` in Info.plist names.
    @objc(addToShelf:userData:error:)
    func addToShelf(_ pasteboard: NSPasteboard, userData: String?,
                    error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        _ = ShelfService.shared.receive(pasteboard: pasteboard)
    }

    /// Files the system asked the app to open.
    func open(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects(files.map { $0 as NSURL })
        _ = ShelfService.shared.receive(pasteboard: pasteboard)
    }
}
