// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

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
        let previousKeyWindow = app.keyWindow
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let previousPolicy = app.activationPolicy()
        let window = SettingsWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.router = SettingsRouter()
        defer {
            window.close()
            app.mainMenu = previousMenu
            previousKeyWindow?.makeKey()
            app.setActivationPolicy(previousPolicy)
            previousApplication?.activate(options: [])
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
        app.setActivationPolicy(.accessory)
        // AppKit must dispatch activation events before it has a key-window responder chain.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            app.stop(nil)
            app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                                             modifierFlags: [], timestamp: 0, windowNumber: 0,
                                             context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
        app.run()
        expect(window.isKeyWindow, "Settings navigation fixture has a key window")
        guard window.isKeyWindow else { return }

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

        // This is the menu-command path used when another app's tap consumes the raw click.
        navigationMenu.performActionForItem(at: 0)
        expect(window.router.page == .about,
               "a Back menu action navigates from Mouse and Trackpad through the responder chain")
        navigationMenu.performActionForItem(at: 1)
        expect(window.router.page == .mouse,
               "a Forward menu action restores Mouse and Trackpad")

        func pressKey(_ character: String, keyCode: UInt16) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: character, charactersIgnoringModifiers: character,
                                        isARepeat: false, keyCode: keyCode)!
            expect(mainMenu.performKeyEquivalent(with: event),
                   "Settings resolves the Command-\(character) navigation shortcut")
        }
        pressKey(back.keyEquivalent, keyCode: 33)
        expect(window.router.page == .about, "a driver-generated Back shortcut navigates Settings")
        pressKey(forward.keyEquivalent, keyCode: 30)
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
        window.resignKey()
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
