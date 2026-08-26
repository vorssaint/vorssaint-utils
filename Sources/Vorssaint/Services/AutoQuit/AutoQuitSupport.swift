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

enum AutoQuitSupport {
    private static let hostBundleIdentifierKey = "CrBundleIdentifier"
    /// Some guest-app windows run as generated helper apps outside their
    /// container bundle. These identifiers are the only stable relationship
    /// the host exposes between the helper and the app the user excepted.
    private static let guestWindowHostBundleIdentifier = "com.parallels.desktop.console"
    private static let guestWindowBundleIdentifierPrefix = "com.parallels.winapp."

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

    /// An exception for an installed app also covers UI processes bundled
    /// inside it. Some apps put their main windows in a nested application
    /// with a different identifier, even though the user picked the outer app.
    static func isExcepted(bundleIdentifier: String?,
                           bundleURL: URL?,
                           exceptions: [String]) -> Bool {
        if let bundleIdentifier, exceptions.contains(bundleIdentifier) { return true }
        if let bundleIdentifier,
           bundleIdentifier.hasPrefix(guestWindowBundleIdentifierPrefix),
           exceptions.contains(guestWindowHostBundleIdentifier) {
            return true
        }
        guard var url = bundleURL?.standardizedFileURL.deletingLastPathComponent() else { return false }

        while url.path != "/" {
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
               let containingIdentifier = Bundle(url: url)?.bundleIdentifier,
               exceptions.contains(containingIdentifier) {
                return true
            }
            let parent = url.deletingLastPathComponent()
            guard parent != url else { break }
            url = parent
        }
        return false
    }

    /// Some standalone apps depend on a separate host process and declare that
    /// relationship in their bundle metadata. Quitting the host while one of
    /// those apps is running would close both from a single window close.
    static func hasDependentApplication(hostBundleIdentifier: String?,
                                        applicationBundleURLs: [URL]) -> Bool {
        guard let hostBundleIdentifier, !hostBundleIdentifier.isEmpty else { return false }
        return applicationBundleURLs.contains { bundleURL in
            Bundle(url: bundleURL)?.object(forInfoDictionaryKey: hostBundleIdentifierKey) as? String
                == hostBundleIdentifier
        }
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
