// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class TouchBarService: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarService()

    private static let volumeItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.volume")
    private static let keepAwakeItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.keep-awake")

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
        bar.defaultItemIdentifiers = [
            Self.keepAwakeItemIdentifier,
            Self.volumeItemIdentifier,
        ]
        return bar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.keepAwakeItemIdentifier:
            return makeKeepAwakeItem(identifier: identifier)

        case Self.volumeItemIdentifier:
            return makeVolumeItem(identifier: identifier)

        default:
            return nil
        }
    }

    private func makeKeepAwakeItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: keepAwakeImage(),
            target: self,
            action: #selector(toggleKeepAwake(_:))
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        item.view = button
        return item
    }

    private func makeVolumeItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSSliderTouchBarItem(identifier: identifier)
        item.label = "Volume"
        item.slider.minValue = 0
        item.slider.maxValue = 1
        item.slider.doubleValue = AppVolumeMixer.shared.systemOutputVolume ?? 0
        item.slider.target = self
        item.slider.action = #selector(volumeChanged(_:))
        return item
    }

    private func keepAwakeImage() -> NSImage {
        let symbol = KeepAwakeManager.shared.isActive
            ? "cup.and.saucer.fill"
            : "cup.and.saucer"

        return NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Keep Awake"
        ) ?? NSImage()
    }

    @objc private func toggleKeepAwake(_ sender: NSButton) {
        KeepAwakeManager.shared.toggle()
        sender.image = keepAwakeImage()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        AppVolumeMixer.shared.setCurrentOutputVolume(sender.doubleValue)
    }
}
