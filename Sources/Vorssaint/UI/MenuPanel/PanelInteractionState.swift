// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Shared hints between the panel content and the AppKit popover host.
final class PanelInteractionState {
    static let shared = PanelInteractionState()

    var viewKeepsPopoverOpen = false

    /// The Settings page of the utility the panel is currently hosting, so the
    /// footer's Settings button lands on it instead of on the general page.
    /// Nil while the panel shows its own lists.
    var hostedSettingsPage: SettingsPage?

    /// A SwiftUI alert or confirmation dialog is presented from the popover.
    /// Closing its parent window underneath the presentation can leave AppKit's
    /// modal state orphaned and make the next panel unresponsive.
    var isPresentingPopoverModal = false

    var preventsPopoverDismissal: Bool {
        isPresentingPopoverModal
            || HomebrewManager.shared.operationStatus?.isActive == true
            || cleanerIsRunning
            || uninstallerIsRunning
    }

    private var cleanerIsRunning: Bool {
        switch JunkCleaner.shared.phase {
        case .scanning, .cleaning: return true
        case .idle, .results, .done: return false
        }
    }

    private var uninstallerIsRunning: Bool {
        switch AppUninstaller.shared.phase {
        case .scanning, .removing: return true
        case .empty, .results, .done: return false
        }
    }

    /// The screen the menu bar icon is on, so the panel caps its height against
    /// that display instead of whichever one happens to be main. Deliberately
    /// not published: the panel reads it while measuring itself, and announcing
    /// a change mid layout would bounce the very height it is capping.
    var anchorScreen: NSScreen?

    private init() {}
}
