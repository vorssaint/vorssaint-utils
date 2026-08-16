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
/// The result is then ordered by how recently each window was used (see
/// `WindowUseTracker`), so the switcher matches the system ⌘Tab toggle.
/// Window titles require Screen Recording on modern macOS; Vorssaint's own
/// titled windows use NSWindow metadata so Settings remains reachable even
/// though the app is a menu-bar accessory.
enum WindowEnumerator {
    /// Window surfaces larger than this are considered real, switchable windows.
    private static let minimumSize = CGSize(width: 80, height: 60)
    /// Hard cap to keep the switcher readable and captures cheap.
    private static let maximumCount = 24
    /// AX calls normally return in a few milliseconds. A process that cannot
    /// answer within this ceiling must not hold the switcher behind it.
    private static let messagingTimeout: Float = 0.2
    /// The app normally owns about twenty threads. This keeps a large helper
    /// tree within the process thread budget while collapsing it into a few
    /// bounded AX batches.
    private static let maximumConcurrentQueries = 24

    struct SwitcherSnapshot {
        struct Application {
            let pid: pid_t
            let bundleIdentifier: String?
            let localizedName: String?
            let isRegular: Bool
            let isTerminated: Bool
            let bundlePath: String?
            let executablePath: String?
        }

        let rawWindows: [[String: Any]]
        let applications: [Application]
        let ownPID: pid_t
        let ownWindowTitles: [CGWindowID: String]
        let frontToBack: WindowUseTracker.FrontToBack
        let windowHistory: [CGWindowID]
        let appHistory: [pid_t]
        let screenFrames: [CGRect]
        let accessibilityGranted: Bool
        let windowlessApps: SwitcherWindowlessApps
        let appRules: [String: SwitcherAppRule]
        let groupByApp: Bool
        let currentSpaceOnly: Bool
    }

    /// Captures AppKit, preference, and WindowServer input on main. Slow
    /// Accessibility and private Space lookups run later on the cache worker.
    static func captureSwitcherSnapshot() -> SwitcherSnapshot {
        dispatchPrecondition(condition: .onQueue(.main))
        let defaults = UserDefaults.standard
        return captureSnapshot(
            windowlessApps: SwitcherWindowlessApps.mode(
                storedValue: defaults.string(forKey: DefaultsKey.switcherWindowlessApps)),
            appRules: SwitcherAppRule.rules(
                storedValue: defaults.dictionary(forKey: DefaultsKey.switcherAppRules)),
            groupByApp: defaults.bool(forKey: DefaultsKey.switcherMergeTabs),
            currentSpaceOnly: defaults.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
        )
    }

    /// Captures the Command Bar's broader window list on main. Its completion
    /// deliberately ignores Switcher app rules so hidden apps remain searchable.
    static func captureCommandBarSnapshot() -> SwitcherSnapshot {
        dispatchPrecondition(condition: .onQueue(.main))
        let defaults = UserDefaults.standard
        return captureSnapshot(
            windowlessApps: SwitcherWindowlessApps.mode(
                storedValue: defaults.string(forKey: DefaultsKey.switcherWindowlessApps)),
            appRules: [:],
            groupByApp: defaults.bool(forKey: DefaultsKey.switcherMergeTabs),
            currentSpaceOnly: defaults.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
        )
    }

