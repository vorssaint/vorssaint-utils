// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

extension Notification.Name {
    /// An AirDrop send chosen from a share menu has sent or was cancelled.
    static let shelfAirDropDidFinish = Notification.Name("VorssaintShelfAirDropDidFinish")
}

/// Opens the system share sheet for shelf files, from the tile menu and from
/// the panel's own button. It holds the picker while the sheet is up, brings
/// the app forward only once a target has actually been chosen (the shelf
/// panel never activates on its own, so a share window would otherwise open
/// behind whatever is in front), and lets the picker go afterwards.
final class ShelfSharePresenter: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private var picker: NSSharingServicePicker?
    private var completion: ((Bool) -> Void)?
    /// The presenters whose AirDrop send has not finished yet. AirDrop's
    /// window belongs to macOS rather than to the app, so the island reads
    /// this to treat a click in it, such as choosing the device, as part of
    /// the send instead of a click away. AirDrop reports through a different
    /// instance than the menu chose, so a send is kept by its presenter.
    private static var sendingPresenters: Set<ObjectIdentifier> = []
    static var isSending: Bool { !sendingPresenters.isEmpty }

    /// Forgets every unfinished send, for a service that never reports back.
    static func forgetSending() { sendingPresenters.removeAll() }

    /// The system's own share menu: AirDrop alongside every other place the
    /// Mac can send files to, kept current by macOS rather than by a list
    /// written here.
    func shareMenuItem(for urls: [URL], title: String) -> NSMenuItem {
        let item = makePicker(for: urls).standardShareMenuItem
        item.title = title
        return item
    }

    /// `completion` reports whether a target was chosen once the sheet
    /// closes. It never runs when there was no window to show the sheet
    /// from, which the result reports as false.
    @discardableResult
    func present(for urls: [URL], from view: NSView, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard view.window != nil else { return false }
        let picker = makePicker(for: urls)
        self.completion = completion
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        return true
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              didChoose service: NSSharingService?) {
        // A late answer from a menu that was already replaced must not take
        // the newer one's completion.
        guard sharingServicePicker === picker else { return }
        picker = nil
        let completion = self.completion
        self.completion = nil
        if let service {
            if Self.isAirDrop(service) { Self.sendingPresenters.insert(ObjectIdentifier(self)) }
            NSApp.activate(ignoringOtherApps: true)
        }
        completion?(service != nil)
    }

    /// Answers AirDrop, so it reports when it has sent or was cancelled.
    /// Every other service keeps the system's own delegate and behaves as
    /// it did before.
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        Self.isAirDrop(sharingService) ? self : nil
    }

    private static func isAirDrop(_ service: NSSharingService) -> Bool {
        service.title == NSSharingService(named: .sendViaAirDrop)?.title
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finishSending()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        finishSending()
    }

    /// A send the island already forgot, because it was closed on purpose,
    /// ends without closing it again.
    private func finishSending() {
        guard Self.sendingPresenters.remove(ObjectIdentifier(self)) != nil else { return }
        NotificationCenter.default.post(name: .shelfAirDropDidFinish, object: nil)
    }

    private func makePicker(for urls: [URL]) -> NSSharingServicePicker {
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = self
        self.picker = picker
        completion = nil
        return picker
    }
}
