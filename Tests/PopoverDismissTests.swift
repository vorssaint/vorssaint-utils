// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// A click outside the panel closes it, unless it landed in content we host
/// out of process (the AirPlay route picker).
enum PopoverDismissContract {
    static func run(_ suite: TestSuite) {
        let click = CGPoint(x: 400, y: 300)
        let picker = PopoverDismissSupport.Window(frame: CGRect(x: 350, y: 250, width: 200, height: 200),
                                                  isVisible: true, ignoresMouseEvents: false)
        let brightnessOverlay = PopoverDismissSupport.Window(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                                             isVisible: true, ignoresMouseEvents: true)
        let hiddenWindow = PopoverDismissSupport.Window(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                                        isVisible: false, ignoresMouseEvents: false)

        suite.expect(PopoverDismissSupport.clickIsInsideOwnWindow(click, windows: [brightnessOverlay, picker]),
                     "a click in the out-of-process route picker keeps the panel open")
        suite.expect(!PopoverDismissSupport.clickIsInsideOwnWindow(click, windows: [brightnessOverlay]),
                     "a full-screen click-through overlay does not keep the panel open")
        suite.expect(!PopoverDismissSupport.clickIsInsideOwnWindow(click, windows: [hiddenWindow]),
                     "a hidden window does not keep the panel open")
        suite.expect(!PopoverDismissSupport.clickIsInsideOwnWindow(CGPoint(x: 10, y: 10), windows: [picker]),
                     "a click outside every window closes the panel")
    }
}
