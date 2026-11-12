// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum SwitcherRememberedSelectionTests {
    typealias Enumerator = SwitcherFullscreenScopeTests.Enumerator
    typealias Preferences = SwitcherFullscreenScopeTests.Preferences
    typealias Tracker = SwitcherFullscreenScopeTests.Tracker

    enum Selection {
        typealias WindowEnumerator = Enumerator
        typealias UserDefaults = Preferences
        typealias WindowUseTracker = Tracker
    }

    enum WindowEvents {}

    private static func window(
        _ id: CGWindowID,
        pid: pid_t? = nil,
        hiddenSpace: Bool = false,
        fullscreen: Bool = false,
        minimized: Bool = false,
        hiddenApp: Bool = false,
        x: CGFloat = 0
    ) -> SwitcherItem {
        SwitcherItem.window(
            id: id,
            title: "Window \(id)",
            appName: "App \(pid ?? pid_t(id))",
            pid: pid ?? pid_t(id),
            isOnScreen: !hiddenSpace && !minimized && !hiddenApp,
            isAppHidden: hiddenApp,
            isMinimized: minimized,
            isFullscreen: fullscreen,
            frame: CGRect(x: x, y: 0, width: 800, height: 600)).withHiddenSpaceState(hiddenSpace)
    }

    static func run(_ suite: TestSuite) {
        for number in [Int.min, -1, 0, Int.max, Int(UInt32.max) + 1] {
            suite.expect(!WindowEvents.matchesWindowNumber(number, windowID: 1),
                         "an unavailable AppKit window number \(number) safely remains unmatched")
        }
        suite.expect(WindowEvents.matchesWindowNumber(42, windowID: 42),
                     "an allocated AppKit window matches its WindowServer ID")
        suite.expect(!WindowEvents.matchesWindowNumber(42, windowID: 43),
                     "another allocated window remains distinct")
        defer {
            Preferences.standard.values = [:]
            Tracker.shared.history = []
        }
        Preferences.standard.values = [
            DefaultsKey.switcherWindowlessApps: "finder",
            DefaultsKey.switcherCurrentSpaceOnly: true,
            DefaultsKey.switcherShowFullscreenWindows: true,
            DefaultsKey.switcherMinimizedPlacement: "hidden",
            DefaultsKey.switcherTreatHiddenAppsLikeMinimized: true
        ]
        var remembered = Enumerator.WindowList(
            items: [window(1), window(2), window(3, hiddenSpace: true, fullscreen: true),
                    window(4, hiddenSpace: true, fullscreen: true), window(5, minimized: true),
                    window(6, hiddenApp: true), .appOnly(appName: "Finder", pid: 7),
                    .appOnly(appName: "Other", pid: 8)],
            sourceItems: [])
        remembered.nativeFullscreenWindowIDs = [3]
        remembered.bundleIdentifiers = [7: Defaults.finderBundleIdentifier, 8: "test.other"]
        func select(
            scope: SwitcherSessionScope = .allApps,
            frontmostPID: pid_t = 1,
            focused: CGWindowID? = 1,
            display: Enumerator.DisplayScope? = nil
        ) -> Enumerator.WindowList {
            Selection.select(
                remembered: remembered,
                scope: scope,
                frontmostPID: frontmostPID,
                focusedWindowID: focused,
                displayScope: display)
        }
        let original = select()
        suite.expect(original.items.map(\.id) == ["w:1", "w:2", "w:3", "a:7"],
                     "remembered windows retain desktop, native fullscreen, minimized, hidden-app and Finder rules")
        Preferences.standard.values[DefaultsKey.switcherAppRules] = ["test.other": "showWithoutWindows"]
        suite.expect(select().items.contains { $0.pid == 8 }, "a windowless per-app override applies at shortcut press")
        Preferences.standard.values[DefaultsKey.switcherAppRules] = [Defaults.finderBundleIdentifier: "hidden"]
        suite.expect(!select().items.contains { $0.pid == 7 }, "a newly hidden app is filtered from remembered results")
        Preferences.standard.values = [DefaultsKey.switcherWindowlessApps: "all"]
        remembered = Enumerator.WindowList(items: [window(1), window(2), window(3)], sourceItems: [])
        Tracker.shared.history = [3, 1, 2]
        suite.expect(select().items.compactMap(\.windowID) == [1, 3, 2],
                     "live recent-use history sorts the remembered list before selecting the next window")
        Tracker.shared.history = [2, 1, 3]
        suite.expect(select().items.compactMap(\.windowID) == [1, 2, 3],
                     "a later shortcut sees focus changes made since discovery")
        suite.expect(original.items.map(\.id) == ["w:1", "w:2", "w:3", "a:7"],
                     "background changes preserve the entries of a captured session")
        remembered = Enumerator.WindowList(items: [window(1), window(2, x: 1000)], sourceItems: [])
        let displays = Enumerator.DisplayScope(
            bounds: [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)],
            targetIndex: 1)
        let onDisplay = select(display: displays)
        suite.expect(onDisplay.items.map(\.id) == ["w:2"] && onDisplay.sourceItems.contains { $0.windowID == 1 },
                     "display filtering retains the foreground source for activation")
        remembered = Enumerator.WindowList(items: [window(1), window(2, pid: 1), window(3)], sourceItems: [])
        Preferences.standard.values[DefaultsKey.switcherMergeTabs] = true
        suite.expect(select().items.count == 2, "merged sessions show one representative per app")
        suite.expect(select(scope: .frontmostApp).items.compactMap(\.windowID) == [1, 2],
                     "the front-app shortcut retains its individual windows")
        Preferences.standard.values[DefaultsKey.switcherSimpleMode] = true
        suite.expect(Set(select().items.compactMap(\.windowID)) == [1, 2, 3],
                     "simple grouped mode retains backing windows for navigation")
        Preferences.standard.values = [:]
        remembered = Enumerator.WindowList(items: (1...80).map { window(CGWindowID($0), pid: 1) } + [window(300)], sourceItems: [])
        let capped = select()
        suite.expect(capped.items.count == 48 && capped.items.contains { $0.pid == 300 },
                     "the visible cap reserves an entry for another app on a crowded desktop")
    }
}
