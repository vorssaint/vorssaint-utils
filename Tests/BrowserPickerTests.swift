// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BrowserPickerTests {
    static func run(_ suite: TestSuite) {
        BrowserPickerOrderContract.run(suite)
        let installed = ["chrome", "firefox", "safari"]
        let saved = BrowserPickerSupport.encodedOrder(["safari", "chrome", "firefox"])
        suite.expect(BrowserPickerSupport.orderedIDs(available: installed, saved: saved)
                     == ["safari", "chrome", "firefox"], "browser order survives serialization")
        suite.expect(BrowserPickerSupport.orderedIDs(available: installed, saved: "invalid") == installed,
                     "invalid saved browser order falls back to installed order")
        suite.expect(BrowserPickerSupport.orderedIDs(available: installed,
                     saved: "[\"missing\",\"safari\",\"safari\"]") == ["safari", "chrome", "firefox"],
                     "browser ordering removes stale duplicates and appends newly installed browsers")
        suite.expect(BrowserPickerSupport.orderedIDs(available: [], saved: saved).isEmpty,
                     "no browsers produces an empty picker")
        suite.expect(BrowserPickerSupport.hiddenIDs("invalid").isEmpty,
                     "invalid visibility preferences default to showing browsers")
        let screen = CGRect(x: 0, y: 24, width: 1440, height: 876)
        let cursor = CGPoint(x: 600, y: 500)
        let centered = BrowserPickerSupport.windowFrame(browserCount: 5, visibleFrame: screen,
                                                        cursor: cursor, placement: "center")
        suite.expect(centered.size == CGSize(width: 588, height: 123.5),
                     "five enabled browsers match the Small Simple List window-row size")
        suite.expect(centered.midX == screen.midX && centered.midY == screen.midY,
                     "center placement centers the picker in the usable screen")
        let single = BrowserPickerSupport.windowFrame(browserCount: 1, visibleFrame: screen,
                                                      cursor: cursor, placement: "center")
        suite.expect(single.size == CGSize(width: 144, height: 123.5),
                     "one browser uses the small window-row tile and both surface and outer padding")
        let nearby = BrowserPickerSupport.windowFrame(browserCount: 3, visibleFrame: screen,
                                                      cursor: cursor, placement: "cursor")
        suite.expect(nearby.minX == cursor.x + 12 && nearby.maxY == cursor.y - 12,
                     "cursor placement opens just beside and below the pointer")
        for screen in [screen, CGRect(x: -1920, y: -200, width: 1920, height: 1080)] {
            for cursor in [CGPoint(x: screen.minX, y: screen.minY),
                           CGPoint(x: screen.maxX, y: screen.maxY)] {
                let rect = BrowserPickerSupport.windowFrame(browserCount: 5, visibleFrame: screen,
                                                            cursor: cursor, placement: "cursor")
                suite.expect(screen.contains(rect), "cursor picker stays on screen at corners and on secondary displays")
            }
        }
        let overflow = BrowserPickerSupport.windowFrame(browserCount: 30, visibleFrame: screen,
                                                        cursor: cursor, placement: "center")
        suite.expect(screen.contains(overflow) && overflow.height == 123.5,
                     "many browsers fit the screen width and keep compact height")
        suite.expect(BrowserPickerSupport.windowFrame(browserCount: 0, visibleFrame: screen,
                     cursor: cursor, placement: "center").width >= 300,
                     "no enabled browsers leaves space for setup guidance")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.browserPickerHiddenBrowsers)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.browserPickerPlacement),
                     "browser visibility and placement participate in settings backup")
        let savedSwitcherSize = UserDefaults.standard.object(forKey: DefaultsKey.switcherPreviewSize)
        UserDefaults.standard.set("small", forKey: DefaultsKey.switcherPreviewSize)
        let switcherLayout = SwitcherIconRowLayout.compute(appCount: 5, selectedWindowCount: 1,
            screenVisibleFrame: screen, showsShortcutHints: false, tileWidth: SwitcherIconRowLayout.windowTileWidth)
        suite.expect(centered.size == switcherLayout.simpleWindowPanelSize
                     && BrowserPickerSupport.iconSize == SwitcherIconRowLayout.iconSize
                     && BrowserPickerSupport.selectedIconSize == SwitcherIconRowLayout.selectedIconSize,
                     "browser picker matches production Simple List Small sizing and both icon sizes")
        if let savedSwitcherSize { UserDefaults.standard.set(savedSwitcherSize, forKey: DefaultsKey.switcherPreviewSize) }
        else { UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherPreviewSize) }
        suite.expect(BrowserPickerSupport.reorderedIDs(installed, moving: "chrome", onto: "safari")
                     == ["firefox", "safari", "chrome"], "dragging down inserts after the target")
        suite.expect(BrowserPickerSupport.reorderedIDs(installed, moving: "safari", onto: "chrome")
                     == ["safari", "chrome", "firefox"], "dragging up inserts before the target")
        for (source, target) in [("chrome", "chrome"), ("missing", "safari"), ("chrome", "removed")] {
            suite.expect(BrowserPickerSupport.reorderedIDs(installed, moving: source, onto: target) == installed,
                         "self-drops and stale or external identities never corrupt browser order")
        }
        let moved = BrowserPickerSupport.reorderedIDs(installed, moving: "chrome", onto: "safari")
        suite.expect(BrowserPickerSupport.orderedIDs(available: installed,
                     saved: BrowserPickerSupport.encodedOrder(moved)) == moved,
                     "drag order survives persistence and browser rediscovery")
        let urls = ["https://example.com/path?q=hello#anchor", "http://example.com", "file:///tmp/test",
                    "javascript:alert(1)", "mailto:example@example.com", "https:///"].compactMap(URL.init(string:))
        suite.expect(BrowserPickerSupport.webURLs(urls).map(\.absoluteString) == Array(urls.prefix(2)).map(\.absoluteString),
                     "only valid web links reach a browser and their query and fragment stay intact")
        suite.expect(BrowserPickerSupport.isPicker("com.vorssaint.utils")
                     && BrowserPickerSupport.isPicker("com.vorssaint.utils.dev")
                     && !BrowserPickerSupport.isPicker("com.apple.Safari"),
                     "both Vorssaint variants are excluded to prevent link-routing loops")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.browserPickerOrder)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.browserPickerShowNumbers)
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.browserPickerPreviousHandlers),
                     "browser ordering and number visibility are portable, original handlers are machine-specific")
        suite.expect(AppFeature.browserPicker.settingsDestination
                     == FeatureSettingsDestination(.quickTools, sectionAnchor: .browserPicker),
                     "browser picker opens its Quick Tools settings section")
        suite.expect(!GlobalShortcutRole.allCases.contains { $0.feature == .browserPicker }
                     && !SettingsBackupSupport.exportKeys().contains("browserPickerShortcut")
                     && !SettingsBackupSupport.exportKeys().contains("browserPickerShortcutEnabled"),
                     "removed global shortcut has no registration role or exported preferences")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.browserPickerShowNumbers] as? Bool == true,
                     "number labels stay visible by default for existing users")
        for language in AppLanguage.allCases {
            let options = FeatureStrings.browserPickerOptions(language)
            suite.expect(!options.position.isEmpty && !options.cursor.isEmpty && !options.noneEnabled.isEmpty && !options.showNumbers.isEmpty,
                         "browser picker options are localized for \(language)")
            let strings = FeatureStrings.browserPicker(language)
            suite.expect(!strings.title.isEmpty && !strings.defaultHint.isEmpty && !strings.orderHint.isEmpty,
                         "browser picker localizes its setup and sorting instructions for \(language)")
        }
    }
}

