// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Sends the pointer to the centre of the next display on a shortcut, in the
/// same order Next display cycles through. Warping the pointer needs no
/// permission.
final class PointerDisplayService: ObservableObject {
    static let shared = PointerDisplayService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 80)

    private init() {
        hotkey.onPress = { [weak self] in self?.moveToNextDisplay() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.windowLayout.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.pointerDisplayEnabled)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled,
                                                  shortcut: GlobalShortcutRole.pointerNextDisplay.savedShortcut,
                                                  storageKey: DefaultsKey.pointerDisplayShortcut)
    }

    func suspend() {
        hotkey.unregister()
    }

    func moveToNextDisplay() {
        let screens = NSScreen.screens
        // NSMouseInRect, like the brightness shortcuts: frame.contains misses
        // a pointer resting on a display's top edge.
        guard let currentIndex = screens.firstIndex(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              let target = WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: currentIndex,
                                                                      frames: screens.map(\.frame),
                                                                      movingForward: true)
        else { return }
        let displayID = screens[target].displayID
        guard displayID != 0 else { return }
        let bounds = CGDisplayBounds(displayID)
        CGWarpMouseCursorPosition(CGPoint(x: bounds.midX, y: bounds.midY))
        // Without this the next physical movement can snap the pointer back
        // to where it was before the warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
