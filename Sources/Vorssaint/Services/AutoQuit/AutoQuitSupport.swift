// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Foundation

enum AutoQuitWindowEvent: Equatable {
    case windowDestroyed
    case appHidden
    case appDeactivated
    case appActivated
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
             .appActivated,
             .mainWindowChanged,
             .focusedWindowChanged,
             .windowCreated,
             .windowDeminiaturized,
             .appShown,
             .other:
            return false
        }
    }

    /// Every found user window requires a registered destroy notification.
    /// Accessibility-listed windows set that count directly; window-server
    /// evidence when Accessibility lists none still requires one watch.
    /// An app that has never yet shown any window also retries during its initial
    /// watch window so apps creating windows asynchronously on launch are caught.
    static func needsWindowWatchRetry(registeredWindows: Int,
                                      listedWindows: Int,
                                      foundUserWindow: Bool,
                                      hadPriorWindows: Bool = false) -> Bool {
        if foundUserWindow {
            return registeredWindows < max(listedWindows, 1)
        }
        return !hadPriorWindows && registeredWindows == 0
    }

    /// Whether adding a window notification left the observer watching for it.
    /// Already registered is the ordinary answer, not a failure: every refresh
    /// registers the windows it is already watching again, and counting those
    /// as unwatched would zero the count above on every refresh and leave the
    /// retry firing for as long as the app runs.
    static func isWindowNotificationRegistered(_ result: AXError) -> Bool {
        result == .success || result == .notificationAlreadyRegistered
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

    /// Menu bar and background apps (LSUIElement, LSBackgroundOnly) take a
    /// Dock icon only while a window such as Settings is open. Closing that
    /// window is not quitting the app (issue #1824).
    static func isBackgroundApp(bundleURL: URL?) -> Bool {
        guard let bundleURL, let bundle = Bundle(url: bundleURL) else { return false }
        return ["LSUIElement", "LSBackgroundOnly"].contains { key in
            (bundle.object(forInfoDictionaryKey: key) as? NSNumber)?.boolValue
                ?? (bundle.object(forInfoDictionaryKey: key) as? NSString)?.boolValue
                ?? false
        }
    }

    static func isCommandW(keyCode: Int64, command: Bool, control: Bool) -> Bool {
        keyCode == commandWKeyCode && command && !control
    }

    /// A click Accessibility names as one of these is never a close, wherever
    /// it landed.
    static func isWindowButtonOtherThanClose(subrole: String?) -> Bool {
        guard let subrole else { return false }
        return [kAXMinimizeButtonSubrole, kAXZoomButtonSubrole, kAXFullScreenButtonSubrole].contains(subrole)
    }

    /// Phone is kept as a mandatory quit exception for Continuity calls, but on
    /// macOS builds without Phone.app a locked row would show the raw bundle
    /// id. Hide it from the settings list while leaving protection in place.
    static func shouldDisplayException(bundleID: String, isInstalled: Bool) -> Bool {
        if bundleID == Defaults.phoneBundleIdentifier { return isInstalled }
        return true
    }

    static func visibleExceptions(_ bundleIDs: [String],
                                  isInstalled: (String) -> Bool) -> [String] {
        bundleIDs.filter { shouldDisplayException(bundleID: $0, isInstalled: isInstalled($0)) }
    }

    /// What one window the window server lists says about its app.
    enum WindowServerWindowRole: Equatable {
        /// On screen and visible: the app is still in use.
        case shownOnScreen
        /// A normal window the screen is not showing. It keeps the app only
        /// from another Space; see `offscreenWindowKeepsAppAlive`.
        case normalWindowOffScreen
        /// Says nothing about the app.
        case unrelated
    }

    /// How the window check reads one window of the app, or of a helper that
    /// draws for it. Normal windows sit at layer 0. Before an app is asked to
    /// quit, anything else it shows on screen counts too: a screen recorder's
    /// control bar floating above other apps (layer 3, #2941), a slideshow that
    /// covers the menu bar (#1721, #2013), and an Open panel, which Apple draws
    /// in a service of its own (#1869). Only what is on screen when the check
    /// runs counts there, so a palette already hidden by then still lets it
    /// quit. Nothing watches these windows, so one going away later starts no
    /// check of its own, and the app can stay until a normal window of it
    /// closes again. Deciding whether an app ever had a window keeps reading
    /// normal windows only.
    static func windowServerWindowRole(layer: Int,
                                       alpha: Double,
                                       width: Double,
                                       height: Double,
                                       isOnScreen: Bool,
                                       isAppsOwnWindow: Bool,
                                       countsEverythingShown: Bool) -> WindowServerWindowRole {
        guard alpha > 0, width >= 80, height >= 80 else { return .unrelated }
        if isAppsOwnWindow, layer == 0 {
            return isOnScreen ? .shownOnScreen : .normalWindowOffScreen
        }
        // Below layer 0 are the desktop's own levels, never an app in use.
        guard countsEverythingShown, isOnScreen, layer >= 0 else { return .unrelated }
        return .shownOnScreen
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

    /// Whether the window server's list (`CGWindowListCopyWindowInfo`) still
    /// holds a window of the app at `pid` that the user has. The system
    /// lookups come in as closures so any list can be judged:
    /// `processDrawsForApp` says whether another process draws this app's own
    /// interface, and `windowIsMinimized`, `visibleSpaces` and
    /// `windowSpaces` judge a normal window off screen. A minimized window
    /// sits off screen on the Space in front, exactly like a window the app
    /// hid on close, so only the window server's minimized tag keeps it from
    /// reading as closed when Accessibility cannot see it (issue #3249).
    static func windowListHasUserWindow(_ windows: [[String: Any]],
                                        pid: pid_t,
                                        countsEverythingShown: Bool,
                                        processDrawsForApp: (pid_t) -> Bool,
                                        windowIsMinimized: (CGWindowID) -> Bool,
                                        visibleSpaces: () -> Set<UInt64>?,
                                        windowSpaces: (CGWindowID) -> [UInt64]) -> Bool {
        var shownSpaces: Set<UInt64>?
        var askedForVisibleSpaces = false
        // One answer per process: every window of a process shares it.
        var drawsForApp: [pid_t: Bool] = [:]

        for window in windows {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid || countsEverythingShown,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
            let isOnScreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? (window[kCGWindowIsOnscreen as String] as? Bool)
                ?? false
            let role = windowServerWindowRole(
                layer: layer,
                alpha: (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                width: width,
                height: height,
                isOnScreen: isOnScreen,
                isAppsOwnWindow: ownerPID == pid,
                countsEverythingShown: countsEverythingShown)
            if role == .shownOnScreen {
                if ownerPID == pid { return true }
                if drawsForApp[ownerPID] == nil {
                    drawsForApp[ownerPID] = processDrawsForApp(ownerPID)
                }
                if drawsForApp[ownerPID] == true { return true }
                continue
            }
            guard role == .normalWindowOffScreen,
                  let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            if windowIsMinimized(CGWindowID(windowID)) { return true }
            // Asked once per check, and only when there is an off-screen window
            // to judge: the common case never pays for it.
            if !askedForVisibleSpaces {
                shownSpaces = visibleSpaces()
                askedForVisibleSpaces = true
            }
            let title = window[kCGWindowName as String] as? String ?? ""
            if offscreenWindowKeepsAppAlive(
                windowSpaces: windowSpaces(CGWindowID(windowID)),
                visibleSpaces: shownSpaces,
                hasTitle: !title.isEmpty) {
                return true
            }
        }
        return false
    }
}