enum BrowserPickerOrderContract {
    struct Browser { let id: String }
    class Fixture {
        typealias PickerBrowser = Browser
        var browsers = ["chrome", "safari", "firefox"].map { Browser(id: $0) }
        var hiddenBrowserIDs: Set<String> = []
        var selection = 0
        func updateVisiblePanelFrame() {}
        enum UserDefaults {
            static let suiteName = "com.vorssaint.tests.browser-order"
            static let standard = Foundation.UserDefaults(suiteName: suiteName)!
        }
    }

    static func run(_ suite: TestSuite) {
        let defaults = Fixture.UserDefaults.standard
        defaults.removePersistentDomain(forName: Fixture.UserDefaults.suiteName)
        defer { defaults.removePersistentDomain(forName: Fixture.UserDefaults.suiteName) }
        let service = Service()
        service.selection = 1
        let drag = BrowserPickerMenuDragContract.Handler()
        drag.order = service.browsers.map { BrowserPickerMenuDragContract.Item(rawValue: $0.id) }
        drag.onOrderChange = { service.setBrowserOrder($0.map(\.rawValue)) }
        drag.dragging = .init(rawValue: "safari")
        drag.item = .init(rawValue: "firefox")
        drag.dropEntered(info: .init())
        suite.expect(service.browsers.map(\.id) == ["chrome", "firefox", "safari"],
                     "shared Menu Bar drag delegate moves browser rows immediately on hover")
        suite.expect(drag.performDrop(info: .init()) && drag.dragging == nil,
                     "shared Menu Bar drop completion clears the active browser drag")
        suite.expect(service.selection == 2 && service.visibleBrowsers[service.selection].id == "safari",
                     "drag reorder keeps keyboard selection on the same browser")
        suite.expect(defaults.string(forKey: DefaultsKey.browserPickerOrder)
                     == BrowserPickerSupport.encodedOrder(["chrome", "firefox", "safari"]),
                     "production drag reorder persists the displayed browser order")
        let safari = service.browsers[2]
        service.setBrowserEnabled(safari, enabled: false)
        service.moveBrowser("firefox", onto: "chrome")
        suite.expect(service.visibleBrowsers.map(\.id) == ["firefox", "chrome"]
                     && BrowserPickerSupport.hiddenIDs(defaults.string(forKey: DefaultsKey.browserPickerHiddenBrowsers)!) == ["safari"],
                     "production reorder preserves switches and saved hidden state")
        service.setBrowserEnabled(safari, enabled: true)
        suite.expect(service.visibleBrowsers.map(\.id) == ["firefox", "chrome", "safari"],
                     "reenabling restores the browser at its saved position")
        for browser in service.browsers { service.setBrowserEnabled(browser, enabled: false) }
        suite.expect(service.visibleBrowsers.isEmpty, "turning every switch off does not silently enable a browser")
        service.setBrowserEnabled(safari, enabled: true)
        suite.expect(service.visibleBrowsers.map(\.id) == ["safari"],
                     "visible browsers follow the actual saved switches")
        let before = service.browsers.map(\.id)
        drag.order = service.browsers.map { BrowserPickerMenuDragContract.Item(rawValue: $0.id) }
        drag.dragging = nil
        drag.item = .init(rawValue: "chrome")
        drag.dropEntered(info: .init())
        suite.expect(service.browsers.map(\.id) == before,
                     "a drop without a local Menu Bar drag cannot change browser order")
        service.setBrowserOrder(["chrome", "chrome", "safari"])
        suite.expect(service.browsers.map(\.id) == before, "duplicate browser IDs are rejected")
        service.setBrowserOrder(["chrome", "safari"])
        suite.expect(service.browsers.map(\.id) == before, "stale partial browser orders are rejected")
        service.moveBrowser("uninstalled", onto: "chrome")
        suite.expect(service.browsers.map(\.id) == before, "a browser removed during a drag cannot corrupt the order")
    }
}

/// The real shared Menu Bar drop methods run against the browser order binding.
enum BrowserPickerMenuDragContract {
    struct Item: RawRepresentable, Hashable { let rawValue: String }
    class Fixture {
        struct DropInfo {}
        var item = Item(rawValue: "")
        var dragging: Item?
        var onOrderChange: (([Item]) -> Void)?
        var order: [Item] = [] { didSet { onOrderChange?(order) } }
    }
}