    private static func captureSnapshot(windowlessApps: SwitcherWindowlessApps,
                                        appRules: [String: SwitcherAppRule],
                                        groupByApp: Bool,
                                        currentSpaceOnly: Bool) -> SwitcherSnapshot {
        dispatchPrecondition(condition: .onQueue(.main))
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let runningApps = NSWorkspace.shared.runningApplications
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windowIDs = raw.compactMap {
            ($0[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) }
        }
        let frontToBack = WindowUseTracker.frontToBack()
        WindowUseTracker.shared.reconcile(existingWindows: Set(windowIDs),
                                          frontToBack: frontToBack,
                                          running: Set(runningApps.map(\.processIdentifier)))
        let ownWindowTitlePairs: [(CGWindowID, String)] = (NSApp?.windows ?? []).compactMap { window in
            guard window.styleMask.contains(.titled), window.canBecomeKey,
                  window.isVisible || window.isMiniaturized else { return nil }
            let title = window.title.isEmpty ? AppInfo.name : window.title
            return (CGWindowID(window.windowNumber), title)
        }
        let ownWindowTitles = Dictionary(uniqueKeysWithValues: ownWindowTitlePairs)
        return SwitcherSnapshot(
            rawWindows: raw,
            applications: runningApps.map { app in
                SwitcherSnapshot.Application(pid: app.processIdentifier,
                                             bundleIdentifier: app.bundleIdentifier,
                                             localizedName: app.localizedName,
                                             isRegular: app.activationPolicy == .regular,
                                             isTerminated: app.isTerminated,
                                             bundlePath: app.bundleURL?.path,
                                             executablePath: app.executableURL?.path)
            },
            ownPID: pid_t(ownPID),
            ownWindowTitles: ownWindowTitles,
            frontToBack: frontToBack,
            windowHistory: WindowUseTracker.shared.windows,
            appHistory: WindowUseTracker.shared.apps,
            screenFrames: NSScreen.screens.map(\.frame),
            accessibilityGranted: NSApp == nil
                ? AXIsProcessTrusted()
                : Permissions.shared.accessibility,
            windowlessApps: windowlessApps,
            appRules: appRules,
            groupByApp: groupByApp,
            currentSpaceOnly: currentSpaceOnly
        )
    }

