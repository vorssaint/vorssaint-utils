// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AppWindowTravel {
    private static let moveTimeout: TimeInterval = 0.3
    private static let movePollInterval: TimeInterval = 0.01

    static func travelTarget(for app: NSRunningApplication) -> CGWindowID? {
        guard let topology = SpaceWindowBridge.topology() else { return nil }
        let pid = app.processIdentifier
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var frontToBack: [CGWindowID] = []
        var info: [CGWindowID: [String: Any]] = [:]
        for entry in raw where (entry[kCGWindowOwnerPID as String] as? pid_t) == pid
            && (entry[kCGWindowLayer as String] as? Int) == 0 {
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            frontToBack.append(windowID)
            info[windowID] = entry
        }
        let appIsHidden = app.isHidden
        let hiddenWithApp = appIsHidden ? SpaceWindowBridge.windowsHiddenWithApp(among: frontToBack) : nil
        let ordered = AppWindowTravelSupport.recencyOrder(frontToBack, history: WindowUseTracker.shared.windows)
        let candidates = ordered.map { windowID in
            candidate(windowID, info: info[windowID] ?? [:], appIsHidden: appIsHidden,
                      isHiddenWithApp: hiddenWithApp.map { $0.contains(windowID) })
        }
        return AppWindowTravelSupport.travelTarget(candidates: candidates,
                                                   appIsHidden: appIsHidden,
                                                   visibleSpaces: topology.visibleSpaces)
    }

    static func canBringHere(_ windowID: CGWindowID, to screen: NSScreen?) -> Bool {
        SpaceWindowBridge.canRequestMoves && destination(for: windowID, screen: screen) != nil
    }

    static func bringHere(pid: pid_t, windowID: CGWindowID, appName: String,
                          screen: NSScreen?, handoffSourcePID: pid_t?, activationGeneration: UInt64,
                          requiresAllWindowsHidden: Bool = false) {
        guard WindowActivator.isCurrentActivation(activationGeneration) else { return }
        if requiresAllWindowsHidden,
           NSRunningApplication(processIdentifier: pid).flatMap({ travelTarget(for: $0) }) != windowID {
            guard WindowActivator.isCurrentActivation(activationGeneration) else { return }
            WindowActivator.activate(pid: pid, windowID: nil, appName: appName,
                                     handoffSourcePID: handoffSourcePID)
            return
        }
        let activate = {
            guard WindowActivator.isCurrentActivation(activationGeneration) else { return }
            WindowActivator.activate(pid: pid, windowID: windowID, appName: appName,
                                     handoffSourcePID: handoffSourcePID)
        }
        guard let space = destination(for: windowID, screen: screen),
              SpaceWindowBridge.requestMove(windowID, toSpace: space)
        else { return activate() }
        let deadline = Date().addingTimeInterval(moveTimeout)
        func waitForArrival() {
            guard WindowActivator.isCurrentActivation(activationGeneration) else { return }
            if SpaceWindowBridge.spaces(of: windowID).contains(space) {
                placeOnScreen(windowID, pid: pid, screen: screen)
                activate()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + movePollInterval, execute: waitForArrival)
            } else {
                activate()
            }
        }
        waitForArrival()
    }

    private static func destination(for windowID: CGWindowID, screen: NSScreen?) -> UInt64? {
        guard Permissions.shared.accessibility, let topology = SpaceWindowBridge.topology(),
              let entry = (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]])?.first,
              let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let app = NSRunningApplication(processIdentifier: pid),
              let isMinimized = SpaceWindowBridge.isMinimized(windowID)
        else { return nil }
        let hiddenWithApp = app.isHidden ? SpaceWindowBridge.windowsHiddenWithApp(among: [windowID]) : nil
        let window = candidate(windowID, info: entry, appIsHidden: app.isHidden,
                               isHiddenWithApp: hiddenWithApp.map { $0.contains(windowID) },
                               isMinimized: isMinimized)
        guard AppWindowTravelSupport.isUsable(window, appIsHidden: app.isHidden) else { return nil }
        return AppWindowTravelSupport.moveDestination(
            windowSpaces: window.spaces,
            destination: SpaceWindowBridge.visibleSpace(on: screen, in: topology),
            visibleSpaces: topology.visibleSpaces,
            fullscreenSpaces: topology.fullscreenSpaces,
            isMinimized: isMinimized)
    }

    private static func candidate(_ windowID: CGWindowID, info: [String: Any], appIsHidden: Bool,
                                   isHiddenWithApp: Bool?, isMinimized: Bool? = nil) -> AppWindowTravelSupport.Candidate {
        let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
            .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
        return AppWindowTravelSupport.Candidate(
            windowID: windowID,
            spaces: SpaceWindowBridge.spaces(of: windowID),
            size: bounds.size,
            alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            isOrderedIn: appIsHidden ? nil : SpaceWindowBridge.isWindowOrderedIn(windowID),
            isHiddenWithApp: isHiddenWithApp,
            isMinimized: isMinimized ?? SpaceWindowBridge.isMinimized(windowID) ?? false,
            isExcludedFromWindowCycle: SpaceWindowBridge.isExcludedFromWindowCycle(windowID),
            hasParent: SpaceWindowBridge.parentWindowID(of: windowID) != nil)
    }

    private static func placeOnScreen(_ windowID: CGWindowID, pid: pid_t, screen: NSScreen?) {
        guard let screen, let primary = NSScreen.screens.first,
              let entry = (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]])?.first,
              let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds)
        else { return }
        let visible = screen.visibleFrame
        let destination = CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY,
                                 width: visible.width, height: visible.height)
        guard let origin = AppWindowTravelSupport.placement(windowFrame: frame, destination: destination)
        else { return }
        WindowActivator.setWindowOrigin(origin, windowID: windowID, pid: pid)
    }
}
