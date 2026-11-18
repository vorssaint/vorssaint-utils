// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// The hand-back of ⌘Tab to macOS while a game draws its own exclusive full
/// screen (issue #2636), decided from window-server snapshots alone.
enum SwitcherExclusiveFullscreenTests {
    static func run(_ suite: TestSuite) {
        suite.run("SwitcherExclusiveFullscreen") {
            let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
            let second = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
            let displays = [display, second]
            let game: pid_t = 400, dock: pid_t = 300, own: pid_t = 500
            let shielding = Int(CGShieldingWindowLevel())

            func window(_ number: CGWindowID, pid: pid_t, layer: Int, alpha: Double = 1,
                        bounds: CGRect) -> NotchAppFullscreen.WindowInfo {
                NotchAppFullscreen.WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
            }
            func raises(_ windows: [NotchAppFullscreen.WindowInfo], frontmost: pid_t? = game) -> Bool {
                SwitcherSupport.frontmostAppRaisesFullscreen(windows: windows, frontmostPID: frontmost,
                                                             ownPID: own, displays: displays)
            }

            let exclusive = window(1, pid: game, layer: shielding, bounds: display)
            let desktopApp = window(2, pid: 200, layer: 0, bounds: CGRect(x: 100, y: 100, width: 1200, height: 800))
            suite.expect(raises([exclusive, desktopApp]),
                         "a frontmost game covering the display at the shielding level hands ⌘Tab back")
            suite.expect(raises([window(1, pid: game, layer: 3, bounds: display.insetBy(dx: 1, dy: 1))]),
                         "any raised level counts, and a point of rounding on each edge still covers")
            suite.expect(raises([window(1, pid: game, layer: shielding, bounds: second)]),
                         "covering a secondary display alone counts")

            suite.expect(!raises([window(1, pid: game, layer: 0, bounds: display)]),
                         "a borderless or macOS full-screen window at level 0 keeps the switcher")
            suite.expect(!raises([window(1, pid: game, layer: shielding,
                                         bounds: CGRect(x: 800, y: 600, width: 400, height: 80))]),
                         "a raised window covering part of a display, such as a tooltip, keeps the switcher")
            suite.expect(!raises([window(1, pid: dock, layer: 20, bounds: display), window(2, pid: game, layer: 0, bounds: display)]),
                         "a window another app raises over the display, as the Dock does, is not the game's")
            suite.expect(!raises([window(1, pid: game, layer: shielding, alpha: 0, bounds: display)]),
                         "an invisible raised window keeps the switcher")
            suite.expect(!raises([exclusive], frontmost: 200) && !raises([exclusive], frontmost: nil),
                         "only the frontmost app's window counts")
            suite.expect(!raises([window(1, pid: own, layer: shielding, bounds: display)], frontmost: own),
                         "Vorssaint's own overlays never hand the keys back")

            let liveEntries = [
                LiveSystemShortcut(id: 1, shortcut: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.command]), enabled: true),
                LiveSystemShortcut(id: 2, shortcut: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.command, .shift]), enabled: true),
                LiveSystemShortcut(id: 27, shortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.command]), enabled: true),
                LiveSystemShortcut(id: 220, shortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.command, .shift]), enabled: true),
            ]
            suite.expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true, secureInputEnabled: false,
                                                         exclusiveFullscreen: true,
                                                         appsShortcut: .switcherDefault,
                                                         windowShortcut: .switcherWindowDefault,
                                                         liveEntries: liveEntries).isEmpty,
                         "while a game owns the display, ⌘Tab and ⌘` stay with macOS")
            suite.expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true, secureInputEnabled: false,
                                                         exclusiveFullscreen: false,
                                                         appsShortcut: .switcherDefault,
                                                         windowShortcut: .switcherWindowDefault,
                                                         liveEntries: liveEntries) == [1, 2, 27, 220],
                         "once the game's full screen ends the switcher takes its four ids again")

            // The decision reaches macOS only through the live take-over; the
            // tap, the Carbon stand-ins and the session start all follow it.
            let source = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Switcher/AppSwitcher.swift",
                                      encoding: .utf8)) ?? ""
            suite.expect(source.contains("exclusiveFullscreen: yieldsToExclusiveFullscreen")
                             && source.components(separatedBy: "!yieldsToExclusiveFullscreen").count >= 3
                             && source.contains("guard !routeYieldsToExclusiveFullscreen,")
                             && source.contains("reason: \"exclusive_fullscreen\""),
                         "the live take-over, the tap's routing, the Carbon stand-ins and the session start all follow the hand-back")
        }
    }
}
