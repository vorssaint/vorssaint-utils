// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

/// Builds the list of switchable windows from the window server.
///
/// `CGWindowListCopyWindowInfo` is queried with `.optionAll` so windows that
/// are minimized or parked on other Spaces are included. The result is then
/// ordered by the app activation MRU (see `AppActivationTracker`), so the
/// switcher matches the system ⌘Tab toggle. Window titles require Screen
/// Recording on modern macOS; Vorssaint's own titled windows use NSWindow
/// metadata so Settings remains reachable even though the app is a menu-bar
/// accessory.
enum WindowEnumerator {
    /// Window surfaces larger than this are considered real, switchable windows.
    private static let minimumSize = CGSize(width: 80, height: 60)
    /// Hard cap to keep the switcher readable and captures cheap.
    private static let maximumCount = 24

    static func listWindows() -> [SwitcherItem] {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPid = ProcessInfo.processInfo.processIdentifier
        var regularApps: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            regularApps[app.processIdentifier] = app.localizedName ?? ""
        }
        regularApps[pid_t(ownPid)] = AppInfo.name
        let liveWindowIDs = accessibilityWindowIDs(for: Set(regularApps.keys).subtracting([pid_t(ownPid)]))

        let currentSpaceOnly   = UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
        let currentMonitorOnly = UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentMonitorOnly)
        let hideMinimized      = UserDefaults.standard.bool(forKey: DefaultsKey.switcherHideMinimized)
        let hideFinder         = UserDefaults.standard.bool(forKey: DefaultsKey.switcherHideFinder)

        let finderPid: pid_t? = hideFinder
            ? NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == Defaults.finderBundleIdentifier })?.processIdentifier
            : nil

        // Minimized IDs are only needed when hiding minimized without currentSpaceOnly,
        // since currentSpaceOnly already excludes off-screen (minimized) windows.
        let minimizedIDs: Set<CGWindowID> = (hideMinimized && !currentSpaceOnly)
            ? collectMinimizedWindowIDs(for: Set(regularApps.keys).subtracting([pid_t(ownPid)]))
            : []

        let currentMonitorFrame: CGRect? = currentMonitorOnly ? NSScreen.withMouse.frame : nil
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0

        var seen = Set<CGWindowID>()
        var windows: [SwitcherItem] = []

        for info in raw {
            guard windows.count < maximumCount else { break }
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  !seen.contains(windowID),
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any]
            else { continue }
            if let liveIDs = liveWindowIDs[pid], !liveIDs.contains(CGWindowID(windowID)) {
                continue
            }

            let frame = CGRect(x: (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0,
                               y: (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0,
                               width: (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0,
                               height: (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0)
            guard frame.width >= minimumSize.width, frame.height >= minimumSize.height else { continue }

            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha == 0 { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? (info[kCGWindowIsOnscreen as String] as? Bool)
                ?? false

            // Windows on other Spaces report isOnScreen == false, same as minimized ones.
            if currentSpaceOnly, !isOnScreen { continue }
            if minimizedIDs.contains(windowID) { continue }
            if let fp = finderPid, pid == fp { continue }
            if let monitorFrame = currentMonitorFrame {
                // kCGWindowBounds is in CoreGraphics coords (origin top-left, Y down).
                // NSScreen.frame is in AppKit coords (origin bottom-left, Y up). Convert.
                let appKitFrame = CGRect(x: frame.minX,
                                         y: primaryScreenHeight - frame.maxY,
                                         width: frame.width,
                                         height: frame.height)
                guard appKitFrame.intersects(monitorFrame) else { continue }
            }

            let appName: String
            let displayTitle: String
            if pid == ownPid {
                guard let title = ownWindowTitle(for: windowID) else { continue }
                appName = AppInfo.name
                displayTitle = title
            } else {
                guard let name = regularApps[pid] else { continue }
                appName = name
                displayTitle = title
            }

            // Off-screen *and* untitled windows are usually invisible helpers
            // (web pickers, framework shells), not something to switch to.
            if !isOnScreen && displayTitle.isEmpty { continue }

            seen.insert(windowID)
            windows.append(.window(id: windowID,
                                   title: displayTitle,
                                   appName: appName,
                                   pid: pid,
                                   isOnScreen: isOnScreen,
                                   frame: frame))
        }
        if !hideFinder {
            appendWindowlessFinder(to: &windows, regularApps: regularApps)
        }
        if UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs) {
            windows = groupWindowsByApp(windows)
        }
        return orderByActivation(windows)
    }

    /// WindowServer can keep stale, titled surfaces around after some apps close
    /// tabs or windows. Cross-checking against Accessibility removes those ghosts
    /// while preserving minimized windows and windows on other Spaces.
    private static func accessibilityWindowIDs(for pids: Set<pid_t>) -> [pid_t: Set<CGWindowID>] {
        guard Permissions.shared.accessibility else { return [:] }

        var result: [pid_t: Set<CGWindowID>] = [:]
        for pid in pids {
            guard let ids = accessibilityWindowIDs(for: pid) else { continue }
            result[pid] = ids
        }
        return result
    }

    private static func accessibilityWindowIDs(for pid: pid_t) -> Set<CGWindowID>? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement]
        else { return nil }

        var ids = Set<CGWindowID>()
        for window in axWindows {
            if let id = AXWindowResolver.windowID(for: window) {
                ids.insert(id)
            }
        }

        // If an app reports AX windows but none resolve to WindowServer ids,
        // keep the old behavior instead of hiding a real window for that app.
        if axWindows.isEmpty || !ids.isEmpty {
            return ids
        }
        return nil
    }

    private static func collectMinimizedWindowIDs(for pids: Set<pid_t>) -> Set<CGWindowID> {
        guard Permissions.shared.accessibility else { return [] }
        var result = Set<CGWindowID>()
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let axWindows = value as? [AXUIElement] else { continue }
            for window in axWindows {
                var minimized: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
                      (minimized as? Bool) == true,
                      let id = AXWindowResolver.windowID(for: window) else { continue }
                result.insert(id)
            }
        }
        return result
    }

    private static func appendWindowlessFinder(to windows: inout [SwitcherItem],
                                               regularApps: [pid_t: String]) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == Defaults.finderBundleIdentifier && $0.activationPolicy == .regular
        }) else { return }
        let pid = app.processIdentifier
        guard windows.contains(where: { $0.pid == pid }) == false,
              regularApps[pid] != nil else { return }

        let name = app.localizedName ?? "Finder"
        windows.append(.appOnly(appName: name, pid: pid))
    }

    private static func ownWindowTitle(for windowID: CGWindowID) -> String? {
        guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }),
              window.styleMask.contains(.titled),
              window.canBecomeKey else { return nil }
        return window.title.isEmpty ? AppInfo.name : window.title
    }

    /// Groups windows by app in most-recently-used order while preserving the
    /// window server's front-to-back order within each app. A stable sort is
    /// required so the within-app order survives the regrouping. This is what
    /// puts the window you were just in (including another window of the same
    /// app) right next to the current one.
    private static func orderByActivation(_ windows: [SwitcherItem]) -> [SwitcherItem] {
        let tracker = AppActivationTracker.shared
        return windows.enumerated().sorted { lhs, rhs in
            let rankL = tracker.rank(of: lhs.element.pid)
            let rankR = tracker.rank(of: rhs.element.pid)
            return rankL != rankR ? rankL < rankR : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Collapses every window of an app into a single entry, so an app shows once
    /// in the switcher instead of once per window (or tab). Keeps one
    /// representative per app, preferring the on-screen, front window so its title
    /// and thumbnail are the one you would expect when switching to that app.
    private static func groupWindowsByApp(_ windows: [SwitcherItem]) -> [SwitcherItem] {
        var indexByPid: [pid_t: Int] = [:]
        var grouped: [SwitcherItem] = []
        for window in windows {
            if let index = indexByPid[window.pid] {
                // Another window of the same app: prefer an on-screen window as
                // the representative when the one we kept is off-screen.
                if window.isOnScreen && !grouped[index].isOnScreen {
                    grouped[index] = window
                }
            } else {
                indexByPid[window.pid] = grouped.count
                grouped.append(window)
            }
        }
        return grouped
    }
}
