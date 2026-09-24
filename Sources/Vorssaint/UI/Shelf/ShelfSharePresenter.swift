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
    private var completion: ((Bool) -> Void)?

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
        picker = nil
        let completion = self.completion
        self.completion = nil
        if service != nil { NSApp.activate(ignoringOtherApps: true) }
        completion?(service != nil)
    }

    private func makePicker(for urls: [URL]) -> NSSharingServicePicker {
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = self
        self.picker = picker
        completion = nil
        return picker
    }
}
