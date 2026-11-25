// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct WindowActivationRetention {
    private(set) var count = 0

    mutating func retain() -> Bool {
        count += 1
        return count == 1
    }

    mutating func release() -> Bool {
        guard count > 0 else { return false }
        count -= 1
        return count == 0
    }
}

/// Whether the app should be a regular one (Dock icon, place in Command Tab)
/// for the windows it is keeping reachable. The user can turn that off, so
/// Command Tab never offers the app, and its Q never quits it by accident.
enum WindowActivationDecision {
    static func wantsRegular(retainedWindows: Int, showsInAppSwitcher: Bool) -> Bool {
        retainedWindows > 0 && showsInAppSwitcher
    }
}

/// The app is normally accessory only, with no Dock icon and no place in
/// Command Tab. While a user-facing window needs to remain reachable it becomes
/// a regular app, then returns to its normal policy after the last one closes,
/// unless the user chose to keep it out of the Dock and Command Tab.
enum WindowActivationPolicy {
    private static var retention = WindowActivationRetention()
    private static var promoted = false

    static func retain() {
        _ = retention.retain()
        apply()
    }

    static func release() {
        _ = retention.release()
        apply()
    }

    /// Applies a change of the Dock and Command Tab setting to the windows
    /// already open.
    static func preferenceChanged() {
        apply()
    }

    private static func apply() {
        let showsInAppSwitcher = UserDefaults.standard.bool(forKey: DefaultsKey.showInAppSwitcher)
        if WindowActivationDecision.wantsRegular(retainedWindows: retention.count,
                                                 showsInAppSwitcher: showsInAppSwitcher) {
            guard !promoted, NSApp.activationPolicy() != .regular else { return }
            promoted = NSApp.setActivationPolicy(.regular)
        } else if promoted, NSApp.setActivationPolicy(.accessory) {
            promoted = false
        }
    }
}
