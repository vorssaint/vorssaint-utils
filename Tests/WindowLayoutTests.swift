// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

enum WindowLayoutTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Window layout shortcut resolution (issue #169)

        expect(WindowLayoutAction.resolvedShortcut(storedValue: nil,
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutLeftDefault,
               "window layout falls back to the default shortcut when nothing was saved")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: WindowLayoutAction.clearedShortcutStorageValue,
                                                   defaultShortcut: .windowLayoutLeftDefault) == nil,
               "a cleared window layout shortcut resolves to no shortcut at all")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value",
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutLeftDefault,
               "a corrupt stored shortcut falls back to the default, never to cleared")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: GlobalShortcut.windowLayoutRightDefault.storageValue,
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutRightDefault,
               "a saved window layout shortcut wins over the default")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: nil, defaultShortcut: nil) == nil,
               "a window layout action without a default shortcut stays unassigned")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value", defaultShortcut: nil) == nil,
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
        expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[3]) == historyFrames[2]
               && layoutHistory.popPrevious(for: historyWindow, current: historyFrames[2]) == historyFrames[1]
               && layoutHistory.popPrevious(for: historyWindow, current: historyFrames[1]) == historyFrames[0],
               "window layout restore walks backward through each window's placement history")
        expect(layoutHistory.popPrevious(for: otherHistoryWindow, current: historyFrames[4]) == historyFrames[3],
               "window layout restore histories stay isolated across processes")
        layoutHistory.record(historyFrames[5], for: historyWindow)
        layoutHistory.record(historyFrames[6], for: historyWindow)
        layoutHistory.discardLatest(for: historyWindow)
        expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[7]) == historyFrames[5],
               "a failed window layout action removes only the frame it recorded")
        layoutHistory.record(historyFrames[8], for: historyWindow)
        layoutHistory.record(historyFrames[9], for: historyWindow)
        expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[9]) == historyFrames[8],
               "restore skips a saved frame that already matches the current placement")
        layoutHistory.record(historyFrames[10], for: historyWindow)
        layoutHistory.record(historyFrames[11], for: reusedHistoryWindow)
        layoutHistory.removeStaleWindows(keeping: [reusedHistoryWindow])
        expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[12]) == nil
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
        expect(boundedFrames.count == WindowLayoutHistory.perWindowLimit
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
        expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY))
               == WindowEdgeSnapTarget(zone: .top,
                                       frame: topSnapFrame,
                                       visibleFrame: snapVisibleFrame),
               "touching the lower edge of the menu bar previews maximize")
        expect(snapTarget(CGPoint(x: 720, y: 900))?.action == .maximize,
               "the full menu bar band remains a top snap target for maximize")
        expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY - 13)) == nil,
               "the top target does not reach below its activation band")
        expect(snapTarget(CGPoint(x: 0, y: 450))?.action == .leftHalf
               && snapTarget(CGPoint(x: 1440, y: 450))?.action == .rightHalf
               && snapTarget(CGPoint(x: 720, y: 0))?.action == .bottomHalf,
               "straight edges choose their matching placements")
        expect(snapTarget(CGPoint(x: 0, y: snapVisibleFrame.maxY))?.action == .topLeft
               && snapTarget(CGPoint(x: 1440, y: snapVisibleFrame.maxY))?.action == .topRight
               && snapTarget(CGPoint(x: 0, y: 0))?.action == .bottomLeft
               && snapTarget(CGPoint(x: 1440, y: 0))?.action == .bottomRight,
               "inclusive screen corners take priority over straight edges")
        expect(snapTarget(CGPoint(x: 720, y: 450)) == nil,
               "dragging inside a display never creates a snap target")

        let disabledZoneStorage = WindowEdgeSnapZone.disabledZonesStorageValue([.right, .top])
        expect(disabledZoneStorage == "top,right"
               && WindowEdgeSnapZone.disabledZones(
                   from: "unknown, right,top"
               ) == Set([.top, .right]),
               "edge snap zones serialize visibly and discard unknown saved ids")
        let withoutTop = WindowEdgeSnapZone.enabledZones(from: disabledZoneStorage)
        expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY),
                          enabledZones: withoutTop) == nil
               && snapTarget(CGPoint(x: 0, y: 450),
                             enabledZones: withoutTop)?.zone == .left,
               "turning off the top zone leaves the other visual snap areas active")
        expect(WindowEdgeSnapSupport.target(
                   at: CGPoint(x: 720, y: snapVisibleFrame.maxY),
                   screens: [snapScreen],
                   enabledZones: []
               ) == nil,
               "turning off every visual zone leaves no snap target")

        let quartzScreenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let quartzTopCenter = CGPoint(x: 720, y: 0)
        expect(WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(
                   quartzTopCenter,
                   screenFrames: [quartzScreenFrame]
               ) == CGPoint(x: 720, y: 1),
               "an active top snap zone stays clear of the system top drag")
        expect(WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(
                   quartzTopCenter,
                   screenFrames: [quartzScreenFrame],
                   enabledZones: withoutTop
               ) == quartzTopCenter,
               "a disabled top zone returns the exact pointer event to the system")
        expect(WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(
                   CGPoint(x: 20, y: 0),
                   screenFrames: [quartzScreenFrame],
                   enabledZones: [.topLeft]
               ) == CGPoint(x: 20, y: 1),
               "an active top corner still protects its own snap gesture")

        let leftSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: -1280, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: -1280, y: 25, width: 1280, height: 775)
        )
        expect(snapTarget(CGPoint(x: -1280, y: 400), screens: [leftSnapScreen])?.frame
               == CGRect(x: -1280, y: 25, width: 640, height: 775),
               "edge snapping keeps negative display origins and its visible frame")
        let rightSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: 40, width: 1920, height: 1040)
        )
        expect(snapTarget(CGPoint(x: 1440, y: 450),
                          screens: [snapScreen, rightSnapScreen]) == nil,
               "a shared display seam stays open for moving a window across")
        expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 1415, y: 450),
                                            screens: [snapScreen, rightSnapScreen],
                                            distance: 30) == nil,
               "the whole activation band around a shared seam stays open")
        let upperSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: 0, y: 900, width: 1280, height: 800),
            visibleFrame: CGRect(x: 0, y: 900, width: 1280, height: 775)
        )
        expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY),
                          screens: [snapScreen, upperSnapScreen]) == nil,
               "a menu bar boundary below another display remains an open seam")
        expect(WindowEdgeSnapSupport.systemTilingEnabled { _ in nil },
               "unwritten system tiling choices keep their enabled default")
        expect(!WindowEdgeSnapSupport.systemTilingEnabled { _ in false },
               "edge snapping can start after every conflicting system choice is off")
        expect(WindowEdgeSnapSupport.systemTilingEnabled {
                   $0 == "EnableTilingByEdgeDrag" ? true : false
               },
               "one enabled system edge gesture is enough to prevent competing previews")

        let dragFrame = CGRect(x: 100, y: 100, width: 800, height: 500)
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 40, dy: 20),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 220)) == .moving,
               "edge snap confirms a window that follows the pointer")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame,
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 300, y: 300)) == .waiting,
               "a content drag with a still window never becomes window snapping")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: CGRect(x: 100, y: 100, width: 840, height: 500),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 200)) == .resizing,
               "native window resizing cancels edge snapping")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                   currentFrame: CGRect(x: 100, y: 50, width: 800, height: 500),
                   pointerStart: CGPoint(x: 200, y: 100),
                   pointerNow: CGPoint(x: 300, y: 150)) == .moving,
               "a tiled window restoring its size while dragged is still a window move")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: CGRect(x: 0, y: 0, width: 720, height: 900),
                   currentFrame: CGRect(x: 100, y: 0, width: 800, height: 900),
                   pointerStart: CGPoint(x: 200, y: 100),
                   pointerNow: CGPoint(x: 300, y: 100)) == .moving,
               "a side tile restoring only its width is still a horizontal window move")
        expect(WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.maxX, y: dragFrame.maxY),
                   frame: dragFrame),
               "a symmetric corner resize is rejected before movement classification")
        expect(WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.midX, y: dragFrame.minY + 3),
                   frame: dragFrame),
               "a symmetric edge resize is rejected at the native resize handle")
        expect(!WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.midX, y: dragFrame.minY + 14),
                   frame: dragFrame),
               "the title bar stays available away from resize corners")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 40, dy: 0),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 160, y: 200)) == .unrelated,
               "an unrelated window move cannot follow a pointer going the other way")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 10, dy: 0),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 200)) == .moving,
               "a short Accessibility lag still confirms the same drag")
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 720, height: 860),
               "window layout left half targets the full left side")
        expect(WindowLayoutGeometry.rect(for: .rightHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 40, width: 720, height: 860),
               "window layout right half targets the full right side")
        expect(WindowLayoutGeometry.rect(for: .topHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 470, width: 1440, height: 430),
               "window layout top half targets the upper visible frame")
        expect(WindowLayoutGeometry.rect(for: .bottomHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 1440, height: 430),
               "window layout bottom half targets the lower visible frame")
        expect(WindowLayoutGeometry.rect(for: .leftThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 480, height: 860),
               "window layout left third targets the first third")
        expect(WindowLayoutGeometry.rect(for: .centerThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 480, height: 860),
               "window layout center third targets the middle third")
        expect(WindowLayoutGeometry.rect(for: .rightThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 960, y: 40, width: 480, height: 860),
               "window layout right third targets the final third")
        expect(WindowLayoutGeometry.rect(for: .leftTwoThirds, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 960, height: 860),
               "window layout left two thirds targets the first two thirds")
        expect(WindowLayoutGeometry.rect(for: .rightTwoThirds, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 960, height: 860),
               "window layout right two thirds targets the final two thirds")
        expect(WindowLayoutGeometry.rect(for: .centerHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 360, y: 40, width: 720, height: 860),
               "window layout center half sits half wide in the middle of the screen")
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 0, y: 40, width: 712, height: 860),
               "the window gap shaves half the gap off the shared edge and leaves screen edges flush")
        expect(WindowLayoutGeometry.rect(for: .rightHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 728, y: 40, width: 712, height: 860),
               "two gapped halves end up exactly one window gap apart")
        expect(WindowLayoutGeometry.rect(for: .centerThird, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 488, y: 40, width: 464, height: 860),
               "a middle placement gives up half the gap on each shared edge")
        expect(WindowLayoutGeometry.rect(for: .topLeft, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 32)
               == CGRect(x: 0, y: 486, width: 704, height: 414),
               "a corner shaves only its two interior edges")
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         screenGap: 32)
               == CGRect(x: 32, y: 72, width: 688, height: 796),
               "the screen gap insets the visible frame before placement")
        expect(WindowLayoutGeometry.rect(for: .maximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == CGRect(x: 32, y: 72, width: 1376, height: 796),
               "maximize respects the screen gap and ignores the window gap")
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == CGRect(x: 32, y: 72, width: 680, height: 796),
               "window and screen gaps combine")
        expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 64)
               == WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame),
               "centering has no neighbours, so the window gap leaves it alone")
        expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 64)
               == WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame),
               "margin maximize keeps its own margin instead of the window gap")
        expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame),
               "margin maximize keeps its plain percentage margin under a screen gap instead of compounding")
        expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame,
                                         screenGap: 32)
               == WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame),
               "centering keeps the window's size under a screen gap instead of clamping to the inset frame")
        expect(WindowLayoutGeometry.screenGapFrame(CGRect(x: 0, y: 0, width: 100, height: 100), screenGap: 128)
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
            expect(WindowLayoutGeometry.rect(for: action,
                                             current: currentWindow,
                                             visibleFrame: visibleFrame) == target,
                   "\(action.rawValue) targets its cell in the 3 by 2 grid")
            expect(WindowLayoutGeometry.anchoredRect(for: action,
                                                     targetRect: target,
                                                     actualSize: CGSize(width: 600, height: 500),
                                                     visibleFrame: visibleFrame) == anchored,
                   "\(action.rawValue) preserves its requested horizontal and vertical anchors")
            expect(WindowLayoutGeometry.accepts(actualRect: anchored,
                                                targetRect: target,
                                                action: action,
                                                anchorTolerance: 36),
                   "\(action.rawValue) accepts a larger minimum-sized window on the same anchors")
        }
        let nextDisplayFrame = CGRect(x: 1440, y: 80, width: 1920, height: 1000)
        let rightHalfWindow = CGRect(x: 720, y: 40, width: 720, height: 860)
        expect(WindowLayoutGeometry.rectForDisplay(current: rightHalfWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == CGRect(x: 2640, y: 220, width: 720, height: 860),
               "window layout display transfer keeps a right-half on the right and under the menu bar")
        let leftHalfWindow = CGRect(x: 0, y: 40, width: 720, height: 860)
        expect(WindowLayoutGeometry.rectForDisplay(current: leftHalfWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == CGRect(x: 1440, y: 220, width: 720, height: 860),
               "window layout display transfer keeps a left-half on the left and under the menu bar")
        let oversizedWindow = CGRect(x: -40, y: 0, width: 2000, height: 1200)
        expect(WindowLayoutGeometry.rectForDisplay(current: oversizedWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "window layout display transfer clamps oversized windows to the destination visible frame")
        expect(WindowLayoutGeometry.rectForDisplay(current: visibleFrame,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "display transfer fills the destination when the window already fills the source")
        let almostFilled = CGRect(x: 4, y: 44, width: 1432, height: 852)
        expect(WindowLayoutGeometry.rectForDisplay(current: almostFilled,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "display transfer treats a window within settle tolerance of maximize as filling the destination")
        let ultrawideFrame = CGRect(x: 1440, y: 0, width: 3440, height: 1400)
        expect(WindowLayoutGeometry.rectForDisplay(current: currentWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1640, y: 700, width: 800, height: 500),
               "display transfer keeps a laptop window's size and top-left insets on an ultrawide")
        let nearFullWidth = CGRect(x: 2, y: 200, width: 1436, height: 500)
        expect(WindowLayoutGeometry.rectForDisplay(current: nearFullWidth,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1442, y: 700, width: 1436, height: 500),
               "display transfer keeps a near-full-width window's left inset on an ultrawide")
        let nearFullWidthRightish = CGRect(x: 6, y: 200, width: 1432, height: 500)
        expect(WindowLayoutGeometry.rectForDisplay(current: nearFullWidthRightish,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1446, y: 700, width: 1432, height: 500),
               "display transfer does not treat a few points of leftover width as a right edge")
        let shortDisplay = CGRect(x: 1440, y: 80, width: 1920, height: 400)
        let shrunkWindow = WindowLayoutGeometry.rectForDisplay(current: currentWindow,
                                                               sourceVisibleFrame: visibleFrame,
                                                               destinationVisibleFrame: shortDisplay)
        expect(shrunkWindow == CGRect(x: 1640, y: 80, width: 800, height: 400),
               "display transfer shrinks a taller window to fit a shorter display")
        expect(WindowLayoutGeometry.rectForDisplay(current: shrunkWindow,
                                                   sourceVisibleFrame: shortDisplay,
                                                   destinationVisibleFrame: visibleFrame)
               == CGRect(x: 200, y: 500, width: 800, height: 400),
               "display transfer does not restore the original height after shrinking to fit")
        let horizontalDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: -1200, y: -200, width: 1200, height: 1920),
            CGRect(x: 1440, y: 300, width: 2560, height: 1440),
        ]
        expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
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
        expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: verticalDisplays,
                                                         movingForward: false) == 2
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                             frames: verticalDisplays,
                                                             movingForward: true) == 1,
               "window layout orders stacked displays by their vertical origin")
        expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: [visibleFrame],
                                                         movingForward: false) == nil
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 3,
                                                             frames: horizontalDisplays,
                                                             movingForward: true) == nil,
               "window layout leaves one display and invalid selections unchanged")
        expect(WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 0,
                                                             frames: horizontalDisplays,
                                                             movingRight: true) == 2
                && WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 0,
                                                                 frames: horizontalDisplays,
                                                                 movingRight: false) == 1
                && WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 2,
                                                                 frames: horizontalDisplays,
                                                                 movingRight: false) == 0,
               "window layout finds the display starting on the asked side")
        expect(WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 2,
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
        expect(WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 0,
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
        expect(WindowLayoutGeometry.horizontalNeighbourIndex(currentIndex: 0,
                                                             frames: towerDisplays,
                                                             movingRight: true) == 2,
               "window layout picks the closest display when several share the same edge")
        let portraitFrame = CGRect(x: -1200, y: -200, width: 1200, height: 1800)
        let scaledFrame = CGRect(x: 1440, y: 100, width: 2000, height: 1000)
        let portraitWindow = CGRect(x: -900, y: 1000, width: 600, height: 400)
        let scaledWindow = WindowLayoutGeometry.rectForDisplay(current: portraitWindow,
                                                               sourceVisibleFrame: portraitFrame,
                                                               destinationVisibleFrame: scaledFrame)
        expect(scaledWindow == CGRect(x: 1740, y: 500, width: 600, height: 400)
                && WindowLayoutGeometry.rectForDisplay(current: scaledWindow,
                                                       sourceVisibleFrame: scaledFrame,
                                                       destinationVisibleFrame: portraitFrame)
                    == portraitWindow,
               "display transfer keeps size and edge insets across rotated frames")
        expect(WindowLayoutAction.shortcutActions.count == WindowLayoutAction.allCases.count,
               "every window layout action can register a global shortcut")
        expect(WindowLayoutAction.shortcutActions.contains(.previousDisplay)
                && WindowLayoutAction.shortcutActions.contains(.nextDisplay),
               "both display directions can register a global shortcut")
        expect(Set(WindowLayoutAction.shortcutActions.map(\.shortcutKey)).count
               == WindowLayoutAction.shortcutActions.count,
               "every window layout shortcut has its own defaults key")
        expect(WindowLayoutAction.shortcutActions.contains(.leftHalf),
               "existing half actions keep global shortcuts")
        expect([WindowLayoutAction.topLeftSixth, .topCenterSixth, .topRightSixth,
                .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]
               .allSatisfy { $0.supportsShortcut && $0.defaultShortcut == nil },
               "sixth actions support optional shortcuts without claiming defaults")
        expect(WindowLayoutGeometry.rect(for: .topLeft, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 470, width: 720, height: 430),
               "window layout top left targets the upper-left quadrant")
        expect(WindowLayoutGeometry.rect(for: .topRight, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 470, width: 720, height: 430),
               "window layout top right targets the upper-right quadrant")
        expect(WindowLayoutGeometry.rect(for: .bottomLeft, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 720, height: 430),
               "window layout bottom left targets the lower-left quadrant")
        expect(WindowLayoutGeometry.rect(for: .bottomRight, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 40, width: 720, height: 430),
               "window layout bottom right targets the lower-right quadrant")
        expect(WindowLayoutGeometry.rect(for: .maximize, current: currentWindow, visibleFrame: visibleFrame)
               == visibleFrame,
               "window layout maximize uses the full visible frame")
        let marginMaximizeTarget = WindowLayoutGeometry.rect(for: .marginMaximize,
                                                              current: currentWindow,
                                                              visibleFrame: visibleFrame)
        expect(marginMaximizeTarget == CGRect(x: 72, y: 83, width: 1296, height: 774),
               "window layout margin maximize keeps five percent on every usable edge")
        expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 320, y: 220, width: 800, height: 500),
               "window layout center preserves current size and centers inside the visible frame")
        expect(WindowLayoutGeometry.rect(for: .restore, current: currentWindow, visibleFrame: visibleFrame)
               == currentWindow,
               "window layout restore keeps the saved frame")
        let topWindow = CGRect(x: 0, y: 470, width: 1440, height: 430)
        let bottomWindow = CGRect(x: 0, y: 40, width: 1440, height: 430)
        let leftWindow = CGRect(x: 0, y: 40, width: 720, height: 860)
        let topLeftWindow = CGRect(x: 0, y: 470, width: 720, height: 430)
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top half stays direct when the previous layout action was not top")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf) == .maximize,
               "window layout top half promotes only when top is used twice in a row")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top half stays top when the window is elsewhere")
        expect(WindowLayoutGeometry.effectiveAction(for: .bottomHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .bottomHalf,
               "window layout bottom does not promote while at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct when the window is already at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf) == .leftHalf,
               "window layout left does not become a corner after top")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .rightHalf,
               "window layout right stays direct when the window is already at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct when the window is already at the bottom")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame) == .rightHalf,
               "window layout right stays direct when the window is already at the bottom")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topLeftWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct from the upper-left corner")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topLeftWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top stays direct from the upper-left corner")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: leftWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top stays direct when the window is already on the left")
        expect(WindowLayoutGeometry.effectiveAction(for: .bottomHalf,
                                                    current: leftWindow,
                                                    visibleFrame: visibleFrame) == .bottomHalf,
               "window layout bottom stays direct when the window is already on the left")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .bottomHalf) == .rightHalf,
               "window layout right does not become a corner after bottom")
        expect(WindowLayoutGeometry.displayCrossing(for: .rightHalf,
                                                    previousAction: .rightHalf)?.action == .leftHalf
                && WindowLayoutGeometry.displayCrossing(for: .rightHalf,
                                                        previousAction: .rightHalf)?.movingRight == true,
               "window layout right twice enters the display on the right from its left half")
        expect(WindowLayoutGeometry.displayCrossing(for: .leftHalf,
                                                    previousAction: .leftHalf)?.action == .rightHalf
                && WindowLayoutGeometry.displayCrossing(for: .leftHalf,
                                                        previousAction: .leftHalf)?.movingRight == false,
               "window layout left twice enters the display on the left from its right half")
        expect(WindowLayoutGeometry.displayCrossing(for: .leftHalf, previousAction: nil) == nil
                && WindowLayoutGeometry.displayCrossing(for: .leftHalf, previousAction: .rightHalf) == nil,
               "window layout only crosses displays when the same side is used twice in a row")
        expect(WindowLayoutGeometry.displayCrossing(for: .topHalf, previousAction: .topHalf) == nil
                && WindowLayoutGeometry.displayCrossing(for: .bottomHalf, previousAction: .bottomHalf) == nil
                && WindowLayoutGeometry.displayCrossing(for: .leftThird, previousAction: .leftThird) == nil,
               "window layout keeps top, bottom and thirds on their own display")
        let leftTarget = WindowLayoutGeometry.rect(for: .leftHalf,
                                                   current: currentWindow,
                                                   visibleFrame: visibleFrame)
        let rightTarget = WindowLayoutGeometry.rect(for: .rightHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 0, y: 40, width: 720, height: 430),
                                            targetRect: leftTarget,
                                            action: .leftHalf,
                                            anchorTolerance: 36) == false,
               "window layout left half does not accept a lower-left corner as the full side")
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 720, y: 40, width: 720, height: 430),
                                            targetRect: rightTarget,
                                            action: .rightHalf,
                                            anchorTolerance: 36) == false,
               "window layout right half does not accept a lower-right corner as the full side")
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 540, y: 40, width: 900, height: 860),
                                            targetRect: rightTarget,
                                            action: .rightHalf,
                                            anchorTolerance: 36),
               "window layout right half accepts a larger app minimum size when it spans the full height")
        expect(WindowLayoutGeometry.anchoredRect(for: .rightHalf,
                                                 targetRect: rightTarget,
                                                 actualSize: CGSize(width: 900, height: 700),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 540, y: 40, width: 900, height: 700),
               "window layout right anchors the accepted app size to the right edge")
        let bottomTarget = WindowLayoutGeometry.rect(for: .bottomHalf,
                                                     current: currentWindow,
                                                     visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.anchoredRect(for: .bottomHalf,
                                                 targetRect: bottomTarget,
                                                 actualSize: CGSize(width: 1000, height: 620),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 1000, height: 620),
               "window layout bottom anchors the accepted app size to the bottom edge")
        let bottomRightTarget = WindowLayoutGeometry.rect(for: .bottomRight,
                                                          current: currentWindow,
                                                          visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.anchoredRect(for: .bottomRight,
                                                 targetRect: bottomRightTarget,
                                                 actualSize: CGSize(width: 900, height: 620),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 540, y: 40, width: 900, height: 620),
               "window layout bottom right anchors the accepted app size to both requested edges")
        expect(WindowLayoutGeometry.anchoredRect(for: .marginMaximize,
                                                 targetRect: marginMaximizeTarget,
                                                 actualSize: CGSize(width: 1400, height: 820),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 20, y: 60, width: 1400, height: 820),
               "window layout margin maximize keeps a constrained app centered")
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 320, y: 220, width: 800, height: 500),
                                            targetRect: marginMaximizeTarget,
                                            action: .marginMaximize,
                                            anchorTolerance: 36) == false,
               "window layout margin maximize rejects a merely centered small window")

        // MARK: Window move and resize gestures

        expect(WindowGestureSupport.modifiers(from: nil) == [.control, .command],
               "window gestures fall back to control-command")
        expect(WindowGestureSupport.modifiers(from: "option+shift") == [.option],
               "shift stays reserved for trackpad resizing")
        expect(WindowGestureSupport.modifiers(from: "shift") == [.control, .command],
               "shift alone never takes over ordinary system dragging")
        expect(WindowGestureSupport.modifiers(from: "invalid") == [.control, .command],
               "corrupt window gesture modifiers fall back safely")
        expect(WindowGestureSupport.storageValue(for: [.command, .control]) == "control+command",
               "window gesture modifiers serialize in stable order")
        expect(WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand],
                                                   expected: [.control, .command]),
               "window gestures match their exact modifier chord")
        expect(!WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift],
                                                    expected: [.control, .command]),
               "the resize chord does not trigger window movement")
        let resizeModifiers = WindowGestureSupport.resizeModifiers(from: [.control, .command])
        expect(resizeModifiers == [.control, .shift, .command],
               "trackpad resizing adds shift to the chosen move chord")
        expect(WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift],
                                                   expected: resizeModifiers),
               "trackpad resizing matches its exact primary-drag chord")
        expect(!WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift, .maskAlternate],
                                                    expected: resizeModifiers),
               "unexpected extra modifiers do not trigger trackpad resizing")
        expect(WindowGestureSupport.movedOrigin(from: CGPoint(x: 100, y: 80),
                                                pointerStart: CGPoint(x: 300, y: 200),
                                                pointerNow: CGPoint(x: 345, y: 175))
               == CGPoint(x: 145, y: 55),
               "window movement follows the full pointer delta")
        let gestureFrame = CGRect(x: 100, y: 80, width: 600, height: 420)
        expect(WindowGestureSupport.resizeEdges(at: CGPoint(x: 110, y: 90), in: gestureFrame)
               == [.left, .top],
               "a top-left press resizes from both matching edges")
        expect(WindowGestureSupport.resizeEdges(at: CGPoint(x: 400, y: 90), in: gestureFrame)
               == [.top],
               "a top-center press resizes only the top edge")
        expect(!WindowGestureSupport.resizeEdges(at: CGPoint(x: 400, y: 290), in: gestureFrame).isEmpty,
               "the center region always chooses a usable nearest edge")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 110, y: 90),
                                                 pointerNow: CGPoint(x: 160, y: 120),
                                                 edges: [.left, .top])
               == CGRect(x: 150, y: 110, width: 550, height: 390),
               "top-left resizing keeps the opposite corner anchored")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 690, y: 490),
                                                 pointerNow: CGPoint(x: 760, y: 540),
                                                 edges: [.right, .bottom])
               == CGRect(x: 100, y: 80, width: 670, height: 470),
               "bottom-right resizing grows in both axes")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 100, y: 80),
                                                 pointerNow: CGPoint(x: 900, y: 700),
                                                 edges: [.left, .top])
               == CGRect(x: 580, y: 420, width: 120, height: 80),
               "gesture minimum size keeps the far corner fixed")
        expect(WindowGestureSupport.anchoredOrigin(original: gestureFrame,
                                                   requestedOrigin: CGPoint(x: 580, y: 420),
                                                   acceptedSize: CGSize(width: 260, height: 180),
                                                   edges: [.left, .top])
               == CGPoint(x: 440, y: 320),
               "an app-specific minimum size keeps the opposite corner anchored")
        expect(WindowGestureSupport.anchoredOrigin(original: gestureFrame,
                                                   requestedOrigin: gestureFrame.origin,
                                                   acceptedSize: CGSize(width: 760, height: 540),
                                                   edges: [.right, .bottom])
               == gestureFrame.origin,
               "right and bottom resizing keep the original window origin")
        expect(WindowGestureSupport.anchoredOriginIfNeeded(original: gestureFrame,
                                                           requestedOrigin: gestureFrame.origin,
                                                           acceptedSize: CGSize(width: 760, height: 540),
                                                           edges: [.right, .bottom]) == nil,
               "right and bottom resizing never adds a redundant position mutation")
        expect(WindowGestureSupport.anchoredOriginIfNeeded(original: gestureFrame,
                                                           requestedOrigin: CGPoint(x: 580, y: 420),
                                                           acceptedSize: CGSize(width: 260, height: 180),
                                                           edges: [.left, .top])
               == CGPoint(x: 440, y: 320),
               "left and top resizing reanchors only after the accepted size is known")

        // MARK: Click versus drag custody (issue #321)

        let slopOrigin = CGPoint(x: 100, y: 80)
        expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: slopOrigin),
               "a press that never moves stays a click")
        expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 106, y: 80)),
               "movement exactly at the slop still counts as a click")
        expect(WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 106.1, y: 80)),
               "movement past the slop becomes a window gesture")
        expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 94, y: 80)),
               "the slop is symmetric in both directions")
        expect(WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 105, y: 85)),
               "diagonal movement is measured as a distance, not per axis")
        expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 95, y: 77)),
               "hand jitter under the slop keeps the click")

        expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDown(sameButton: false, chordMatched: false)) == .passThrough,
               "a press without the chord is never touched")
        expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDown(sameButton: false, chordMatched: true)) == .arm,
               "a press with the chord is only held, not taken")
        expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDragged(tracked: false, pastSlop: true)) == .passThrough,
               "movement with nothing held is never touched")
        expect(WindowGestureSupport.decide(state: .idle, input: .buttonUp(tracked: false)) == .passThrough,
               "a release with nothing held is never touched")
        expect(WindowGestureSupport.decide(state: .idle,
                                           input: .tapDisabled(buttonStillDown: false)) == .passThrough,
               "an idle tap has nothing to give back when it is switched off")

        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: true, pastSlop: false)) == .hold,
               "jitter under the slop keeps the press held")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: true, pastSlop: true)) == .promote,
               "movement past the slop turns the held press into a gesture")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: false, pastSlop: true)) == .flushThenPass,
               "movement of another button gives the held press back")
        expect(WindowGestureSupport.decide(state: .pending, input: .buttonUp(tracked: true)) == .replayThenPass,
               "a release without movement gives the whole click back to the app")
        expect(WindowGestureSupport.decide(state: .pending, input: .buttonUp(tracked: false)) == .flushThenPass,
               "a release of another button gives the held press back")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: true, chordMatched: true)) == .restartAsIdle,
               "the same button pressing again replaces a held press whose release went missing")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: true, chordMatched: false)) == .restartAsIdle,
               "a stale held press is cleared even when the new press has no chord")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: false, chordMatched: true)) == .flushThenRestart,
               "a second button gives the first press back instead of eating it")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: false, chordMatched: false)) == .flushThenRestart,
               "a second button without the chord also gives the first press back")
        expect(WindowGestureSupport.decide(state: .pending, input: .otherEvent) == .flushThenPass,
               "anything unexpected gives the held press back")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .tapDisabled(buttonStillDown: true)) == .flushThenPass,
               "a tap switched off while the button is still down gives the click back")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .tapDisabled(buttonStillDown: false)) == .dropState,
               "a press whose release already reached the app is never handed back pressed")
        expect(WindowGestureSupport.decide(state: .pending, input: .accessibilityLost) == .flushThenPass,
               "losing Accessibility mid press still gives the click back")

        expect(WindowGestureSupport.decide(state: .active,
                                           input: .buttonDragged(tracked: true, pastSlop: false)) == .applyMove,
               "a running gesture keeps following the pointer")
        expect(WindowGestureSupport.decide(state: .active, input: .buttonUp(tracked: true)) == .applyFinish,
               "releasing ends a running gesture")
        expect(WindowGestureSupport.decide(state: .active, input: .buttonUp(tracked: false)) == .passThrough,
               "another button is never swallowed by a running gesture")
        expect(WindowGestureSupport.decide(state: .active, input: .otherEvent) == .passThrough,
               "a running gesture never swallows unrelated events")
        expect(WindowGestureSupport.decide(state: .active,
                                           input: .tapDisabled(buttonStillDown: true)) == .dropState,
               "a gesture that already took the press has nothing to give back")
        expect(WindowGestureSupport.decide(state: .active, input: .accessibilityLost) == .dropState,
               "losing Accessibility mid gesture drops it without a phantom click")

        // No path may invent a release, and every held press is given back
        // exactly once: only these decisions replay, and none of them can be
        // reached twice for the same press.
        let allInputs: [WindowGestureInput] = [
            .buttonDown(sameButton: true, chordMatched: true),
            .buttonDown(sameButton: true, chordMatched: false),
            .buttonDown(sameButton: false, chordMatched: true),
            .buttonDown(sameButton: false, chordMatched: false),
            .buttonDragged(tracked: true, pastSlop: true),
            .buttonDragged(tracked: true, pastSlop: false),
            .buttonDragged(tracked: false, pastSlop: true),
            .buttonDragged(tracked: false, pastSlop: false),
            .buttonUp(tracked: true), .buttonUp(tracked: false),
            .otherEvent, .tapDisabled(buttonStillDown: true),
            .tapDisabled(buttonStillDown: false), .accessibilityLost,
        ]
        var pendingExits = 0
        var pendingReplays = 0
        for input in allInputs {
            let decision = WindowGestureSupport.decide(state: .pending, input: input)
            if decision != .hold {
                pendingExits += 1
                if decision == .replayThenPass || decision == .flushThenPass
                    || decision == .flushThenRestart { pendingReplays += 1 }
            }
            let replaying: [WindowGestureDecision] = [.replayThenPass, .flushThenPass, .flushThenRestart]
            expect(!replaying.contains(WindowGestureSupport.decide(state: .idle, input: input)),
                   "nothing is ever replayed while no press is held")
            expect(!replaying.contains(WindowGestureSupport.decide(state: .active, input: input)),
                   "a press already spent on a gesture is never replayed")
        }
        expect(pendingExits == 13 && pendingReplays == 9,
               "every way out of a held press either promotes it, replaces it or gives it back")

        // MARK: Directional pointer layout

        let dirOrigin = CGPoint(x: 200, y: 200)
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: dirOrigin) == nil,
               "stationary pointer does not trigger directional layout")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 220, y: 200)) == nil,
               "pointer movement below activation distance produces no action")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 200)) == .rightHalf,
               "moving right triggers right half")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 350, y: 200)) == .rightHalf,
               "fast long flick right triggers right half reliably")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 200)) == .leftHalf,
               "moving left triggers left half")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 240)) == .topHalf,
               "moving up triggers top half")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 350)) == .topHalf,
               "fast long flick up triggers top half reliably")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 160)) == .bottomHalf,
               "moving down triggers bottom half")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 50)) == .bottomHalf,
               "fast long flick down triggers bottom half without accidental minimize")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 240)) == .topRight,
               "moving up-right triggers top right")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 240)) == .topLeft,
               "moving up-left triggers top left")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 160)) == .bottomRight,
               "moving down-right triggers bottom right")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 160)) == .bottomLeft,
               "moving down-left triggers bottom left")
    }
}
