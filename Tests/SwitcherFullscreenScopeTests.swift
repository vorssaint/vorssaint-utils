// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

/// Runs the production window walk against window-server and AX snapshots.
/// No real windows, preferences or desktop changes are needed.
enum SwitcherFullscreenScopeTests {
    enum Enumerator {
        typealias SpaceWindowBridge = SwitcherFullscreenScopeTests.Bridge
        typealias WindowUseTracker = SwitcherFullscreenScopeTests.Tracker
        typealias UserDefaults = SwitcherFullscreenScopeTests.Preferences
        static let minimumSize = CGSize(width: 80, height: 60)
        static let maximumCount = 48
        static var raw: [[String: Any]] = []
        static var answers: [pid_t: AccessibilityWindowSnapshotList] = [:]

        static func CGWindowListCopyWindowInfo(_ options: CGWindowListOption,
                                               _ relativeToWindow: CGWindowID) -> CFArray? {
            raw as CFArray
        }

        static func accessibilityWindows(for pids: Set<pid_t>, bundleIdentifiers: [pid_t: String],
                                         undescribedSubrolePids: Set<pid_t>, accessibilityGranted: Bool,
                                         normalLevelWindowIDs: Set<CGWindowID>, screenFrames: [CGRect],
                                         isCancelled: @escaping () -> Bool) -> [pid_t: AccessibilityWindowSnapshotList] {
            answers
        }

        static func orderByUse(_ windows: [SwitcherItem], frontToBack: [CGWindowID]) -> [SwitcherItem] {
            windows
        }
    }

    final class Preferences {
        static let standard = Preferences()
        var values: [String: Any] = [:]
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func string(forKey key: String) -> String? { values[key] as? String }
        func object(forKey key: String) -> Any? { values[key] }
        func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    }

    enum Bridge {
        struct Topology {
            let visibleSpaces: Set<UInt64>
            let fullscreenSpaces: Set<UInt64>
        }
        static var memberships: [CGWindowID: [UInt64]] = [:]
        static var excluded: Set<CGWindowID> = []
        static let canResolveSpaces = true
        static func topology(displayIDsByUUID: [String: CGDirectDisplayID]) -> Topology? {
            Topology(visibleSpaces: [1], fullscreenSpaces: [3])
        }
        static func spaces(of id: CGWindowID) -> [UInt64] { memberships[id] ?? [] }
        static func isExcludedFromWindowCycle(_ id: CGWindowID) -> Bool { excluded.contains(id) }
        static func isWindowOrderedIn(_ id: CGWindowID) -> Bool? { true }
    }

    final class Tracker {
        static let shared = Tracker()
        let historyRevision: UInt64 = 0
        static func frontToBack() -> [CGWindowID] { [] }
        func reconcile(existingWindows: Set<CGWindowID>, frontToBack: [CGWindowID],
                       running: Set<pid_t>, revision: UInt64) {}
        func rank(of pid: pid_t) -> Int { Int(pid) }
    }

