// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class TouchBarService: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarService()

    private static let volumeItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.volume")

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
        bar.defaultItemIdentifiers = [Self.volumeItemIdentifier]
        return bar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == Self.volumeItemIdentifier else { return nil }

        let item = NSSliderTouchBarItem(identifier: identifier)
        item.label = "Volume"
        item.slider.minValue = 0
        item.slider.maxValue = 1
        item.slider.doubleValue = AppVolumeMixer.shared.systemOutputVolume ?? 0
        item.slider.target = self
        item.slider.action = #selector(volumeChanged(_:))
        return item
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        AppVolumeMixer.shared.setCurrentOutputVolume(sender.doubleValue)
    }

}
