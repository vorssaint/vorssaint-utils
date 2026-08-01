// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The app is normally accessory only, with no Dock icon and no place in
/// Command Tab. While an editor window is open it becomes a regular app, so
/// the window is reachable again after clicking away from it.
///
/// Counted in one place because more than one tool opens editors: if each kept
/// its own flag, closing a screenshot editor would drop the app back to
/// accessory while a recording editor was still on screen, and that window
/// would become unreachable.
enum EditorActivationPolicy {
    private static var openEditors = 0
    private static var promoted = false

    static func retain() {
        openEditors += 1
        guard openEditors == 1, NSApp.activationPolicy() != .regular else { return }
        promoted = NSApp.setActivationPolicy(.regular)
    }

    static func release() {
        openEditors = max(0, openEditors - 1)
        guard openEditors == 0, promoted else { return }
        NSApp.setActivationPolicy(.accessory)
        promoted = false
    }
}
