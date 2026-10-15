// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScreenshotPinWindowTests {
    @MainActor static func run(_ suite: TestSuite) {
        guard let context = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { suite.expect(false, "pin fixture image"); return }
        let namespace = "com.vorssaint.tests.pin-window-\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: namespace) else { return }
        defer { preferences.removePersistentDomain(forName: namespace) }
        let pin = ScreenshotPinWindow(image: image, scale: 2, preferences: preferences)
        defer { pin.closePin() }
        pin.setOpacity(0.1)
        suite.expectClose(pin.alphaValue, 1, "pin controls retain an opaque window at ten percent image opacity")
        suite.expectClose(pin.displayedImageOpacity, 0.1, "only the image becomes ten percent opaque")
        suite.expectClose(pin.cornerRadius, 10, "pin corners use the fixed ten point default")
        preferences.set(false, forKey: DefaultsKey.screenshotPinRoundedCorners)
        pin.refreshAppearance()
        suite.expectClose(pin.cornerRadius, 0, "disabling rounded corners updates an existing pin")
        preferences.set(true, forKey: DefaultsKey.screenshotPinRoundedCorners)
        pin.refreshAppearance()
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenshotPinRoundedCorners),
                     "the rounded pin preference travels with settings backups")

        pin.setOpacity(0.9)
        pin.setClickThrough(true)
        pin.updateHover(at: CGPoint(x: pin.frame.midX, y: pin.frame.midY))
        suite.expect(pin.ignoresMouseEvents, "click-through releases the image's mouse events")
        suite.expectClose(pin.displayedImageOpacity, 0.25, "hovering a click-through pin dims the image")
        pin.updateHover(at: CGPoint(x: pin.frame.maxX + 10, y: pin.frame.maxY + 10))
        suite.expectClose(pin.displayedImageOpacity, 0.9, "leaving restores the chosen opacity")
        pin.updateHover(at: CGPoint(x: pin.frame.midX, y: pin.frame.midY))
        pin.setOpacity(0.1)
        suite.expectClose(pin.displayedImageOpacity, 0.1, "hover dimming never makes a faint pin more opaque")
        pin.setClickThrough(false)
        suite.expect(!pin.ignoresMouseEvents, "the cursor action restores image interaction")

        let frame = pin.frame
        pin.setPositionLocked(true)
        let wheel = ScreenshotPinGestureTests.Gesture()
        wheel.scroll = 1
        let pinch = ScreenshotPinGestureTests.Gesture()
        pinch.pinch = 0.5
        let surface = pin.contentView as? ScreenshotPinGestureView
        surface?.scrollWheel(with: wheel)
        surface?.magnify(with: pinch)
        if let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: pin.windowNumber, context: nil,
                                       characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124) {
            pin.keyDown(with: arrow)
        }
        suite.expect(pin.frame == frame && !pin.styleMask.contains(.resizable),
                     "locking a production pin freezes arrows, wheel, pinch and native resize")
        wheel.flags = .option
        surface?.scrollWheel(with: wheel)
        suite.expect(pin.chosenOpacity > 0.1, "production locked pins still accept opacity changes")
        pin.setPositionLocked(false)
        surface?.magnify(with: pinch)
        suite.expect(pin.frame.width > frame.width && pin.styleMask.contains(.resizable),
                     "unlocking restores zoom and native edge resizing")
        suite.expectClose(pin.cornerRadius, 10, "zoom does not scale the corner radius")
        suite.expectClose(pin.zoomMultiplier, 1.5, "zoom feedback uses original display points")

        var closed = 0
        pin.onClose = { closed += 1 }
        let drag = ScreenshotPinDragView(pin: pin)
        drag.completeDrag(operation: [], modifiers: [])
        suite.expect(!pin.isClosed, "cancelling or rejecting a file drop keeps the pin")
        drag.completeDrag(operation: .copy, modifiers: .option)
        suite.expect(!pin.isClosed, "Option-dropping a file keeps its pin")
        drag.completeDrag(operation: .copy, modifiers: [])
        pin.closePin()
        suite.expect(pin.isClosed && closed == 1, "a successful ordinary file drop closes its pin once")
        ScreenshotPinFilePromiseTests.run(suite, image: image)
        ScreenshotPinChromeTests.run(suite, image: image)
    }
}
