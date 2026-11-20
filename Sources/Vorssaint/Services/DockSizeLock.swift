// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Locks the Dock's size through its `size-immutable` preference, the switch
/// `defaults write com.apple.dock size-immutable -bool true` flips. The
/// preference itself is the state, so a change made in Terminal shows here
/// too and nothing is kept in the app's own preferences.
enum DockSizeLock {
    private static let domain = "com.apple.dock" as CFString
    private static let key = "size-immutable" as CFString

    static var isLocked: Bool {
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.boolValue == true
    }

    /// A management profile owns the value, so writing it would change nothing.
    static var isManaged: Bool { CFPreferencesAppValueIsForced(key, domain) }

    /// Writes the preference, removing it when unlocking so the Dock is back
    /// to its default, then restarts the Dock, which reads it only at launch.
    /// Blocks on the restart, so it runs off the main thread.
    @discardableResult
    static func setLocked(_ locked: Bool) -> Bool {
        CFPreferencesSetAppValue(key, locked ? kCFBooleanTrue : nil, domain)
        guard CFPreferencesAppSynchronize(domain) else { return false }
        // A terminated Dock counts as an unexpected exit, so the system
        // starts it again at once.
        return Shell.run("/usr/bin/killall", ["Dock"]).status == 0
    }

    /// Removing Dock tweaks from the Features hub hands the Dock back its
    /// default, so no lock outlives the switch that controls it. Bindings run
    /// only for an installed feature at launch, so this acts on the removal
    /// itself and never on a lock set in Terminal without the feature.
    static func syncWithAvailability() {
        guard !AppFeature.dockTweaks.isAvailable else { return }
        DispatchQueue.global(qos: .utility).async {
            guard isLocked, !isManaged else { return }
            setLocked(false)
        }
    }
}
