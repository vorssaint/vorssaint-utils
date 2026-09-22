// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DockPreviewFrameRestorationTests {
    struct SwitcherItem {
        let pid: Int = 10
        let windowOwnerPID: Int = 11
        let windowID: UInt32? = 12
    }
    struct Screen {
        let id: UInt32 = 1
        var frame: CGRect
        var visibleFrame: CGRect
    }
    enum NSWorkspace {
        static let shared = Workspace()
        final class Workspace { var frontmostApplication: App? = App() }
        struct App { var processIdentifier = 10 }
    }
    enum WindowActivator {
        static var focused: UInt32? = 12
        static var restores = 0
        static func focusedWindowID(for pid: Int) -> UInt32? { focused }
        static func restoreFrameAfterDockHold(_ item: SwitcherItem, original: CGRect, heldVisibleFrame: CGRect) {
            restores += 1
        }
    }
    static var currentScreen: Screen?
    static func screen(_ id: UInt32) -> Screen? { currentScreen }
    static func axFrame(_ rect: CGRect) -> CGRect { rect }

    static func run(_ suite: TestSuite) {
        let original = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let bottom = CGRect(x: 0, y: 25, width: 1440, height: 810)
        let left = CGRect(x: 65, y: 25, width: 1375, height: 875)
        let right = CGRect(x: 0, y: 25, width: 1375, height: 875)
        for visible in [bottom, left, right] {
            suite.expect(DockPreviewFrameSupport.wasConstrained(visible, original: original, visibleFrame: visible),
                         "a maximized window recovers from a bottom or side Dock constraint")
        }
        let custom = CGRect(x: 100, y: 400, width: 700, height: 500)
        suite.expect(DockPreviewFrameSupport.wasConstrained(custom.intersection(bottom), original: custom,
                                                           visibleFrame: bottom),
                     "a partially clipped custom size can be restored without maximizing it")
        suite.expect(DockPreviewFrameSupport.wasConstrained(custom.offsetBy(dx: 0, dy: -65), original: custom,
                                                           visibleFrame: bottom),
                     "a window moved above the Dock keeps its original position and size")
        for actual in [original, CGRect(x: 100, y: 100, width: 600, height: 400),
                       bottom.offsetBy(dx: 20, dy: 0), .zero] {
            suite.expect(!DockPreviewFrameSupport.wasConstrained(actual, original: original, visibleFrame: bottom),
                         "unchanged, manually moved, resized and missing windows are left alone")
        }
        suite.expect(!DockPreviewFrameSupport.wasConstrained(bottom, original: original, visibleFrame: original),
                     "no window is restored when the Dock did not reduce the work area")
        let secondaryOffset = CGVector(dx: -1440, dy: -900)
        suite.expect(DockPreviewFrameSupport.wasConstrained(
            left.offsetBy(dx: secondaryOffset.dx, dy: secondaryOffset.dy),
            original: original.offsetBy(dx: secondaryOffset.dx, dy: secondaryOffset.dy),
            visibleFrame: left.offsetBy(dx: secondaryOffset.dx, dy: secondaryOffset.dy)),
                     "secondary screens with negative global coordinates preserve their geometry")

        let screen = Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: original)
        currentScreen = Screen(frame: screen.frame, visibleFrame: bottom)
        WindowActivator.restores = 0
        restore(SwitcherItem(), original: original, screen: screen,
                heldVisibleFrame: bottom, isCurrent: { true }, attempt: 0)
        drain(for: 0.2)
        suite.expect(WindowActivator.restores == 0, "activation never restores against the Dock-reduced work area")
        currentScreen = screen
        drain(for: 0.15)
        suite.expect(WindowActivator.restores == 1, "the selected window is restored once the work area recovers")

        for scenario in 0..<4 {
            currentScreen = screen
            WindowActivator.focused = scenario == 0 ? 99 : 12
            if scenario == 1 { currentScreen = nil }
            if scenario == 2 { currentScreen?.frame.size.width = 1280 }
            restore(SwitcherItem(), original: original, screen: screen,
                    heldVisibleFrame: bottom, isCurrent: { scenario != 3 }, attempt: 0)
            drain(for: 0.2)
            suite.expect(WindowActivator.restores == 1,
                         "focus changes, disconnected or reconfigured displays and newer holds cancel restoration")
        }
        WindowActivator.focused = 12
        currentScreen = Screen(frame: screen.frame, visibleFrame: bottom)
        restore(SwitcherItem(), original: original, screen: screen,
                heldVisibleFrame: bottom, isCurrent: { true }, attempt: 15)
        drain(for: 0.1)
        currentScreen = screen
        drain(for: 0.1)
        suite.expect(WindowActivator.restores == 1, "an unrecovered work area has a bounded retry budget")
    }

    private static func drain(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }
}
