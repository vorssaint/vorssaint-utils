// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Production selection methods run against synthetic windows. Key events are
/// inspected in memory, never posted to the desktop or registered as hotkeys.
enum SwitcherAllWindowsTests {
    final class Model {
        var windows: [SwitcherItem] = []
        var selectedIndex = 0
        var sessionScope: SwitcherSessionScope = .allApps
        var userNavigated = false
        var usesIconRowLayout = true
        var simpleMode = false
        var mergeWindowsByApp = false
        var currentSpaceOnly = false
        var usesWindowRow: Bool {
            SwitcherSupport.usesWindowRow(simpleMode: simpleMode,
                                          mergeWindowsByApp: mergeWindowsByApp,
                                          sessionScope: sessionScope)
        }
        func cancelIconRowEdgeHover() {}
    }

    static func run(_ suite: TestSuite) {
        let first = SwitcherItem.window(id: 1, title: "Editor one", appName: "Editor", pid: 10,
                                        isOnScreen: true, frame: .zero)
        let second = SwitcherItem.window(id: 2, title: "Editor two", appName: "Editor", pid: 10,
                                         isOnScreen: true, frame: .zero)
        let browser = SwitcherItem.window(id: 3, title: "Browser", appName: "Browser", pid: 20,
                                          isOnScreen: true, frame: .zero)
        let minimized = SwitcherItem.window(id: 4, title: "Minimized", appName: "Editor", pid: 10,
                                            isOnScreen: false, isMinimized: true, frame: .zero)
        let fullscreen = SwitcherItem.window(id: 5, title: "Fullscreen", appName: "Browser", pid: 20,
                                             isOnScreen: false, isFullscreen: true, frame: .zero)
            .withHiddenSpaceState(true)
        let windowless = SwitcherItem.appOnly(appName: "Empty app", pid: 30)
        let items = [first, second, browser, minimized, fullscreen, windowless]
        let expectedIDs = [first, second, browser, minimized, fullscreen].map(\.id)
        let allWindows = SwitcherSupport.windowsForSession(items, scope: .allWindows, frontmostPID: 10)
        suite.expect(allWindows.map(\.id) == expectedIDs,
                     "all windows preserves window order, minimized and fullscreen entries, excluding windowless apps")
        suite.expect(SwitcherSupport.windowsForSession(items, scope: .allApps, frontmostPID: 10).map(\.id)
                     == items.map(\.id), "the existing app shortcut keeps windowless entries")
        suite.expect(SwitcherSupport.windowsForSession(items, scope: .frontmostApp, frontmostPID: 10).map(\.id)
                     == [first.id, second.id, minimized.id], "the existing window shortcut stays within one app")
        suite.expect(SwitcherSupport.windowsForSession([windowless], scope: .allWindows, frontmostPID: 30).isEmpty,
                     "all windows does not open an app-only session when no windows are eligible")
        suite.expect(SwitcherSupport.windowsForSession([browser], scope: .allWindows, frontmostPID: 10).map(\.id)
                     == [browser.id], "all windows never reintroduces windows removed by display, Space or app filters")

        // The first two MRU windows belong to the same app: grouping them would
        // skip the second window, the behavior this shortcut is meant to avoid.
        for (name, iconRow, simple) in [("previews", false, false), ("icons", true, false), ("simple", true, true)] {
            for merge in [false, true] {
                let model = Model()
                model.windows = allWindows
                model.usesIconRowLayout = iconRow
                model.simpleMode = simple
                model.mergeWindowsByApp = merge
                model.sessionScope = .allWindows
                suite.expect(model.initialSelectionIndex(in: allWindows, reversed: false,
                                                         hasForegroundItem: true, frontmostPID: 10) == 1,
                             "\(name), grouped \(merge): a quick press reaches the other window of the same app")
                suite.expect(model.initialSelectionIndex(in: allWindows, reversed: true,
                                                         hasForegroundItem: true, frontmostPID: 10) == 4,
                             "\(name), grouped \(merge): reverse starts at the last eligible window")
                suite.expect(model.initialSelectionIndex(in: allWindows, reversed: false,
                                                         hasForegroundItem: false, frontmostPID: 10) == 0,
                             "\(name), grouped \(merge): a filtered foreground starts at the first visible entry")
                var visited = [String]()
                for _ in 0..<allWindows.count {
                    visited.append(model.windows[model.selectedIndex].id)
                    model.advanceSelection(by: 1)
                }
                suite.expect(visited == expectedIDs && model.selectedIndex == 0,
                             "\(name), grouped \(merge): every window is visited exactly once before wrapping")
                model.advanceSelection(by: -1)
                suite.expect(model.selectedIndex == 4, "\(name): reverse wraps to the last window")
                model.advanceSelection(by: 1, wrapping: false)
                suite.expect(model.selectedIndex == 4, "\(name): key repeat stops at the end")
                model.selectedIndex = 0
                model.advanceSelection(by: -1, wrapping: false)
                suite.expect(model.selectedIndex == 0, "\(name): reverse key repeat stops at the start")
                model.advanceWindowInSelectedApp(by: 1)
                suite.expect(model.selectedIndex == 1, "\(name): the existing window key still cycles the selected app")
                if iconRow && !simple {
                    suite.expect(!model.usesWindowRow,
                                 "Large icons keeps its app icons and selected app's preview strip")
                }
                if simple {
                    suite.expect(model.usesWindowRow, "Simple list shows each window even with app grouping enabled")
                }
            }
        }

        let legacy = Model()
        legacy.windows = [first, second, browser]
        suite.expect(legacy.initialSelectionIndex(in: legacy.windows, reversed: false,
                                                  hasForegroundItem: true, frontmostPID: 10) == 2,
                     "the existing Large icons shortcut still starts at the next app")
        legacy.advanceSelection(by: 1)
        suite.expect(legacy.selectedIndex == 2, "the existing Large icons shortcut still steps by app")
        legacy.advanceSelection(by: 1)
        suite.expect(legacy.selectedIndex == 0, "the existing app shortcut still wraps between apps")
        legacy.sessionScope = .frontmostApp
        legacy.windows = [first, second]
        legacy.advanceSelection(by: 1)
        suite.expect(legacy.selectedIndex == 1, "the current-app shortcut still steps between its windows")
        legacy.windows = [first]
        legacy.selectedIndex = 0
        legacy.advanceSelection(by: 1)
        suite.expect(legacy.selectedIndex == 0, "a single eligible window remains selectable")
        legacy.windows = []
        legacy.advanceSelection(by: 1)
        suite.expect(legacy.selectedIndex == 0, "an empty list never indexes a missing window")

        shortcutChecks(suite)
        preferenceChecks(suite)
    }

