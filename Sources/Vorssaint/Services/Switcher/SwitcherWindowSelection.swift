// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum SwitcherWindowSelection {
    static func select(
        remembered: WindowEnumerator.WindowList,
        scope: SwitcherSessionScope,
        frontmostPID: pid_t,
        focusedWindowID: CGWindowID?,
        displayScope: WindowEnumerator.DisplayScope?
    ) -> WindowEnumerator.WindowList {
        let defaults = UserDefaults.standard
        let rules = SwitcherAppRule.rules(storedValue: defaults.dictionary(forKey: DefaultsKey.switcherAppRules))
        let windowlessMode = SwitcherWindowlessApps.mode(
            storedValue: defaults.string(forKey: DefaultsKey.switcherWindowlessApps),
            takeOverSystemShortcuts: defaults.bool(forKey: DefaultsKey.switcherTakeOverSystemShortcuts))
        let candidates = remembered.items.filter(\.isAppEntry).map {
            SwitcherAppCandidate(pid: $0.pid, bundleIdentifier: remembered.bundleIdentifiers[$0.pid])
        }
        let windowlessPIDs = Set(SwitcherSupport.windowlessAppPIDs(
            mode: windowlessMode,
            candidates: candidates,
            pidsWithWindows: Set(remembered.items.filter { !$0.isAppEntry }.map(\.pid)),
            pidsWithWithheldWindows: [],
            desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
            appRules: rules))
        let currentSpaceOnly = defaults.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
        let showFullscreen = defaults.object(forKey: DefaultsKey.switcherShowFullscreenWindows) as? Bool ?? true
        let minimizedPlacement = WindowSwitchMinimizedPlacement(
            rawValue: defaults.string(forKey: DefaultsKey.switcherMinimizedPlacement) ?? "") ?? .normal
        let treatHiddenAsMinimized = defaults.bool(forKey: DefaultsKey.switcherTreatHiddenAppsLikeMinimized)
        let mergeWindows = defaults.bool(forKey: DefaultsKey.switcherMergeTabs)
        let groupByApp = scope == .allApps && mergeWindows
        let preservesGroupedWindows = SwitcherSupport.preservesGroupedWindowsDuringEnumeration(
            allApps: scope == .allApps,
            mergeWindowsByApp: mergeWindows,
            simpleMode: defaults.bool(forKey: DefaultsKey.switcherSimpleMode))
        let filtered = remembered.items.filter { item in
            if SwitcherSupport.hidesApp(bundleIdentifier: remembered.bundleIdentifiers[item.pid], appRules: rules) {
                return false
            }
            if item.isAppEntry, !windowlessPIDs.contains(item.pid) { return false }
            if currentSpaceOnly, item.isOnHiddenSpace,
               !(showFullscreen && item.windowID.map { remembered.nativeFullscreenWindowIDs.contains($0) } == true) {
                return false
            }
            return true
        }
        let sessionItems = SwitcherSupport.windowsForSession(filtered, scope: scope, frontmostPID: frontmostPID)
        let hiddenSpaceIDs = Set(sessionItems.filter(\.isOnHiddenSpace).compactMap(\.windowID))
        let frontToBack = WindowUseTracker.FrontToBack(windows: sessionItems.compactMap(\.windowID), apps: [])
        var list = WindowEnumerator.selectWindows(
            sessionItems,
            maximumCount: 48,
            windowlessApps: windowlessMode,
            groupByApp: groupByApp,
            minimizedPlacement: minimizedPlacement,
            treatHiddenAppsLikeMinimized: treatHiddenAsMinimized,
            showFullscreenWindows: showFullscreen,
            preservingGroupedWindows: preservesGroupedWindows,
            currentSpaceOnly: currentSpaceOnly,
            windowsOnly: scope == .allWindows,
            scopedToFrontmostPID: scope == .frontmostApp ? frontmostPID : nil,
            displayScope: displayScope,
            frontToBack: frontToBack,
            isOnHiddenSpace: { hiddenSpaceIDs.contains($0) },
            resolveSource: { items in
                SwitcherSupport.sessionSourceItem(
                    frontmostPID: frontmostPID,
                    focusedWindowID: focusedWindowID,
                    items: items)
            })
        list.activationSnapshot = remembered.activationSnapshot
        return list
    }
}
