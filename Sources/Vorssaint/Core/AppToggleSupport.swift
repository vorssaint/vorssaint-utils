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

    /// What a press of an app row's own key asks for.
    ///
    /// `press` counts the presses of that one row's combination, so the first
    /// one is a launch and only a later one can mean "put it away".
    ///
    /// - A hidden app always activates. This branch is read before the press
    ///   count and before frontmost, and it is what makes the toggle
    ///   reversible at any press count: no sequence of presses can leave a
    ///   running app hidden with no way to call it back.
    /// - A later press hides only what is actually in front. Pressing the key
    ///   for an app the person is not looking at means "bring it here", and
    ///   hiding it instead would swallow the press.
    ///
    /// The rapid double press is why frontmost is not the only guard. A
    /// second press can land before the first has finished activating, when
    /// the app is neither in front nor hidden; "press two means hide" on its
    /// own would then hide something that was never shown.
    static func action(forPress press: Int,
                       isFrontmost: Bool,
                       isHidden: Bool) -> AppToggleAction {
        if isHidden { return .activate }
        if press <= 1 { return .activate }
        return isFrontmost ? .hide : .activate
    }
}
