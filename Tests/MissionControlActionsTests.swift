// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MissionControlActionsTests {
    static func run(_ suite: TestSuite) {
        let first = MissionControlTileSnapshot(
            frame: CGRect(x: 100, y: 100, width: 400, height: 240),
            role: "AXButton", windowID: 101
        )
        let second = MissionControlTileSnapshot(
            frame: CGRect(x: 600, y: 120, width: 420, height: 260),
            role: "AXButton", windowID: 202
        )
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windows = [
            MissionControlWindowSnapshot(windowID: 101, ownerPID: 1101, ownerIsWindowManager: false,
                                         layer: 0, bounds: CGRect(x: 80, y: 60, width: 800, height: 480),
                                         onScreen: true, alpha: 1),
            MissionControlWindowSnapshot(windowID: 202, ownerPID: 2202, ownerIsWindowManager: false,
                                         layer: 4, bounds: CGRect(x: 520, y: 80, width: 840, height: 520),
                                         onScreen: true, alpha: 1),
            MissionControlWindowSnapshot(windowID: 9001, ownerPID: 77, ownerIsWindowManager: true,
                                         layer: 0, bounds: CGRect(x: 93, y: 93, width: 414, height: 254),
                                         onScreen: true, alpha: 1),
            MissionControlWindowSnapshot(windowID: 9002, ownerPID: 77, ownerIsWindowManager: true,
                                         layer: 2, bounds: CGRect(x: 170, y: 180, width: 250, height: 80),
                                         onScreen: true, alpha: 1),
            MissionControlWindowSnapshot(windowID: 9003, ownerPID: 77, ownerIsWindowManager: true,
                                         layer: 19, bounds: screen, onScreen: true, alpha: 1),
        ]
        func fixture(tiles: [MissionControlTileSnapshot] = [first, second],
                     windows replacement: [MissionControlWindowSnapshot]? = nil,
                     bundleIdentifier: String? = "com.apple.WindowManager",
                     displayIdentifier: String? = "mc.display",
                     displayChildren: Int = 2,
                     axTreeComplete: Bool = true,
                     stageManagerEnabled: Bool = false,
                     ownPID: pid_t = 9999) -> MissionControlDetectionSnapshot {
            MissionControlDetectionSnapshot(
                windowManagerBundleIdentifier: bundleIdentifier,
                displayIdentifier: displayIdentifier,
                displayFrame: screen,
                displayChildrenCount: displayChildren,
                tiles: tiles,
                windows: replacement ?? windows,
                screenFrames: [screen],
                axTreeComplete: axTreeComplete,
                stageManagerEnabled: stageManagerEnabled,
                ownPID: ownPID
            )
        }

        // Minimal, anonymized shape from measurement 2: two apps, numeric wid,
        // one WindowManager hover frame on layer 0 and its layer-2 companion.
        let hit = MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200), in: fixture()
        )
        let expectedHit = MissionControlTarget(
            windowID: 101, ownerPID: 1101, tileFrame: first.frame
        )
        suite.expect(hit == expectedHit,
                     "the measured positive signature resolves the hovered tile to one real window")
        suite.expect(hit != nil,
                     "a nonzero app window layer elsewhere in the complete tile tree remains valid")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 700, y: 200), in: fixture()) == nil,
                     "a tile without the matching WindowManager hover frame passes through")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 20, y: 20), in: fixture()) == nil,
                     "a point outside every tile passes through")

        let noLayer2 = windows.filter { !($0.ownerIsWindowManager && $0.layer == 2) }
        suite.expect(MissionControlActionsSupport.cgWindowSignaturePresent(in: windows)
                     && !MissionControlActionsSupport.cgWindowSignaturePresent(in: noLayer2)
                     && !MissionControlActionsSupport.cgWindowSignaturePresent(
                        in: windows.filter { !($0.ownerIsWindowManager && $0.layer == 0) }
                     ),
                     "the cheap preflight requires the measured WindowManager layer-0/2 signature")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200), in: fixture(windows: noLayer2)) == nil,
                     "the desktop-like fixture without layer 2 is uncertain")
        let duplicate = windows + [MissionControlWindowSnapshot(
            windowID: 101, ownerPID: 3303, ownerIsWindowManager: false,
            layer: 0, bounds: CGRect(x: 90, y: 70, width: 800, height: 480),
            onScreen: true, alpha: 1)]
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200), in: fixture(windows: duplicate)) == nil,
                     "a non-unique CGWindowID match passes through")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200),
            in: fixture(windows: windows.filter { $0.windowID != 202 })) == nil,
                     "an incomplete whole-tree wid snapshot passes through")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200),
            in: fixture(tiles: [first, MissionControlTileSnapshot(
                frame: second.frame, role: second.role, windowID: 101
            )])) == nil,
                     "duplicate tile ids make the snapshot uncertain")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200),
            in: fixture(bundleIdentifier: "com.example.WindowManager")) == nil,
                     "a lookalike process never passes for WindowManager")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200),
            in: fixture(displayIdentifier: nil)) == nil,
                     "a tree without mc.display passes through")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200),
            in: fixture(axTreeComplete: false)) == nil,
                     "an AX error or traversal limit makes the whole snapshot uncertain")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200),
            in: fixture(stageManagerEnabled: true)) == nil,
                     "Stage Manager disables Mission Control actions even for a lookalike tree")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200),
            in: fixture(ownPID: 1101)) == nil,
                     "the app never targets one of its own windows")
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200),
            in: fixture(tiles: [first])) == nil,
                     "a one-app App-Expose-like snapshot passes through")

        var fullscreenWindows = windows
        fullscreenWindows[0] = MissionControlWindowSnapshot(
            windowID: 101, ownerPID: 1101, ownerIsWindowManager: false,
            layer: 0, bounds: screen, onScreen: true, alpha: 1)
        suite.expect(MissionControlActionsSupport.target(
            at: CGPoint(x: 300, y: 200), in: fixture(windows: fullscreenWindows)) == nil,
                     "a fullscreen real window passes through")

        let settings = MissionControlActionSettings(
            rightClick: .terminateApp, middleClick: .none, keyboardShortcutsEnabled: true
        )
        suite.expect(MissionControlActionsSupport.action(for: .rightClick, settings: settings) == .terminateApp
                     && MissionControlActionsSupport.action(for: .middleClick, settings: settings)
                        == MissionControlAction.none,
                     "right and middle click use their independent configured actions")
        suite.expect(MissionControlActionsSupport.action(for: .commandW, settings: settings) == .closeWindow
                     && MissionControlActionsSupport.action(for: .commandQ, settings: settings) == .terminateApp
                     && MissionControlActionsSupport.action(for: .commandH, settings: settings) == .hideApp
                     && MissionControlActionsSupport.action(for: .commandM, settings: settings) == .minimizeWindow,
                     "Command-W/Q/H/M map to the documented hovered-window actions")
        suite.expect([MissionControlInput.leftArrow, .rightArrow, .upArrow, .downArrow, .enter]
            .allSatisfy { MissionControlActionsSupport.action(for: $0, settings: settings) == nil },
                     "arrow keys and Enter are never claimed")
        let noKeys = MissionControlActionSettings(
            rightClick: .closeWindow, middleClick: .minimizeWindow,
            keyboardShortcutsEnabled: false
        )
        suite.expect(MissionControlActionsSupport.action(for: .commandW, settings: noKeys) == nil
                     && MissionControlActionsSupport.action(for: .rightClick, settings: noKeys) == .closeWindow,
                     "the shortcut switch does not change mouse actions")

        suite.expect(MissionControlAction.sanitized("unknown") == .none
                     && MissionControlAction.sanitized(MissionControlAction.hideApp.rawValue) == .hideApp,
                     "unknown restored action values fail open to Nothing")
        let identity = MissionControlProcessIdentity(processIdentifier: 1101, launchTime: 50)
        let validatedHit = MissionControlValidatedTarget(
            target: expectedHit, processIdentity: identity, windowResolved: true
        )
        let pendingQuit = MissionControlPendingAction(target: validatedHit, action: .terminateApp)
        var gesture = MissionControlPointerGesture()
        suite.expect(gesture.resolveBeforeNewDown() == .none,
                     "a first down has no stale press to resolve")
        suite.expect(gesture.beginDown(button: .right, point: CGPoint(x: 200, y: 180),
                                      target: validatedHit, action: .terminateApp, now: 10) == .suppress,
                     "an unambiguous actionable down is held")
        suite.expect(gesture.drag(button: .right, point: CGPoint(x: 204, y: 182)) == .suppress,
                     "pointer jitter remains a click candidate")
        suite.expect(gesture.endUp(button: .right, point: CGPoint(x: 204, y: 182), now: 10.3)
            == .revalidate(pendingQuit),
                     "a clean release requests fresh off-tap validation before acting")

        suite.expect(gesture.beginDown(button: .middle, point: CGPoint(x: 200, y: 180),
                                      target: validatedHit, action: .closeWindow, now: 20) == .suppress,
                     "a middle-button action starts the same guarded gesture")
        suite.expect(gesture.drag(button: .middle, point: CGPoint(x: 210, y: 180))
            == .replayDownAndPass,
                     "movement past the slop returns the gesture to Mission Control")
        suite.expect(gesture.endUp(button: .middle, point: CGPoint(x: 210, y: 180), now: 20.2)
            == .passThrough,
                     "the release after a native drag is not swallowed")
        suite.expect(gesture.beginDown(button: .right, point: .zero,
                                      target: nil, action: .terminateApp, now: 30) == .passThrough
                     && gesture.beginDown(button: .right, point: .zero,
                                          target: validatedHit, action: .none, now: 31) == .passThrough,
                     "uncertainty and Nothing pass every event through")
        _ = gesture.beginDown(button: .right, point: .zero, target: validatedHit,
                              action: .terminateApp, now: 40)
        suite.expect(gesture.endUp(button: .right, point: .zero, now: 41.501)
            == .replayPairNoAction,
                     "a press held for more than 1.5 seconds replays both events without acting")
        _ = gesture.beginDown(button: .right, point: .zero, target: validatedHit,
                              action: .terminateApp, now: 50)
        suite.expect(gesture.resolveBeforeNewDown() == .replayIfStillHeld,
                     "a new down first resolves a pending press whose up was lost")
        suite.expect(gesture.beginDown(button: .right, point: .zero, target: nil,
                                      action: .terminateApp, now: 50.2) == .passThrough
                     && gesture.resolveBeforeNewDown() == .none,
                     "a non-suppressed down leaves no stale pending state")
        _ = gesture.beginDown(button: .right, point: .zero, target: validatedHit,
                              action: .terminateApp, now: 60)
        suite.expect(gesture.expire(now: 61.4) == .none
                     && gesture.expire(now: 61.501) == .replayIfStillHeld
                     && gesture.expire(now: 62) == .none,
                     "the pending-down timeout releases custody once and prevents a later action")
        _ = gesture.beginDown(button: .right, point: .zero, target: validatedHit,
                              action: .terminateApp, now: 70)
        suite.expect(gesture.reset() == .replayIfStillHeld
                     && gesture.reset() == .none,
                     "tap recovery clears pending custody exactly once")

        let timing = MissionControlSnapshotTiming(startedAt: 100, finishedAt: 100.2)
        suite.expect(timing.isUsable(now: 100.44),
                     "a sub-250ms snapshot remains usable inside the cache age")
        suite.expect(!timing.isUsable(now: 100.451),
                     "cache age is measured from capture start, not completion")
        suite.expect(!MissionControlSnapshotTiming(startedAt: 100, finishedAt: 100.251)
            .isUsable(now: 100.251),
                     "a capture taking more than 250ms is discarded immediately")

        let runtimeOn = MissionControlRuntimeConditions(
            featureWanted: true, accessibilityGranted: true, sessionIsActive: true,
            stageManagerEnabled: false, cgWindowSignaturePresent: true,
            axGatePositive: true, snapshotFresh: true
        )
        suite.expect(runtimeOn.decision == MissionControlRuntimeDecision(
            monitor: true, captureAX: true, holdEventTap: true
        ), "the event tap exists only behind the cheap and complete Mission Control gate")
        suite.expect(runtimeOn.replacing(accessibilityGranted: false).decision
            == MissionControlRuntimeDecision(monitor: false, captureAX: false, holdEventTap: false)
                     && runtimeOn.replacing(accessibilityGranted: true).decision.holdEventTap,
                     "permission revocation stops monitoring and a new grant can restart it")
        suite.expect(runtimeOn.replacing(stageManagerEnabled: true).decision
            == MissionControlRuntimeDecision(monitor: false, captureAX: false, holdEventTap: false),
                     "Stage Manager blocks both AX polling and the tap")
        suite.expect(runtimeOn.replacing(cgWindowSignaturePresent: false).decision
            == MissionControlRuntimeDecision(monitor: true, captureAX: false, holdEventTap: false),
                     "the cheap CGWindowList gate prevents an AX walk outside Mission Control")
        suite.expect(!runtimeOn.replacing(axGatePositive: false).decision.holdEventTap
                     && !runtimeOn.replacing(snapshotFresh: false).decision.holdEventTap,
                     "uncertain AX state or a stale cache removes the event tap")

        let fresh = MissionControlValidatedTarget(
            target: expectedHit, processIdentity: identity, windowResolved: true
        )
        suite.expect(MissionControlRevalidationSupport.decision(
            original: pendingQuit, freshTarget: fresh, ownPID: 9999) == .perform,
                     "a fresh same-tile, same-process, existing-window match may perform")
        let closedFreshTarget = MissionControlValidatedTarget(
            target: expectedHit, processIdentity: identity, windowResolved: false
        )
        suite.expect(MissionControlAction.allCases.filter { $0 != .none }.allSatisfy { action in
            MissionControlRevalidationSupport.decision(
                original: MissionControlPendingAction(target: validatedHit, action: action),
                freshTarget: closedFreshTarget,
                ownPID: 9999
            ) == .replayEvents
        }, "every window and app action requires the real window to still exist")
        let reusedPID = MissionControlValidatedTarget(
            target: expectedHit,
            processIdentity: MissionControlProcessIdentity(processIdentifier: 1101, launchTime: 51),
            windowResolved: true
        )
        suite.expect(MissionControlRevalidationSupport.decision(
            original: pendingQuit, freshTarget: reusedPID, ownPID: 9999) == .replayEvents,
                     "a reused PID with a different launch identity replays instead of acting")
        let changedPID = MissionControlValidatedTarget(
            target: MissionControlTarget(
                windowID: expectedHit.windowID, ownerPID: 2202, tileFrame: expectedHit.tileFrame
            ),
            processIdentity: MissionControlProcessIdentity(processIdentifier: 2202, launchTime: 50),
            windowResolved: true
        )
        suite.expect(MissionControlRevalidationSupport.decision(
            original: pendingQuit, freshTarget: changedPID, ownPID: 9999) == .replayEvents,
                     "a changed owner PID replays even when the window id is unchanged")
        let movedPointer = MissionControlValidatedTarget(
            target: MissionControlTarget(windowID: 202, ownerPID: 2202, tileFrame: second.frame),
            processIdentity: MissionControlProcessIdentity(processIdentifier: 2202, launchTime: 60),
            windowResolved: true
        )
        suite.expect(MissionControlRevalidationSupport.decision(
            original: pendingQuit, freshTarget: movedPointer, ownPID: 9999) == .replayEvents
                     && MissionControlRevalidationSupport.decision(
                        original: pendingQuit, freshTarget: nil, ownPID: 9999) == .replayEvents
                     && MissionControlRevalidationSupport.decision(
                        original: pendingQuit,
                        freshTarget: closedFreshTarget, ownPID: 9999) == .replayEvents,
                     "a different tile, closed window or failed gate always replays")
        suite.expect(MissionControlRevalidationSupport.decision(
            original: pendingQuit, freshTarget: fresh, ownPID: 1101) == .replayEvents,
                     "revalidation never targets the running Vorssaint process")

        let preferenceKeys: Set<String> = [
            DefaultsKey.missionControlActionsEnabled,
            DefaultsKey.missionControlRightClickAction,
            DefaultsKey.missionControlMiddleClickAction,
            DefaultsKey.missionControlKeyboardShortcutsEnabled,
        ]
        suite.expect(Defaults.registeredDefaults[DefaultsKey.missionControlActionsEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.missionControlRightClickAction] as? String
                        == MissionControlAction.terminateApp.rawValue
                     && Defaults.registeredDefaults[DefaultsKey.missionControlMiddleClickAction] as? String
                        == MissionControlAction.none.rawValue
                     && Defaults.registeredDefaults[DefaultsKey.missionControlKeyboardShortcutsEnabled] as? Bool
                        == false,
                     "the feature starts off with Quit app and Nothing as its mouse defaults")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: preferenceKeys),
                     "all Mission Control preferences travel in Settings backup")
        suite.expect(AppFeature.missionControlActions.group == .windowsDock
                     && AppFeature.missionControlActions.enabledKeys
                        == [DefaultsKey.missionControlActionsEnabled]
                     && AppFeature.missionControlActions.permissions == [.accessibility]
                     && AppFeature.missionControlActions.monitorsPermissionChanges
                     && !AppFeature.missionControlActions.installedByDefault,
                     "the feature catalog keeps Mission Control opt-in and Accessibility-backed")
        suite.expect(AppFeature.missionControlActions.settingsDestination
                        == FeatureSettingsDestination(.missionControl)
                     && FeatureVisibilitySupport.features(for: .missionControl)
                        == [.missionControlActions],
                     "the feature owns one visibility-gated Mission Control Settings page")
        let appDelegateSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift", encoding: .utf8
        )) ?? ""
        let accessibilitySink = appDelegateSource
            .components(separatedBy: "Permissions.shared.$accessibility").dropFirst().first?
            .components(separatedBy: "Permissions.shared.$screenRecording").first ?? ""
        suite.expect(accessibilitySink.contains(".missionControlActions"),
                     "Accessibility permission changes resync Mission Control actions")
        let localized = AppLanguage.allCases.map(FeatureStrings.missionControlActions)
        suite.expect(localized.count == 15 && localized.allSatisfy {
            !$0.title.isEmpty && !$0.pageDescription.isEmpty && !$0.hubDescription.isEmpty
                && !$0.enable.isEmpty && !$0.help.isEmpty && !$0.actionNone.isEmpty
                && !$0.actionCloseWindow.isEmpty && !$0.actionMinimizeWindow.isEmpty
                && !$0.actionTerminateApp.isEmpty && !$0.actionHideApp.isEmpty
        }, "all 15 app languages have the Mission Control page and action strings")
        let limitationMarkers: [AppLanguage: (String, String)] = [
            .enUS: ("Stage Manager", "only one app"),
            .ptBR: ("Stage Manager", "apenas um app"),
            .tr: ("Stage Manager", "bir uygulamanın"),
            .ru: ("Stage Manager", "одного приложения"),
            .es: ("Stage Manager", "una sola app"),
            .sk: ("Stage Manager", "jednej aplikácie"),
            .de: ("Stage Manager", "einer App"),
            .fr: ("Stage Manager", "une seule app"),
            .it: ("Stage Manager", "una sola app"),
            .ja: ("Stage Manager", "1つのアプリ"),
            .ko: ("Stage Manager", "한 앱"),
            .uk: ("Stage Manager", "однієї програми"),
            .zhHans: ("台前调度", "一个 App"),
            .zhTW: ("幕前調度", "一個 App"),
            .zhHK: ("幕前管理", "一個 App"),
        ]
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            guard let markers = limitationMarkers[language] else { return false }
            let help = FeatureStrings.missionControlActions(language).help
            return help.contains(markers.0) && help.contains(markers.1)
        }, "all 15 help texts disclose Stage Manager and the one-app limitation")

        let german = FeatureStrings.missionControlActions(.de)
        suite.expect(german.actionCloseWindow == "Fenster schließen"
                     && german.actionMinimizeWindow == "Im Dock ablegen"
                     && german.actionTerminateApp == "App beenden"
                     && german.actionHideApp == "App ausblenden",
                     "German Mission Control actions use the macOS terms users see")
        suite.expect(AppLanguage.allCases.allSatisfy {
            FeatureStrings.missionControlActions($0).keyboardShortcuts == "⌘W/Q/H/M"
        }, "the shortcut label uses the language-neutral macOS Command glyph")
        suite.expect(AppLanguage.allCases.filter { $0 != .enUS }.allSatisfy { language in
            let strings = FeatureStrings.missionControlActions(language)
            return !strings.help.contains("Return")
                && !strings.enableCaption.contains("Command")
                && !strings.keyboardShortcutsCaption.contains("Command")
        }, "non-English Mission Control copy has no English key-name leftovers")

        let searchFeatureItems = SettingsSearchSupport.featureItems(language: .de) {
            $0 == .missionControlActions ? german.title : $0.rawValue
        }
        let searchItems = [
            SettingsSearchItem(id: .page(.features),
                               destination: FeatureSettingsDestination(.features),
                               title: "Funktionen", icon: "square.grid.2x2"),
        ] + searchFeatureItems
        let searchGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "Mission Control", items: searchItems, isAvailable: { _ in false })
        let missionSuggestion = searchGroups.first?.suggestions.first
        let missionRoute = missionSuggestion.map {
            SettingsSearchSupport.route(for: $0, isAvailable: { _ in false })
        }
        suite.expect(searchGroups.map(\.id) == [.features]
                     && missionSuggestion?.title == "Mission Control"
                     && missionRoute?.destination == FeatureSettingsDestination(.features)
                     && missionRoute?.targetFeature == .missionControlActions,
                     "an uninstalled Mission Control search hit targets its exact Features row")

        let missionSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/MissionControlSettings.swift",
            encoding: .utf8
        )) ?? ""
        suite.expect(missionSettingsSource.contains("missionControl.enable")
                     && !missionSettingsSource.contains("if enabled {\n                    SettingsCard {\n                        Text(text.help)"),
                     "the Mission Control page exposes a stable AX switch and its limits before enabling")
    }
}
