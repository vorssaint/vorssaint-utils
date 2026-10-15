// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The production view receives controlled native events on a real, unordered
/// panel. These checks exercise window geometry, not physical input devices.
enum ScreenshotPinGestureTests {
    final class LockableView: ScreenshotPinGestureView {
        override var isPositionLocked: Bool { true }
    }
    final class Gesture: NSEvent {
        var scroll: CGFloat = 0
        var pinch: CGFloat = 0
        var precise = false
        var flags: NSEvent.ModifierFlags = []
        var momentum: NSEvent.Phase = []
        var point = CGPoint(x: 50, y: 25)
        var backingEvent: CGEvent?
        override var scrollingDeltaY: CGFloat { scroll }
        override var magnification: CGFloat { pinch }
        override var hasPreciseScrollingDeltas: Bool { precise }
        override var modifierFlags: NSEvent.ModifierFlags { flags }
        override var momentumPhase: NSEvent.Phase { momentum }
        override var locationInWindow: NSPoint { point }
        override var cgEvent: CGEvent? { backingEvent }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated { runOnMain(suite) }
    }

    @MainActor private static func runOnMain(_ suite: TestSuite) {
        _ = NSApplication.shared
        ScreenshotPinControlsTests.run(suite)
        guard let screen = NSScreen.main else {
            suite.expect(false, "native pin gesture tests require a display")
            return
        }
        let limits = screen.visibleFrame
        let initial = CGRect(x: limits.midX - 100, y: limits.midY - 50,
                             width: 200, height: 100)
        let window = NSPanel(contentRect: initial,
                             styleMask: [.borderless, .nonactivatingPanel, .resizable],
                             backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = CGSize(width: 2, height: 1)
        window.minSize = CGSize(width: 90, height: 60)
        let view = ScreenshotPinGestureView(frame: .zero)
        window.contentView = view
        defer { window.close() }

        let wheel = Gesture()
        wheel.scroll = 1
        view.scrollWheel(with: wheel)
        suite.expectClose(window.frame.width, 206, "one wheel notch zooms the pin by 3%", tol: 0.6)

        window.setFrame(initial, display: false)
        window.alphaValue = 0.7
        wheel.flags = .option
        view.scrollWheel(with: wheel)
        suite.expectClose(window.alphaValue, 0.75, "Option-scroll increases opacity by five points")
        suite.expectClose(window.frame.width, 200, "Option-scroll changes opacity without zooming")

        let pinch = Gesture()
        pinch.pinch = 0.5
        view.magnify(with: pinch)
        suite.expectClose(window.frame.width, 300, "pinching out zooms the pin", tol: 0.6)
        suite.expectClose(window.frame.height, 150, "pinching preserves the image's proportions", tol: 0.6)
        suite.expectClose(window.frame.minX, initial.minX - 25, "pinch anchors the point under the pointer", tol: 0.6)
        suite.expectClose(window.alphaValue, 0.75, "pinching leaves opacity unchanged")

        window.setFrame(initial, display: false)
        pinch.pinch = -0.99
        view.magnify(with: pinch)
        suite.expectClose(window.frame.width, 120, "zoom respects both dimensions of the 90 by 60 minimum", tol: 0.6)
        suite.expectClose(window.frame.height, 60, "minimum zoom keeps the 2:1 aspect ratio", tol: 0.6)

        window.setFrame(initial, display: false)
        pinch.pinch = 100
        view.magnify(with: pinch)
        suite.expect(window.frame.width <= limits.width + 0.6 && window.frame.height <= limits.height + 0.6,
                     "large zooms fit inside the display's usable area: frame=\(window.frame), limits=\(limits)")
        suite.expect(limits.insetBy(dx: -0.6, dy: -0.6).contains(window.frame),
                     "zooming near an edge keeps the entire pin reachable: frame=\(window.frame), limits=\(limits)")

        window.setFrame(initial, display: false)
        wheel.flags = []
        wheel.precise = true
        view.scrollWheel(with: wheel)
        suite.expectClose(window.frame.width, 202.8, "precise trackpad packets use continuous zoom", tol: 1)
        window.setFrame(initial, display: false)
        wheel.scroll = 100
        view.scrollWheel(with: wheel)
        suite.expectClose(window.frame.width, 267.2, "a fast trackpad packet has bounded zoom gain", tol: 1)
        wheel.flags = .option
        wheel.scroll = 1
        window.alphaValue = 0.7
        view.scrollWheel(with: wheel)
        suite.expectClose(window.alphaValue, 0.705, "precise Option-scroll adjusts opacity smoothly")

        window.setFrame(initial, display: false)
        wheel.precise = false
        for momentum: NSEvent.Phase in [.began, .changed, .ended] {
            wheel.momentum = momentum
            for flags: NSEvent.ModifierFlags in [[], .option] {
                wheel.flags = flags
                view.scrollWheel(with: wheel)
                suite.expect(window.frame == initial && window.alphaValue == 0.705,
                             "coasting never changes zoom or opacity after fingers leave the trackpad")
            }
        }
        wheel.momentum = []
        window.ignoresMouseEvents = true
        view.scrollWheel(with: wheel)
        pinch.pinch = 0.5
        view.magnify(with: pinch)
        suite.expect(window.frame == initial && window.alphaValue == 0.705,
                     "click-through pins ignore both wheel and pinch gestures")
        window.ignoresMouseEvents = false

        window.setFrame(initial, display: false)
        wheel.flags = []
        wheel.scroll = 0
        wheel.backingEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                     wheel1: 1, wheel2: 0, wheel3: 0)
        suite.expect(wheel.backingEvent != nil, "a native wheel event is available")
        view.scrollWheel(with: wheel)
        suite.expectClose(window.frame.width, 206, "a remapped wheel can supply its CGEvent line delta", tol: 0.6)

        window.setFrame(initial, display: false)
        wheel.backingEvent = nil
        wheel.scroll = -1
        view.scrollWheel(with: wheel)
        suite.expectClose(window.frame.width, 194.1748, "reverse scrolling zooms out by the reciprocal step", tol: 1)
        suite.expectClose(window.alphaValue, 0.705, "ordinary scrolling never changes opacity")

        window.setFrame(initial, display: false)
        wheel.flags = .option
        for _ in 0..<30 { view.scrollWheel(with: wheel) }
        suite.expectClose(window.alphaValue, 0.1, "opacity supports the approved ten percent minimum")
        wheel.scroll = 1
        for _ in 0..<30 { view.scrollWheel(with: wheel) }
        suite.expectClose(window.alphaValue, 1, "opacity cannot exceed fully opaque")
        suite.expect(window.frame == initial, "changing opacity never resizes or moves the pin")

        wheel.flags = []
        for invalid: CGFloat in [0, .nan, .infinity, -.infinity] {
            wheel.scroll = invalid
            pinch.pinch = invalid
            view.scrollWheel(with: wheel)
            view.magnify(with: pinch)
            suite.expect(window.frame == initial && window.alphaValue == 1,
                         "empty or invalid gestures leave the pin unchanged")
        }
        for invalid: CGFloat in [-1, -2] {
            pinch.pinch = invalid
            view.magnify(with: pinch)
            suite.expect(window.frame == initial, "a nonpositive pinch scale is ignored")
        }
        wheel.scroll = 1
        wheel.point.x = .nan
        view.scrollWheel(with: wheel)
        suite.expect(window.frame == initial, "an invalid pointer position cannot corrupt the window frame")
        wheel.point = CGPoint(x: 50, y: 25)

        let corner = CGRect(x: limits.maxX - 210, y: limits.maxY - 110, width: 200, height: 100)
        window.setFrame(corner, display: false)
        pinch.pinch = 1
        view.magnify(with: pinch)
        suite.expect(limits.insetBy(dx: -0.6, dy: -0.6).contains(window.frame),
                     "zooming a corner pin slides it back inside the display")
        suite.expectClose(window.frame.width, 400, "clamping the position still permits zoom", tol: 0.6)

        window.setFrame(initial, display: false)
        wheel.precise = true
        wheel.scroll = 0.1
        for _ in 0..<60 { view.scrollWheel(with: wheel) }
        suite.expectClose(window.frame.width / window.frame.height, 2,
                          "repeated precise zooms retain the image aspect ratio", tol: 0.02)

        let detached = ScreenshotPinGestureView(frame: .zero)
        detached.scrollWheel(with: wheel)
        detached.magnify(with: pinch)
        suite.expect(detached.window == nil, "closing a pin leaves late gestures harmless")
        suite.expect(!window.isVisible, "gesture checks never show a panel")

        let locked = LockableView(frame: .zero)
        window.contentView = locked
        window.setFrame(initial, display: false)
        wheel.flags = []
        wheel.scroll = 1
        pinch.pinch = 0.5
        locked.scrollWheel(with: wheel)
        locked.magnify(with: pinch)
        suite.expect(window.frame == initial, "a position lock blocks wheel and pinch resizing")
        wheel.flags = .option
        window.alphaValue = 0.5
        locked.scrollWheel(with: wheel)
        suite.expect(window.alphaValue > 0.5, "locking position still permits opacity changes")
    }
}
