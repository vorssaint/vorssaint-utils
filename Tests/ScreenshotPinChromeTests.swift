// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScreenshotPinChromeTests {
    @MainActor static func run(_ suite: TestSuite, image: CGImage) {
        let pin = ScreenshotPinWindow(image: image, scale: 2)
        pin.showPin()
        defer { pin.closePin() }
        pin.updateHover(at: CGPoint(x: pin.frame.midX, y: pin.frame.midY))
        let children = pin.childWindows ?? []
        suite.expect(children.count == 4 && children.allSatisfy(\.isVisible),
                     "showing a pin attaches its three control surfaces and feedback surface")
        let controls = children.filter { !$0.ignoresMouseEvents }
        suite.expect(controls.count == 3, "only control surfaces receive clicks; feedback passes them through")
        let initialOrigins = children.map { $0.frame.origin }
        pin.setFrameOrigin(CGPoint(x: pin.frame.minX + 20, y: pin.frame.minY + 10))
        suite.expect(zip(initialOrigins, children).allSatisfy { origin, child in
            abs(child.frame.minX - origin.x - 20) < 1 && abs(child.frame.minY - origin.y - 10) < 1
        }, "all child surfaces track pin movement without drifting")
        let buttons = children.flatMap { buttons(in: $0.contentView) }
        let strings = ScreenshotPinStrings.localized(L10n.shared.language)
        let cursor = buttons.first { $0.accessibilityLabel() == strings.clickThrough }
        cursor?.performClick(nil)
        suite.expect(cursor != nil && pin.ignoresMouseEvents && controls.allSatisfy { !$0.ignoresMouseEvents },
                     "cursor button enables image click-through while controls stay interactive")
        cursor?.performClick(nil)
        suite.expect(!pin.ignoresMouseEvents, "the same cursor button turns click-through off")
        buttons.first { $0.accessibilityLabel() == strings.lock }?.performClick(nil)
        suite.expect(pin.isPositionLocked, "the visible lock button locks position and dimensions")
        buttons.first { $0.accessibilityLabel() == L10n.shared.s.menuClose }?.performClick(nil)
        suite.expect(pin.isClosed && (pin.childWindows ?? []).isEmpty && children.allSatisfy { !$0.isVisible },
                     "the visible close button detaches and hides every child surface")
    }

    private static func buttons(in view: NSView?) -> [NSButton] {
        guard let view else { return [] }
        return (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }
}
