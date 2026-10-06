// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// What one key press asks of an application: put it away, or bring it back.
///
/// Both halves are `NSRunningApplication` calls the tree already makes — the
/// Dock click hides at `DockClickService.commit(_:)`, the switcher unhides at
/// `WindowActivator`. What no caller had was the decision of *which* of the
/// two a press means, and that decision is the whole of this shortcut.
enum AppToggleAction: Equatable {
    case hide
    case activate
}

/// The decision behind the Finder key, kept free of AppKit so the test
/// harness compiles it on its own.
enum AppToggleSupport {
    /// Hide what is showing, bring back what is away.
    ///
    /// Read from the live `isHidden` rather than from a remembered flag. A
    /// remembered flag goes stale the moment Finder is unhidden from the Dock
    /// or a script, and the next press would then hide an app the person
    /// could already see.
    static func nextAction(isHidden: Bool) -> AppToggleAction {
        isHidden ? .activate : .hide
    }
}