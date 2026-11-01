// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind full screen on launch, kept free of AppKit and
/// Accessibility so the harness can pin them down.
enum AutoFullscreenSupport {
    /// The first look waits a moment: most apps create their first window
    /// just after the launch notification arrives.
    static let firstLookDelay: TimeInterval = 0.5
    static let lookInterval: TimeInterval = 0.5
    /// How long after the launch a window may still be put in full screen.
    /// Apps that swap a startup window for their real one (a NAS client, a
    /// launcher) need most of it. Measured from the launch rather than counted
    /// in looks, so an app slow to answer cannot stretch it.
    static let launchWindow: TimeInterval = 15

    /// What one look at the launching app found.
    enum WindowState: Equatable {
        /// No main or focused window yet, only a panel, sheet or splash, or
        /// an app too busy to answer.
        case none
        /// A standard window that macOS can put in full screen.
        case windowed
        /// A standard window whose full screen state cannot be changed.
        case fixed
        case fullScreen
    }

    enum Step: Equatable {
        /// Ask for full screen, then look again to confirm it took.
        case requestFullScreen
        case lookAgain
        case finish
    }

    /// Only ordinary apps the user did not list, and never Vorssaint itself.
    static func shouldWatch(bundleIdentifier: String?,
                            isRegularApp: Bool,
                            isOwnApp: Bool,
                            exceptions: [String]) -> Bool {
        guard isRegularApp, !isOwnApp else { return false }
        guard let bundleIdentifier else { return true }
        return !Defaults.sanitizedBundleIdentifierList(exceptions).contains(bundleIdentifier)
    }

    /// With the built-in display option on, any display that is not built in
    /// skips the launch, which also covers clamshell mode where the external
    /// display is the only one. An unreadable display list skips it as well.
    static func displaysAllow(builtInDisplayOnly: Bool, builtInFlags: [Bool]?) -> Bool {
        guard builtInDisplayOnly else { return true }
        guard let builtInFlags, !builtInFlags.isEmpty else { return false }
        return !KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: builtInFlags)
    }

    /// `elapsed` is the time since the launch. A request is never assumed to
    /// work: some apps ignore it while their first window is still settling,
    /// so the next look confirms it or asks again.
    ///
    /// Entering full screen moves to a new Space, so it only happens while
    /// the app is in front. An app launched in the background (`open -g`, a
    /// helper starting its main app, a login item) keeps being watched in
    /// case it comes forward, and is otherwise left where it is.
    static func nextStep(for state: WindowState, appIsFrontmost: Bool, elapsed: TimeInterval) -> Step {
        switch state {
        case .fullScreen, .fixed:
            return .finish
        case .windowed where appIsFrontmost:
            return .requestFullScreen
        case .windowed, .none:
            return hasTimeLeft(after: elapsed) ? .lookAgain : .finish
        }
    }

    /// Whether another look still fits in the launch window.
    static func hasTimeLeft(after elapsed: TimeInterval) -> Bool {
        elapsed + lookInterval <= launchWindow
    }
}
