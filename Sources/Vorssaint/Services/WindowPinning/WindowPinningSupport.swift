// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

/// One pinned window as persisted between launches. The window server's ID is
/// process-lifetime, so a restart of the owning app invalidates the entry; the
/// re-verify sweep prunes those.
struct PinnedWindowEntry: Codable, Equatable {
    let windowID: UInt32
    let ownerPID: pid_t
    let bundleID: String
    let pinnedAt: Date
}

/// The pinned set as a value, so tests and the service hold the same type.
/// Persistence is JSON under one defaults key; any read failure loads empty,
/// because a corrupted pin list must never pin nothing it cannot later unpin.
struct PinnedWindowStore: Equatable {
    private(set) var entries: [PinnedWindowEntry] = []

    var count: Int { entries.count }

    mutating func upsert(_ entry: PinnedWindowEntry) {
        if let index = entries.firstIndex(where: { $0.windowID == entry.windowID }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    @discardableResult
    mutating func remove(windowID: UInt32) -> PinnedWindowEntry? {
        guard let index = entries.firstIndex(where: { $0.windowID == windowID }) else { return nil }
        return entries.remove(at: index)
    }

    func contains(windowID: UInt32) -> Bool {
        entries.contains { $0.windowID == windowID }
    }

    /// Drops every entry whose window no longer exists and returns them, so
    /// the caller can decide what to restore (nothing is restorable for a
    /// window that is gone; the sweep just forgets it).
    mutating func prune(keeping validWindowIDs: Set<UInt32>) -> [PinnedWindowEntry] {
        let removed = entries.filter { !validWindowIDs.contains($0.windowID) }
        entries.removeAll { !validWindowIDs.contains($0.windowID) }
        return removed
    }

    static func load(defaultsKey: String,
                     from defaults: UserDefaults = .standard) -> PinnedWindowStore {
        guard let data = defaults.data(forKey: defaultsKey) else { return PinnedWindowStore() }
        guard let entries = try? JSONDecoder().decode([PinnedWindowEntry].self, from: data)
        else { return PinnedWindowStore() }
        return PinnedWindowStore(entries: entries)
    }

    func save(defaultsKey: String, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

/// Pure frontmost-window resolution over a window list the caller supplies, so
/// tests inject dictionaries and the service passes the live on-screen list.
enum WindowPinningResolver {
    /// The app's real windows: owned by the pid, on the normal layer, and
    /// visible enough to matter. Mirrors the filter in FocusFollowsMouseSupport.
    static func filteredAppWindows(_ windows: [[String: Any]], ownerPID: pid_t) -> [[String: Any]] {
        windows.filter { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01
            else { return false }
            return true
        }
    }

    /// Which of another app's windows pinning would take, given the list
    /// CGWindowListCopyWindowInfo returns back to front. A focused app that is
    /// not us is asked for its windows; a provided frame (read from the app's
    /// Accessibility focused window) picks the exact window, otherwise the
    /// LARGEST filtered window answers — the main window dwarfs the tooltips,
    /// rename fields and child panes that share its pid and sit above it in
    /// the z-order. Our own process or no focus means nothing to pin.
    static func frontmostWindowID(ownPID: pid_t,
                                  windows: [[String: Any]],
                                  focusedPID: pid_t?,
                                  focusedWindowFrame: CGRect?) -> CGWindowID? {
        guard let focusedPID, focusedPID > 0, focusedPID != ownPID else { return nil }
        let candidates = filteredAppWindows(windows, ownerPID: focusedPID)
        guard !candidates.isEmpty else { return nil }
        let fallback = candidates.max { area(of: $0) < area(of: $1) }
        guard let focusedWindowFrame else { return fallback.flatMap { windowID(of: $0) } }
        let matched = candidates.first { window in
            WindowServerSupport.bounds(from: window) == focusedWindowFrame
        }
        return (matched ?? fallback).flatMap { windowID(of: $0) }
    }

    /// Whether a click at `point` (window-server coordinates) should fall
    /// through the clone of `pinnedWindowID`: only when the window that would
    /// take the click is the original itself, or a child of the same app
    /// sitting inside it (a popover, sheet or rename field). Any other window
    /// in front means the original is covered there, so the clone has to
    /// catch the click and bring the original forward. So does an original
    /// missing from the list: a clone showing on another Space takes the
    /// click and leads back to it. `windows` is the on-screen list front to
    /// back; our own panels are skipped.
    static func clickFallsThrough(at point: CGPoint,
                                  pinnedWindowID: CGWindowID,
                                  pinnedOwnerPID: pid_t,
                                  ownPID: pid_t,
                                  windows: [[String: Any]]) -> Bool {
        guard windows.contains(where: { windowID(of: $0) == pinnedWindowID }) else { return false }
        let receiver = windows.first { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ownPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01,
                  let bounds = WindowServerSupport.bounds(from: window)
            else { return false }
            return bounds.contains(point)
        }
        guard let receiver else { return true }
        if windowID(of: receiver) == pinnedWindowID { return true }
        guard (receiver[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pinnedOwnerPID,
              let receiverBounds = WindowServerSupport.bounds(from: receiver),
              let pinnedBounds = windows.first(where: { windowID(of: $0) == pinnedWindowID })
                .flatMap(WindowServerSupport.bounds(from:))
        else { return false }
        return pinnedBounds.contains(receiverBounds)
    }

    /// Whether any other window sits in front of the pinned original and
    /// overlaps it. Only then does the clone need to show: an uncovered
    /// original is already on top, and showing it directly keeps drags and
    /// resizes native. The pinned app's child UI inside the original (a
    /// popover, sheet or rename field) does not count, and neither do our own
    /// panels. An original missing from the on-screen list (on another Space,
    /// minimized or hidden) answers `offScreenIsCovered`: by default the
    /// clone stays on the original's Space, because elsewhere it can only
    /// show a window that may have stopped drawing; with Show on All Spaces
    /// it stands in for an original on another Space. `windows` is the
    /// on-screen list front to back.
    static func isCovered(pinnedWindowID: CGWindowID,
                          pinnedOwnerPID: pid_t,
                          ownPID: pid_t,
                          windows: [[String: Any]],
                          offScreenIsCovered: Bool) -> Bool {
        guard let pinnedIndex = windows.firstIndex(where: { windowID(of: $0) == pinnedWindowID }),
              let pinnedBounds = WindowServerSupport.bounds(from: windows[pinnedIndex])
        else { return offScreenIsCovered }
        return windows[..<pinnedIndex].contains { window in
            let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            guard owner != ownPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01,
                  let bounds = WindowServerSupport.bounds(from: window)
            else { return false }
            if owner == pinnedOwnerPID, pinnedBounds.contains(bounds) { return false }
            let overlap = bounds.intersection(pinnedBounds)
            return !overlap.isNull && overlap.width > 0 && overlap.height > 0
        }
    }

    private static func area(of window: [String: Any]) -> CGFloat {
        guard let bounds = WindowServerSupport.bounds(from: window) else { return 0 }
        return bounds.width * bounds.height
    }

    /// The pid of the app Accessibility says is focused, straight from the
    /// system-wide element. Any error means "unknown", never a guess.
    static func axFocusedAppPID() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedApplicationAttribute as CFString,
                                            &value) == .success,
              let application = value else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(application as! AXUIElement, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    private static func windowID(of window: [String: Any]) -> CGWindowID? {
        (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
    }
}
