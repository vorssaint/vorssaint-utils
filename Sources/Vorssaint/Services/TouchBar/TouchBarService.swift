// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class TouchBarService: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarService()

    private static let keepAwakeItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.keep-awake")
    private static let micMuteItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.mic-mute")
    private static let clipboardItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.clipboard")

    private(set) var isActive = false
    private(set) var touchBar: NSTouchBar?

    private weak var keepAwakeButton: NSButton?
    private weak var micMuteButton: NSButton?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()

        KeepAwakeManager.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateKeepAwakeButton()
            }
            .store(in: &cancellables)

        MicMuteService.shared.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMicMuteButton()
            }
            .store(in: &cancellables)
    }

    func syncWithPreferences() {
        let shouldBeActive = AppFeature.touchBar.isAvailable
            && TouchBarHardware.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.touchBarEnabled)

        isActive = shouldBeActive

        if shouldBeActive {
            touchBar = makeTouchBar()
        } else {
            touchBar = nil
        }
    }

    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = TouchBarControl.visibleOrdered.map { control in
            switch control {
            case .keepAwake:
                return Self.keepAwakeItemIdentifier
            case .micMute:
                return Self.micMuteItemIdentifier
            case .clipboard:
                return Self.clipboardItemIdentifier
            }
        }
        return bar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.keepAwakeItemIdentifier:
            return makeKeepAwakeItem(identifier: identifier)

        case Self.micMuteItemIdentifier:
            return makeMicMuteItem(identifier: identifier)

        case Self.clipboardItemIdentifier:
            return makeClipboardItem(identifier: identifier)

        default:
            return nil
        }
    }

    private func makeClipboardItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "Clipboard"
            ) ?? NSImage(),
            target: self,
            action: #selector(toggleClipboard(_:))
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        item.view = button
        return item
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

        keepAwakeButton = button
        item.view = button
        return item
    }

    private func makeMicMuteItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: micMuteImage(),
            target: self,
            action: #selector(toggleMicMute(_:))
        )
        button.imagePosition = .imageOnly
        button.isBordered = false

        micMuteButton = button
        item.view = button
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

    private func micMuteImage() -> NSImage {
        let symbol = MicMuteService.shared.isMuted
            ? "mic.slash.fill"
            : "mic.fill"

        return NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Microphone Mute"
        ) ?? NSImage()
    }

    private func updateKeepAwakeButton() {
        keepAwakeButton?.image = keepAwakeImage()
    }

    private func updateMicMuteButton() {
        micMuteButton?.image = micMuteImage()
    }

    @objc private func toggleClipboard(_ sender: NSButton) {
        ClipboardHistoryService.shared.toggleHistoryWindow()
    }

    @objc private func toggleKeepAwake(_ sender: NSButton) {
        KeepAwakeManager.shared.toggle()
    }

    @objc private func toggleMicMute(_ sender: NSButton) {
        MicMuteService.shared.toggle()
    }
}
