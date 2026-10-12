// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Gesture mappings: what persists, what is refused, and when a saved action
/// is reported as unable to run.
enum TrackpadGestureMappingTests {
    static func run(_ suite: TestSuite) {
        let swipeUp4 = TrackpadGesture(kind: .swipeUp, fingers: 4)!
        let tap5 = TrackpadGesture(kind: .tap, fingers: 5)!
        let pinchIn5 = TrackpadGesture(kind: .pinchIn, fingers: 5)!
        let shortcut = RadialMenuItem(kind: .shortcut, payload: "command+shift:21")
        let tool = RadialMenuItem(kind: .tool, payload: RadialMenuTool.clipboardHistory.rawValue)
        let mappings: [TrackpadGesture: TriggerAction] = [
            swipeUp4: .navigation(.missionControl),
            tap5: .item(shortcut),
            pinchIn5: .item(tool),
            TrackpadGesture(kind: .swipeLeft, fingers: 3)!: .backForward(.back),
            TrackpadGesture(kind: .swipeRight, fingers: 3)!: .backForward(.forward),
        ]
        let decoded = TrackpadGestureMappingSupport.decode(TrackpadGestureMappingSupport.encode(mappings))
        suite.expect(decoded == mappings, "mappings survive a save and a reload")

        let submenu = RadialMenuItem(kind: .submenu, children: [tool])
        suite.expect(TrackpadGestureMappingSupport.sanitized(.item(submenu)) == nil,
                     "a submenu has no meaning outside the wheel and is refused")
        suite.expect(TrackpadGestureMappingSupport.sanitized(.item(RadialMenuItem(kind: .shortcut, payload: "nonsense"))) == nil
                        && TrackpadGestureMappingSupport.sanitized(.item(RadialMenuItem(kind: .tool, payload: "unknownTool"))) == nil
                        && TrackpadGestureMappingSupport.sanitized(.item(RadialMenuItem(kind: .app, payload: "  "))) == nil,
                     "actions that cannot run are refused like dead wheel slices")
        if case .item(let url)? = TrackpadGestureMappingSupport.sanitized(.item(RadialMenuItem(kind: .url, payload: " example.com "))) {
            suite.expect(url.payload == RadialMenuSupport.normalizedURL("example.com"),
                         "links are normalized as on the wheel")
        } else {
            suite.expect(false, "a plain host is accepted as a link")
        }

        let json = """
        {"tap-5":{"navigation":"spaceRight"},
         "tap-2":{"navigation":"spaceLeft"},
         "wave-4":{"navigation":"spaceLeft"},
         "swipe-up-4":{"navigation":"teleport"},
         "swipe-down-4":{"backForward":"sideways"},
         "swipe-down-5":{"backForward":"forward"},
         "pinch-in-5":{"item":{"kind":"unknownKind","payload":"x"}},
         "swipe-left-3":{"item":{"kind":"tool","payload":"\(RadialMenuTool.shelf.rawValue)"}}}
        """
        let lenient = TrackpadGestureMappingSupport.decode(Data(json.utf8))
        suite.expect(lenient.count == 3
                        && lenient[tap5] == .navigation(.spaceRight)
                        && lenient[TrackpadGesture(kind: .swipeDown, fingers: 5)!] == .backForward(.forward)
                        && lenient[TrackpadGesture(kind: .swipeLeft, fingers: 3)!] != nil,
                     "unknown gestures, kinds and navigations are dropped without losing the rest")
        suite.expect(TrackpadGestureMappingSupport.decode(nil).isEmpty
                        && TrackpadGestureMappingSupport.decode(Data("not json".utf8)).isEmpty,
                     "a missing or corrupt blob reads as no mappings")

        suite.expect(TrackpadGestureMappingSupport.sanitized(.backForward(.back)) == .backForward(.back)
                        && TrackpadGestureMappingSupport.needsAccessibility(.backForward(.back)),
                     "Back and Forward are kept as they are and press the app's command, which needs Accessibility")
        suite.expect(TrackpadGestureMappingSupport.needsAccessibility(.navigation(.spaceLeft))
                        && TrackpadGestureMappingSupport.needsAccessibility(.item(shortcut))
                        && !TrackpadGestureMappingSupport.needsAccessibility(.item(RadialMenuItem(kind: .url, payload: "https://example.com"))),
                     "replaying keys needs Accessibility, opening a link does not")

        func unavailability(_ action: TriggerAction,
                            available: Set<AppFeature> = Set(AppFeature.allCases),
                            files: Set<String> = [],
                            shortcuts: Set<SpaceNavigation> = Set(SpaceNavigation.allCases)) -> TriggerActionUnavailability? {
            TrackpadGestureMappingSupport.unavailability(action,
                                                         isFeatureAvailable: { available.contains($0) },
                                                         boolFor: { _ in true },
                                                         fileExists: { files.contains($0) },
                                                         systemShortcutExists: { shortcuts.contains($0) })
        }
        suite.expect(unavailability(.item(tool)) == nil
                        && unavailability(.item(tool), available: []) == .featureMissing(.clipboardHistory),
                     "a tool whose feature is uninstalled reports which feature to install")
        suite.expect(unavailability(.navigation(.missionControl), shortcuts: []) == .systemShortcutOff,
                     "a navigation whose system shortcut is off says so")
        suite.expect(unavailability(.backForward(.forward), available: [], shortcuts: []) == nil,
                     "Back and Forward depend on no other feature and no system shortcut")
        suite.expect(MouseNavigationSupport.sendsSideButton(miss: .absent, pointerOverApp: true, buttonClaimed: false)
                        && MouseNavigationSupport.buttonNumber(for: .back) == MouseNavigationSupport.backButtonNumber
                        && MouseNavigationSupport.buttonNumber(for: .forward) == MouseNavigationSupport.forwardButtonNumber,
                     "an app with neither command in its menus gets the side button a mouse would send")
        suite.expect(!MouseNavigationSupport.sendsSideButton(miss: .disabled, pointerOverApp: true, buttonClaimed: false)
                        && !MouseNavigationSupport.sendsSideButton(miss: .unanswered, pointerOverApp: true, buttonClaimed: false),
                     "a command that is switched off, or menus that did not answer, send no button")
        suite.expect(!MouseNavigationSupport.sendsSideButton(miss: .absent, pointerOverApp: false, buttonClaimed: false)
                        && !MouseNavigationSupport.sendsSideButton(miss: .absent, pointerOverApp: true, buttonClaimed: true),
                     "the button is held back from another app's window and from a feature that owns it")
        let app = RadialMenuItem(kind: .app, payload: "/Applications/Example.app")
        suite.expect(unavailability(.item(app)) == .targetMissing
                        && unavailability(.item(app), files: ["/Applications/Example.app"]) == nil,
                     "an application moved away is reported, one in place is not")
        suite.expect(unavailability(.item(RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.allCases[0].rawValue)),
                                    available: []) == .featureMissing(.windowLayout),
                     "a window layout needs the window layout feature")
    }
}
