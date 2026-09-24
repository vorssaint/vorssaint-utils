// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

private final class TestSettingsWindow: SettingsWindow {
    var testIsKeyWindow = true

    override var isKeyWindow: Bool { testIsKeyWindow }
}

enum SettingsWindowTests {
    static func run(expect: (Bool, String) -> Void) {
        let app = NSApplication.shared
        let defaults = UserDefaults.standard
        let keys = [DefaultsKey.mouseButtonShortcutsEnabled, DefaultsKey.mouseSpacesGestureEnabled,
                    AppFeature.radialMenu.availabilityKey, AppFeature.scrollInverter.availabilityKey]
        let previous = keys.map { defaults.object(forKey: $0) }
        for key in keys { defaults.set(false, forKey: key) }
        defaults.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
        let previousMenu = app.mainMenu
        let window = TestSettingsWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200),
                                        styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.router = SettingsRouter()
        defer {
            window.close()
            app.mainMenu = previousMenu
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }

        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem())
        mainMenu.items[0].submenu = NSMenu(title: "Test")
        let host = NSMenuItem()
        let navigationMenu = SettingsWindow.navigationMenu(language: .enUS)
        host.submenu = navigationMenu
        mainMenu.addItem(host)
        app.mainMenu = mainMenu
        expect(window.isKeyWindow, "Settings navigation fixture has a key window")

        let back = navigationMenu.items[0]
        let forward = navigationMenu.items[1]
        expect(back.target == nil && forward.target == nil,
               "Settings navigation menu uses the key window's responder chain")
        expect(!window.validateMenuItem(back) && !window.validateMenuItem(forward),
               "Settings history commands are disabled before any page visits")
        window.router.page = .about
        window.router.page = .mouse
        expect(window.validateMenuItem(back) && !window.validateMenuItem(forward),
               "Mouse and Trackpad enables Back to the preceding page")

        // The production items remain targetless; direct them explicitly because this
        // isolated fixture deliberately has no active application's responder chain.
        app.sendAction(back.action!, to: window, from: back)
        expect(window.router.page == .about,
               "a Back menu action navigates from Mouse and Trackpad")
        app.sendAction(forward.action!, to: window, from: forward)
        expect(window.router.page == .mouse,
               "a Forward menu action restores Mouse and Trackpad")

        func pressKey(_ item: NSMenuItem, keyCode: UInt16) {
            let character = item.keyEquivalent
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: character, charactersIgnoringModifiers: character,
                                        isARepeat: false, keyCode: keyCode)!
            expect(mainMenu.performKeyEquivalent(with: event),
                   "Settings resolves the Command-\(character) navigation shortcut")
            app.sendAction(item.action!, to: window, from: item)
        }
        pressKey(back, keyCode: 33)
        expect(window.router.page == .about, "a driver-generated Back shortcut navigates Settings")
        pressKey(forward, keyCode: 30)
        expect(window.router.page == .mouse, "a driver-generated Forward shortcut navigates Settings")

        func mouseEvent(_ type: CGEventType, button: Int64) {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero,
                                mouseButton: .center)!
            event.setIntegerValueField(.mouseEventButtonNumber, value: button)
            window.sendEvent(NSEvent(cgEvent: event)!)
        }
        mouseEvent(.otherMouseDown, button: 3)
        expect(window.router.page == .about, "a raw Back side button navigates Settings")
        mouseEvent(.otherMouseDragged, button: 3)
        mouseEvent(.otherMouseUp, button: 3)
        expect(window.router.page == .about, "Back drag and release do not navigate a second time")
        mouseEvent(.otherMouseDown, button: 4)
        mouseEvent(.otherMouseUp, button: 4)
        expect(window.router.page == .mouse, "a raw Forward side button restores the next page")

        window.isMouseButtonCaptureActive = { true }
        expect(!window.validateMenuItem(back), "shortcut capture disables Settings history commands")
        window.goBack(nil)
        mouseEvent(.otherMouseDown, button: 3)
        mouseEvent(.otherMouseUp, button: 3)
        expect(window.router.page == .mouse, "shortcut capture blocks both command and raw-button navigation")
        window.isMouseButtonCaptureActive = { false }
        window.testIsKeyWindow = false
        window.goBack(nil)
        expect(!window.validateMenuItem(back) && window.router.page == .mouse,
               "an unfocused Settings window cannot navigate through a command")

        for language in AppLanguage.allCases {
            let strings = SettingsNavigationStrings.localized(language)
            expect(!strings.go.isEmpty && !strings.back.isEmpty && !strings.forward.isEmpty,
                   "Settings navigation menu is translated for \(language.rawValue)")
        }
    }
}