    static func run(_ suite: TestSuite) {
        defer {
            Enumerator.raw = []
            Enumerator.answers = [:]
            Bridge.memberships = [:]
            Bridge.excluded = []
            Preferences.standard.values = [:]
        }
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let apps = (1...6).map { id in
            Enumerator.AppSnapshot(pid: pid_t(id), bundleIdentifier: "test.app.\(id)",
                                   localizedName: "App \(id)", isRegular: true, isHidden: false,
                                   bundlePath: nil, executablePath: nil)
        }
        let snapshot = Enumerator.Snapshot(accessibilityGranted: true, runningApps: apps,
                                            ownWindowTitles: [:], screenFrames: [frame], displayIDsByUUID: [:])
        // Current desktop, another ordinary desktop, and a native fullscreen
        // Space. The ordinary sibling deliberately fills the screen too.
        Bridge.memberships = [1: [1], 2: [2], 3: [3], 4: [3], 5: [2], 6: [2]]
        Enumerator.raw = (1...3).map { id -> [String: Any] in
            let bounds = ["X": 0, "Y": 0, "Width": id == 1 ? 600 : 900, "Height": id == 1 ? 400 : 600]
            return [kCGWindowNumber as String: NSNumber(value: id),
             kCGWindowOwnerPID as String: NSNumber(value: id),
             kCGWindowLayer as String: NSNumber(value: 0),
             kCGWindowBounds as String: bounds,
             kCGWindowIsOnscreen as String: NSNumber(value: id == 1),
             kCGWindowAlpha as String: NSNumber(value: 1),
             kCGWindowName as String: "Window \(id)"]
        }
        // AX-only fullscreen and ordinary siblings exercise the second pass.
        // App 6 has an AX fullscreen flag while topology still says desktop.
        for id: CGWindowID in [1, 2, 4, 5, 6] {
            let window = Enumerator.AccessibilityWindowSnapshot(
                title: "Window \(id)", frame: id == 1 ? CGRect(x: 0, y: 0, width: 600, height: 400) : frame,
                isMinimized: id == 5, isFullscreen: id != 1, isNativeFullscreen: id == 4 || id == 6)
            Enumerator.answers[pid_t(id)] = .init(ordered: [(id, window)], byID: [id: window])
        }
        // The browser's hidden fullscreen window can be missing from AX.
        Enumerator.answers[3] = .init(ordered: [], byID: [:])

        func enumerate(currentSpaceOnly: Bool, showFullscreen: Bool = true, groupByApp: Bool = false,
                       appRules: [String: SwitcherAppRule] = [:]) -> Enumerator.WindowList {
            Preferences.standard.values = [DefaultsKey.switcherCurrentSpaceOnly: currentSpaceOnly,
                                            DefaultsKey.switcherShowFullscreenWindows: showFullscreen,
                                            DefaultsKey.switcherWindowlessApps: "off",
                                            DefaultsKey.switcherAppRules: SwitcherAppRule.storedValue(appRules)]
            return Enumerator.enumerateSwitcherWindows(groupByApp: groupByApp,
                                                        preservingGroupedWindows: false, snapshot: snapshot)
        }
        let scoped = enumerate(currentSpaceOnly: true)
        suite.expect(Set(scoped.items.compactMap(\.windowID)) == [1, 3, 4, 6],
                     "current-desktop mode retains native fullscreen windows from both enumeration passes")
        let fullscreenTargets = scoped.items.filter { [3, 4, 6].contains($0.windowID) }
        suite.expect(fullscreenTargets.count == 3 && fullscreenTargets.allSatisfy(\.isOnHiddenSpace)
                        && scoped.items.contains { $0.windowID == 3 && $0.isFullscreen },
                     "fullscreen targets keep their desktop-travel metadata even when AX omits them")
        suite.expect(!scoped.items.contains { $0.windowID == 2 || $0.windowID == 5 },
                     "a screen-sized ordinary window on another desktop does not bypass desktop scope")
        suite.expect(enumerate(currentSpaceOnly: true, showFullscreen: false).items.compactMap(\.windowID) == [1],
                     "hiding fullscreen windows retains the current-desktop ordinary window")
        let hiddenApps = enumerate(currentSpaceOnly: true, appRules: ["test.app.3": .hidden, "test.app.4": .hidden])
        suite.expect(Set(hiddenApps.items.compactMap(\.windowID)) == [1, 6],
                     "fullscreen scope does not override app exclusions in either enumeration pass")
        suite.expect(Set(enumerate(currentSpaceOnly: false).items.compactMap(\.windowID)) == [1, 2, 3, 4, 5, 6],
                     "all-desktop enumeration retains ordinary and fullscreen windows")
        suite.expect(Set(enumerate(currentSpaceOnly: true, groupByApp: true).items.compactMap(\.windowID)) == [1, 3, 4, 6],
                     "one entry per app keeps a fullscreen window for an app with no window on this desktop")
        let dock = Enumerator.listWindows(filterPID: 3, maximumCount: 12, windowlessApps: .off,
                                          appRules: [:], groupByApp: false, minimizedPlacement: .normal,
                                          treatHiddenAppsLikeMinimized: false, showFullscreenWindows: true,
                                          preservingGroupedWindows: false, currentSpaceOnly: true,
                                          marksHiddenSpaces: false, snapshot: snapshot)
        suite.expect(dock.items.isEmpty,
                     "Dock Preview keeps its independent strict current-desktop scope")
        Preferences.standard.values[DefaultsKey.switcherCurrentSpaceOnly] = true
        suite.expect(Enumerator.listWindowsForCommandBar(snapshot: snapshot).compactMap(\.windowID) == [1],
                     "Command Bar keeps its existing current-desktop scope")
        Bridge.excluded = [3]
        suite.expect(!enumerate(currentSpaceOnly: true).items.contains { $0.windowID == 3 },
                     "an unmatched cycle-excluded fullscreen helper stays out")

        // App 1 also plays a fullscreen video on another desktop. With one
        // entry per app, its window here must stay the entry to pick.
        Bridge.excluded = []
        Bridge.memberships = [7: [1], 8: [3]]
        func browser(_ order: [CGWindowID], minimized: Bool = false) {
            Enumerator.raw = order.map { id -> [String: Any] in
                let bounds = ["X": 0, "Y": 0, "Width": id == 7 ? 600 : 900, "Height": id == 7 ? 400 : 600]
                return [kCGWindowNumber as String: NSNumber(value: id),
                 kCGWindowOwnerPID as String: NSNumber(value: 1),
                 kCGWindowLayer as String: NSNumber(value: 0),
                 kCGWindowBounds as String: bounds,
                 kCGWindowIsOnscreen as String: NSNumber(value: id == 7 && !minimized),
                 kCGWindowAlpha as String: NSNumber(value: 1),
                 kCGWindowName as String: "Window \(id)"]
            }
            let local = Enumerator.AccessibilityWindowSnapshot(
                title: "Window 7", frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                isMinimized: minimized, isFullscreen: false, isNativeFullscreen: false)
            let video = Enumerator.AccessibilityWindowSnapshot(
                title: "Window 8", frame: frame, isMinimized: false, isFullscreen: true, isNativeFullscreen: true)
            Enumerator.answers = [1: .init(ordered: [(id: CGWindowID(7), snapshot: local),
                                                    (id: CGWindowID(8), snapshot: video)],
                                           byID: [7: local, 8: video])]
        }
        func representative(currentSpaceOnly: Bool) -> [CGWindowID] {
            enumerate(currentSpaceOnly: currentSpaceOnly, groupByApp: true).items.compactMap(\.windowID)
        }
        browser([7, 8])
        suite.expect(representative(currentSpaceOnly: true) == [7],
                     "one entry per app keeps the window here over a later fullscreen window on another desktop")
        suite.expect(representative(currentSpaceOnly: false) == [8],
                     "all-desktop grouping still prefers the app's fullscreen window")
        browser([8, 7], minimized: true)
        suite.expect(representative(currentSpaceOnly: true) == [7],
                     "a minimized window here replaces a fullscreen window from another desktop as the app's entry")
        suite.expect(enumerate(currentSpaceOnly: true).items.compactMap(\.windowID) == [8, 7],
                     "without grouping both windows of the app stay listed")
    }
}
