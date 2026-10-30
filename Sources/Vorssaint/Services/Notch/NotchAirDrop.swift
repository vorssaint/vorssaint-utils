// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Sends files straight to AirDrop, without the share menu in between. macOS
/// shows its own recipient picker; receiving is the system's, not an app's.
final class NotchAirDrop: NSObject, NSSharingServiceDelegate {
    static let shared = NotchAirDrop()
    private var service: NSSharingService?

    /// The file URLs a drag carries, when every dragged item is a file.
    /// Promised files (browser downloads in flight) are not on disk yet.
    private func urls(from pasteboard: NSPasteboard) -> [URL] {
        guard !pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) else { return [] }
        let urls = ShelfService.shared.fileURLs(from: pasteboard)
        return urls.count >= (pasteboard.pasteboardItems?.count ?? 0) ? urls : []
    }

    func canSend(_ pasteboard: NSPasteboard) -> Bool {
        let urls = urls(from: pasteboard)
        return !urls.isEmpty && NSSharingService(named: .sendViaAirDrop)?.canPerform(withItems: urls) == true
    }

    @discardableResult
    func send(_ pasteboard: NSPasteboard) -> Bool { send(urls(from: pasteboard)) }

    @discardableResult
    func send(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return false }
        service.delegate = self
        self.service = service
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        return true
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { service = nil }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { service = nil }
}
