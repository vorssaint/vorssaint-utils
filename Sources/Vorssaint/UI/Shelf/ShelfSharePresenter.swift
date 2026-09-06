// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Opens the system share sheet for shelf files, from the tile menu and from
/// the panel's own button. It holds the picker while the sheet is up, brings
/// the app forward only once a target has actually been chosen (the shelf
/// panel never activates on its own, so a share window would otherwise open
/// behind whatever is in front), and lets the picker go afterwards.
final class ShelfSharePresenter: NSObject, NSSharingServicePickerDelegate {
    private var picker: NSSharingServicePicker?

    /// The system's own share menu: AirDrop alongside every other place the
    /// Mac can send files to, kept current by macOS rather than by a list
    /// written here.
    func shareMenuItem(for urls: [URL], title: String) -> NSMenuItem {
        let item = makePicker(for: urls).standardShareMenuItem
        item.title = title
        return item
    }

    func present(for urls: [URL], from view: NSView) {
        guard view.window != nil else { return }
        makePicker(for: urls).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              didChoose service: NSSharingService?) {
        picker = nil
        guard service != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePicker(for urls: [URL]) -> NSSharingServicePicker {
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = self
        self.picker = picker
        return picker
    }
}
