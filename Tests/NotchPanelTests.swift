// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The production panel class is compiled here. Creating it deferred neither
/// shows a window nor needs a running application.
enum NotchPanelTests {
    static func run(expect: (Bool, String) -> Void) {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        expect(panel.accessibilitySubrole() == .unknown,
               "the island describes itself as an undescribed borderless overlay, so window managers skip it "
               + "instead of listing a ghost window of this app on the current space")
        expect(panel.accessibilityRole() == .window && panel.isAccessibilityElement(),
               "the island stays an accessible window for assistive technology")
    }
}
