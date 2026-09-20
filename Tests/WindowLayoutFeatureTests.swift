// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum WindowLayoutFeatureTests {
    static func run(_ suite: TestSuite) {
        // The native full screen action, wired like the sixths: real strings,
        // a stable id, and no system-wide key claimed until someone asks.
        suite.expect(WindowLayoutAction.allCases.contains(.fullScreen)
                && WindowLayoutAction.fullScreen.shortcutID == 53
                && WindowLayoutAction(shortcutID: 53) == .fullScreen,
               "full screen exists and answers to its own shortcut id")
        suite.expect(WindowLayoutAction.fullScreen.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutFullScreen] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "full screen starts with no combination of its own")
        suite.expect(WindowLayoutAction.allCases.contains(.previousDisplay)
                && WindowLayoutAction.previousDisplay.shortcutID == 54
                && WindowLayoutAction(shortcutID: 54) == .previousDisplay,
               "previous display exists and answers to its own shortcut id")
        suite.expect(WindowLayoutAction.previousDisplay.defaultShortcut == nil,
               "previous display does not claim a new system-wide combination")
        suite.expect(WindowLayoutAction.allCases.contains(.marginMaximize)
                && WindowLayoutAction.marginMaximize.shortcutID == 55
                && WindowLayoutAction(shortcutID: 55) == .marginMaximize,
               "margin maximize exists and answers to its own shortcut id")
        suite.expect(WindowLayoutAction.marginMaximize.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutMarginMaximize] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "margin maximize starts with no combination of its own")
        suite.expect(WindowLayoutAction.allCases.contains(.centerHalf)
                && WindowLayoutAction.centerHalf.shortcutID == 57
                && WindowLayoutAction(shortcutID: 57) == .centerHalf,
               "center half exists and answers to its own shortcut id")
        suite.expect(WindowLayoutAction.centerHalf.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutCenterHalf] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "center half starts with no combination of its own")
        suite.expect(WindowLayoutAction.allCases.contains(.centerTwoThirds)
                && WindowLayoutAction.centerTwoThirds.shortcutID == 56
                && WindowLayoutAction(shortcutID: 56) == .centerTwoThirds,
               "center two thirds exists and answers to its own shortcut id")
        suite.expect(WindowLayoutAction.centerTwoThirds.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutCenterTwoThirds] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "center two thirds starts with no combination of its own")
        let verticalLayouts: [(WindowLayoutAction, UInt32, String)] = [
            (.topQuarter, 66, DefaultsKey.windowLayoutShortcutTopQuarter),
            (.upperMiddleQuarter, 58, DefaultsKey.windowLayoutShortcutUpperMiddleQuarter),
            (.lowerMiddleQuarter, 59, DefaultsKey.windowLayoutShortcutLowerMiddleQuarter),
            (.bottomQuarter, 60, DefaultsKey.windowLayoutShortcutBottomQuarter),
            (.leftQuarter, 67, DefaultsKey.windowLayoutShortcutLeftQuarter),
            (.leftMiddleQuarter, 68, DefaultsKey.windowLayoutShortcutLeftMiddleQuarter),
            (.rightMiddleQuarter, 69, DefaultsKey.windowLayoutShortcutRightMiddleQuarter),
            (.rightQuarter, 70, DefaultsKey.windowLayoutShortcutRightQuarter),
            (.topThird, 61, DefaultsKey.windowLayoutShortcutTopThird),
            (.middleThird, 62, DefaultsKey.windowLayoutShortcutMiddleThird),
            (.bottomThird, 63, DefaultsKey.windowLayoutShortcutBottomThird),
            (.topTwoThirds, 64, DefaultsKey.windowLayoutShortcutTopTwoThirds),
            (.bottomTwoThirds, 65, DefaultsKey.windowLayoutShortcutBottomTwoThirds),
        ]
        for (action, shortcutID, defaultsKey) in verticalLayouts {
            suite.expect(WindowLayoutAction.allCases.contains(action)
                    && action.shortcutID == shortcutID
                    && WindowLayoutAction(shortcutID: shortcutID) == action,
                   "\(action.rawValue) exists and answers to its own shortcut id")
            suite.expect(action.defaultShortcut == nil
                    && Defaults.registeredDefaults[defaultsKey] as? String
                        == WindowLayoutAction.clearedShortcutStorageValue,
                   "\(action.rawValue) starts with no combination of its own")
        }
        suite.expect(Set(WindowLayoutAction.allCases.map(\.shortcutID)).count
                == WindowLayoutAction.allCases.count,
               "every layout action keeps a distinct shortcut id")
        for language in AppLanguage.allCases {
            let layoutStrings = FeatureStrings.windowLayout(language)
            suite.expect(!layoutStrings.fullScreen.isEmpty && !layoutStrings.previousDisplay.isEmpty
                    && !layoutStrings.marginMaximize.isEmpty
                    && !layoutStrings.centerHalf.isEmpty
                    && !layoutStrings.centerTwoThirds.isEmpty
                    && !layoutStrings.quarterRows.isEmpty
                    && !layoutStrings.quarterColumns.isEmpty
                    && !layoutStrings.leftQuarter.isEmpty
                    && !layoutStrings.leftMiddleQuarter.isEmpty
                    && !layoutStrings.rightMiddleQuarter.isEmpty
                    && !layoutStrings.rightQuarter.isEmpty
                    && !layoutStrings.topQuarter.isEmpty
                    && !layoutStrings.upperMiddleQuarter.isEmpty
                    && !layoutStrings.lowerMiddleQuarter.isEmpty
                    && !layoutStrings.bottomQuarter.isEmpty
                    && !layoutStrings.topThird.isEmpty
                    && !layoutStrings.middleThird.isEmpty
                    && !layoutStrings.bottomThird.isEmpty
                    && !layoutStrings.topTwoThirds.isEmpty
                    && !layoutStrings.bottomTwoThirds.isEmpty,
                   "\(language.rawValue) names the latest window layout actions")
        }
        suite.expect(WindowLayoutGeometry.accepts(actualRect: .zero, targetRect: .zero,
                                            action: .fullScreen, anchorTolerance: 10) == false,
               "full screen never joins the frame-based gesture acceptance")
        suite.expect(WindowLayoutAction.center.targetCapability == .position
                && WindowLayoutAction.fullScreen.targetCapability == .fullScreen
                && WindowLayoutAction.maximize.targetCapability == .frame
                && WindowLayoutAction.restore.targetCapability == .position,
               "window layout targets only the attributes each action changes")

        // MARK: Window layout shortcut resolution (issue #169)

        suite.expect(WindowLayoutAction.resolvedShortcut(storedValue: nil,
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutLeftDefault,
               "window layout falls back to the default shortcut when nothing was saved")
        suite.expect(WindowLayoutAction.resolvedShortcut(storedValue: WindowLayoutAction.clearedShortcutStorageValue,
                                                   defaultShortcut: .windowLayoutLeftDefault) == nil,
               "a cleared window layout shortcut resolves to no shortcut at all")
        suite.expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value",
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutLeftDefault,
               "a corrupt stored shortcut falls back to the default, never to cleared")
        suite.expect(WindowLayoutAction.resolvedShortcut(storedValue: GlobalShortcut.windowLayoutRightDefault.storageValue,
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutRightDefault,
               "a saved window layout shortcut wins over the default")
        suite.expect(WindowLayoutAction.resolvedShortcut(storedValue: nil, defaultShortcut: nil) == nil,
               "a window layout action without a default shortcut stays unassigned")
        suite.expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value", defaultShortcut: nil) == nil,
               "a corrupt shortcut cannot assign an action that has no default")

        // MARK: Window layout restore history (issue #414)

        let historyWindow = WindowLayoutWindowKey(processID: 41,
                                                  processLaunchTime: 100,
                                                  windowID: 414)
        let otherHistoryWindow = WindowLayoutWindowKey(processID: 42,
                                                       processLaunchTime: 100,
                                                       windowID: 414)
        let reusedHistoryWindow = WindowLayoutWindowKey(processID: 41,
                                                        processLaunchTime: 101,
                                                        windowID: 414)
        let historyFrames: [WindowLayoutFrame] = (0...WindowLayoutHistory.perWindowLimit).map { index in
            let origin = CGPoint(x: index * 10, y: index * 20)
            let size = CGSize(width: 800 + index, height: 500 + index)
            return WindowLayoutFrame(origin: origin, size: size)
        }
        var layoutHistory = WindowLayoutHistory()
        layoutHistory.record(historyFrames[0], for: historyWindow)
        layoutHistory.record(historyFrames[1], for: historyWindow)
        layoutHistory.record(historyFrames[2], for: historyWindow)
        layoutHistory.record(historyFrames[3], for: otherHistoryWindow)
        suite.expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[3]) == historyFrames[2]
               && layoutHistory.popPrevious(for: historyWindow, current: historyFrames[2]) == historyFrames[1]
               && layoutHistory.popPrevious(for: historyWindow, current: historyFrames[1]) == historyFrames[0],
               "window layout restore walks backward through each window's placement history")
        suite.expect(layoutHistory.popPrevious(for: otherHistoryWindow, current: historyFrames[4]) == historyFrames[3],
               "window layout restore histories stay isolated across processes")
        layoutHistory.record(historyFrames[5], for: historyWindow)
        layoutHistory.record(historyFrames[6], for: historyWindow)
        layoutHistory.discardLatest(for: historyWindow)
        suite.expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[7]) == historyFrames[5],
               "a failed window layout action removes only the frame it recorded")
        layoutHistory.record(historyFrames[8], for: historyWindow)
        layoutHistory.record(historyFrames[9], for: historyWindow)
        suite.expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[9]) == historyFrames[8],
               "restore skips a saved frame that already matches the current placement")
        layoutHistory.record(historyFrames[10], for: historyWindow)
        layoutHistory.record(historyFrames[11], for: reusedHistoryWindow)
        layoutHistory.removeStaleWindows(keeping: [reusedHistoryWindow])
        suite.expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[12]) == nil
               && layoutHistory.popPrevious(for: reusedHistoryWindow,
                                            current: historyFrames[12]) == historyFrames[11],
               "closed windows and earlier process lifetimes cannot leak restore history")
        var boundedHistory = WindowLayoutHistory()
        for frame in historyFrames {
            boundedHistory.record(frame, for: historyWindow)
        }
        var boundedFrames: [WindowLayoutFrame] = []
        var boundedCurrent = WindowLayoutFrame(origin: CGPoint(x: -1, y: -1),
                                               size: CGSize(width: 1, height: 1))
        while let previous = boundedHistory.popPrevious(for: historyWindow, current: boundedCurrent) {
            boundedFrames.append(previous)
            boundedCurrent = previous
        }
        suite.expect(boundedFrames.count == WindowLayoutHistory.perWindowLimit
               && boundedFrames.last == historyFrames[1],
               "window layout history keeps only the most recent bounded set of placements")

        // MARK: Window layout geometry

        let visibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let currentWindow = CGRect(x: 200, y: 200, width: 800, height: 500)
        let snapVisibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 835)
        let snapScreen = WindowEdgeSnapScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                              visibleFrame: snapVisibleFrame)
        func snapTarget(_ point: CGPoint,
                        screens: [WindowEdgeSnapScreen] = [snapScreen],
                        enabledZones: Set<WindowEdgeSnapZone> =
                            WindowEdgeSnapZone.allEnabled) -> WindowEdgeSnapTarget? {
            WindowEdgeSnapSupport.target(at: point,
                                         screens: screens,
                                         enabledZones: enabledZones)
        }
        let topSnapFrame = WindowLayoutGeometry.rect(for: .maximize,
                                                     current: snapVisibleFrame,
                                                     visibleFrame: snapVisibleFrame)
        suite.expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY))
               == WindowEdgeSnapTarget(zone: .top,
                                       frame: topSnapFrame,
                                       visibleFrame: snapVisibleFrame),
               "touching the lower edge of the menu bar previews maximize")
        suite.expect(snapTarget(CGPoint(x: 720, y: 900))?.action == .maximize,
               "the full menu bar band remains a top snap target for maximize")
        suite.expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY - 13)) == nil,
               "the top target does not reach below its activation band")
        suite.expect(snapTarget(CGPoint(x: 0, y: 450))?.action == .leftHalf
               && snapTarget(CGPoint(x: 1440, y: 450))?.action == .rightHalf
               && snapTarget(CGPoint(x: 720, y: 0))?.action == .bottomHalf,
               "straight edges choose their matching placements")
        suite.expect(snapTarget(CGPoint(x: 0, y: snapVisibleFrame.maxY))?.action == .topLeft
               && snapTarget(CGPoint(x: 1440, y: snapVisibleFrame.maxY))?.action == .topRight
               && snapTarget(CGPoint(x: 0, y: 0))?.action == .bottomLeft
               && snapTarget(CGPoint(x: 1440, y: 0))?.action == .bottomRight,
               "inclusive screen corners take priority over straight edges")
        suite.expect(snapTarget(CGPoint(x: 720, y: 450)) == nil,
               "dragging inside a display never creates a snap target")

        let disabledZoneStorage = WindowEdgeSnapZone.disabledZonesStorageValue([.right, .top])
        suite.expect(disabledZoneStorage == "top,right"
               && WindowEdgeSnapZone.disabledZones(
                   from: "unknown, right,top"
               ) == Set([.top, .right]),
               "edge snap zones serialize visibly and discard unknown saved ids")
        let withoutTop = WindowEdgeSnapZone.enabledZones(from: disabledZoneStorage)
        suite.expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY),
                          enabledZones: withoutTop) == nil
               && snapTarget(CGPoint(x: 0, y: 450),
                             enabledZones: withoutTop)?.zone == .left,
               "turning off the top zone leaves the other visual snap areas active")
        suite.expect(WindowEdgeSnapSupport.target(
                   at: CGPoint(x: 720, y: snapVisibleFrame.maxY),
                   screens: [snapScreen],
                   enabledZones: []
               ) == nil,
               "turning off every visual zone leaves no snap target")

        let quartzScreenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let quartzTopCenter = CGPoint(x: 720, y: 0)
        suite.expect(WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(
                   quartzTopCenter,
                   screenFrames: [quartzScreenFrame]
               ) == CGPoint(x: 720, y: 1),
               "an active top snap zone stays clear of the system top drag")
        suite.expect(WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(
                   quartzTopCenter,
                   screenFrames: [quartzScreenFrame],
                   enabledZones: withoutTop
               ) == quartzTopCenter,
               "a disabled top zone returns the exact pointer event to the system")
        suite.expect(WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(
                   CGPoint(x: 20, y: 0),
                   screenFrames: [quartzScreenFrame],
                   enabledZones: [.topLeft]
               ) == CGPoint(x: 20, y: 1),
               "an active top corner still protects its own snap gesture")

        let leftSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: -1280, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: -1280, y: 25, width: 1280, height: 775)
        )
        suite.expect(snapTarget(CGPoint(x: -1280, y: 400), screens: [leftSnapScreen])?.frame
               == CGRect(x: -1280, y: 25, width: 640, height: 775),
               "edge snapping keeps negative display origins and its visible frame")
        let rightSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: 40, width: 1920, height: 1040)
        )
        suite.expect(snapTarget(CGPoint(x: 1440, y: 450),
                          screens: [snapScreen, rightSnapScreen]) == nil,
               "a shared display seam stays open for moving a window across")
        suite.expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 1415, y: 450),
                                            screens: [snapScreen, rightSnapScreen],
                                            distance: 30) == nil,
               "the whole activation band around a shared seam stays open")
        let upperSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: 0, y: 900, width: 1280, height: 800),
            visibleFrame: CGRect(x: 0, y: 900, width: 1280, height: 775)
        )
        suite.expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY),
                          screens: [snapScreen, upperSnapScreen]) == nil,
               "a menu bar boundary below another display remains an open seam")
        suite.expect(WindowEdgeSnapSupport.systemTilingEnabled { _ in nil },
               "unwritten system tiling choices keep their enabled default")
        suite.expect(!WindowEdgeSnapSupport.systemTilingEnabled { _ in false },
               "edge snapping can start after every conflicting system choice is off")
        suite.expect(WindowEdgeSnapSupport.systemTilingEnabled {
                   $0 == "EnableTilingByEdgeDrag" ? true : false
               },
               "one enabled system edge gesture is enough to prevent competing previews")

        let dragFrame = CGRect(x: 100, y: 100, width: 800, height: 500)
        suite.expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 40, dy: 20),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 220)) == .moving,
               "edge snap confirms a window that follows the pointer")
        suite.expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame,
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 300, y: 300)) == .waiting,
               "a content drag with a still window never becomes window snapping")
        suite.expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: CGRect(x: 100, y: 100, width: 840, height: 500),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 200)) == .resizing,
               "native window resizing cancels edge snapping")
        suite.expect(WindowEdgeSnapSupport.classify(
                   initialFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                   currentFrame: CGRect(x: 100, y: 50, width: 800, height: 500),
                   pointerStart: CGPoint(x: 200, y: 100),
                   pointerNow: CGPoint(x: 300, y: 150)) == .moving,
               "a tiled window restoring its size while dragged is still a window move")
        suite.expect(WindowEdgeSnapSupport.classify(
                   initialFrame: CGRect(x: 0, y: 0, width: 720, height: 900),
                   currentFrame: CGRect(x: 100, y: 0, width: 800, height: 900),
                   pointerStart: CGPoint(x: 200, y: 100),
                   pointerNow: CGPoint(x: 300, y: 100)) == .moving,
               "a side tile restoring only its width is still a horizontal window move")
        suite.expect(WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.maxX, y: dragFrame.maxY),
                   frame: dragFrame),
               "a symmetric corner resize is rejected before movement classification")
        suite.expect(WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.midX, y: dragFrame.minY + 3),
                   frame: dragFrame),
               "a symmetric edge resize is rejected at the native resize handle")
        suite.expect(!WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.midX, y: dragFrame.minY + 14),
                   frame: dragFrame),
               "the title bar stays available away from resize corners")
        suite.expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 40, dy: 0),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 160, y: 200)) == .unrelated,
               "an unrelated window move cannot follow a pointer going the other way")
        suite.expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 10, dy: 0),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 200)) == .moving,
               "a short Accessibility lag still confirms the same drag")
        suite.expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 720, height: 860),
               "window layout left half targets the full left side")
        suite.expect(WindowLayoutGeometry.rect(for: .rightHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 40, width: 720, height: 860),
               "window layout right half targets the full right side")
        suite.expect(WindowLayoutGeometry.rect(for: .topHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 470, width: 1440, height: 430),
               "window layout top half targets the upper visible frame")
        suite.expect(WindowLayoutGeometry.rect(for: .bottomHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 1440, height: 430),
               "window layout bottom half targets the lower visible frame")
        suite.expect(WindowLayoutGeometry.rect(for: .leftThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 480, height: 860),
               "window layout left third targets the first third")
        suite.expect(WindowLayoutGeometry.rect(for: .centerThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 480, height: 860),
               "window layout center third targets the middle third")
        suite.expect(WindowLayoutGeometry.rect(for: .rightThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 960, y: 40, width: 480, height: 860),
               "window layout right third targets the final third")
        suite.expect(WindowLayoutGeometry.rect(for: .leftTwoThirds, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 960, height: 860),
               "window layout left two thirds targets the first two thirds")
        suite.expect(WindowLayoutGeometry.rect(for: .rightTwoThirds, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 960, height: 860),
               "window layout right two thirds targets the final two thirds")
        suite.expect(WindowLayoutGeometry.rect(for: .centerHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 360, y: 40, width: 720, height: 860),
               "window layout center half sits half wide in the middle of the screen")
        suite.expect(WindowLayoutGeometry.rect(for: .centerTwoThirds, current: currentWindow,
                                               visibleFrame: visibleFrame)
               == CGRect(x: 240, y: 40, width: 960, height: 860),
               "window layout center two thirds sits two thirds wide in the middle of the screen")
        let verticalStripLayouts: [(WindowLayoutAction, CGRect)] = [
            (.topQuarter, CGRect(x: 0, y: 685, width: 1440, height: 215)),
            (.upperMiddleQuarter, CGRect(x: 0, y: 470, width: 1440, height: 215)),
            (.lowerMiddleQuarter, CGRect(x: 0, y: 255, width: 1440, height: 215)),
            (.bottomQuarter, CGRect(x: 0, y: 40, width: 1440, height: 215)),
            (.leftQuarter, CGRect(x: 0, y: 40, width: 360, height: 860)),
            (.leftMiddleQuarter, CGRect(x: 360, y: 40, width: 360, height: 860)),
            (.rightMiddleQuarter, CGRect(x: 720, y: 40, width: 360, height: 860)),
            (.rightQuarter, CGRect(x: 1080, y: 40, width: 360, height: 860)),
            (.topThird, CGRect(x: 0, y: 613, width: 1440, height: 287)),
            (.middleThird, CGRect(x: 0, y: 326, width: 1440, height: 288)),
            (.bottomThird, CGRect(x: 0, y: 40, width: 1440, height: 287)),
            (.topTwoThirds, CGRect(x: 0, y: 326, width: 1440, height: 574)),
            (.bottomTwoThirds, CGRect(x: 0, y: 40, width: 1440, height: 574)),
        ]
        for (action, target) in verticalStripLayouts {
            suite.expect(WindowLayoutGeometry.rect(for: action,
                                                   current: currentWindow,
                                                   visibleFrame: visibleFrame) == target,
                   "\(action.rawValue) targets its strip")
        }
        suite.expect(WindowLayoutGeometry.anchoredRect(for: .leftQuarter,
                                                       targetRect: CGRect(x: 0, y: 40, width: 360, height: 860),
                                                       actualSize: CGSize(width: 600, height: 860),
                                                       visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 600, height: 860),
               "left quarter grows from the left edge of its column")
        suite.expect(WindowLayoutGeometry.anchoredRect(for: .rightMiddleQuarter,
                                                       targetRect: CGRect(x: 720, y: 40, width: 360, height: 860),
                                                       actualSize: CGSize(width: 600, height: 860),
                                                       visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 600, height: 860),
               "right middle quarter grows from the right edge of its column")
        suite.expect(WindowLayoutGeometry.anchoredRect(for: .topQuarter,
                                                       targetRect: CGRect(x: 0, y: 685, width: 1440, height: 215),
                                                       actualSize: CGSize(width: 1440, height: 400),
                                                       visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 500, width: 1440, height: 400),
               "top quarter keeps a larger window flush with the top of its strip")
        suite.expect(WindowLayoutGeometry.anchoredRect(for: .middleThird,
                                                       targetRect: CGRect(x: 0, y: 326, width: 1440, height: 288),
                                                       actualSize: CGSize(width: 1440, height: 400),
                                                       visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 270, width: 1440, height: 400),
               "middle third centers a larger window on its strip")
        suite.expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 0, y: 40, width: 712, height: 860),
               "the window gap shaves half the gap off the shared edge and leaves screen edges flush")
        suite.expect(WindowLayoutGeometry.rect(for: .rightHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 728, y: 40, width: 712, height: 860),
               "two gapped halves end up exactly one window gap apart")
        suite.expect(WindowLayoutGeometry.rect(for: .centerThird, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 488, y: 40, width: 464, height: 860),
               "a middle placement gives up half the gap on each shared edge")
        suite.expect(WindowLayoutGeometry.rect(for: .topLeft, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 32)
               == CGRect(x: 0, y: 486, width: 704, height: 414),
               "a corner shaves only its two interior edges")
        suite.expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         screenGap: 32)
               == CGRect(x: 32, y: 72, width: 688, height: 796),
               "the screen gap insets the visible frame before placement")
        suite.expect(WindowLayoutGeometry.rect(for: .maximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == CGRect(x: 32, y: 72, width: 1376, height: 796),
               "maximize respects the screen gap and ignores the window gap")
        suite.expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == CGRect(x: 32, y: 72, width: 680, height: 796),
               "window and screen gaps combine")
        suite.expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 64)
               == WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame),
               "centering has no neighbours, so the window gap leaves it alone")
        suite.expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 64)
               == WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame),
               "margin maximize keeps its own margin instead of the window gap")
        suite.expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame),
               "margin maximize keeps its plain percentage margin under a screen gap instead of compounding")
        suite.expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame,
                                         screenGap: 32)
               == WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame),
               "centering keeps the window's size under a screen gap instead of clamping to the inset frame")
        suite.expect(WindowLayoutGeometry.screenGapFrame(CGRect(x: 0, y: 0, width: 100, height: 100), screenGap: 128)
               == CGRect(x: 10, y: 10, width: 80, height: 80),
               "an oversized screen gap keeps 80pt of layout space instead of inverting the frame")
        let sixthLayouts: [(WindowLayoutAction, CGRect, CGRect)] = [
            (.topLeftSixth,
             CGRect(x: 0, y: 470, width: 480, height: 430),
             CGRect(x: 0, y: 400, width: 600, height: 500)),
            (.topCenterSixth,
             CGRect(x: 480, y: 470, width: 480, height: 430),
             CGRect(x: 420, y: 400, width: 600, height: 500)),
            (.topRightSixth,
             CGRect(x: 960, y: 470, width: 480, height: 430),
             CGRect(x: 840, y: 400, width: 600, height: 500)),
            (.bottomLeftSixth,
             CGRect(x: 0, y: 40, width: 480, height: 430),
             CGRect(x: 0, y: 40, width: 600, height: 500)),
            (.bottomCenterSixth,
             CGRect(x: 480, y: 40, width: 480, height: 430),
             CGRect(x: 420, y: 40, width: 600, height: 500)),
            (.bottomRightSixth,
             CGRect(x: 960, y: 40, width: 480, height: 430),
             CGRect(x: 840, y: 40, width: 600, height: 500)),
        ]
        for (action, target, anchored) in sixthLayouts {
            suite.expect(WindowLayoutGeometry.rect(for: action,
                                             current: currentWindow,
                                             visibleFrame: visibleFrame) == target,
                   "\(action.rawValue) targets its cell in the 3 by 2 grid")
            suite.expect(WindowLayoutGeometry.anchoredRect(for: action,
                                                     targetRect: target,
                                                     actualSize: CGSize(width: 600, height: 500),
                                                     visibleFrame: visibleFrame) == anchored,
                   "\(action.rawValue) preserves its requested horizontal and vertical anchors")
            suite.expect(WindowLayoutGeometry.accepts(actualRect: anchored,
                                                targetRect: target,
                                                action: action,
                                                anchorTolerance: 36),
                   "\(action.rawValue) accepts a larger minimum-sized window on the same anchors")
        }
        let nextDisplayFrame = CGRect(x: 1440, y: 80, width: 1920, height: 1000)
        let rightHalfWindow = CGRect(x: 720, y: 40, width: 720, height: 860)
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: rightHalfWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == CGRect(x: 2640, y: 220, width: 720, height: 860),
               "window layout display transfer keeps a right-half on the right and under the menu bar")
        let leftHalfWindow = CGRect(x: 0, y: 40, width: 720, height: 860)
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: leftHalfWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == CGRect(x: 1440, y: 220, width: 720, height: 860),
               "window layout display transfer keeps a left-half on the left and under the menu bar")
        let oversizedWindow = CGRect(x: -40, y: 0, width: 2000, height: 1200)
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: oversizedWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "window layout display transfer clamps oversized windows to the destination visible frame")
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: visibleFrame,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "display transfer fills the destination when the window already fills the source")
        let almostFilled = CGRect(x: 4, y: 44, width: 1432, height: 852)
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: almostFilled,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "display transfer treats a window within settle tolerance of maximize as filling the destination")
        let ultrawideFrame = CGRect(x: 1440, y: 0, width: 3440, height: 1400)
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: currentWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1640, y: 700, width: 800, height: 500),
               "display transfer keeps a laptop window's size and top-left insets on an ultrawide")
        let nearFullWidth = CGRect(x: 2, y: 200, width: 1436, height: 500)
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: nearFullWidth,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1442, y: 700, width: 1436, height: 500),
               "display transfer keeps a near-full-width window's left inset on an ultrawide")
        let nearFullWidthRightish = CGRect(x: 6, y: 200, width: 1432, height: 500)
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: nearFullWidthRightish,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1446, y: 700, width: 1432, height: 500),
               "display transfer does not treat a few points of leftover width as a right edge")
        let shortDisplay = CGRect(x: 1440, y: 80, width: 1920, height: 400)
        let shrunkWindow = WindowLayoutGeometry.rectForDisplay(current: currentWindow,
                                                               sourceVisibleFrame: visibleFrame,
                                                               destinationVisibleFrame: shortDisplay)
        suite.expect(shrunkWindow == CGRect(x: 1640, y: 80, width: 800, height: 400),
               "display transfer shrinks a taller window to fit a shorter display")
        suite.expect(WindowLayoutGeometry.rectForDisplay(current: shrunkWindow,
                                                   sourceVisibleFrame: shortDisplay,
                                                   destinationVisibleFrame: visibleFrame)
               == CGRect(x: 200, y: 500, width: 800, height: 400),
               "display transfer does not restore the original height after shrinking to fit")
        let horizontalDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: -1200, y: -200, width: 1200, height: 1920),
            CGRect(x: 1440, y: 300, width: 2560, height: 1440),
        ]
        suite.expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: horizontalDisplays,
                                                         movingForward: false) == 1
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 2,
                                                             frames: horizontalDisplays,
                                                             movingForward: true) == 1,
               "window layout orders unequal displays left to right and wraps both ways")
        let verticalDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 900, height: 1440),
            CGRect(x: 0, y: -1200, width: 1920, height: 1200),
        ]
        suite.expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: verticalDisplays,
                                                         movingForward: false) == 2
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                             frames: verticalDisplays,
                                                             movingForward: true) == 1,
               "window layout orders stacked displays by their vertical origin")
        suite.expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: [visibleFrame],
                                                         movingForward: false) == nil
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 3,
                                                             frames: horizontalDisplays,
                                                             movingForward: true) == nil,
               "window layout leaves one display and invalid selections unchanged")
        suite.expect(WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 0,
                                                             frames: horizontalDisplays,
                                                             movingRight: true) == 2
                && WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 0,
                                                                 frames: horizontalDisplays,
                                                                 movingRight: false) == 1
                && WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 2,
                                                                 frames: horizontalDisplays,
                                                                 movingRight: false) == 0,
               "window layout finds the display starting on the asked side")
        suite.expect(WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 2,
                                                             frames: horizontalDisplays,
                                                             movingRight: true) == nil
                && WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 1,
                                                                 frames: horizontalDisplays,
                                                                 movingRight: false) == nil,
               "window layout stops at the outermost display instead of wrapping sideways")
        let stackedDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 1440, height: 900),
        ]
        suite.expect(WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 0,
                                                             frames: stackedDisplays,
                                                             movingRight: true) == nil
                && WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 1,
                                                                 frames: stackedDisplays,
                                                                 movingRight: false) == nil,
               "window layout never answers a sideways push with a stacked display")
        let towerDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 800, width: 1000, height: 1000),
            CGRect(x: 1440, y: -100, width: 1000, height: 1000),
        ]
        suite.expect(WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 0,
                                                             frames: towerDisplays,
                                                             movingRight: true) == 2,
               "window layout picks the closest display when several share the same edge")
        let portraitFrame = CGRect(x: -1200, y: -200, width: 1200, height: 1800)
        let scaledFrame = CGRect(x: 1440, y: 100, width: 2000, height: 1000)
        let portraitWindow = CGRect(x: -900, y: 1000, width: 600, height: 400)
        let scaledWindow = WindowLayoutGeometry.rectForDisplay(current: portraitWindow,
                                                               sourceVisibleFrame: portraitFrame,
                                                               destinationVisibleFrame: scaledFrame)
        suite.expect(scaledWindow == CGRect(x: 1740, y: 500, width: 600, height: 400)
                && WindowLayoutGeometry.rectForDisplay(current: scaledWindow,
                                                       sourceVisibleFrame: scaledFrame,
                                                       destinationVisibleFrame: portraitFrame)
                    == portraitWindow,
               "display transfer keeps size and edge insets across rotated frames")
        suite.expect(WindowLayoutAction.shortcutActions.count == WindowLayoutAction.allCases.count,
               "every window layout action can register a global shortcut")
        suite.expect(WindowLayoutAction.shortcutActions.contains(.previousDisplay)
                && WindowLayoutAction.shortcutActions.contains(.nextDisplay),
               "both display directions can register a global shortcut")
        suite.expect(Set(WindowLayoutAction.shortcutActions.map(\.shortcutKey)).count
               == WindowLayoutAction.shortcutActions.count,
               "every window layout shortcut has its own defaults key")
        suite.expect(WindowLayoutAction.shortcutActions.contains(.leftHalf),
               "existing half actions keep global shortcuts")
        suite.expect([WindowLayoutAction.topLeftSixth, .topCenterSixth, .topRightSixth,
                .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]
               .allSatisfy { $0.supportsShortcut && $0.defaultShortcut == nil },
               "sixth actions support optional shortcuts without claiming defaults")
        suite.expect(WindowLayoutGeometry.rect(for: .topLeft, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 470, width: 720, height: 430),
               "window layout top left targets the upper-left quadrant")
        suite.expect(WindowLayoutGeometry.rect(for: .topRight, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 470, width: 720, height: 430),
               "window layout top right targets the upper-right quadrant")
        suite.expect(WindowLayoutGeometry.rect(for: .bottomLeft, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 720, height: 430),
               "window layout bottom left targets the lower-left quadrant")
        suite.expect(WindowLayoutGeometry.rect(for: .bottomRight, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 40, width: 720, height: 430),
               "window layout bottom right targets the lower-right quadrant")
        suite.expect(WindowLayoutGeometry.rect(for: .maximize, current: currentWindow, visibleFrame: visibleFrame)
               == visibleFrame,
               "window layout maximize uses the full visible frame")
        let marginMaximizeTarget = WindowLayoutGeometry.rect(for: .marginMaximize,
                                                              current: currentWindow,
                                                              visibleFrame: visibleFrame)
        suite.expect(marginMaximizeTarget == CGRect(x: 72, y: 83, width: 1296, height: 774),
               "window layout margin maximize keeps five percent on every usable edge")
        suite.expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 320, y: 220, width: 800, height: 500),
               "window layout center preserves current size and centers inside the visible frame")
        suite.expect(WindowLayoutGeometry.rect(for: .restore, current: currentWindow, visibleFrame: visibleFrame)
               == currentWindow,
               "window layout restore keeps the saved frame")
        let topWindow = CGRect(x: 0, y: 470, width: 1440, height: 430)
        let bottomWindow = CGRect(x: 0, y: 40, width: 1440, height: 430)
        let leftWindow = CGRect(x: 0, y: 40, width: 720, height: 860)
        let topLeftWindow = CGRect(x: 0, y: 470, width: 720, height: 430)
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top half stays direct when the previous layout action was not top")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf) == .maximize,
               "window layout top half promotes only when top is used twice in a row")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top half stays top when the window is elsewhere")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .bottomHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .bottomHalf,
               "window layout bottom does not promote while at the top")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct when the window is already at the top")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf) == .leftHalf,
               "window layout left does not become a corner after top")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .rightHalf,
               "window layout right stays direct when the window is already at the top")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct when the window is already at the bottom")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame) == .rightHalf,
               "window layout right stays direct when the window is already at the bottom")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topLeftWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct from the upper-left corner")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topLeftWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top stays direct from the upper-left corner")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: leftWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top stays direct when the window is already on the left")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .bottomHalf,
                                                    current: leftWindow,
                                                    visibleFrame: visibleFrame) == .bottomHalf,
               "window layout bottom stays direct when the window is already on the left")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .bottomHalf) == .rightHalf,
               "window layout right does not become a corner after bottom")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .rightHalf,
                                                    previousAction: .rightHalf)?.action == .leftHalf
                && WindowLayoutGeometry.displayCrossing(for: .rightHalf,
                                                        previousAction: .rightHalf)?.movingRight == true,
               "window layout right twice enters the display on the right from its left half")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .leftHalf,
                                                    previousAction: .leftHalf)?.action == .rightHalf
                && WindowLayoutGeometry.displayCrossing(for: .leftHalf,
                                                        previousAction: .leftHalf)?.movingRight == false,
               "window layout left twice enters the display on the left from its right half")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .leftHalf, previousAction: nil) == nil
                && WindowLayoutGeometry.displayCrossing(for: .leftHalf, previousAction: .rightHalf) == nil,
               "window layout only crosses displays when the same side is used twice in a row")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .topHalf, previousAction: .topHalf) == nil
                && WindowLayoutGeometry.displayCrossing(for: .bottomHalf, previousAction: .bottomHalf) == nil
                && WindowLayoutGeometry.displayCrossing(for: .leftThird, previousAction: .leftThird) == nil,
               "window layout keeps top, bottom and thirds on their own display")
        let leftTarget = WindowLayoutGeometry.rect(for: .leftHalf,
                                                   current: currentWindow,
                                                   visibleFrame: visibleFrame)
        let rightTarget = WindowLayoutGeometry.rect(for: .rightHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame)
        suite.expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 0, y: 40, width: 720, height: 430),
                                            targetRect: leftTarget,
                                            action: .leftHalf,
                                            anchorTolerance: 36) == false,
               "window layout left half does not accept a lower-left corner as the full side")
        suite.expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 720, y: 40, width: 720, height: 430),
                                            targetRect: rightTarget,
                                            action: .rightHalf,
                                            anchorTolerance: 36) == false,
               "window layout right half does not accept a lower-right corner as the full side")
        suite.expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 540, y: 40, width: 900, height: 860),
                                            targetRect: rightTarget,
                                            action: .rightHalf,
                                            anchorTolerance: 36),
               "window layout right half accepts a larger app minimum size when it spans the full height")
        suite.expect(WindowLayoutGeometry.anchoredRect(for: .rightHalf,
                                                 targetRect: rightTarget,
                                                 actualSize: CGSize(width: 900, height: 700),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 540, y: 40, width: 900, height: 700),
               "window layout right anchors the accepted app size to the right edge")
        let bottomTarget = WindowLayoutGeometry.rect(for: .bottomHalf,
                                                     current: currentWindow,
                                                     visibleFrame: visibleFrame)
        suite.expect(WindowLayoutGeometry.anchoredRect(for: .bottomHalf,
                                                 targetRect: bottomTarget,
                                                 actualSize: CGSize(width: 1000, height: 620),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 1000, height: 620),
               "window layout bottom anchors the accepted app size to the bottom edge")
        let bottomRightTarget = WindowLayoutGeometry.rect(for: .bottomRight,
                                                          current: currentWindow,
                                                          visibleFrame: visibleFrame)
        suite.expect(WindowLayoutGeometry.anchoredRect(for: .bottomRight,
                                                 targetRect: bottomRightTarget,
                                                 actualSize: CGSize(width: 900, height: 620),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 540, y: 40, width: 900, height: 620),
               "window layout bottom right anchors the accepted app size to both requested edges")
        suite.expect(WindowLayoutGeometry.anchoredRect(for: .marginMaximize,
                                                 targetRect: marginMaximizeTarget,
                                                 actualSize: CGSize(width: 1400, height: 820),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 20, y: 60, width: 1400, height: 820),
               "window layout margin maximize keeps a constrained app centered")
        suite.expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 320, y: 220, width: 800, height: 500),
                                            targetRect: marginMaximizeTarget,
                                            action: .marginMaximize,
                                            anchorTolerance: 36) == false,
               "window layout margin maximize rejects a merely centered small window")

    }
}
