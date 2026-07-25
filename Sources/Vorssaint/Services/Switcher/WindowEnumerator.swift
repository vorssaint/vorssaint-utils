// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

/// Builds the list of switchable windows from the window server and
/// Accessibility.
///
/// `CGWindowListCopyWindowInfo` is queried with `.optionAll` so windows that
/// are minimized or parked on other Spaces are included when WindowServer
/// exposes them. Fullscreen windows on other Spaces can be missing from that
/// list, so Accessibility supplies a second pass for real app windows by id.
/// The result is then ordered by the app activation MRU (see
/// `AppActivationTracker`), so the switcher matches the system ⌘Tab toggle.
/// Window titles require Screen Recording on modern macOS; Vorssaint's own
/// titled windows use NSWindow metadata so Settings remains reachable even
/// though the app is a menu-bar accessory.
enum WindowEnumerator {
    /// Window surfaces larger than this are considered real, switchable windows.
    private static let minimumSize = CGSize(width: 80, height: 60)
    /// Hard cap to keep the switcher readable and captures cheap.
    private static let maximumCount = 24

    static func listWindows() -> [SwitcherItem] {
        listWindows(filterPID: nil,
                    maximumCount: maximumCount,
                    includeWindowlessFinder: UserDefaults.standard.bool(forKey: DefaultsKey.switcherShowWindowlessFinder),
                    groupByApp: UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs),
                    currentSpaceOnly: UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly))
    }

    static func listWindows(for pid: pid_t, maximumCount: Int = 12) -> [SwitcherItem] {
        // The Dock previews honor the same current-desktop choice as the
        // switcher: the Settings caption promises that picking a window
        // never hops desktops while the option is on, and a preview click
        // is a pick like any other.
        listWindows(filterPID: pid,
                    maximumCount: maximumCount,
                    includeWindowlessFinder: false,
                    groupByApp: false,
                    currentSpaceOnly: UserDefaults.standard.bool(
                        forKey: DefaultsKey.switcherCurrentSpaceOnly))
    }

    private static func listWindows(filterPID: pid_t?,
                                    maximumCount: Int,
                                    includeWindowlessFinder: Bool,
                                    groupByApp: Bool,
                                    currentSpaceOnly: Bool) -> [SwitcherItem] {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

        let ownPid = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        var regularApps: [pid_t: String] = [:]
        var regularBundlePaths: [pid_t: String] = [:]
        for app in runningApps where app.activationPolicy == .regular {
            regularApps[app.processIdentifier] = app.localizedName ?? ""
            if let path = app.bundleURL?.path {
                regularBundlePaths[app.processIdentifier] = path
            }
        }
        regularApps[pid_t(ownPid)] = AppInfo.name
        // Programs hosted by a compatibility layer (bottles) run in bare
        // loader processes: no bundle, sometimes not even a regular
        // activation policy, and Accessibility describes their windows with no
        // standard subrole. Track those pids so the guards below treat their
        // real windows as switchable instead of hiding the app (issue #274).
        var compatibilityLayerPids: Set<pid_t> = []
        for app in runningApps where SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: app.bundleIdentifier,
            executablePath: app.executableURL?.path,
            localizedName: app.localizedName) {
            compatibilityLayerPids.insert(app.processIdentifier)
            if regularApps[app.processIdentifier] == nil {
                regularApps[app.processIdentifier] = app.localizedName ?? ""
            }
        }
        let embeddedHostPairs: [(pid_t, pid_t)] = runningApps.compactMap { app in
            guard app.activationPolicy != .regular,
                  let helperPath = app.bundleURL?.path,
                  let hostPID = SwitcherSupport.embeddedHostPID(helperBundlePath: helperPath,
                                                               regularBundlePaths: regularBundlePaths)
            else { return nil }
            return (app.processIdentifier, hostPID)
        }
        let embeddedHostPIDs = Dictionary(uniqueKeysWithValues: embeddedHostPairs)
        // The regular process owns the app identity, but an embedded accessory
        // process can own its real windows. Query both sides of that mapping.
        let accessibilityPids: Set<pid_t>
        if let filterPID {
            let embeddedPIDs = embeddedHostPIDs.compactMap { ownerPID, hostPID in
                hostPID == filterPID ? ownerPID : nil
            }
            accessibilityPids = Set([filterPID] + embeddedPIDs)
        } else {
            accessibilityPids = Set(regularApps.keys)
                .union(embeddedHostPIDs.keys)
                .subtracting([pid_t(ownPid)])
        }
        let accessibilityWindows = accessibilityWindows(for: accessibilityPids,
                                                        undescribedSubrolePids: compatibilityLayerPids)

        var seen = Set<CGWindowID>()
        var windows: [SwitcherItem] = []

        // Accessibility cannot describe windows parked on a Space that is not
        // visible, so the ghost veto below would silently hide real windows
        // (issue #339). The window server tells them apart: a real parked
        // window belongs to a Space, a stale leftover surface belongs to none.
        // Resolved lazily and cached, so fully Accessibility-confirmed lists
        // pay nothing.
        var visibleSpaces: Set<UInt64>?
        var hiddenSpaceVerdicts: [CGWindowID: Bool] = [:]
        func isOnHiddenSpace(_ windowID: CGWindowID) -> Bool {
            if let verdict = hiddenSpaceVerdicts[windowID] { return verdict }
            if visibleSpaces == nil {
                visibleSpaces = SpaceWindowBridge.topology()?.visibleSpaces ?? []
            }
            guard let visible = visibleSpaces, !visible.isEmpty else { return false }
            let verdict = SpaceHopSupport.isParkedOnHiddenSpace(
                windowSpaces: SpaceWindowBridge.spaces(of: windowID),
                visibleSpaces: visible
            )
            hiddenSpaceVerdicts[windowID] = verdict
            return verdict
        }

        // No cap during enumeration: the raw window-server order is not
        // "visible first" (windows parked on other Spaces can come before the
        // frontmost app), so truncating here silently drops whole apps on
        // busy Macs (issue #172). Everything is collected, ordered by the
        // activation MRU, and only then trimmed, so the cap always cuts the
        // least recently used tail.
        for info in raw {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  !seen.contains(windowID),
                  let windowOwnerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any]
            else { continue }
            let appPID = regularApps[windowOwnerPID] != nil
                ? windowOwnerPID
                : embeddedHostPIDs[windowOwnerPID]
            guard let appPID else { continue }
            if let filterPID, appPID != filterPID { continue }
            // Current-Space mode (issue #337): windows living on another
            // desktop are left out entirely, including minimized ones that
            // kept their desktop of origin, so picking an entry never moves
            // the user somewhere else. Windows the server cannot place on any
            // Space are not "elsewhere", so they keep the regular treatment.
            if currentSpaceOnly, isOnHiddenSpace(CGWindowID(windowID)) { continue }
            let axWindow = accessibilityWindows[windowOwnerPID]?.byID[CGWindowID(windowID)]
            if accessibilityWindows[windowOwnerPID] != nil, axWindow == nil,
               !isOnHiddenSpace(CGWindowID(windowID)) {
                continue
            }
            let cgFrame = CGRect(x: (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0,
                                 y: (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0,
                                 width: (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0,
                                 height: (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0)
            let isMinimized = axWindow?.isMinimized ?? false
            let isFullscreen = (axWindow?.isFullscreen ?? false) || frameLooksFullscreen(cgFrame)
            guard let frame = switchableFrame(cgFrame, fallback: axWindow?.frame, isMinimized: isMinimized) else {
                continue
            }

            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha == 0, !isMinimized {
                continue
            }

            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? (info[kCGWindowIsOnscreen as String] as? Bool)
                ?? false

            let appName: String
            let displayTitle: String
            if windowOwnerPID == ownPid {
                guard let title = ownWindowTitle(for: windowID) else { continue }
                appName = AppInfo.name
                displayTitle = title
            } else {
                guard let name = regularApps[appPID] else { continue }
                appName = name
                displayTitle = title.isEmpty ? (axWindow?.title ?? "") : title
            }

            // Off-screen *and* untitled windows are usually invisible helpers
            // (web pickers, framework shells), not something to switch to. But
            // fullscreen windows on another Space can be reported off-screen
            // and untitled by WindowServer; if Accessibility confirms the same
            // window id, keep it switchable and fall back to the app name.
            // Windows the window server places on a hidden Space are equally
            // real even when untitled (their titles need Screen Recording).
            if !isOnScreen && displayTitle.isEmpty && axWindow == nil
                && !isOnHiddenSpace(windowID) { continue }

            seen.insert(windowID)
            windows.append(.window(id: windowID,
                                   title: displayTitle,
                                   appName: appName,
                                   pid: appPID,
                                   windowOwnerPID: windowOwnerPID,
                                   isOnScreen: isOnScreen,
                                   isMinimized: isMinimized,
                                   isFullscreen: isFullscreen,
                                   frame: frame))
        }
        appendAccessibilityOnlyWindows(to: &windows,
                                       snapshots: accessibilityWindows,
                                       regularApps: regularApps,
                                       embeddedHostPIDs: embeddedHostPIDs,
                                       seen: &seen,
                                       filterPID: filterPID,
                                       excludeWindow: { currentSpaceOnly && isOnHiddenSpace($0) })
        if includeWindowlessFinder {
            appendWindowlessFinder(to: &windows, regularApps: regularApps)
        }
        if groupByApp {
            windows = groupWindowsByApp(windows)
        }
        let ordered = orderByActivation(windows)
        guard ordered.count > maximumCount else { return ordered }
        var trimmed = Array(ordered.prefix(maximumCount))
        // The windowless Finder tile is an explicit user choice; it must not
        // vanish just because the list happens to be full.
        if includeWindowlessFinder,
           let finderTile = ordered.dropFirst(maximumCount).first(where: { $0.windowID == nil }) {
            trimmed.append(finderTile)
        }
        return trimmed
    }

    /// WindowServer can keep stale, titled surfaces around after some apps close
    /// tabs or windows. Cross-checking against Accessibility removes those ghosts
    /// while preserving minimized windows and windows on other Spaces.
    private struct AccessibilityWindowSnapshot {
        let title: String
        let frame: CGRect?
        let isMinimized: Bool
        let isFullscreen: Bool
    }

    private struct AccessibilityWindowSnapshotList {
        let ordered: [(id: CGWindowID, snapshot: AccessibilityWindowSnapshot)]
        let byID: [CGWindowID: AccessibilityWindowSnapshot]
    }

    private static func accessibilityWindows(for pids: Set<pid_t>,
                                             undescribedSubrolePids: Set<pid_t> = []) -> [pid_t: AccessibilityWindowSnapshotList] {
        guard Permissions.shared.accessibility else { return [:] }

        var result: [pid_t: AccessibilityWindowSnapshotList] = [:]
        for pid in pids {
            guard let windows = accessibilityWindows(for: pid,
                                                     acceptsUndescribedSubroles: undescribedSubrolePids.contains(pid))
            else { continue }
            result[pid] = windows
        }
        return result
    }

    private static func accessibilityWindows(for pid: pid_t,
                                             acceptsUndescribedSubroles: Bool = false) -> AccessibilityWindowSnapshotList? {
        let app = AXUIElementCreateApplication(pid)
        // This runs on the main thread (tap callback and activation warm-ups):
        // an app that is not servicing its run loop would hold every AX call
        // for the 6 second default timeout, and a blocked main thread stalls
        // the event taps with it, freezing typing system wide (issue #189).
        AXUIElementSetMessagingTimeout(app, 0.35)
        var axWindows: [AXUIElement] = []
        var value: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        // Not responding: skip the remaining calls, each would block again.
        guard windowsResult != .cannotComplete else { return nil }
        if windowsResult == .success, let windows = value as? [AXUIElement] {
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.35)
                if isUserFacingWindow(window, acceptsUndescribedSubroles: acceptsUndescribedSubroles) {
                    appendUnique(window, to: &axWindows)
                }
            }
        }
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let window = accessibilityWindowAttribute(app, attribute as String) {
                AXUIElementSetMessagingTimeout(window, 0.35)
                if isUserFacingWindow(window, acceptsUndescribedSubroles: acceptsUndescribedSubroles) {
                    appendUnique(window, to: &axWindows)
                }
            }
        }

        var byID: [CGWindowID: AccessibilityWindowSnapshot] = [:]
        var ordered: [(id: CGWindowID, snapshot: AccessibilityWindowSnapshot)] = []
        for window in axWindows {
            if let id = AXWindowResolver.windowID(for: window) {
                let frame = accessibilityFrame(for: window)
                let snapshot = AccessibilityWindowSnapshot(title: accessibilityTitle(for: window),
                                                           frame: frame,
                                                           isMinimized: boolAttribute(window, kAXMinimizedAttribute as String),
                                                           isFullscreen: isFullscreenWindow(window)
                                                            || frameLooksFullscreen(frame))
                byID[id] = snapshot
                ordered.append((id, snapshot))
            }
        }

        // An app that answers with zero user-facing windows normally vetoes
        // its CG surfaces as stale ghosts. For a compatibility-layer process
        // an empty answer only means Accessibility could not describe the
        // windows, so withhold the veto instead of hiding real windows.
        if axWindows.isEmpty {
            return acceptsUndescribedSubroles
                ? nil
                : AccessibilityWindowSnapshotList(ordered: ordered, byID: byID)
        }
        // If an app reports AX windows but none resolve to WindowServer ids,
        // keep the old behavior instead of hiding a real window for that app.
        if !ordered.isEmpty {
            return AccessibilityWindowSnapshotList(ordered: ordered, byID: byID)
        }
        return nil
    }

    private static func appendAccessibilityOnlyWindows(to windows: inout [SwitcherItem],
                                                       snapshots: [pid_t: AccessibilityWindowSnapshotList],
                                                       regularApps: [pid_t: String],
                                                       embeddedHostPIDs: [pid_t: pid_t],
                                                       seen: inout Set<CGWindowID>,
                                                       filterPID: pid_t?,
                                                       excludeWindow: (CGWindowID) -> Bool = { _ in false }) {
        let tracker = AppActivationTracker.shared
        let pids = snapshots.keys
            .filter { windowOwnerPID in
                guard windowOwnerPID != ProcessInfo.processInfo.processIdentifier else { return false }
                let appPID = regularApps[windowOwnerPID] != nil
                    ? windowOwnerPID
                    : embeddedHostPIDs[windowOwnerPID]
                guard let appPID, regularApps[appPID] != nil else { return false }
                return filterPID == nil || appPID == filterPID
            }
            .sorted { lhs, rhs in
                let rankL = tracker.rank(of: embeddedHostPIDs[lhs] ?? lhs)
                let rankR = tracker.rank(of: embeddedHostPIDs[rhs] ?? rhs)
                return rankL != rankR ? rankL < rankR : lhs < rhs
            }

        for windowOwnerPID in pids {
            let appPID = embeddedHostPIDs[windowOwnerPID] ?? windowOwnerPID
            guard let appName = regularApps[appPID],
                  let list = snapshots[windowOwnerPID] else { continue }
            for entry in list.ordered {
                guard !seen.contains(entry.id),
                      !excludeWindow(entry.id),
                      let frame = switchableFrame(entry.snapshot.frame,
                                                  fallback: nil,
                                                  isMinimized: entry.snapshot.isMinimized) else { continue }
                seen.insert(entry.id)
                windows.append(.window(id: entry.id,
                                       title: entry.snapshot.title,
                                       appName: appName,
                                       pid: appPID,
                                       windowOwnerPID: windowOwnerPID,
                                       isOnScreen: false,
                                       isMinimized: entry.snapshot.isMinimized,
                                       isFullscreen: entry.snapshot.isFullscreen,
                                       frame: frame))
            }
        }
    }

    private static func accessibilityTitle(for window: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private static func accessibilityFrame(for window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func frameIsSwitchable(_ frame: CGRect) -> Bool {
        frame.width >= minimumSize.width && frame.height >= minimumSize.height
    }

    private static func switchableFrame(_ frame: CGRect?,
                                        fallback: CGRect?,
                                        isMinimized: Bool) -> CGRect? {
        if let frame, frameIsSwitchable(frame) { return frame }
        if let fallback, frameIsSwitchable(fallback) { return fallback }
        guard isMinimized else { return nil }
        return CGRect(origin: .zero, size: minimumSize)
    }

    private static func frameLooksFullscreen(_ frame: CGRect?) -> Bool {
        guard let frame else { return false }
        return NSScreen.screens.contains { screen in
            abs(frame.width - screen.frame.width) <= 2
                && abs(frame.height - screen.frame.height) <= 2
        }
    }

    private static func isUserFacingWindow(_ window: AXUIElement,
                                           acceptsUndescribedSubroles: Bool = false) -> Bool {
        if isFullscreenWindow(window) { return true }
        if boolAttribute(window, kAXMinimizedAttribute as String),
           stringAttribute(window, kAXRoleAttribute as String) == (kAXWindowRole as String) {
            return true
        }
        if let subrole = stringAttribute(window, kAXSubroleAttribute as String) {
            if subrole == "AXStandardWindow" || subrole == "AXFullScreenWindow" { return true }
            // Compatibility-layer processes draw their own window chrome on
            // borderless surfaces, which Accessibility reports as AXUnknown;
            // for them the window role is the real signal.
            return acceptsUndescribedSubroles
                && subrole == "AXUnknown"
                && stringAttribute(window, kAXRoleAttribute as String) == (kAXWindowRole as String)
        }
        return stringAttribute(window, kAXRoleAttribute as String) == "AXWindow"
    }

    private static func isFullscreenWindow(_ window: AXUIElement) -> Bool {
        if boolAttribute(window, "AXFullScreen") { return true }
        return stringAttribute(window, kAXSubroleAttribute as String) == "AXFullScreenWindow"
    }

    private static func appendUnique(_ window: AXUIElement, to windows: inout [AXUIElement]) {
        guard !windows.contains(where: { CFEqual($0, window) }) else { return }
        windows.append(window)
    }

    private static func accessibilityWindowAttribute(_ app: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return false }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return (value as? Bool) ?? false
        }
        return CFBooleanGetValue((value as! CFBoolean))
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
              window.canBecomeKey,
              window.isVisible || window.isMiniaturized else { return nil }
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
                if (window.isOnScreen && !grouped[index].isOnScreen)
                    || (window.isFullscreen && !grouped[index].isFullscreen) {
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
