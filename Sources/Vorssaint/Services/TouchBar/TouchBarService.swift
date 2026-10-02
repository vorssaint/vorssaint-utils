// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class TouchBarService: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarService()

    private static let vorssaintItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.vorssaint")

    private(set) var isActive = false
    private(set) var touchBar: NSTouchBar?

    private override init() {}

    func syncWithPreferences() {
        let shouldBeActive = AppFeature.touchBar.isAvailable
            && TouchBarHardware.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.touchBarEnabled)


        isActive = shouldBeActive

        if shouldBeActive {
            if touchBar == nil {
                touchBar = makeTouchBar()
            }
        } else {
            touchBar = nil
        }
    }

    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.vorssaintItemIdentifier]
        return bar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == Self.vorssaintItemIdentifier else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = NSButton(title: "Vorssaint", target: nil, action: nil)
        return item
    }
}
