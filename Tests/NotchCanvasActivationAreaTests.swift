// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Every refresh of the island hands its canvas the activation area again.
/// Runs the production method on a view that counts its layout passes; an
/// unchanged area must not force one, since forcing it also runs SwiftUI's
/// pending update inside the refresh.
enum NotchCanvasActivationAreaTests {
    class Layouts: NSView {
        let activationButton = NotchActivationButton()
        var activationRect = CGRect.zero
        var layouts = 0
        override func layout() {
            layouts += 1
            super.layout()
        }
    }

    static func run(_ suite: TestSuite) {
        let canvas = Canvas(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let area = CGRect(x: 40, y: 0, width: 200, height: 32)
        var pressed = 0
        canvas.setActivationArea(area, title: "Open", willPress: {}, activate: {})
        let first = canvas.layouts
        suite.expect(first > 0 && !canvas.activationButton.isHidden && canvas.activationRect == area,
                     "a new activation area lays the canvas out at once")

        canvas.setActivationArea(area, title: "Collapse", willPress: {}, activate: { pressed += 1 })
        canvas.activationButton.invoke()
        suite.expect(canvas.layouts == first && pressed == 1
                     && canvas.activationButton.accessibilityLabel() == "Collapse",
                     "the same area again takes the new title and action without a layout pass")

        canvas.setActivationArea(.zero, title: "", willPress: {}, activate: {})
        suite.expect(canvas.layouts > first && canvas.activationButton.isHidden && canvas.activationRect == .zero,
                     "an emptied area hides the button and lays the canvas out")
    }
}
