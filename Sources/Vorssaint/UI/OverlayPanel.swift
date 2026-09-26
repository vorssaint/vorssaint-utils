// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A panel that floats over other apps' windows, such as the Shelf. AppKit
/// describes a non-activating panel as a system dialog, which tiling window
/// managers then track and list on whichever space is current; the borderless
/// overlays they leave alone are undescribed windows. It stays an accessible
/// window for assistive technology.
class OverlayPanel: NSPanel {
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}
