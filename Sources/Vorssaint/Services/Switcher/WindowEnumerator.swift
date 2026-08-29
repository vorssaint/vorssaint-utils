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
    /// Ceiling on the whole batch, which the main thread waits out. Generous
    /// against the messaging timeouts above even with every query as slow as
    /// they allow, so only a dispatch pool with no thread to give can outlast
    /// it (issue #971) — and then no answer was ever coming. A stalled main
    /// thread stalls the event taps with it (issue #189), so it must expire.
    private static let accessibilityBatchBudget: TimeInterval = 5.0

    static func listWindows(groupByApp: Bool = UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs),
                            preservingGroupedWindows: Bool = false) -> [SwitcherItem] {
        listWindows(
            appRules: SwitcherAppRule.rules(
                storedValue: UserDefaults.standard.dictionary(forKey: DefaultsKey.switcherAppRules)),
            groupByApp: groupByApp,
            preservingGroupedWindows: preservingGroupedWindows,
            marksHiddenSpaces: true
        )
    }

    /// The Command Bar shares the window walk, not the Switcher's visibility
    /// preferences. An app hidden from ⌘Tab must remain searchable there.
    static func listWindowsForCommandBar() -> [SwitcherItem] {
        listWindows(appRules: [:], groupByApp: false,
                    preservingGroupedWindows: false, marksHiddenSpaces: false)
    }

    private static func listWindows(appRules: [String: SwitcherAppRule],
                                    groupByApp: Bool,
                                    preservingGroupedWindows: Bool,
                                    marksHiddenSpaces: Bool) -> [SwitcherItem] {
        let windowlessApps = SwitcherWindowlessApps.mode(
            storedValue: UserDefaults.standard.string(forKey: DefaultsKey.switcherWindowlessApps))
        let currentSpaceOnly = UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
        let minimizedPlacement = WindowSwitchMinimizedPlacement(
            rawValue: UserDefaults.standard.string(forKey: DefaultsKey.switcherMinimizedPlacement) ?? ""
        ) ?? .normal
        let showFullscreenWindows = UserDefaults.standard.object(forKey: DefaultsKey.switcherShowFullscreenWindows) as? Bool ?? true
        return listWindows(filterPID: nil,
                           maximumCount: maximumCount,
                           windowlessApps: windowlessApps,
                           appRules: appRules,
                           groupByApp: groupByApp,
                           minimizedPlacement: minimizedPlacement,
                           showFullscreenWindows: showFullscreenWindows,
                           preservingGroupedWindows: preservingGroupedWindows,
                           currentSpaceOnly: currentSpaceOnly,
                           marksHiddenSpaces: marksHiddenSpaces && !currentSpaceOnly)
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
                    minimizedPlacement: .normal,
                    showFullscreenWindows: true,
                    preservingGroupedWindows: false,
                    currentSpaceOnly: false,
                    marksHiddenSpaces: false)
    }

    private static func listWindows(filterPID: pid_t?,
                                    maximumCount: Int,
                                    windowlessApps: SwitcherWindowlessApps,
                                    appRules: [String: SwitcherAppRule],
                                    groupByApp: Bool,
                                    minimizedPlacement: WindowSwitchMinimizedPlacement,
                                    showFullscreenWindows: Bool,
                                    preservingGroupedWindows: Bool,
                                    currentSpaceOnly: Bool,
                                    marksHiddenSpaces: Bool) -> [SwitcherItem] {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

        let ownPid = ProcessInfo.processInfo.processIdentifier
        // Terminating processes linger in the workspace list while they shut
        // down, and the window server can keep their surfaces for a moment
        // after that. Mapping those pids to a regular app used to admit their
        // leftover surfaces as switchable windows, which is how an app's
        // preview outlived its quit (issue #807).
        let runningApps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let hiddenAppPIDs = Set(runningApps.lazy
            .filter { $0.isHidden }
            .map(\.processIdentifier))
        let bundleIdentifiers = SwitcherSupport.firstValuesByPID(runningApps.compactMap { app in
            app.bundleIdentifier.map { (app.processIdentifier, $0) }
        })
        // Bring the use history up to date before ordering by it: windows that
        // are gone leave, and any window that appeared without ever taking
        // focus is filed by the window server's front-to-back order.
        let frontToBack = WindowUseTracker.frontToBack()
        WindowUseTracker.shared.reconcile(
            existingWindows: Set(raw.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }),
            frontToBack: frontToBack,
            running: Set(runningApps.map(\.processIdentifier)))
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
                                                        undescribedSubrolePids: compatibilityLayerPids)

        var seen = Set<CGWindowID>()
        var windows: [SwitcherItem] = []
        // Apps whose windows exist but were left out on purpose. They must
        // never look windowless afterwards: handing them an entry of their own
        // would put back exactly what the user asked to hide, and picking it
        // would carry them to the desktop they chose to stay away from.
        var withheldPIDs = Set<pid_t>()

        // Accessibility cannot describe windows parked on a Space that is not
        // visible, so the ghost veto below needs the window server as a second
        // witness. A stale surface can retain an old Space assignment, so
        // membership alone is not proof that it is still a real window.
        // Resolved lazily and cached, so fully Accessibility-confirmed lists
        // pay nothing.
        var topologyResolved = false
        var topology: SpaceWindowBridge.Topology?
        var windowSpaces: [CGWindowID: [UInt64]] = [:]
        var hiddenSpaceVerdicts: [CGWindowID: Bool] = [:]
        var fullscreenSpaceVerdicts: [CGWindowID: Bool] = [:]
        func resolvedTopology() -> SpaceWindowBridge.Topology? {
            if !topologyResolved {
                topology = SpaceWindowBridge.topology()
                topologyResolved = true
            }
            return topology
        }
        func spaces(of windowID: CGWindowID) -> [UInt64] {
            if let cached = windowSpaces[windowID] { return cached }
            let resolved = SpaceWindowBridge.spaces(of: windowID)
            windowSpaces[windowID] = resolved
            return resolved
        }
        func isOnHiddenSpace(_ windowID: CGWindowID) -> Bool {
            if let verdict = hiddenSpaceVerdicts[windowID] { return verdict }
            guard let visible = resolvedTopology()?.visibleSpaces, !visible.isEmpty else { return false }
            let verdict = SpaceHopSupport.isParkedOnHiddenSpace(
                windowSpaces: spaces(of: windowID),
                visibleSpaces: visible
            )
            hiddenSpaceVerdicts[windowID] = verdict
            return verdict
        }
        func isOnFullscreenSpace(_ windowID: CGWindowID) -> Bool {
            if let verdict = fullscreenSpaceVerdicts[windowID] { return verdict }
            guard let fullscreen = resolvedTopology()?.fullscreenSpaces, !fullscreen.isEmpty else {
                return false
            }
            let verdict = SpaceHopSupport.isOnFullscreenSpace(
                windowSpaces: spaces(of: windowID),
                fullscreenSpaces: fullscreen
            )
            fullscreenSpaceVerdicts[windowID] = verdict
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
            let isAppHidden = hiddenAppPIDs.contains(appPID)
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? (info[kCGWindowIsOnscreen as String] as? Bool)
                ?? false
            let isConfirmedHiddenAppWindow = isAppHidden
                && SwitcherSupport.isConfirmedHiddenAppWindow(
                    appIsHidden: isAppHidden,
                    windowSpaces: spaces(of: CGWindowID(windowID)))
            let axSnapshot = accessibilityWindows[windowOwnerPID]
            let axWindow = axSnapshot?.byID[CGWindowID(windowID)]
            // A stale dialog can keep an old ordinary-Space tag indefinitely.
            // Trust an unmatched hidden surface only when Accessibility could
            // not describe any window for that owner (and that pass was not
            // itself cut short by a per-window read timeout — an incomplete
            // pass does not get to vouch for a window it is missing), or when
            // the window server puts this exact surface on a native
            // fullscreen Space.
            let staleSurfaceVetoShouldBeSkipped = SpaceHopSupport.shouldSkipStaleSurfaceVeto(
                hasNoWindowsForOwner: axSnapshot?.ordered.isEmpty ?? true,
                hadAttributeReadFailure: axSnapshot?.hadAttributeReadFailure ?? false)
            let hiddenSpaceSurfaceIsWitnessed = isOnHiddenSpace(CGWindowID(windowID))
                && (staleSurfaceVetoShouldBeSkipped
                    || isOnFullscreenSpace(CGWindowID(windowID)))
            if axSnapshot != nil, axWindow == nil {
                // WindowServer kept a surface Accessibility does not vouch for:
                // a stale leftover from a closed tab or window. Windows parked
                // on a hidden Space and confirmed hidden-app windows are real,
                // so they survive this veto.
                if (!hiddenSpaceSurfaceIsWitnessed && !isConfirmedHiddenAppWindow)
                    || SpaceWindowBridge.isExcludedFromWindowCycle(CGWindowID(windowID)) {
                    continue
                }
            } else if axSnapshot == nil,
                      SwitcherSupport.unwitnessedSurfaceIsLeftover(
                        isOnScreen: isOnScreen,
                        canResolveSpaces: SpaceWindowBridge.canResolveSpaces,
                        windowSpacesCount: spaces(of: CGWindowID(windowID)).count) {
                // No Accessibility witness at all: the owner was too busy to
                // answer or is shutting down, which used to wave every one of
                // its surfaces through, closed windows included (issue #807).
                // The window server's own leftover signature decides instead.
                continue
            }
            let cgFrame = CGRect(x: (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0,
                                 y: (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0,
                                 width: (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0,
                                 height: (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0)
            let isMinimized = axWindow?.isMinimized ?? false
            let isFullscreen = (axWindow?.isFullscreen ?? false)
                || (axWindow == nil && isOnFullscreenSpace(CGWindowID(windowID)))
                || frameLooksFullscreen(cgFrame)
            guard let frame = switchableFrame(cgFrame, fallback: axWindow?.frame, isMinimized: isMinimized) else {
                continue
            }

            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
               alpha == 0, !isMinimized, !isConfirmedHiddenAppWindow {
                continue
            }

            let title = info[kCGWindowName as String] as? String ?? ""

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
                && !hiddenSpaceSurfaceIsWitnessed && !isConfirmedHiddenAppWindow { continue }

            seen.insert(windowID)
            windows.append(.window(id: windowID,
                                   title: displayTitle,
                                   appName: appName,
                                   pid: appPID,
                                   windowOwnerPID: windowOwnerPID,
                                   isOnScreen: isOnScreen,
                                   isAppHidden: isAppHidden,
                                   isMinimized: isMinimized,
                                   isFullscreen: isFullscreen,
                                   frame: frame))
        }
        appendAccessibilityOnlyWindows(to: &windows,
                                       snapshots: accessibilityWindows,
                                       regularApps: regularApps,
                                       embeddedHostPIDs: embeddedHostPIDs,
                                       hiddenAppPIDs: hiddenAppPIDs,
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
        let filtered = windows.filter { item in
            if !showFullscreenWindows, item.isFullscreen { return false }
            if minimizedPlacement == .hidden, item.isMinimized { return false }
            return true
        }
        let groupedBackingWindows = groupByApp && preservingGroupedWindows ? filtered : []
        let ordered: [SwitcherItem]
        if minimizedPlacement == .end {
            let primary = filtered.filter { !$0.isMinimized }
            let deferred = filtered.filter { $0.isMinimized }
            let orderedPrimary = orderByUse(primary, frontToBack: frontToBack)
            let orderedDeferred = orderByUse(deferred, frontToBack: frontToBack)
            let groupedPrimary = groupByApp ? groupWindowsByApp(orderedPrimary) : orderedPrimary
            let groupedDeferred = groupByApp ? groupWindowsByApp(orderedDeferred) : orderedDeferred
            ordered = groupedPrimary + groupedDeferred
        } else {
            let orderedRaw = orderByUse(filtered, frontToBack: frontToBack)
            ordered = groupByApp ? groupWindowsByApp(orderedRaw) : orderedRaw
        }
        var result = ordered
        if ordered.count > maximumCount {
            result = Array(ordered.prefix(maximumCount))
            // Asking for the desktop app alone names one entry, so that entry must
            // not vanish just because the list happens to be full. Asking for every
            // windowless app is a bulk choice instead, and there the cap keeps
            // cutting the least recently used tail exactly as it does for windows.
            if windowlessApps == .finder,
               let desktopEntry = ordered.dropFirst(maximumCount).first(where: { $0.windowID == nil }) {
                result.append(desktopEntry)
            }
        }
        if groupByApp, preservingGroupedWindows {
            let backingOrdered: [SwitcherItem]
            if minimizedPlacement == .end {
                let primary = groupedBackingWindows.filter { !$0.isMinimized }
                let deferred = groupedBackingWindows.filter { $0.isMinimized }
                backingOrdered = orderByUse(primary, frontToBack: frontToBack) + orderByUse(deferred, frontToBack: frontToBack)
            } else {
                backingOrdered = orderByUse(groupedBackingWindows, frontToBack: frontToBack)
            }
            result = SwitcherSupport.expandGroupedWindows(
                orderedWindows: backingOrdered,
                representatives: result)
        }
        // Space lookups are comparatively expensive. Resolve badges only for
        // the entries whose apps survived grouping and the visible cap.
        if marksHiddenSpaces {
            result = result.map { window in
                guard let windowID = window.windowID else { return window }
                return window.withHiddenSpaceState(isOnHiddenSpace(windowID))
            }
        }
        return result
    }

    /// WindowServer can keep stale, titled surfaces around after some apps close
    /// tabs or windows. Cross-checking against Accessibility removes those ghosts
    /// while preserving minimized windows and windows on other Spaces. When the
    /// owner cannot answer Accessibility at all (busy or terminating), surfaces
    /// that are off screen and belong to no Space are leftovers by the same
    /// definition instead of trusted blindly (issue #807).
    private struct AccessibilityWindowSnapshot {
        let title: String
        let frame: CGRect?
        let isMinimized: Bool
        let isFullscreen: Bool
    }

    private struct AccessibilityWindowSnapshotList {
        let ordered: [(id: CGWindowID, snapshot: AccessibilityWindowSnapshot)]
        let byID: [CGWindowID: AccessibilityWindowSnapshot]
        /// True when at least one of this owner's windows hit the 0.35s
        /// per-window AX messaging timeout during this pass. A window that
        /// times out is silently absent from `byID` just like a window that
        /// genuinely does not exist, so callers deciding whether an absence
        /// means "AX vouches this owner has nothing else" must also check
        /// this flag — an incomplete read is not a vouch.
        let hadAttributeReadFailure: Bool
    }

    private static func accessibilityWindows(for pids: Set<pid_t>,
                                             bundleIdentifiers: [pid_t: String] = [:],
                                             undescribedSubrolePids: Set<pid_t> = []) -> [pid_t: AccessibilityWindowSnapshotList] {
        guard Permissions.shared.accessibility else { return [:] }

        let orderedPIDs = pids.sorted()
        guard !orderedPIDs.isEmpty else { return [:] }
        let screenFrames = NSScreen.screens.map(\.frame)
        var result: [pid_t: AccessibilityWindowSnapshotList] = [:]
        var pendingQueries = orderedPIDs.count
        let resultLock = NSCondition()
        // A remote app can consume its whole messaging timeout. Overlap those
        // independent calls so several slow background helpers cost one wait,
        // not one wait each, while preserving Accessibility-only windows. The
        // bound keeps a helper-heavy app from creating an unbounded thread burst.
        let queryQueue = OperationQueue()
        queryQueue.qualityOfService = .userInteractive
        queryQueue.maxConcurrentOperationCount = min(maximumConcurrentQueries, orderedPIDs.count)
        for pid in orderedPIDs {
            queryQueue.addOperation {
                let windows = accessibilityWindows(
                    for: pid,
                    bundleIdentifier: bundleIdentifiers[pid],
                    acceptsUndescribedSubroles: undescribedSubrolePids.contains(pid),
                    screenFrames: screenFrames
                )
                resultLock.lock()
                if let windows { result[pid] = windows }
                pendingQueries -= 1
                if pendingQueries == 0 { resultLock.broadcast() }
                resultLock.unlock()
            }
        }
        // Operations still queued when the budget runs out are cancelled and
        // the answers already in hand are returned. An app missing from that
        // map reads downstream like an app that could not answer Accessibility,
        // which every caller already handles.
        let deadline = Date(timeIntervalSinceNow: accessibilityBatchBudget)
        resultLock.lock()
        while pendingQueries > 0, resultLock.wait(until: deadline) {}
        let exhaustedBudget = pendingQueries > 0
        let collected = result
        resultLock.unlock()
        if exhaustedBudget { queryQueue.cancelAllOperations() }
        return collected
    }

    private static func accessibilityWindows(for pid: pid_t,
                                             bundleIdentifier: String? = nil,
                                             acceptsUndescribedSubroles: Bool = false,
                                             screenFrames: [CGRect]) -> AccessibilityWindowSnapshotList? {
        let app = AXUIElementCreateApplication(pid)
        // This runs on the main thread (tap callback and activation warm-ups):
        // an app that is not servicing its run loop would hold every AX call
        // for the 6 second default timeout, and a blocked main thread stalls
        // the event taps with it, freezing typing system wide (issue #189).
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var axWindows: [AXUIElement] = []
        var value: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        // Not responding: skip the remaining calls, each would block again.
        guard windowsResult != .cannotComplete else { return nil }
        var hadAttributeReadFailure = false
        if windowsResult == .success, let windows = value as? [AXUIElement] {
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.35)
                if isUserFacingWindow(window,
                                      bundleIdentifier: bundleIdentifier,
                                      acceptsUndescribedSubroles: acceptsUndescribedSubroles,
                                      screenFrames: screenFrames,
                                      hadReadFailure: &hadAttributeReadFailure) {
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
                                      screenFrames: screenFrames,
                                      hadReadFailure: &hadAttributeReadFailure) {
                    appendUnique(window, to: &axWindows)
                }
            }
        }

        var byID: [CGWindowID: AccessibilityWindowSnapshot] = [:]
        var ordered: [(id: CGWindowID, snapshot: AccessibilityWindowSnapshot)] = []
        for window in axWindows {
            let idAttr = AXWindowResolver.readWindowID(for: window)
            if idAttr.timedOut { hadAttributeReadFailure = true }
            if let id = idAttr.id {
                let frameAttr = accessibilityFrame(for: window)
                if frameAttr.timedOut { hadAttributeReadFailure = true }
                let frame = frameAttr.frame
                let isMinimizedAttr = readBoolAttribute(window, kAXMinimizedAttribute as String)
                if isMinimizedAttr.timedOut { hadAttributeReadFailure = true }
                let snapshot = AccessibilityWindowSnapshot(title: accessibilityTitle(for: window),
                                                           frame: frame,
                                                           isMinimized: isMinimizedAttr.value ?? false,
                                                           isFullscreen: isFullscreenWindow(window, hadReadFailure: &hadAttributeReadFailure)
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
                : AccessibilityWindowSnapshotList(ordered: ordered, byID: byID,
                                                  hadAttributeReadFailure: hadAttributeReadFailure)
        }
        // If an app reports AX windows but none resolve to WindowServer ids,
        // keep the old behavior instead of hiding a real window for that app.
        if !ordered.isEmpty {
            return AccessibilityWindowSnapshotList(ordered: ordered, byID: byID,
                                                  hadAttributeReadFailure: hadAttributeReadFailure)
        }
        return nil
    }

    private static func appendAccessibilityOnlyWindows(to windows: inout [SwitcherItem],
                                                       snapshots: [pid_t: AccessibilityWindowSnapshotList],
                                                       regularApps: [pid_t: String],
                                                       embeddedHostPIDs: [pid_t: pid_t],
                                                       hiddenAppPIDs: Set<pid_t>,
                                                       seen: inout Set<CGWindowID>,
                                                       filterPID: pid_t?,
                                                       excludeWindow: (CGWindowID, pid_t) -> Bool = { _, _ in false }) {
        let tracker = WindowUseTracker.shared
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
                                       isAppHidden: hiddenAppPIDs.contains(appPID),
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

    /// Reports whether either attribute read hit its messaging timeout, same
    /// reason as `readStringAttribute`/`readBoolAttribute`: a caller deciding
    /// whether an absent frame means "AX has nothing to say" needs to tell
    /// that apart from "AX never answered in time".
    private static func accessibilityFrame(for window: AXUIElement) -> (frame: CGRect?, timedOut: Bool) {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        let timedOut = positionResult == .cannotComplete || sizeResult == .cannotComplete
        guard positionResult == .success,
              sizeResult == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return (nil, timedOut) }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return (nil, timedOut) }
        return (CGRect(origin: position, size: size), timedOut)
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
                                           screenFrames: [CGRect],
                                           hadReadFailure: inout Bool) -> Bool {
        if isFullscreenWindow(window, hadReadFailure: &hadReadFailure) { return true }
        let minimizedAttr = readBoolAttribute(window, kAXMinimizedAttribute as String)
        if minimizedAttr.timedOut { hadReadFailure = true }
        if minimizedAttr.value == true {
            let roleAttr = readStringAttribute(window, kAXRoleAttribute as String)
            if roleAttr.timedOut { hadReadFailure = true }
            if roleAttr.value == (kAXWindowRole as String) {
                return true
            }
        }
        let subroleAttr = readStringAttribute(window, kAXSubroleAttribute as String)
        if subroleAttr.timedOut { hadReadFailure = true }
        if let subrole = subroleAttr.value {
            if subrole == "AXStandardWindow" || subrole == "AXFullScreenWindow" { return true }
            if SwitcherSupport.isSupportedMediaFloatingWindow(bundleIdentifier: bundleIdentifier,
                                                              subrole: subrole) { return true }
            let roleAttr = readStringAttribute(window, kAXRoleAttribute as String)
            if roleAttr.timedOut { hadReadFailure = true }
            let role = roleAttr.value
            let canBePlaybackSurface = subrole == "AXUnknown" || subrole == "AXFloatingWindow"
            let frameAttr = accessibilityFrame(for: window)
            if frameAttr.timedOut { hadReadFailure = true }
            let fillsScreen = canBePlaybackSurface
                && frameLooksFullscreen(frameAttr.frame, screenFrames: screenFrames)
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
        let finalRoleAttr = readStringAttribute(window, kAXRoleAttribute as String)
        if finalRoleAttr.timedOut { hadReadFailure = true }
        return finalRoleAttr.value == "AXWindow"
    }

    private static func isFullscreenWindow(_ window: AXUIElement, hadReadFailure: inout Bool) -> Bool {
        let fullscreenAttr = readBoolAttribute(window, "AXFullScreen")
        if fullscreenAttr.timedOut { hadReadFailure = true }
        if fullscreenAttr.value == true { return true }
        let subroleAttr = readStringAttribute(window, kAXSubroleAttribute as String)
        if subroleAttr.timedOut { hadReadFailure = true }
        return subroleAttr.value == "AXFullScreenWindow"
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

    /// A messaging timeout (`AXUIElementSetMessagingTimeout`) makes
    /// `AXUIElementCopyAttributeValue` return `.cannotComplete` rather than
    /// hang, but that error looks identical to "this attribute legitimately
    /// has no value" unless the caller checks for it specifically. Callers
    /// that need to tell "AX answered false/absent" apart from "AX never
    /// answered" read `timedOut` instead of collapsing both into `nil`/`false`.
    private static func readStringAttribute(_ element: AXUIElement,
                                             _ attribute: String) -> (value: String?, timedOut: Bool) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return (nil, error == .cannotComplete) }
        return (value as? String, false)
    }

    private static func readBoolAttribute(_ element: AXUIElement,
                                          _ attribute: String) -> (value: Bool?, timedOut: Bool) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return (nil, error == .cannotComplete) }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return (value as? Bool, false)
        }
        return (CFBooleanGetValue((value as! CFBoolean)), false)
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
                                             runningApps: [NSRunningApplication],
                                             regularApps: [pid_t: String],
                                             accessibilityWindows: [pid_t: AccessibilityWindowSnapshotList],
                                             ownPID: pid_t,
                                             withheldPIDs: Set<pid_t>,
                                             appRules: [String: SwitcherAppRule]) {
        // The window server order is stable across calls, so apps that were
        // never brought to the front keep a settled place instead of shuffling
        // between one press and the next.
        let candidates = runningApps.compactMap { app -> SwitcherAppCandidate? in
            let pid = app.processIdentifier
            guard app.activationPolicy == .regular,
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
            let isAppHidden = runningApps.first { $0.processIdentifier == pid }?.isHidden ?? false
            windows.append(.appOnly(appName: name, pid: pid, isAppHidden: isAppHidden))
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
                                   frontToBack: WindowUseTracker.FrontToBack) -> [SwitcherItem] {
        let tracker = WindowUseTracker.shared
        let entries = windows.map { WindowUseOrder.Entry(windowID: $0.windowID, pid: $0.pid) }
        return WindowUseOrder.order(entries,
                                    windowHistory: tracker.windows,
                                    appHistory: tracker.apps,
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
