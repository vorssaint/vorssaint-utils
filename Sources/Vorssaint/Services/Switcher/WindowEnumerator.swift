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
    struct Request {
        let filterPID: pid_t?
        let maximumCount: Int
        let includeWindowlessFinder: Bool
        let groupByApp: Bool
        let currentSpaceOnly: Bool
        let ownPID: pid_t
        let apps: [RunningApp]
        let ownWindowTitles: [CGWindowID: String]
        let screenFrames: [CGRect]
        let activationRanks: [pid_t: Int]
        let hasAccessibility: Bool

        func withAccessibility(_ enabled: Bool) -> Request {
            Request(filterPID: filterPID,
                    maximumCount: maximumCount,
                    includeWindowlessFinder: includeWindowlessFinder,
                    groupByApp: groupByApp,
                    currentSpaceOnly: currentSpaceOnly,
                    ownPID: ownPID,
                    apps: apps,
                    ownWindowTitles: ownWindowTitles,
                    screenFrames: screenFrames,
                    activationRanks: activationRanks,
                    hasAccessibility: enabled)
        }
    }

    struct Snapshot {
        let items: [SwitcherItem]
        let focusedWindowIDs: [pid_t: CGWindowID]
        let existingWindowIDs: Set<CGWindowID>
        let observationTargets: [pid_t: ObservationTarget]
        let capturedAt: TimeInterval

        static let empty = Snapshot(items: [],
                                    focusedWindowIDs: [:],
                                    existingWindowIDs: [],
                                    observationTargets: [:],
                                    capturedAt: 0)

        func focusedWindowID(for pid: pid_t) -> CGWindowID? {
            focusedWindowIDs[pid]
        }
    }

    struct ObservationTarget {
        let appElement: AXUIElement
        let windowsByID: [CGWindowID: AXUIElement]
    }

    struct RunningApp {
        let pid: pid_t
        let isRegular: Bool
        let localizedName: String
        let bundleIdentifier: String?
        let bundlePath: String?
        let executablePath: String?
    }

    /// Window surfaces larger than this are considered real, switchable windows.
    private static let minimumSize = CGSize(width: 80, height: 60)
    /// Hard cap to keep the switcher readable and captures cheap.
    private static let maximumCount = 24

    static func listWindows() -> [SwitcherItem] {
        captureSnapshot(using: makeRequest()).items
    }

    static func listWindows(for pid: pid_t, maximumCount: Int = 12) -> [SwitcherItem] {
        captureSnapshot(using: makeRequest(filterPID: pid,
                                           maximumCount: maximumCount,
                                           includeWindowlessFinder: false,
                                           groupByApp: false,
                                           currentSpaceOnly: false)).items
    }

    static func makeRequest(filterPID: pid_t? = nil,
                            maximumCount: Int = WindowEnumerator.maximumCount,
                            includeWindowlessFinder: Bool? = nil,
                            groupByApp: Bool? = nil,
                            currentSpaceOnly: Bool? = nil) -> Request {
        let apps = NSWorkspace.shared.runningApplications.map { app in
            RunningApp(pid: app.processIdentifier,
                       isRegular: app.activationPolicy == .regular,
                       localizedName: app.localizedName ?? "",
                       bundleIdentifier: app.bundleIdentifier,
                       bundlePath: app.bundleURL?.path,
                       executablePath: app.executableURL?.path)
        }
        let ownWindowTitles: [CGWindowID: String] = Dictionary(
            uniqueKeysWithValues: NSApp.windows.compactMap { window -> (CGWindowID, String)? in
                guard window.styleMask.contains(.titled),
                      window.canBecomeKey,
                      window.isVisible || window.isMiniaturized else { return nil }
                return (CGWindowID(window.windowNumber), window.title.isEmpty ? AppInfo.name : window.title)
            })
        let activationRanks = Dictionary(uniqueKeysWithValues:
            AppActivationTracker.shared.mru.enumerated().map { ($0.element, $0.offset) })
        return Request(filterPID: filterPID,
                       maximumCount: maximumCount,
                       includeWindowlessFinder: includeWindowlessFinder
                        ?? UserDefaults.standard.bool(forKey: DefaultsKey.switcherShowWindowlessFinder),
                       groupByApp: groupByApp
                        ?? UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs),
                       currentSpaceOnly: currentSpaceOnly
                        ?? UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly),
                       ownPID: ProcessInfo.processInfo.processIdentifier,
                       apps: apps,
                       ownWindowTitles: ownWindowTitles,
                       screenFrames: NSScreen.screens.map(\.frame),
                       activationRanks: activationRanks,
                       hasAccessibility: Permissions.shared.accessibility)
    }

    static func captureSnapshot(using request: Request) -> Snapshot {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

        let ownPid = request.ownPID
        let runningApps = request.apps
        var regularApps: [pid_t: String] = [:]
        var regularBundlePaths: [pid_t: String] = [:]
        for app in runningApps where app.isRegular {
            regularApps[app.pid] = app.localizedName
            if let path = app.bundlePath {
                regularBundlePaths[app.pid] = path
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
            executablePath: app.executablePath,
            localizedName: app.localizedName) {
            compatibilityLayerPids.insert(app.pid)
            if regularApps[app.pid] == nil {
                regularApps[app.pid] = app.localizedName
            }
        }
        let embeddedHostPairs: [(pid_t, pid_t)] = runningApps.compactMap { app in
            guard !app.isRegular,
                  let helperPath = app.bundlePath,
                  let hostPID = SwitcherSupport.embeddedHostPID(helperBundlePath: helperPath,
                                                               regularBundlePaths: regularBundlePaths)
            else { return nil }
            return (app.pid, hostPID)
        }
        let embeddedHostPIDs = Dictionary(uniqueKeysWithValues: embeddedHostPairs)
        // The regular process owns the app identity, but an embedded accessory
        // process can own its real windows. Query both sides of that mapping.
        let accessibilityPids: Set<pid_t>
        if let filterPID = request.filterPID {
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
                                                        undescribedSubrolePids: compatibilityLayerPids,
                                                        hasAccessibility: request.hasAccessibility,
                                                        screenFrames: request.screenFrames)

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
            if let filterPID = request.filterPID, appPID != filterPID { continue }
            // Current-Space mode (issue #337): windows living on another
            // desktop are left out entirely, including minimized ones that
            // kept their desktop of origin, so picking an entry never moves
            // the user somewhere else. Windows the server cannot place on any
            // Space are not "elsewhere", so they keep the regular treatment.
            if request.currentSpaceOnly, isOnHiddenSpace(CGWindowID(windowID)) { continue }
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
            let isFullscreen = (axWindow?.isFullscreen ?? false)
                || frameLooksFullscreen(cgFrame, screenFrames: request.screenFrames)
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
                guard let title = request.ownWindowTitles[windowID] else { continue }
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
                                       filterPID: request.filterPID,
                                       ownPID: request.ownPID,
                                       activationRanks: request.activationRanks,
                                       excludeWindow: {
                                           request.currentSpaceOnly && isOnHiddenSpace($0)
                                       })
        if request.includeWindowlessFinder {
            appendWindowlessFinder(to: &windows,
                                   regularApps: regularApps,
                                   runningApps: runningApps)
        }
        if request.groupByApp {
            windows = groupWindowsByApp(windows)
        }
        let ordered = orderByActivation(windows, activationRanks: request.activationRanks)
        let items: [SwitcherItem]
        if ordered.count <= request.maximumCount {
            items = ordered
        } else {
            var trimmed = Array(ordered.prefix(request.maximumCount))
            // The windowless Finder tile is an explicit user choice; it must not
            // vanish just because the list happens to be full.
            if request.includeWindowlessFinder,
               let finderTile = ordered.dropFirst(request.maximumCount).first(where: { $0.windowID == nil }) {
                trimmed.append(finderTile)
            }
            items = trimmed
        }

        let focusedWindowIDs = accessibilityWindows.compactMapValues(\.focusedWindowID)
        let observationTargets = accessibilityWindows.mapValues { list in
            ObservationTarget(appElement: list.appElement,
                              windowsByID: list.windowElementsByID)
        }
        let rawWindowIDs = Set(raw.compactMap {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
        let existingWindowIDs = rawWindowIDs.union(items.compactMap(\.windowID))
        return Snapshot(items: items,
                        focusedWindowIDs: focusedWindowIDs,
                        existingWindowIDs: existingWindowIDs,
                        observationTargets: observationTargets,
                        capturedAt: ProcessInfo.processInfo.systemUptime)
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
        let focusedWindowID: CGWindowID?
        let appElement: AXUIElement
        let windowElementsByID: [CGWindowID: AXUIElement]
    }

    private static func accessibilityWindows(for pids: Set<pid_t>,
                                             undescribedSubrolePids: Set<pid_t> = [],
                                             hasAccessibility: Bool,
                                             screenFrames: [CGRect]) -> [pid_t: AccessibilityWindowSnapshotList] {
        guard hasAccessibility else { return [:] }

        var result: [pid_t: AccessibilityWindowSnapshotList] = [:]
        for pid in pids {
            guard let windows = accessibilityWindows(for: pid,
                                                     acceptsUndescribedSubroles: undescribedSubrolePids.contains(pid),
                                                     screenFrames: screenFrames)
            else { continue }
            result[pid] = windows
        }
        return result
    }

    private static func accessibilityWindows(for pid: pid_t,
                                             acceptsUndescribedSubroles: Bool = false,
                                             screenFrames: [CGRect]) -> AccessibilityWindowSnapshotList? {
        let app = AXUIElementCreateApplication(pid)
        // A catalog refresh normally runs on its worker. Callers that need a
        // one-off synchronous list still share this bound: an app that is not
        // servicing its run loop must never hold a window feature for the six
        // second default timeout (issue #189).
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
        var focusedWindow: AXUIElement?
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            let attributeName = attribute as String
            if let window = accessibilityWindowAttribute(app, attributeName) {
                AXUIElementSetMessagingTimeout(window, 0.35)
                if isUserFacingWindow(window, acceptsUndescribedSubroles: acceptsUndescribedSubroles) {
                    appendUnique(window, to: &axWindows)
                    if attributeName == (kAXFocusedWindowAttribute as String) {
                        focusedWindow = window
                    }
                }
            }
        }

        var byID: [CGWindowID: AccessibilityWindowSnapshot] = [:]
        var ordered: [(id: CGWindowID, snapshot: AccessibilityWindowSnapshot)] = []
        var windowElementsByID: [CGWindowID: AXUIElement] = [:]
        var focusedWindowID: CGWindowID?
        for window in axWindows {
            if let id = AXWindowResolver.windowID(for: window) {
                let frame = accessibilityFrame(for: window)
                let snapshot = AccessibilityWindowSnapshot(title: accessibilityTitle(for: window),
                                                           frame: frame,
                                                           isMinimized: boolAttribute(window, kAXMinimizedAttribute as String),
                                                           isFullscreen: isFullscreenWindow(window)
                                                            || frameLooksFullscreen(frame,
                                                                                    screenFrames: screenFrames))
                byID[id] = snapshot
                ordered.append((id, snapshot))
                windowElementsByID[id] = window
                if let focusedWindow, CFEqual(window, focusedWindow) {
                    focusedWindowID = id
                }
            }
        }

        // An app that answers with zero user-facing windows normally vetoes
        // its CG surfaces as stale ghosts. For a compatibility-layer process
        // an empty answer only means Accessibility could not describe the
        // windows, so withhold the veto instead of hiding real windows.
        if axWindows.isEmpty {
            return acceptsUndescribedSubroles
                ? nil
                : AccessibilityWindowSnapshotList(ordered: ordered,
                                                   byID: byID,
                                                   focusedWindowID: focusedWindowID,
                                                   appElement: app,
                                                   windowElementsByID: windowElementsByID)
        }
        // If an app reports AX windows but none resolve to WindowServer ids,
        // keep the old behavior instead of hiding a real window for that app.
        if !ordered.isEmpty {
            return AccessibilityWindowSnapshotList(ordered: ordered,
                                                   byID: byID,
                                                   focusedWindowID: focusedWindowID,
                                                   appElement: app,
                                                   windowElementsByID: windowElementsByID)
        }
        return nil
    }

    private static func appendAccessibilityOnlyWindows(to windows: inout [SwitcherItem],
                                                       snapshots: [pid_t: AccessibilityWindowSnapshotList],
                                                       regularApps: [pid_t: String],
                                                       embeddedHostPIDs: [pid_t: pid_t],
                                                       seen: inout Set<CGWindowID>,
                                                       filterPID: pid_t?,
                                                       ownPID: pid_t,
                                                       activationRanks: [pid_t: Int],
                                                       excludeWindow: (CGWindowID) -> Bool = { _ in false }) {
        let pids = snapshots.keys
            .filter { windowOwnerPID in
                guard windowOwnerPID != ownPID else { return false }
                let appPID = regularApps[windowOwnerPID] != nil
                    ? windowOwnerPID
                    : embeddedHostPIDs[windowOwnerPID]
                guard let appPID, regularApps[appPID] != nil else { return false }
                return filterPID == nil || appPID == filterPID
            }
            .sorted { lhs, rhs in
                let rankL = activationRanks[embeddedHostPIDs[lhs] ?? lhs] ?? Int.max
                let rankR = activationRanks[embeddedHostPIDs[rhs] ?? rhs] ?? Int.max
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

    private static func frameLooksFullscreen(_ frame: CGRect?, screenFrames: [CGRect]) -> Bool {
        guard let frame else { return false }
        return screenFrames.contains { screenFrame in
            abs(frame.width - screenFrame.width) <= 2
                && abs(frame.height - screenFrame.height) <= 2
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
                                               regularApps: [pid_t: String],
                                               runningApps: [RunningApp]) {
        guard let app = runningApps.first(where: {
            $0.bundleIdentifier == Defaults.finderBundleIdentifier && $0.isRegular
        }) else { return }
        let pid = app.pid
        guard windows.contains(where: { $0.pid == pid }) == false,
              regularApps[pid] != nil else { return }

        let name = app.localizedName.isEmpty ? "Finder" : app.localizedName
        windows.append(.appOnly(appName: name, pid: pid))
    }

    /// Groups windows by app in most-recently-used order while preserving the
    /// window server's front-to-back order within each app. A stable sort is
    /// required so the within-app order survives the regrouping. This is what
    /// puts the window you were just in (including another window of the same
    /// app) right next to the current one.
    private static func orderByActivation(_ windows: [SwitcherItem],
                                          activationRanks: [pid_t: Int]) -> [SwitcherItem] {
        return windows.enumerated().sorted { lhs, rhs in
            let rankL = activationRanks[lhs.element.pid] ?? Int.max
            let rankR = activationRanks[rhs.element.pid] ?? Int.max
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