    private static func shortcutChecks(_ suite: TestSuite) {
        func event(_ shortcut: GlobalShortcut, reversed: Bool = false) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true)!
            event.flags = shortcut.modifiers.cgFlags
            if reversed { event.flags.insert(.maskShift) }
            return event
        }
        for (shortcut, scope) in [(GlobalShortcut.switcherDefault, SwitcherSessionScope.allApps),
                                  (.switcherWindowDefault, .frontmostApp),
                                  (.switcherAllWindowsDefault, .allWindows)] {
            for reversed in [false, true] {
                let match = SwitcherSupport.shortcutMatch(event: event(shortcut, reversed: reversed),
                                                          appsShortcut: .switcherDefault,
                                                          windowShortcut: .switcherWindowDefault,
                                                          allWindowsShortcut: .switcherAllWindowsDefault)
                suite.expect(match?.scope == scope && match?.shortcut == shortcut && match?.reversed == reversed,
                             "\(scope) routes its own shortcut and reverse direction")
            }
        }
        suite.expect(SwitcherSupport.shortcutMatch(event: event(.switcherAllWindowsDefault),
                                                   appsShortcut: .switcherDefault,
                                                   windowShortcut: .switcherWindowDefault) == nil,
                     "disabled all-windows shortcut leaves Option-Tab untouched")
        for existing in [GlobalShortcut.switcherDefault, .switcherWindowDefault] {
            let match = SwitcherSupport.shortcutMatch(event: event(existing), appsShortcut: .switcherDefault,
                                                      windowShortcut: .switcherWindowDefault,
                                                      allWindowsShortcut: existing)
            suite.expect(match?.scope != .allWindows, "a conflicting imported shortcut preserves the existing binding")
        }
        let custom = GlobalShortcut(keyCode: Int64(kVK_ANSI_J), modifiers: [.control, .option, .shift])
        suite.expect(SwitcherSupport.shortcutMatch(event: event(custom), appsShortcut: .switcherDefault,
                                                   windowShortcut: .switcherWindowDefault,
                                                   allWindowsShortcut: custom)?.reversed == false,
                     "Shift required by a custom shortcut does not reverse its first step")

        let native = [LiveSystemShortcut(id: 1, shortcut: .switcherDefault, enabled: true),
                      LiveSystemShortcut(id: 2, shortcut: GlobalShortcut(keyCode: 48, modifiers: [.command, .shift]), enabled: true)]
        for takeOver in [false, true] {
            for secure in [false, true] {
                let ids = SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: takeOver,
                                                          secureInputEnabled: secure,
                                                          appsShortcut: custom, windowShortcut: custom,
                                                          allWindowsShortcut: .switcherDefault, liveEntries: native)
                suite.expect(ids == (takeOver && !secure ? [1, 2] : []),
                             "all windows suppresses native keys only with takeover enabled and secure input off")
            }
        }
        suite.expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true, secureInputEnabled: false,
                                                      appsShortcut: custom, windowShortcut: custom,
                                                      liveEntries: native).isEmpty,
                     "disabling all windows releases the native combination it used")
    }

    private static func preferenceChecks(_ suite: TestSuite) {
        let role = GlobalShortcutRole.switcherAllWindows
        let defaults = Defaults.registeredDefaults
        suite.expect(defaults[DefaultsKey.switcherAllWindowsShortcutEnabled] as? Bool == false
                     && defaults[role.storageKey] as? String == role.defaultShortcut.storageValue,
                     "all windows is opt-in and has a registered configurable default")
        for disabled in role.requiredEnableKeys {
            suite.expect(!GlobalShortcutRole.activeRoles(isOn: { $0 != disabled }, isAvailable: { _ in true }).contains(role),
                         "all windows releases its key when \(disabled) is off")
        }
        suite.expect(!GlobalShortcutRole.availableRoles(isAvailable: { $0 != .switcher }).contains(role),
                     "uninstalling the switcher also removes the new shortcut")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [role.storageKey, DefaultsKey.switcherAllWindowsShortcutEnabled]),
                     "the shortcut and opt-in travel in settings backups")
        let english = FeatureStrings.switcherShortcuts(.enUS)
        for language in AppLanguage.allCases {
            let text = FeatureStrings.switcherShortcuts(language)
            suite.expect(!text.allWindows.isEmpty && !text.allWindowsCaption.isEmpty,
                         "all windows has complete labels in \(language.rawValue)")
            if language != .enUS {
                suite.expect(text.allWindows != english.allWindows && text.allWindowsCaption != english.allWindowsCaption,
                             "all windows is translated in \(language.rawValue)")
            }
        }
    }
}