    static func listWindows(from snapshot: SwitcherSnapshot) -> [SwitcherItem] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return listWindows(snapshot: snapshot, filterPID: nil, maximumCount: maximumCount)
    }

    static func listWindowsForCommandBar(from snapshot: SwitcherSnapshot) -> [SwitcherItem] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return listWindows(snapshot: snapshot, filterPID: nil, maximumCount: maximumCount)
    }

    /// Captures the main-thread-only inputs for cache validation. Private Space
    /// membership is resolved later on the cache worker.
    static func captureSwitcherFingerprint() -> SwitcherWindowFingerprint {
        dispatchPrecondition(condition: .onQueue(.main))
        let defaults = UserDefaults.standard
        let currentSpaceOnly = defaults.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = raw.compactMap { info -> SwitcherWindowFingerprint.Window? in
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any]
            else { return nil }
            let bounds = CGRect(x: (boundsDictionary["X"] as? NSNumber)?.doubleValue ?? 0,
                                y: (boundsDictionary["Y"] as? NSNumber)?.doubleValue ?? 0,
                                width: (boundsDictionary["Width"] as? NSNumber)?.doubleValue ?? 0,
                                height: (boundsDictionary["Height"] as? NSNumber)?.doubleValue ?? 0)
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? (info[kCGWindowIsOnscreen as String] as? Bool)
                ?? false
            return SwitcherWindowFingerprint.Window(
                id: CGWindowID(id),
                ownerPID: ownerPID,
                layer: layer,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: bounds,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                isOnScreen: isOnScreen,
                spaces: []
            )
        }
        let applications = NSWorkspace.shared.runningApplications.map { app in
            SwitcherWindowFingerprint.Application(
                pid: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                name: app.localizedName,
                isRegular: app.activationPolicy == .regular,
                isTerminated: app.isTerminated,
                bundlePath: app.bundleURL?.path,
                executablePath: app.executableURL?.path
            )
        }.sorted { $0.pid < $1.pid }
        let appRules = SwitcherAppRule.rules(
            storedValue: defaults.dictionary(forKey: DefaultsKey.switcherAppRules)
        )
        return SwitcherWindowFingerprint(
            windows: windows,
            applications: applications,
            visibleSpaces: [],
            preferences: .init(
                appRules: appRules,
                windowlessApps: defaults.string(forKey: DefaultsKey.switcherWindowlessApps),
                mergeTabs: defaults.bool(forKey: DefaultsKey.switcherMergeTabs),
                currentSpaceOnly: currentSpaceOnly
            )
        )
    }

    /// Completes cache validation away from main. Current Desktop Only must
    /// include Space membership so moving a window invalidates a warm list.
    static func resolveSwitcherFingerprint(
        _ captured: SwitcherWindowFingerprint
    ) -> SwitcherWindowFingerprint {
        SwitcherSupport.resolvingFingerprintSpaces(
            captured,
            spacesOf: SpaceWindowBridge.spaces,
            visibleSpaces: { SpaceWindowBridge.topology()?.visibleSpaces ?? [] }
        )
    }

    static func listWindows() -> [SwitcherItem] {
        listWindows(appRules: SwitcherAppRule.rules(
            storedValue: UserDefaults.standard.dictionary(forKey: DefaultsKey.switcherAppRules)))
    }

    private static func listWindows(appRules: [String: SwitcherAppRule]) -> [SwitcherItem] {
        let windowlessApps = SwitcherWindowlessApps.mode(
            storedValue: UserDefaults.standard.string(forKey: DefaultsKey.switcherWindowlessApps))
        return listWindows(filterPID: nil,
                           maximumCount: maximumCount,
                           windowlessApps: windowlessApps,
                           appRules: appRules,
                           groupByApp: UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs),
                           currentSpaceOnly: UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly))
    }

    static func listWindows(for pid: pid_t, maximumCount: Int = 12) -> [SwitcherItem] {
        // The current-desktop choice belongs to the switcher alone (issue
        // #337): its caption promises it trims the switcher list, nothing
        // else. Dock previews keep showing windows from every desktop, the
        // behavior issue #339 made first-class; honoring the toggle here
        // would leave an empty preview with no setting anywhere near the
        // Dock to explain it.
        // An entry for the app itself belongs to the switcher alone for the
        // same reason: a Dock preview is opened by pointing at one app's icon,
        // so a card naming that app says nothing the pointer did not, and
        // picking it would only repeat the Dock click.
        listWindows(filterPID: pid,
                    maximumCount: maximumCount,
                    windowlessApps: .off,
                    appRules: [:],
                    groupByApp: false,
                    currentSpaceOnly: false)
    }

    /// Re-enumerates one app using the switcher's live visibility contract.
    /// Release validation stays bounded without borrowing the Dock preview's
    /// deliberately broader rules.
    static func listSwitcherWindows(for pid: pid_t, maximumCount: Int = 64) -> [SwitcherItem] {
        let defaults = UserDefaults.standard
        return listWindows(
            filterPID: pid,
            maximumCount: maximumCount,
            windowlessApps: SwitcherWindowlessApps.mode(
                storedValue: defaults.string(forKey: DefaultsKey.switcherWindowlessApps)),
            appRules: SwitcherAppRule.rules(
                storedValue: defaults.dictionary(forKey: DefaultsKey.switcherAppRules)),
            groupByApp: defaults.bool(forKey: DefaultsKey.switcherMergeTabs),
            currentSpaceOnly: defaults.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
        )
    }

    /// Re-reads just the app that owns a release candidate. This AX-aware
    /// check catches closed, minimized, restored, fullscreen and AX-only
    /// windows without making the consumed shortcut enumerate every app.
    static func refreshedSwitcherCandidate(_ item: SwitcherItem) -> SwitcherItem? {
        dispatchPrecondition(condition: .onQueue(.main))
        let groupedByApp = UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs)
        return SwitcherSupport.eligibleCandidate(
            item,
            in: listSwitcherWindows(for: item.pid),
            groupedByApp: groupedByApp
        )
    }

    private static func listWindows(filterPID: pid_t?,
                                    maximumCount: Int,
                                    windowlessApps: SwitcherWindowlessApps,
                                    appRules: [String: SwitcherAppRule],
                                    groupByApp: Bool,
                                    currentSpaceOnly: Bool) -> [SwitcherItem] {
        let snapshot = captureSnapshot(windowlessApps: windowlessApps,
                                       appRules: appRules,
                                       groupByApp: groupByApp,
                                       currentSpaceOnly: currentSpaceOnly)
        return listWindows(snapshot: snapshot,
                           filterPID: filterPID,
                           maximumCount: maximumCount)
    }

    private static func listWindows(snapshot: SwitcherSnapshot,
                                    filterPID: pid_t?,
                                    maximumCount: Int) -> [SwitcherItem] {
        let raw = snapshot.rawWindows
        let ownPid = snapshot.ownPID
        let runningApps = snapshot.applications
        let appRules = snapshot.appRules
        let groupByApp = snapshot.groupByApp
        let currentSpaceOnly = snapshot.currentSpaceOnly
        let windowlessApps = snapshot.windowlessApps
        let bundleIdentifiers = SwitcherSupport.firstValuesByPID(runningApps.compactMap { app in
            app.bundleIdentifier.map { (app.pid, $0) }
        })
        var regularApps: [pid_t: String] = [:]
        var regularBundlePaths: [pid_t: String] = [:]
        for app in runningApps where app.isRegular {
            regularApps[app.pid] = app.localizedName ?? ""
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
                regularApps[app.pid] = app.localizedName ?? ""
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
        let embeddedHostPIDs = SwitcherSupport.firstValuesByPID(embeddedHostPairs)
        // The regular process owns the app identity, but an embedded accessory
        // process can own its real windows. Query both sides of that mapping.
        let accessibilityPids = SwitcherSupport.accessibilityPIDs(
            regularAppPIDs: Set(regularApps.keys),
            embeddedHostPIDs: embeddedHostPIDs,
            ownPID: pid_t(ownPid),
            filterPID: filterPID)
        let accessibilityWindows = accessibilityWindows(for: accessibilityPids,
                                                        bundleIdentifiers: bundleIdentifiers,
                                                        undescribedSubrolePids: compatibilityLayerPids,
                                                        screenFrames: snapshot.screenFrames,
                                                        accessibilityGranted: snapshot.accessibilityGranted)

        var seen = Set<CGWindowID>()
        var windows: [SwitcherItem] = []
        // Apps whose windows exist but were left out on purpose. They must
        // never look windowless afterwards: handing them an entry of their own
        // would put back exactly what the user asked to hide, and picking it
        // would carry them to the desktop they chose to stay away from.
        var withheldPIDs = Set<pid_t>()

        // Accessibility cannot describe windows parked on a Space that is not
        // visible, so the ghost veto below would silently hide real windows
        // (issue #339). The window server tells them apart: a real parked
        // window belongs to a Space, a stale leftover surface belongs to none.
        // Resolved lazily and cached, so fully Accessibility-confirmed lists
        // pay nothing.
        var spaceResolver = SwitcherSpaceResolver(
            loadVisibleSpaces: { SpaceWindowBridge.topology()?.visibleSpaces ?? [] },
            loadWindowSpaces: SpaceWindowBridge.spaces,
            loadExcludedFromCycle: SpaceWindowBridge.isExcludedFromWindowCycle
        )
        func isOnHiddenSpace(_ windowID: CGWindowID) -> Bool {
            spaceResolver.isOnHiddenSpace(windowID)
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
            if SwitcherSupport.hidesApp(bundleIdentifier: bundleIdentifiers[appPID],
                                        appRules: appRules) { continue }
            // Current-Space mode (issue #337): windows living on another
            // desktop are left out entirely, including minimized ones that
            // kept their desktop of origin, so picking an entry never moves
            // the user somewhere else. Windows the server cannot place on any
            // Space are not "elsewhere", so they keep the regular treatment.
            if currentSpaceOnly, isOnHiddenSpace(CGWindowID(windowID)) {
                withheldPIDs.insert(appPID)
                continue
            }
            let axWindow = accessibilityWindows[windowOwnerPID]?.byID[CGWindowID(windowID)]
            if accessibilityWindows[windowOwnerPID] != nil, axWindow == nil,
               (!isOnHiddenSpace(CGWindowID(windowID))
                || spaceResolver.isExcludedFromCycle(CGWindowID(windowID))) {
                continue
            }
            let cgFrame = CGRect(x: (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0,
                                 y: (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0,
                                 width: (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0,
                                 height: (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0)
            let isMinimized = axWindow?.isMinimized ?? false
            let isFullscreen = (axWindow?.isFullscreen ?? false)
                || frameLooksFullscreen(cgFrame, screenFrames: snapshot.screenFrames)
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
                guard let title = snapshot.ownWindowTitles[windowID] else { continue }
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
                                       appHistory: snapshot.appHistory,
                                       ownPID: ownPid,
                                       seen: &seen,
                                       filterPID: filterPID,
                                       excludeWindow: { windowID, appPID in
                                           if SwitcherSupport.hidesApp(
                                               bundleIdentifier: bundleIdentifiers[appPID],
                                               appRules: appRules) { return true }
                                           guard currentSpaceOnly, isOnHiddenSpace(windowID) else { return false }
                                           withheldPIDs.insert(appPID)
                                           return true
                                       })
        appendWindowlessApps(to: &windows,
                             mode: windowlessApps,
                             runningApps: runningApps,
                             regularApps: regularApps,
                             accessibilityWindows: accessibilityWindows,
                             ownPID: pid_t(ownPid),
                             withheldPIDs: withheldPIDs,
                             appRules: appRules)
        if groupByApp {
            windows = groupWindowsByApp(windows)
        }
        let ordered = orderByUse(windows,
                                 frontToBack: snapshot.frontToBack,
                                 windowHistory: snapshot.windowHistory,
                                 appHistory: snapshot.appHistory)
        guard ordered.count > maximumCount else { return ordered }
        var trimmed = Array(ordered.prefix(maximumCount))
        // Asking for the desktop app alone names one entry, so that entry must
        // not vanish just because the list happens to be full. Asking for every
        // windowless app is a bulk choice instead, and there the cap keeps
        // cutting the least recently used tail exactly as it does for windows.
        if windowlessApps == .finder,
           let desktopEntry = ordered.dropFirst(maximumCount).first(where: { $0.windowID == nil }) {
            trimmed.append(desktopEntry)
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
                                             bundleIdentifiers: [pid_t: String] = [:],
                                             undescribedSubrolePids: Set<pid_t> = [],
                                             screenFrames: [CGRect]? = nil,
                                             accessibilityGranted: Bool? = nil) -> [pid_t: AccessibilityWindowSnapshotList] {
        guard accessibilityGranted ?? Permissions.shared.accessibility else { return [:] }

        let orderedPIDs = pids.sorted()
        guard !orderedPIDs.isEmpty else { return [:] }
        let screenFrames = screenFrames ?? NSScreen.screens.map(\.frame)
        var result: [pid_t: AccessibilityWindowSnapshotList] = [:]
        let resultLock = NSLock()
        // A remote app can consume its whole messaging timeout. Overlap those
        // independent calls so several slow background helpers cost one wait,
        // not one wait each, while preserving Accessibility-only windows. The
        // bound keeps a helper-heavy app from creating an unbounded thread burst.
        let queryQueue = OperationQueue()
        queryQueue.qualityOfService = .userInteractive
        queryQueue.maxConcurrentOperationCount = min(maximumConcurrentQueries, orderedPIDs.count)
        for pid in orderedPIDs {
            queryQueue.addOperation {
                guard let windows = accessibilityWindows(
                    for: pid,
                    bundleIdentifier: bundleIdentifiers[pid],
                    acceptsUndescribedSubroles: undescribedSubrolePids.contains(pid),
                    screenFrames: screenFrames
                ) else { return }
                resultLock.lock()
                result[pid] = windows
                resultLock.unlock()
            }
        }
        queryQueue.waitUntilAllOperationsAreFinished()
        return result
    }

    private static func accessibilityWindows(for pid: pid_t,
                                             bundleIdentifier: String? = nil,
                                             acceptsUndescribedSubroles: Bool = false,
                                             screenFrames: [CGRect]) -> AccessibilityWindowSnapshotList? {
        let app = AXUIElementCreateApplication(pid)
        // An app that is not servicing its run loop must not hold a query batch
        // for Accessibility's six-second default (issue #189).
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var axWindows: [AXUIElement] = []
        var value: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        // Not responding: skip the remaining calls, each would block again.
        guard windowsResult != .cannotComplete else { return nil }
        if windowsResult == .success, let windows = value as? [AXUIElement] {
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.35)
                if isUserFacingWindow(window,
                                      bundleIdentifier: bundleIdentifier,
                                      acceptsUndescribedSubroles: acceptsUndescribedSubroles,
                                      screenFrames: screenFrames) {
                    appendUnique(window, to: &axWindows)
                }
            }
        }
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let window = accessibilityWindowAttribute(app, attribute as String) {
                AXUIElementSetMessagingTimeout(window, 0.35)
                if isUserFacingWindow(window,
                                      bundleIdentifier: bundleIdentifier,
                                      acceptsUndescribedSubroles: acceptsUndescribedSubroles,
                                      screenFrames: screenFrames) {
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
                                                            || frameLooksFullscreen(frame,
                                                                                    screenFrames: screenFrames))
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
                                                       appHistory: [pid_t],
                                                       ownPID: pid_t,
                                                       seen: inout Set<CGWindowID>,
                                                       filterPID: pid_t?,
                                                       excludeWindow: (CGWindowID, pid_t) -> Bool = { _, _ in false }) {
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
                let rankL = appHistory.firstIndex(of: embeddedHostPIDs[lhs] ?? lhs) ?? Int.max
                let rankR = appHistory.firstIndex(of: embeddedHostPIDs[rhs] ?? rhs) ?? Int.max
                return rankL != rankR ? rankL < rankR : lhs < rhs
            }

        for windowOwnerPID in pids {
            let appPID = embeddedHostPIDs[windowOwnerPID] ?? windowOwnerPID
            guard let appName = regularApps[appPID],
                  let list = snapshots[windowOwnerPID] else { continue }
            for entry in list.ordered {
                guard !seen.contains(entry.id),
                      !excludeWindow(entry.id, appPID),
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

    private static func frameLooksFullscreen(_ frame: CGRect?,
                                             screenFrames: [CGRect]? = nil) -> Bool {
        guard let frame else { return false }
        let frames = screenFrames ?? NSScreen.screens.map(\.frame)
        return frames.contains { screenFrame in
            abs(frame.width - screenFrame.width) <= 2
                && abs(frame.height - screenFrame.height) <= 2
        }
    }

    private static func isUserFacingWindow(_ window: AXUIElement,
                                           bundleIdentifier: String? = nil,
                                           acceptsUndescribedSubroles: Bool = false,
                                           screenFrames: [CGRect]) -> Bool {
        if isFullscreenWindow(window) { return true }
        if boolAttribute(window, kAXMinimizedAttribute as String),
           stringAttribute(window, kAXRoleAttribute as String) == (kAXWindowRole as String) {
            return true
        }
        if let subrole = stringAttribute(window, kAXSubroleAttribute as String) {
            if subrole == "AXStandardWindow" || subrole == "AXFullScreenWindow" { return true }
            if SwitcherSupport.isSupportedMediaFloatingWindow(bundleIdentifier: bundleIdentifier,
                                                              subrole: subrole) { return true }
            let role = stringAttribute(window, kAXRoleAttribute as String)
            let canBePlaybackSurface = subrole == "AXUnknown" || subrole == "AXFloatingWindow"
            let fillsScreen = canBePlaybackSurface
                && frameLooksFullscreen(accessibilityFrame(for: window), screenFrames: screenFrames)
            // Compatibility-layer processes draw their own window chrome on
            // borderless surfaces, which Accessibility reports as AXUnknown;
            // for them the window role is the real signal.
            // Other apps can expose full-screen playback the same way. The
            // screen-sized frame keeps ordinary utility windows filtered.
            return SwitcherSupport.isSwitchableNonstandardWindow(
                role: role,
                subrole: subrole,
                fillsScreen: fillsScreen,
                acceptsUndescribedSubroles: acceptsUndescribedSubroles)
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

    /// Adds the apps that are running with no window to switch to, so the list
    /// can offer what the system switcher offers.
    ///
    /// Missing from the window list is not proof on its own. Accessibility is
    /// blind to windows parked on a desktop that is not visible, and an app
    /// busy enough not to answer reports nothing either; both would be handed
    /// an entry saying they have no window when they do. Only an app that
    /// answered and described zero user-facing windows qualifies, which is
    /// also what keeps menu bar agents, embedded helpers and programs running
    /// through a compatibility layer out of the list.
    private static func appendWindowlessApps(to windows: inout [SwitcherItem],
                                             mode: SwitcherWindowlessApps,
                                             runningApps: [SwitcherSnapshot.Application],
                                             regularApps: [pid_t: String],
                                             accessibilityWindows: [pid_t: AccessibilityWindowSnapshotList],
                                             ownPID: pid_t,
                                             withheldPIDs: Set<pid_t>,
                                             appRules: [String: SwitcherAppRule]) {
        // The window server order is stable across calls, so apps that were
        // never brought to the front keep a settled place instead of shuffling
        // between one press and the next.
        let candidates = runningApps.compactMap { app -> SwitcherAppCandidate? in
            let pid = app.pid
            guard app.isRegular,
                  !app.isTerminated,
                  pid != ownPID,
                  regularApps[pid]?.isEmpty == false,
                  accessibilityWindows[pid]?.ordered.isEmpty == true
            else { return nil }
            return SwitcherAppCandidate(pid: pid, bundleIdentifier: app.bundleIdentifier)
        }
        let chosen = SwitcherSupport.windowlessAppPIDs(
            mode: mode,
            candidates: candidates,
            pidsWithWindows: Set(windows.map(\.pid)),
            pidsWithWithheldWindows: withheldPIDs,
            desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
            appRules: appRules)
        for pid in chosen {
            guard let name = regularApps[pid] else { continue }
            windows.append(.appOnly(appName: name, pid: pid))
        }
    }

    private static func ownWindowTitle(for windowID: CGWindowID) -> String? {
        guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }),
              window.styleMask.contains(.titled),
              window.canBecomeKey,
              window.isVisible || window.isMiniaturized else { return nil }
        return window.title.isEmpty ? AppInfo.name : window.title
    }

    /// Orders windows by how recently the user used them, so the entry next to
    /// the current one is the window they came from — another app's window, or
    /// another window of the same app, whichever was really used last.
    private static func orderByUse(_ windows: [SwitcherItem],
                                   frontToBack: WindowUseTracker.FrontToBack,
                                   windowHistory: [CGWindowID],
                                   appHistory: [pid_t]) -> [SwitcherItem] {
        let entries = windows.map { WindowUseOrder.Entry(windowID: $0.windowID, pid: $0.pid) }
        return WindowUseOrder.order(entries,
                                    windowHistory: windowHistory,
                                    appHistory: appHistory,
                                    frontToBack: frontToBack.windows)
            .map { windows[$0] }
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
