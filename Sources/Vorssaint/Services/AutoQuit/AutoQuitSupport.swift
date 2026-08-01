// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AutoQuitWindowEvent: Equatable {
    case windowDestroyed
    case appHidden
    case appDeactivated
    case mainWindowChanged
    case focusedWindowChanged
    case windowCreated
    case windowDeminiaturized
    case appShown
    case other
}

enum AutoQuitCloseSignal: Equatable {
    case closeButton
    case commandW
    case programmatic
}

enum AutoQuitSupport {
    /// QWERTY position of the W key — only a fallback for when the event carries
    /// no typed character; the service matches the layout-resolved character
    /// first (key codes are positional: 13 types "z" on AZERTY).
    static let commandWKeyCode: Int64 = 13

    static func shouldScheduleWindowCheck(for event: AutoQuitWindowEvent,
                                          hasRecentCloseRequest: Bool) -> Bool {
        switch event {
        case .windowDestroyed:
            return true
        case .appHidden:
            return hasRecentCloseRequest
        case .appDeactivated,
             .mainWindowChanged,
             .focusedWindowChanged,
             .windowCreated,
             .windowDeminiaturized,
             .appShown,
             .other:
            return false
        }
    }

    static func shouldQuitAfterWindowCheck(hadWindows: Bool,
                                           appIsTerminated: Bool,
                                           appIsExcepted: Bool,
                                           appIsHidden: Bool,
                                           hiddenByCloseRequest: Bool,
                                           hasKnownMinimizedWindow: Bool,
                                           hasUserFacingWindow: Bool) -> Bool {
        guard hadWindows, !appIsTerminated, !appIsExcepted else { return false }
        if appIsHidden && !hiddenByCloseRequest { return false }
        if hasKnownMinimizedWindow { return false }
        return !hasUserFacingWindow
    }

    static func isCommandW(keyCode: Int64, command: Bool, control: Bool) -> Bool {
        keyCode == commandWKeyCode && command && !control
    }

    /// Whether a window the screen is not showing still counts as a window the
    /// user has. A window parked on another Space is one swipe away, so it
    /// keeps the app running; a window the app only hid sits on the Space that
    /// is showing right now, and an app that hides its window instead of
    /// destroying it should still quit on close. Accessibility cannot tell the
    /// two apart (both leave the app with no windows at all), the window server
    /// can. Without a Space answer the old rule stands: anything with a title
    /// keeps the app alive.
    static func offscreenWindowKeepsAppAlive(windowSpaces: [UInt64],
                                             visibleSpaces: Set<UInt64>?,
                                             hasTitle: Bool) -> Bool {
        guard let visibleSpaces, !visibleSpaces.isEmpty, !windowSpaces.isEmpty else { return hasTitle }
        return SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: windowSpaces,
                                                     visibleSpaces: visibleSpaces)
    }
}
