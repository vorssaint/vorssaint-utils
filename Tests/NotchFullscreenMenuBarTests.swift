// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum NotchFullscreenMenuBarTests {
    static func run(_ suite: TestSuite) {
        decisions(suite)
        edgeBars(suite)
        walk(suite)
        assertions(suite)
        gating(suite)
    }

    private typealias Support = NotchFullscreenMenuBarSupport
    private typealias Inputs = NotchFullscreenMenuBarSupport.Inputs

    private static func decisions(_ suite: TestSuite) {
        let video = Inputs(fullscreenApp: 42, playsVideo: true, microphoneInUse: false, appShowsOwnUI: false)
        suite.expect(Support.decide(video) == .release,
                     "full-screen video with nothing else of the app on screen lets macOS hide the bar")
        suite.expect(Support.decide(Inputs(fullscreenApp: 42, playsVideo: true, microphoneInUse: false,
                                           appShowsOwnUI: true)) == .show,
                     "a browser playing a video in its page still shows its tabs or toolbar, so the bar stays")
        suite.expect(Support.decide(Inputs(fullscreenApp: 42, playsVideo: true, microphoneInUse: true,
                                           appShowsOwnUI: false)) == .show,
                     "a call keeps the display awake like video, and keeps the bar")
        suite.expect(Support.decide(Inputs(fullscreenApp: 42, playsVideo: false, microphoneInUse: false,
                                           appShowsOwnUI: false)) == .show,
                     "a full-screen app without video keeps the bar")
        suite.expect(Support.decide(Inputs(fullscreenApp: 42, playsVideo: true, microphoneInUse: false,
                                           appShowsOwnUI: nil)) == .release,
                     "without Accessibility any full-screen video hides the bar")
        suite.expect(Support.decide(Inputs(fullscreenApp: nil, playsVideo: true, microphoneInUse: false,
                                           appShowsOwnUI: false)) == .show,
                     "outside full screen the override is held, so entering full screen never flashes the bar away")
        suite.expect(Support.decide(Inputs(fullscreenApp: nil, playsVideo: false, microphoneInUse: false,
                                           appShowsOwnUI: nil, systemHidesBarOnDesktop: true)) == .release,
                     "when the system hides the bar on the desktop too, the desktop keeps its own setting")
        suite.expect(Support.decide(Inputs(fullscreenApp: 42, playsVideo: false, microphoneInUse: false,
                                           appShowsOwnUI: nil, systemHidesBarOnDesktop: true)) == .show,
                     "that setting still gets the bar in full-screen apps")

        suite.expect(Support.videoHidesBar(video, systemShowsBarInFullscreen: false),
                     "full-screen video that hides the bar hides the island's content too")
        suite.expect(!Support.videoHidesBar(Inputs(fullscreenApp: 42, playsVideo: true, microphoneInUse: false,
                                                   appShowsOwnUI: true), systemShowsBarInFullscreen: false),
                     "a video in a browser page keeps the bar and the island")
        suite.expect(!Support.videoHidesBar(video, systemShowsBarInFullscreen: true),
                     "where macOS keeps the bar in full screen, the island stays beside it")
        suite.expect(!Support.videoHidesBar(Inputs(fullscreenApp: nil, playsVideo: false, microphoneInUse: false,
                                                   appShowsOwnUI: nil, systemHidesBarOnDesktop: true),
                                            systemShowsBarInFullscreen: false),
                     "a desktop with the bar set to hide is not video, and keeps the island")
    }

    /// Frames from probes on a 1728x1117 notched display (top-left
    /// coordinates; a full-screen window starts below the 33 pt notch strip).
    private static func edgeBars(_ suite: TestSuite) {
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x, y: y, width: w, height: h)
        }
        let display = r(0, 0, 1728, 1117), full = r(0, 33, 1728, 1084), windowed = r(0, 33, 1728, 1023)
        let cases: [(String, [CGRect], CGRect, Bool)] = [
            ("a toolbar always shown sits above the window", [r(0, 33, 1728, 47), r(680, 45, 368, 50)],
             r(0, 80, 1728, 1037), true),
            ("a toolbar parked above the display is hidden", [r(0, -79, 1728, 47), r(639, 45, 449, 50), full],
             full, false),
            ("vertical tabs down the side", [r(0, -79, 1728, 47), r(0, 33, 240, 1084), r(240, 33, 1488, 1084),
                                             r(239, 33, 10, 8)], full, true),
            ("a toolbar revealed under the menu bar", [r(0, 65, 1728, 47), full], full, true),
            ("a toolbar beside vertical tabs in a window", [r(240, 33, 1488, 46), r(240, 79, 1488, 977),
                                                            r(0, 33, 240, 1023)], windowed, true),
            ("a content area is not a bar", [r(240, 79, 1488, 977)], windowed, false),
            ("a toolbar across the top", [r(0, 33, 1728, 52), r(-1, 85, 0, 1032)], full, true),
            ("a video's own full-screen window has no bars", [full], full, false),
            ("a notice near the top is not a toolbar", [r(639, 45, 449, 50)], full, false),
            ("a slim resize handle is not a sidebar", [r(235, 33, 5, 1084)], full, false),
            ("a bottom control bar is not app chrome around the video", [r(0, 1037, 1728, 80)], full, false),
        ]
        for (name, elements, window, expected) in cases {
            suite.expect(Support.edgeBarsVisible(elements, window: window, display: display) == expected,
                         "edge bars: \(name)")
        }
    }

    private final class Node {
        let role: String
        let frame: CGRect
        let children: [Node]
        var read = false
        init(_ role: String, _ frame: CGRect, _ children: [Node] = []) {
            self.role = role
            self.frame = frame
            self.children = children
        }
    }

    /// Chrome's window with vertical tabs, as its native tree reports it: four
    /// wrappers the window's size, then the bars beside the content, with the
    /// web page two levels further down.
    private static func walk(_ suite: TestSuite) {
        let frame = CGRect(x: 0, y: 33, width: 1728, height: 1023)
        let page = Node("AXScrollArea", CGRect(x: 240, y: 80, width: 1488, height: 976),
                        [Node("AXWebArea", CGRect(x: 240, y: 80, width: 1488, height: 976))])
        let content = Node("AXGroup", CGRect(x: 240, y: 79, width: 1488, height: 977),
                           [Node("AXGroup", CGRect(x: 240, y: 80, width: 1488, height: 976), [page])])
        let tabs = Node("AXTabGroup", CGRect(x: 0, y: 33, width: 240, height: 1023))
        let toolbar = Node("AXGroup", CGRect(x: 240, y: 33, width: 1488, height: 46),
                           [Node("AXToolbar", CGRect(x: 240, y: 33, width: 1488, height: 46))])
        let close = Node("AXButton", CGRect(x: 12, y: 48, width: 16, height: 16))
        var level = Node("AXGroup", frame, [toolbar, content, tabs])
        for _ in 0..<3 { level = Node("AXGroup", frame, [level]) }
        let window = Node("AXWindow", frame, [level, close])

        func children(_ node: Node) -> [Node] {
            node.read = true
            return node.children
        }
        let found = Support.edgeCandidates(of: window, frame: frame, children: children,
                                           role: { $0.role }, frame: { $0.frame })
        suite.expect(Set(found.map(\.minX)) == [240, 0] && found.contains(tabs.frame) && found.contains(toolbar.frame),
                     "the walk passes the window-sized wrappers and collects the bars beside the content")
        suite.expect(!page.read && !content.read,
                     "the walk never opens the content area, so a browser's web tree stays untouched")
        suite.expect(!found.contains(close.frame), "buttons are not candidates")

        var deep = Node("AXGroup", frame, [Node("AXGroup", CGRect(x: 0, y: 33, width: 240, height: 1023))])
        for _ in 0..<(Support.maximumWalkDepth + 2) { deep = Node("AXGroup", frame, [deep]) }
        let tooDeep = Support.edgeCandidates(of: Node("AXWindow", frame, [deep]), frame: frame,
                                             children: { $0.children }, role: { $0.role }, frame: { $0.frame })
        suite.expect(!tooDeep.contains(CGRect(x: 0, y: 33, width: 240, height: 1023)),
                     "the walk stops at its depth limit")
    }

    private static func assertions(_ suite: TestSuite) {
        let byPID: [pid_t: [[String: Any]]] = [
            501: [["AssertType": "PreventUserIdleDisplaySleep", "AssertLevel": 255, "AssertName": "Video Wake Lock"]],
            502: [["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 255]],
            503: [["AssertType": "NoDisplaySleepAssertion", "AssertLevel": 0]],
            504: [["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 255],
                  ["AssertType": "NoDisplaySleepAssertion", "AssertLevel": 255, "AssertionOnBehalfOfPID": 900]],
        ]
        let owners: [pid_t: pid_t] = [501: 100]
        let found = Support.displayAwakeOwners(byPID, owner: { owners[$0] ?? $0 })
        suite.expect(found.contains(100), "a helper's display assertion counts for the app responsible for it")
        suite.expect(!found.contains(502), "keeping the system awake is not keeping the display awake")
        suite.expect(!found.contains(503), "a released assertion does not count")
        suite.expect(found.contains(900) && found.contains(504),
                     "an assertion taken on behalf of another process counts for both")
    }

    private static func gating(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-fullscreen-menu-bar"
        guard let defaults = UserDefaults(suiteName: domain) else {
            suite.expect(false, "scratch defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        suite.expect(!Support.isEnabled(in: defaults), "off until installed and switched on")
        defaults.set(true, forKey: AppFeature.notchFullscreenMenuBar.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.notchFullscreenMenuBarEnabled)
        suite.expect(!Support.isEnabled(in: defaults), "it belongs to the island and needs it on")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(Support.isEnabled(in: defaults), "installed, switched on and with the island, it runs")
        defaults.set(false, forKey: AppFeature.notchFullscreenMenuBar.availabilityKey)
        suite.expect(!Support.isEnabled(in: defaults), "uninstalling it stops it")
        defaults.set(false, forKey: "AppleMenuBarVisibleInFullscreen")
        suite.expect(!Support.systemShowsBarInFullscreen(in: defaults),
                     "In Full Screen Only and Always hide the bar in full screen, so video can")
        defaults.set(true, forKey: "AppleMenuBarVisibleInFullscreen")
        suite.expect(Support.systemShowsBarInFullscreen(in: defaults),
                     "Never and On Desktop Only keep it, and Settings says video cannot hide it")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchFullscreenMenuBarEnabled] as? Bool == false
                        && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchFullscreenMenuBarEnabled),
                     "the switch starts off and is part of settings backup")
        suite.expect(!AppFeature.notchFullscreenMenuBar.installedByDefault
                        && !AppFeature.notch.initialInstallGroup.contains(.notchFullscreenMenuBar)
                        && AppFeature.notchFullscreenMenuBar.permissions == [.accessibility],
                     "an opt-in extension that uses Accessibility")
    }
}
