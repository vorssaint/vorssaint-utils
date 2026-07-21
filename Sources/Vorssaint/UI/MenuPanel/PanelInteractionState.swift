// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Shared hints between the panel content and the AppKit popover host.
final class PanelInteractionState: ObservableObject {
    static let shared = PanelInteractionState()

    @Published var keepsPopoverOpen = false

    /// The screen the menu bar icon is on, so the panel caps its height against
    /// that display instead of whichever one happens to be main. Deliberately
    /// not published: the panel reads it while measuring itself, and announcing
    /// a change mid layout would bounce the very height it is capping.
    var anchorScreen: NSScreen?

    private init() {}
}
