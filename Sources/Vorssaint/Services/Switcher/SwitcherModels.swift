// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// One selectable entry in the switcher. Most entries are real user-facing
/// windows; Finder can also appear as an app entry when it has no windows, so
/// the user can still switch to the desktop/menu bar like the system switcher.
struct SwitcherItem: Identifiable, Equatable {
    let id: String
    let title: String
    let appName: String
    let pid: pid_t
    /// The backing CGWindow: thumbnails and AX raising go through it.
    let windowID: CGWindowID?
    let isOnScreen: Bool
    let isMinimized: Bool
    let isFullscreen: Bool
    let frame: CGRect

    /// The window whose thumbnail represents this entry.
    var previewWindowID: CGWindowID? { windowID }

    /// Label shown under the thumbnail; untitled windows fall back to the app name.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    var appIcon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    static func window(id: CGWindowID, title: String, appName: String, pid: pid_t,
                       isOnScreen: Bool, isMinimized: Bool = false,
                       isFullscreen: Bool = false, frame: CGRect) -> SwitcherItem {
        SwitcherItem(id: "w:\(id)", title: title, appName: appName,
                     pid: pid, windowID: id, isOnScreen: isOnScreen,
                     isMinimized: isMinimized, isFullscreen: isFullscreen,
                     frame: frame)
    }

    static func appOnly(appName: String, pid: pid_t) -> SwitcherItem {
        SwitcherItem(id: "a:\(pid)", title: appName, appName: appName,
                     pid: pid, windowID: nil, isOnScreen: false,
                     isMinimized: false, isFullscreen: false, frame: .zero)
    }
}
