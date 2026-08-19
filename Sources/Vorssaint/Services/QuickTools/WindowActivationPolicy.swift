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

/// The app is normally accessory only, with no Dock icon and no place in
/// Command Tab. While a user-facing window needs to remain reachable it becomes
/// a regular app, then returns to its normal policy after the last one closes.
enum WindowActivationPolicy {
    private static var retention = WindowActivationRetention()
    private static var promoted = false

    static func retain() {
        _ = retention.retain()
        guard !promoted, NSApp.activationPolicy() != .regular else { return }
        promoted = NSApp.setActivationPolicy(.regular)
    }

    static func release() {
        guard retention.release(), promoted else { return }
        if NSApp.setActivationPolicy(.accessory) {
            promoted = false
        }
    }
}
