// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Exercise the production toggle without changing any real window or setting.
enum WindowStageManagerMaximizerTests {
    struct Screen { var windowLayoutVisibleFrame: CGRect }
    struct ClickTarget { let window = 1; let windowID: CGWindowID = 1 }

    class Fixture {
        var originalFrames: [CGWindowID: AXFrame] = [:]
        var maximizedFrames: [CGWindowID: AXFrame] = [:]
        let frameTolerance: CGFloat = 4
        let menuBarScreenTopY: CGFloat = 900
        var current = AXFrame(origin: CGPoint(x: 250, y: 180), size: CGSize(width: 600, height: 450))
        var screen = Screen(windowLayoutVisibleFrame: CGRect(x: 75, y: 0, width: 1365, height: 875))
        var acceptsChange = true
        func frame(of window: Int) -> AXFrame? { current }
        func bestScreen(for frame: AXFrame) -> Screen? { screen }
        func changeFrame(to frame: AXFrame, of target: ClickTarget,
                         completion: @escaping (Bool) -> Void) -> Bool {
            guard acceptsChange else { return false }
            current = frame
            completion(true)
            return true
        }
    }

    static func run(_ suite: TestSuite) {
        let host = Host()
        let original = host.current
        let target = ClickTarget()
        suite.expect(host.toggle(target) && host.current.origin == CGPoint(x: 75, y: 25)
                && host.current.size == CGSize(width: 1365, height: 875),
                     "the green button uses the Stage Manager layout frame in AX coordinates")
        host.screen.windowLayoutVisibleFrame = CGRect(x: 136, y: 0, width: 1304, height: 875)
        suite.expect(host.toggle(target) && host.current == original
                && host.originalFrames.isEmpty && host.maximizedFrames.isEmpty,
                     "the second green click restores the original after a previously covered strip becomes measurable")
        suite.expect(host.toggle(target) && host.current.origin.x == 136,
                     "the next maximize uses the newly measured strip")
        host.screen.windowLayoutVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        suite.expect(host.toggle(target) && host.current == original,
                     "turning Stage Manager off between green clicks still restores the original")
        let manual = AXFrame(origin: CGPoint(x: 400, y: 200), size: CGSize(width: 500, height: 400))
        _ = host.toggle(target)
        host.current = manual
        suite.expect(host.toggle(target) && host.originalFrames[target.windowID] == manual
                && host.toggle(target) && host.current == manual,
                     "a manual resize starts a new maximize/restore pair")
        host.acceptsChange = false
        suite.expect(!host.toggle(target) && host.originalFrames.isEmpty && host.maximizedFrames.isEmpty,
                     "a rejected maximize leaves no stale restore state")
    }
}
