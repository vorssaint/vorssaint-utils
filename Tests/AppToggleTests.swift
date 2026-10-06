// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Finder key, and the strings that name it.
///
/// Two failures are pinned here, both of which look fine on the first press
/// and only misbehave on the second:
///
/// - A key that hides without ever reading `isHidden` cannot be brought
///   back. Finder is unhidden constantly — from the Dock, from a script — and
///   a remembered "we hid it" flag disagrees with reality the first time
///   anyone else touches it.
/// - The role name in the shortcut list and the row title in Settings are one
///   string, not two. Two copies translate independently, and the pair drifts
///   in whichever language someone edits last.
enum AppToggleTests {
    static func run(_ suite: TestSuite) {
        finderKeyDecision(suite)
        finderKeyStaysReversible(suite)
        stringsCoverEveryLanguage(suite)
    }

    /// The decision itself: visible means hide, hidden means bring it back.
    private static func finderKeyDecision(_ suite: TestSuite) {
        suite.expect(AppToggleSupport.nextAction(isHidden: false) == .hide,
                     "a key pressed with Finder showing puts Finder away")
        suite.expect(AppToggleSupport.nextAction(isHidden: true) == .activate,
                     "a key pressed with Finder away brings it back")
    }

    /// Presses in a row, alternating the live state as the real call would.
    /// A toggle that cannot return to where it started is not a toggle.
    private static func finderKeyStaysReversible(_ suite: TestSuite) {
        var hidden = false
        for press in 1...6 {
            let action = AppToggleSupport.nextAction(isHidden: hidden)
            hidden = action == .hide
            suite.expect(hidden == (press % 2 == 1),
                         "press \(press) alternates the Finder key instead of latching one way")
        }

        // Unhidden by something else — the Dock, a script — between presses.
        // A remembered flag would still claim "we hid it" and hide a Finder
        // the person can already see; the live read hides it as asked, which
        // is the only outcome consistent with what is on screen.
        let afterOutsideUnhide = AppToggleSupport.nextAction(isHidden: false)
        suite.expect(afterOutsideUnhide == .hide,
                     "the Finder key reads isHidden live rather than a remembered flag")
    }

    private static func stringsCoverEveryLanguage(_ suite: TestSuite) {
        let english = FinderToggleStrings.localized(.enUS)
        // Exactly two fields. The `.toggleFinder` role name reads `title`
        // rather than carrying a second copy of the same words, so a third
        // field here is the first step of the two drifting apart.
        suite.expect(Set(LocalizationTests.fields(english).keys) == ["title", "caption"],
                     "the Finder toggle has one title and one caption, not a second copy of the name")
        for language in AppLanguage.allCases {
            let strings = FinderToggleStrings.localized(language)
            suite.expect(Set(LocalizationTests.fields(strings).keys) == ["title", "caption"],
                         "\(language.rawValue) fills the same two fields")
            suite.expect(!strings.title.isEmpty && !strings.caption.isEmpty,
                         "the Finder toggle says something in \(language.rawValue)")
            if language != .enUS {
                suite.expect(strings.title != english.title && strings.caption != english.caption,
                             "the Finder toggle is translated in \(language.rawValue)")
            }
        }
    }
}