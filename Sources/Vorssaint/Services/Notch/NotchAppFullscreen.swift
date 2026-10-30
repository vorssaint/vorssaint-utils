// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Full screen an app draws on its own, without a macOS full-screen Space.
/// Games built on GLFW or SDL raise one borderless window over the menu bar
/// on the current desktop, so Space queries never report them. Apps like VLC
/// fill the display with a normal-level window and hide the menu bar themselves.
enum NotchAppFullscreen {
    struct WindowInfo: Equatable {
        let number: CGWindowID
        let ownerPID: pid_t
        let layer: Int
        let alpha: Double
        let bounds: CGRect
    }

    /// Displays an app covers with its own full screen, judged per display.
    /// `windows` run front to back. The app in front on a display owns its
    /// topmost visible level 0 window, so a window of another app, or one
    /// the Dock raises over the display, never counts. That app covers the
    /// display with a window raised above normal windows (the frontmost app
    /// counts even with no level 0 window at all, as games), or with a level 0
    /// window it hid the menu bar for. A zoomed window under a menu bar the
    /// user auto-hides keeps the island. Only the frontmost app sets the
    /// presentation options, so a level 0 window is confirmed while its app
    /// is frontmost and stays so, by window number, while it still covers
    /// the display in front. That keeps it covered after focus moves to
    /// another display. Returns the covered displays and the new confirmed set.
    static func coveredDisplays(windows: [WindowInfo], frontmostPID: pid_t?, ownPID: pid_t,
                                displays: [CGDirectDisplayID: CGRect], menuBarHidden: Bool,
                                confirmed: Set<CGWindowID>)
        -> (displays: Set<CGDirectDisplayID>, confirmed: Set<CGWindowID>) {
        var covered = Set<CGDirectDisplayID>(), kept = Set<CGWindowID>()
        for (id, frame) in displays {
            let front = windows.first(where: {
                $0.layer == 0 && $0.alpha > 0 && $0.ownerPID != ownPID && !$0.bounds.intersection(frame).isEmpty
            })?.ownerPID
            for window in windows where window.alpha > 0 && window.ownerPID != ownPID
                && covers(window.bounds, frame) {
                if window.layer > 0 {
                    if window.ownerPID == front || window.ownerPID == frontmostPID { covered.insert(id) }
                } else if let front, window.ownerPID == front,
                          (window.ownerPID == frontmostPID && menuBarHidden) || confirmed.contains(window.number) {
                    covered.insert(id)
                    kept.insert(window.number)
                }
            }
        }
        return (covered, kept)
    }

    /// Allows a point of rounding on each edge.
    static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        guard !display.isEmpty else { return false }
        return window.insetBy(dx: -1, dy: -1).contains(display)
    }

    /// Level 0 windows confirmed as full screen by an earlier read. Read and
    /// written on the main thread only.
    private static var confirmed = Set<CGWindowID>()

    /// Reads the windows on screen, front to back. The presentation options
    /// are the frontmost app's, as it sets them itself.
    static func coveredDisplays() -> Set<CGDirectDisplayID> {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let windows: [WindowInfo] = entries.compactMap { entry in
            guard let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: rect)
        }
        let menuBarHidden = !NSApp.currentSystemPresentationOptions
            .intersection([.autoHideMenuBar, .hideMenuBar]).isEmpty
        let result = coveredDisplays(windows: windows,
                                     frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                     ownPID: ownPID, displays: activeDisplays(), menuBarHidden: menuBarHidden,
                                     confirmed: confirmed)
        confirmed = result.confirmed
        return result.displays
    }

    private static func activeDisplays() -> [CGDirectDisplayID: CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [:] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [:] }
        var frames: [CGDirectDisplayID: CGRect] = [:]
        for id in ids.prefix(Int(count)) { frames[id] = CGDisplayBounds(id) }
        return frames
    }
}
