// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
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
            let panelLevel = NSWindow.Level.statusBar.rawValue

            func window(_ number: CGWindowID, pid: pid_t, layer: Int, alpha: Double = 1,
                        bounds: CGRect) -> NotchAppFullscreen.WindowInfo {
                NotchAppFullscreen.WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
            }
            func raises(_ windows: [NotchAppFullscreen.WindowInfo]?, frontmost: pid_t? = game,
                        frames: [CGRect] = displays) -> Bool? {
                SwitcherSupport.frontmostAppRaisesFullscreen(windows: windows, frontmostPID: frontmost,
                                                             ownPID: own, displays: frames)
            }

            let exclusive = window(1, pid: game, layer: shielding, bounds: display)
            let desktopApp = window(2, pid: 200, layer: 0, bounds: CGRect(x: 100, y: 100, width: 1200, height: 800))
            suite.expect(raises([exclusive, desktopApp]) == true,
                         "a frontmost game covering the display at the shielding level hands ⌘Tab back")
            suite.expect(raises([window(1, pid: game, layer: panelLevel, bounds: display.insetBy(dx: 1, dy: 1))]) == true,
                         "a window at the panel level can cover it even with a point of rounding on each edge")
            suite.expect(raises([window(1, pid: game, layer: shielding, bounds: second)]) == true,
                         "covering a secondary display alone counts")

            suite.expect(raises([window(1, pid: game, layer: 0, bounds: display)]) == false,
                         "a borderless or macOS full-screen window at level 0 keeps the switcher")
            suite.expect(raises([window(1, pid: game, layer: NSWindow.Level.floating.rawValue, bounds: display)]) == false
                             && raises([window(1, pid: game, layer: panelLevel - 1, bounds: display)]) == false,
                         "a window below the panel keeps the switcher even when it covers the whole display")
            suite.expect(raises([window(1, pid: game, layer: shielding,
                                        bounds: CGRect(x: 800, y: 600, width: 400, height: 80))]) == false,
                         "a raised window covering part of a display, such as a tooltip, keeps the switcher")
            suite.expect(raises([window(1, pid: dock, layer: shielding, bounds: display),
                                 window(2, pid: game, layer: 0, bounds: display)]) == false,
                         "a window another app raises over the display, as the Dock does, is not the game's")
            suite.expect(raises([window(1, pid: game, layer: shielding, alpha: 0, bounds: display)]) == false,
                         "an invisible raised window keeps the switcher")
            suite.expect(raises([exclusive], frontmost: 200) == false,
                         "only the frontmost app's window counts")
            suite.expect(raises([window(1, pid: own, layer: shielding, bounds: display)], frontmost: own) == false,
                         "Vorssaint's own overlays never hand the keys back")

            let duringDisplayChange = [
                raises([exclusive]), raises(nil), raises([exclusive], frontmost: nil),
                raises([exclusive], frames: []), raises([exclusive], frames: [.zero]),
                raises([exclusive], frames: [display, .infinite]), raises([exclusive]), raises([])
            ]
            suite.expect(duringDisplayChange == [true, nil, nil, nil, nil, nil, true, false],
                         "incomplete snapshots leave ownership undecided until the game or desktop is visible again")

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
        }
        suite.run("SwitcherExclusiveFullscreenWatch") {
            watchChecks(suite)
        }
    }

    private static func watchChecks(_ suite: TestSuite) {
        let game: pid_t = 400, editor: pid_t = 500
        var frontmost: pid_t? = game
        var reads: [pid_t] = []
        var observations: [Bool] = []
        var pending: ((Bool?) -> Void)?
        let watch = SwitcherExclusiveFullscreenWatch(
            frontmostPID: { frontmost },
            read: { pid, completion in
                suite.expect(pending == nil, "only one window-server read can be in flight")
                reads.append(pid)
                pending = completion
            },
            onObservation: { observations.append($0) })
        defer { watch.stop() }

        func finishRead(_ result: Bool?) {
            guard let completion = pending else {
                suite.expect(false, "expected a window-server read to complete")
                return
            }
            pending = nil
            completion(result)
        }

        watch.start()
        finishRead(false)
        watch.refresh()
        watch.refresh()
        watch.refresh()
        finishRead(true)
        suite.expect(reads == [game, game] && observations == [false, true] && pending == nil,
                     "polls share one read and detect silent entry without opening the switcher")
        watch.refresh()
        finishRead(nil)
        frontmost = nil
        watch.refresh()
        suite.expect(reads.count == 3 && observations == [false, true] && pending == nil,
                     "inconclusive window and foreground reads preserve the native shortcuts")
        frontmost = game
        watch.refresh()
        finishRead(false)
        suite.expect(observations == [false, true, false],
                     "a later poll detects silent exit without any switcher candidates or key press")

        observations.removeAll()
        reads.removeAll()
        watch.refresh()
        frontmost = editor
        finishRead(true)
        suite.expect(observations.isEmpty && reads == [game, editor],
                     "a delayed game result is discarded and the current app is read immediately")
        watch.refresh(environmentChanged: true)
        watch.refresh(environmentChanged: true)
        finishRead(true)
        suite.expect(observations.isEmpty && reads == [game, editor, editor],
                     "a burst of environment changes requests one fresh read even for the same app")
        finishRead(false)
        suite.expect(observations == [false], "only the up-to-date editor result reaches the switcher")

        observations.removeAll()
        reads.removeAll()
        watch.refresh()
        watch.stop()
        watch.start()
        finishRead(true)
        suite.expect(observations.isEmpty && reads == [editor, editor],
                     "a restart on the same app discards the read from before the stop")
        finishRead(false)
        suite.expect(observations == [false], "the restarted monitor delivers the new result")
        watch.refresh()
        watch.stop()
        finishRead(true)
        watch.refresh(environmentChanged: true)
        suite.expect(observations == [false] && reads == [editor, editor, editor] && pending == nil,
                     "a stopped monitor ignores its last result and makes no further reads")
    }
}
