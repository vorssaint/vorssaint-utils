// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Full screen an app draws on its own, without a macOS full-screen Space.
/// Games built on GLFW or SDL raise one borderless window over the menu bar
/// on the current desktop, so Space queries never report them.
enum NotchAppFullscreen {
    struct WindowInfo: Equatable {
        let ownerPID: pid_t
        let layer: Int
        let alpha: Double
        let bounds: CGRect
    }

    /// Displays the frontmost app covers with a window raised above normal
    /// windows. A level 0 window never counts, so a zoomed window under an
    /// auto-hidden menu bar keeps the island.
    static func coveredDisplays(windows: [WindowInfo], frontmostPID: pid_t?, ownPID: pid_t,
                                displays: [CGDirectDisplayID: CGRect]) -> Set<CGDirectDisplayID> {
        guard let frontmostPID, frontmostPID != ownPID else { return [] }
        let raised = windows.filter { $0.ownerPID == frontmostPID && $0.layer > 0 && $0.alpha > 0 }
        guard !raised.isEmpty else { return [] }
        return Set(displays.compactMap { id, frame in
            raised.contains { covers($0.bounds, frame) } ? id : nil
        })
    }

    /// Allows a point of rounding on each edge.
    static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        guard !display.isEmpty else { return false }
        return window.insetBy(dx: -1, dy: -1).contains(display)
    }

    /// Reads the windows on screen only when another app is frontmost.
    static func coveredDisplays() -> Set<CGDirectDisplayID> {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontmostPID != ownPID,
              let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let windows: [WindowInfo] = entries.compactMap { entry in
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid == frontmostPID,
                  let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return WindowInfo(ownerPID: pid, layer: layer, alpha: alpha, bounds: rect)
        }
        guard !windows.isEmpty else { return [] }
        return coveredDisplays(windows: windows, frontmostPID: frontmostPID, ownPID: ownPID,
                               displays: activeDisplays())
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
