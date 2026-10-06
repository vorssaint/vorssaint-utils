// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// One key that puts Finder away and brings it back.
///
/// Hiding an application needs no permission: it is the same
/// `NSRunningApplication` call the Dock click makes at
/// `DockClickService.commit(_:)`, and unhiding is the one the switcher makes
/// at `WindowActivator`. What was missing was a key that chose between them,
/// which is `AppToggleSupport`'s whole job.
///
/// Unlike Window Layout's other keys this one does NOT step aside for an app
/// on the Ignore list. It acts on Finder rather than on whatever is in front,
/// so pausing it for an ignored app would refuse the exact press it exists
/// for — the common case is Finder being in front and the person pressing
/// this to get it out of the way.
final class FinderToggleService: ObservableObject {
    static let shared = FinderToggleService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 81)

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.windowLayout.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.toggleFinderEnabled)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled,
                                                  shortcut: GlobalShortcutRole.toggleFinder.savedShortcut,
                                                  storageKey: DefaultsKey.toggleFinderShortcut)
    }

    func suspend() {
        hotkey.unregister()
    }

    /// The decision reads Finder's own `isHidden` rather than a remembered
    /// flag, so unhiding Finder from the Dock or a script cannot leave the
    /// next press hiding an app the person can already see.
    func toggle() {
        guard let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.finderBundleID).first else {
            // Finder is not running, and there is nothing to bring forward.
            NSSound.beep()
            return
        }
        switch AppToggleSupport.nextAction(isHidden: finder.isHidden) {
        case .hide:
            // A refusal leaves Finder where it was, which is the visible
            // answer already; saying so beats a key that looks like it worked.
            if !finder.hide() { NSSound.beep() }
        case .activate:
            if !finder.activate(options: []) { NSSound.beep() }
        }
    }

    private static let finderBundleID = "com.apple.finder"
}
