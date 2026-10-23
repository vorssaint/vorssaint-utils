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
        WindowDirectionalModifierRuntimeTests.run(suite)
        WindowEdgeSnapRuntimeTests.run(suite)
        WindowGestureApplyRuntimeTests.run(suite)
        let modifierTrigger = WindowDirectionalTrigger(storageValue: "modifiers:control+command")
        suite.expect(modifierTrigger?.displayString == "⌃⌘"
                && modifierTrigger?.storageValue == "modifiers:control+command",
                     "pointer layout reloads a modifier-only trigger without inventing a key")

        for first: GlobalShortcutModifiers in [.control, .command] {
            for remaining: GlobalShortcutModifiers in [.control, .command] {
                var recording = ModifierShortcutRecording()
                suite.expect(recording.flagsChanged(first) == nil
                    && recording.flagsChanged([.control, .command]) == nil
                    && recording.flagsChanged(remaining) == nil
                    && recording.flagsChanged([]) == [.control, .command],
                    "modifier recorder captures the held chord after either press/release order")
            }
        }
        for first: GlobalShortcutModifiers in [.control, .command] {
            for remaining: GlobalShortcutModifiers in [.control, .command] {
                var hold = WindowDirectionalModifierHold(expected: [.control, .command])
                suite.expect(hold.update(first) == .none
                    && hold.update([.control, .command]) == .begin
                    && hold.update([.control, .command]) == .none
                    && hold.update(remaining) == .finish
                    && hold.update([]) == .none,
                    "modifier pointer layout begins once and finishes on either required-key release")
            }
        }
        for shortcut in [GlobalShortcut.windowDirectionalDefault,
                         GlobalShortcut(keyCode: Int64(kVK_F1), modifiers: [])] {
            let trigger = WindowDirectionalTrigger(storageValue: shortcut.storageValue)
            suite.expect(trigger == .key(shortcut) && trigger?.storageValue == shortcut.storageValue,
                         "pointer layout keeps existing key-based shortcut storage")
        }
        for value in ["modifiers:", "modifiers:shift", "modifiers:control",
                      "modifiers:shift+command", "modifiers:fn", "modifiers:control+",
                      "modifiers:control+unknown"] {
            suite.expect(WindowDirectionalTrigger(storageValue: value) == nil,
                         "invalid modifier trigger is rejected: \(value)")
        }
        let shiftedOption: GlobalShortcutModifiers = [.shift, .option]
        let controlCommand: GlobalShortcutModifiers = [.control, .command]
        let shiftedOptionCommand: GlobalShortcutModifiers = [.shift, .option, .command]
        suite.expect(!GlobalShortcutModifiers.command.isValidWindowDirectionalTrigger
                && !shiftedOption.isValidWindowDirectionalTrigger
                && controlCommand.isValidWindowDirectionalTrigger
                && shiftedOptionCommand.isValidWindowDirectionalTrigger,
            "modifier-only pointer layout requires two primary modifiers")
        suite.expect(GlobalShortcut(storageValue: "modifiers:control+command") == nil,
                     "ordinary global shortcuts do not accept modifier-only triggers")
        var interruptedRecording = ModifierShortcutRecording()
        _ = interruptedRecording.flagsChanged([.control, .command])
        interruptedRecording.keyPressed()
        suite.expect(interruptedRecording.flagsChanged(.command) == nil
            && interruptedRecording.flagsChanged([]) == nil,
            "releasing modifiers after a key never overwrites the recorded key or saves an invalid attempt")
        _ = interruptedRecording.flagsChanged([.control, .command])
        suite.expect(interruptedRecording.flagsChanged([]) == [.control, .command],
                     "a fresh modifier chord can be recorded after an invalid key attempt")
        var fnRecording = ModifierShortcutRecording()
        _ = fnRecording.flagsChanged([.control, .command], hasUnsupportedModifier: true)
        suite.expect(fnRecording.flagsChanged([.control, .command]) == nil
            && fnRecording.flagsChanged([]) == nil,
            "an unsupported Fn chord never saves just its supported modifiers")
        var changingRecording = ModifierShortcutRecording()
        _ = changingRecording.flagsChanged([.control, .command])
        _ = changingRecording.flagsChanged(.command)
        _ = changingRecording.flagsChanged([.option, .command])
        suite.expect(changingRecording.flagsChanged([]) == [.control, .command],
                     "recording never combines modifiers that were not held together")
        var cancelledHold = WindowDirectionalModifierHold(expected: [.control, .command])
        _ = cancelledHold.update([.control, .command])
        cancelledHold.cancel()
        suite.expect(cancelledHold.update(.command) == .none
            && cancelledHold.update([.control, .command]) == .none
            && cancelledHold.update([]) == .none
            && cancelledHold.update([.control, .command]) == .begin,
            "cancellation waits for a fresh chord and never finishes a cancelled placement")
        var extraModifierHold = WindowDirectionalModifierHold(expected: [.control, .command])
        _ = extraModifierHold.update([.control, .command])
        suite.expect(extraModifierHold.update([.control, .command, .shift]) == .cancel
            && extraModifierHold.update([.control, .command]) == .none
            && extraModifierHold.update([]) == .none
            && extraModifierHold.update([.control, .command]) == .begin,
            "extra modifiers cancel pointer layout until the chord is released")
        var releasedExtraHold = WindowDirectionalModifierHold(expected: [.control, .command])
        suite.expect(releasedExtraHold.update([.control, .option]) == .cancel
            && releasedExtraHold.update(.control) == .none
            && releasedExtraHold.update([.control, .command]) == .none
            && releasedExtraHold.update([]) == .none
            && releasedExtraHold.update([.control, .command]) == .begin,
            "releasing an extra modifier cannot turn the same physical hold into a trigger")
        var initiallyHeld = WindowDirectionalModifierHold(expected: [.control, .command],
                                                          initiallyHeld: [.control, .command])
        suite.expect(initiallyHeld.update([.control, .command]) == .none
            && initiallyHeld.update(.command) == .none
            && initiallyHeld.update([]) == .none
            && initiallyHeld.update([.control, .command]) == .begin,
            "enabling or resuming pointer layout does not activate an already-held chord")
        var releasedHold = WindowDirectionalModifierHold(expected: [.control, .command])
        _ = releasedHold.update([.control, .command])
        suite.expect(releasedHold.update(.command) == .finish
            && releasedHold.update([.control, .command]) == .none
            && releasedHold.update([]) == .none
            && releasedHold.update([.control, .command]) == .begin,
            "a finished gesture needs a fresh chord before starting again")

        var pendingShortcutHold = WindowDirectionalModifierHold(expected: [.control, .command])
        let pendingBegin = pendingShortcutHold.update([.control, .command])
        let pendingGeneration = pendingShortcutHold.generation
        suite.expect(pendingBegin == .begin
            && pendingShortcutHold.cancelForKeyPress()
            && pendingShortcutHold.generation != pendingGeneration
            && pendingShortcutHold.update(.command) == .none
            && pendingShortcutHold.update([]) == .none,
            "a normal shortcut invalidates a deferred modifier start before release can place a window")
        var partialShortcutHold = WindowDirectionalModifierHold(expected: [.control, .command])
        _ = partialShortcutHold.update(.control)
        suite.expect(partialShortcutHold.cancelForKeyPress()
            && partialShortcutHold.update([.control, .command]) == .none
            && partialShortcutHold.update([]) == .none
            && partialShortcutHold.update([.control, .command]) == .begin,
            "a key press during a partial chord blocks activation until every modifier is released")
        pendingShortcutHold = WindowDirectionalModifierCancellation.preserveHold.applied(
            to: pendingShortcutHold)
        suite.expect(pendingShortcutHold.update([.control, .command]) == .begin,
            "late session cleanup preserves completed releases so the next fresh chord starts")

        let observedTypes: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .leftMouseUp,
                                            .rightMouseDown, .rightMouseUp, .otherMouseDown,
                                            .otherMouseUp, .scrollWheel]
        let passiveMask = WindowDirectionalModifierTapSupport.eventMask
        suite.expect(WindowDirectionalModifierTapSupport.options == .listenOnly
                && passiveMask.nonzeroBitCount == observedTypes.count
                && observedTypes.allSatisfy { passiveMask & (CGEventMask(1) << $0.rawValue) != 0 },
            "idle modifier observation retains ordered cancellation without filtering input or observing movement")
        suite.expect(!WindowDirectionalModifierInputPolicy.canBegin(
                mouseButtonPressed: true, pointerInputSinceArm: false)
                && !WindowDirectionalModifierInputPolicy.canBegin(
                    mouseButtonPressed: false, pointerInputSinceArm: true)
                && WindowDirectionalModifierInputPolicy.canBegin(
                    mouseButtonPressed: false, pointerInputSinceArm: false),
            "a modifier trigger never begins after an app-owned mouse press, click or scroll")
        for type in [CGEventType.scrollWheel, .leftMouseDown, .rightMouseDown,
                     .otherMouseDown, .keyDown] {
            suite.expect(WindowDirectionalModifierInputPolicy.cancelsAndPassesThrough(type),
                "modifier trigger cancels and passes through native input type \(type.rawValue)")
        }
        suite.expect(!WindowDirectionalModifierInputPolicy.cancelsAndPassesThrough(.mouseMoved)
                && !WindowDirectionalModifierInputPolicy.cancelsAndPassesThrough(.flagsChanged),
            "pointer aiming and modifier releases remain part of the layout gesture")
        let pointerSnapshot = WindowDirectionalModifierPointerSnapshot(
            leftMouseDown: 1, rightMouseDown: 2, otherMouseDown: 3, scrollWheel: 4)
        suite.expect(!pointerSnapshot.hasPointerInput(since: pointerSnapshot)
                && WindowDirectionalModifierPointerSnapshot(
                    leftMouseDown: 1, rightMouseDown: 2, otherMouseDown: 3, scrollWheel: 5
                ).hasPointerInput(since: pointerSnapshot),
            "pointer counters invalidate a deferred modifier start after quick input completes")
        var startupSnapshot = pointerSnapshot
        var startupOrder: [String] = []
        let interruptedStartup = WindowDirectionalModifierStartupGuard.resolve(
            armedAt: pointerSnapshot,
            currentSnapshot: { startupSnapshot },
            mouseButtonPressed: { false },
            startObserving: {
                startupOrder.append("observe")
                return true
            },
            lookupTarget: {
                startupOrder.append("lookup")
                startupSnapshot = WindowDirectionalModifierPointerSnapshot(
                    leftMouseDown: 2, rightMouseDown: 2,
                    otherMouseDown: 3, scrollWheel: 4)
                return "target"
            })
        let cancelledDuringLookup: Bool
        if case .cancelled = interruptedStartup { cancelledDuringLookup = true }
        else { cancelledDuringLookup = false }
        suite.expect(cancelledDuringLookup
                && startupOrder == ["observe", "lookup"]
                && WindowDirectionalModifierInputPolicy.cancelsAndPassesThrough(.leftMouseDown),
            "pointer input during deferred target lookup cancels startup and remains pass-through")
        startupSnapshot = pointerSnapshot
        let uninterruptedStartup = WindowDirectionalModifierStartupGuard.resolve(
            armedAt: pointerSnapshot,
            currentSnapshot: { startupSnapshot },
            mouseButtonPressed: { false },
            startObserving: { true },
            lookupTarget: { "target" })
        let resolvedStartup: Bool
        if case .ready("target") = uninterruptedStartup { resolvedStartup = true }
        else { resolvedStartup = false }
        suite.expect(resolvedStartup,
            "deferred modifier startup proceeds when pointer custody stays unchanged")
        let deferredModifierWork = DispatchSemaphore(value: 0)
        WindowDirectionalModifierTapSupport.afterCallback { deferredModifierWork.signal() }
        let modifierWorkWasDeferred = deferredModifierWork.wait(timeout: .now()) == .timedOut
        let modifierWorkDeadline = Date().addingTimeInterval(0.2)
        var modifierWorkRan = false
        while !modifierWorkRan, Date() < modifierWorkDeadline {
            RunLoop.current.run(until: min(modifierWorkDeadline, Date().addingTimeInterval(0.005)))
            modifierWorkRan = deferredModifierWork.wait(timeout: .now()) == .success
        }
        suite.expect(modifierWorkWasDeferred && modifierWorkRan,
            "modifier target lookup and placement begin only after the input callback returns")
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
        // A strip that borrowed another placement's glyph would show two
        // different places as the same picture wherever the actions are listed.
        for (action, _, _) in verticalLayouts {
            suite.expect(WindowLayoutAction.allCases.allSatisfy { $0 == action || $0.symbolName != action.symbolName },
                   "\(action.rawValue) draws a glyph no other placement uses")
        }
        for language in AppLanguage.allCases {
            let layoutStrings = FeatureStrings.windowLayout(language)
            suite.expect(!layoutStrings.fullScreen.isEmpty && !layoutStrings.previousDisplay.isEmpty
                    && !layoutStrings.marginMaximize.isEmpty
                    && !layoutStrings.marginPerEdge.isEmpty
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
                            WindowEdgeSnapZone.allEnabled,
                        layout: WindowEdgeSnapLayout = .standard) -> WindowEdgeSnapTarget? {
            WindowEdgeSnapSupport.target(at: point,
                                         screens: screens,
                                         enabledZones: enabledZones,
                                         layout: layout)
        }
        let topSnapFrame = WindowLayoutGeometry.rect(for: .maximize,
                                                     current: snapVisibleFrame,
                                                     visibleFrame: snapVisibleFrame)
        suite.expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY))
               == WindowEdgeSnapTarget(zone: .top,
                                       action: .maximize,
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

        // MARK: Placements chosen for the drop areas

        suite.expect(WindowEdgeSnapLayout(storageValue: "") == .standard
               && WindowEdgeSnapLayout(storageValue: nil) == .standard
               && WindowEdgeSnapZone.allCases.allSatisfy {
                   WindowEdgeSnapLayout.standard.actions(for: $0) == [$0.defaultAction]
               },
               "with nothing chosen every drop area keeps the placement it always had")
        var chosen = WindowEdgeSnapLayout.standard
        chosen.setAction(.topHalf, for: .top, part: 0)
        chosen.setAction(.rightThird, for: .right, part: 0)
        suite.expect(chosen.storageValue == "top=topHalf,right=rightThird"
               && WindowEdgeSnapLayout(storageValue: chosen.storageValue) == chosen,
               "a chosen placement is saved under its area's name and read back the same")
        let snapTop = snapVisibleFrame.maxY
        suite.expect(snapTarget(CGPoint(x: 720, y: snapTop), layout: chosen)
               == WindowEdgeSnapTarget(zone: .top,
                                       action: .topHalf,
                                       frame: WindowLayoutGeometry.rect(for: .topHalf,
                                                                        current: snapVisibleFrame,
                                                                        visibleFrame: snapVisibleFrame),
                                       visibleFrame: snapVisibleFrame)
               && snapTarget(CGPoint(x: 1440, y: 450), layout: chosen)?.action == .rightThird
               && snapTarget(CGPoint(x: 0, y: 450), layout: chosen)?.action == .leftHalf,
               "an area previews the placement chosen for it while the others keep theirs")
        suite.expect(snapTarget(CGPoint(x: 720, y: snapTop), enabledZones: withoutTop, layout: chosen) == nil,
               "an area that is off stays off whatever placement it holds")
        chosen.setAction(.maximize, for: .top, part: 0)
        suite.expect(chosen.storageValue == "right=rightThird",
               "choosing an area's default again leaves nothing saved for it")

        let saved = WindowEdgeSnapLayout(storageValue: [
            "top=fullScreen", " left = leftThird ", "topLeft=topLeft+topRight", "bottom=leftThird+",
            "right=nextDisplay", "unknown=leftHalf", "bottomRight=center", "topRight=futurePlacement",
            "bottomLeft=bottomLeftSixth",
        ].joined(separator: ","))
        suite.expect(saved.actions(for: .top) == [.maximize]
               && saved.actions(for: .left) == [.leftThird]
               && saved.actions(for: .topLeft) == [.topLeft]
               && saved.actions(for: .bottom) == [.bottomHalf]
               && saved.actions(for: .right) == [.rightHalf]
               && saved.actions(for: .bottomRight) == [.bottomRight]
               && saved.actions(for: .topRight) == [.topRight]
               && saved.actions(for: .bottomLeft) == [.bottomLeftSixth],
               "a saved area with an unknown placement, one a drop cannot preview or more than one area in a corner keeps its default, and the valid ones still apply")
        let fiveAreas = "top=" + [WindowLayoutAction.leftQuarter, .leftMiddleQuarter, .rightMiddleQuarter,
                                  .rightQuarter, .maximize].map(\.rawValue).joined(separator: "+")
        suite.expect(WindowEdgeSnapLayout(storageValue: fiveAreas) == .standard,
               "an edge saved with more than four areas keeps its default")

        var split = WindowEdgeSnapLayout.standard
        split.setPartCount(3, for: .top)
        split.setPartCount(2, for: .left)
        suite.expect(split.actions(for: .top) == [.leftThird, .centerThird, .rightThird]
               && split.actions(for: .left) == [.topHalf, .bottomHalf]
               && split.storageValue == "top=leftThird+centerThird+rightThird,left=topHalf+bottomHalf",
               "a split edge starts with the screen's columns along the top and its rows along a side")
        // The 1440 pt test screen keeps 180 pt corners, so the 1080 pt between
        // them makes three 360 pt areas.
        suite.expect(snapTarget(CGPoint(x: 181, y: snapTop), layout: split)?.action == .leftThird
               && snapTarget(CGPoint(x: 539, y: snapTop), layout: split)?.action == .leftThird
               && snapTarget(CGPoint(x: 541, y: snapTop), layout: split)?.action == .centerThird
               && snapTarget(CGPoint(x: 899, y: snapTop), layout: split)?.action == .centerThird
               && snapTarget(CGPoint(x: 901, y: snapTop), layout: split)?.action == .rightThird
               && snapTarget(CGPoint(x: 1259, y: snapTop), layout: split)?.action == .rightThird,
               "a split top edge shares its length between the corners equally, from left to right")
        suite.expect(snapTarget(CGPoint(x: 100, y: snapTop), layout: split)?.action == .topLeft
               && snapTarget(CGPoint(x: 1340, y: snapTop), layout: split)?.action == .topRight,
               "the corners beside a split edge keep their own placements")
        suite.expect(snapTarget(CGPoint(x: 0, y: 700), layout: split)?.action == .topHalf
               && snapTarget(CGPoint(x: 0, y: 200), layout: split)?.frame
                   == WindowLayoutGeometry.rect(for: .bottomHalf,
                                                current: snapVisibleFrame,
                                                visibleFrame: snapVisibleFrame),
               "a split side stacks its areas from top to bottom and previews each one's placement")
        split.setAction(.maximize, for: .top, part: 1)
        split.setAction(.leftHalf, for: .top, part: 3)
        suite.expect(split.actions(for: .top) == [.leftThird, .maximize, .rightThird]
               && snapTarget(CGPoint(x: 720, y: snapTop), layout: split)?.action == .maximize,
               "each area of a split edge takes its own placement, and an area that does not exist is ignored")
        split.setPartCount(1, for: .top)
        split.setPartCount(5, for: .left)
        split.setPartCount(2, for: .topLeft)
        suite.expect(split.actions(for: .top) == [.maximize]
               && split.actions(for: .left) == [.topHalf, .bottomHalf]
               && split.actions(for: .topLeft) == [.topLeft]
               && split.storageValue == "left=topHalf+bottomHalf",
               "one area brings an edge back to its default, and a corner or more than four areas never splits")
        var kept = WindowEdgeSnapLayout(storageValue: "top=topHalf,left=leftThird+leftTwoThirds")
        kept.setPartCount(1, for: .top)
        kept.setPartCount(2, for: .left)
        suite.expect(kept.storageValue == "top=topHalf,left=leftThird+leftTwoThirds",
               "picking the number of areas an edge already has keeps the placements chosen for them")

        let offered = WindowEdgeSnapPlacementGroup.allCases.flatMap(\.actions)
        let pictures = offered.map(WindowEdgeSnapLayout.previewRect(for:))
        let screenBounds = CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.001, dy: -0.001)
        suite.expect(Set(offered).count == offered.count
               && pictures.indices.allSatisfy { first in
                   pictures.indices.allSatisfy { first == $0 || pictures[first] != pictures[$0] }
               }
               && pictures.allSatisfy { screenBounds.contains($0) },
               "every placement an area offers draws its own picture on the map, inside the screen")
        suite.expect(WindowEdgeSnapLayout.previewRect(for: .topHalf) == CGRect(x: 0, y: 0, width: 1, height: 0.5)
               && WindowEdgeSnapLayout.previewRect(for: .bottomRight)
                   == CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
               "the map draws a placement from the top left, the way the screen shows it")

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
                          screens: [snapScreen, rightSnapScreen])
               == WindowEdgeSnapTarget(zone: .left,
                                       action: .leftHalf,
                                       frame: CGRect(x: 1440, y: 40, width: 960, height: 1040),
                                       visibleFrame: rightSnapScreen.visibleFrame),
               "the first column of a display is its left half, even against a neighbor")
        suite.expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 1415, y: 450),
                                            screens: [snapScreen, rightSnapScreen],
                                            distance: 30)
               == WindowEdgeSnapTarget(zone: .right,
                                       action: .rightHalf,
                                       frame: CGRect(x: 720, y: 40, width: 720, height: 835),
                                       visibleFrame: snapVisibleFrame),
               "a pointer slowed at a shared seam previews the half of the display it is still on")
        suite.expect(snapTarget(CGPoint(x: 1440, y: 1000),
                          screens: [snapScreen, rightSnapScreen])?.action == .topLeft,
               "the corners of a shared seam keep their two-axis placements")
        let seamPoint = CGPoint(x: 1435, y: 450)
        let seamScreens = [snapScreen, rightSnapScreen]
        let fast = WindowEdgeSnapSupport.crossingSpeed * 3
        suite.expect(WindowEdgeSnapSupport.target(at: seamPoint, screens: seamScreens,
                                                  velocity: CGVector(dx: fast, dy: 0)) == nil
                && WindowEdgeSnapSupport.target(at: seamPoint, screens: seamScreens,
                                                velocity: CGVector(dx: -fast, dy: 0)) == nil,
               "a pointer passing through a shared seam at speed, either way, is not caught")
        suite.expect(WindowEdgeSnapSupport.target(at: seamPoint, screens: seamScreens,
                                                  velocity: CGVector(dx: 0, dy: fast))?.action == .rightHalf,
               "sliding fast along a seam keeps its preview, so a corner stays one slide away")
        suite.expect(WindowEdgeSnapSupport.target(
                   at: seamPoint, screens: seamScreens,
                   velocity: CGVector(dx: WindowEdgeSnapSupport.crossingSpeed, dy: 0))?.action == .rightHalf,
               "a pointer slowed to the crossing speed counts as aiming")
        suite.expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 1440, y: 450), screens: [snapScreen],
                                                  velocity: CGVector(dx: fast, dy: 0))?.action == .rightHalf
                && WindowEdgeSnapSupport.target(at: CGPoint(x: 0, y: 450), screens: seamScreens,
                                                velocity: CGVector(dx: -fast, dy: 0))?.action == .leftHalf,
               "an edge with no display beyond it snaps at any speed, so a window flung at it and let go still tiles")
        let shortRightScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: 1440, y: 0, width: 1280, height: 600),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1280, height: 600)
        )
        suite.expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 1440, y: 700),
                                                  screens: [snapScreen, shortRightScreen],
                                                  velocity: CGVector(dx: fast, dy: 0))?.action == .rightHalf
                && WindowEdgeSnapSupport.target(at: CGPoint(x: 1435, y: 450),
                                                screens: [snapScreen, shortRightScreen],
                                                velocity: CGVector(dx: fast, dy: 0)) == nil,
               "beside a shorter display, only the stretch of the edge it reaches waits for the pointer to slow")
        let upperSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: 0, y: 900, width: 1280, height: 800),
            visibleFrame: CGRect(x: 0, y: 900, width: 1280, height: 775)
        )
        suite.expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY),
                          screens: [snapScreen, upperSnapScreen])?.action == .maximize,
               "a menu bar below another display still previews maximize")
        let stackedSeam = snapTarget(CGPoint(x: 720, y: 900), screens: [snapScreen, upperSnapScreen])
        suite.expect(stackedSeam?.visibleFrame == snapVisibleFrame && stackedSeam?.action == .maximize,
               "the top row of a lower display is its own, as the pointer sees it, so it maximizes there")
        suite.expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 720, y: 905),
                                                  screens: [snapScreen, upperSnapScreen],
                                                  velocity: CGVector(dx: 0, dy: fast)) == nil,
               "a pointer passing up through a stacked seam at speed is not caught")
        let menuBarPoint = CGPoint(x: 720, y: snapVisibleFrame.maxY)
        suite.expect(WindowEdgeSnapSupport.target(at: menuBarPoint, screens: [snapScreen],
                                                  velocity: CGVector(dx: 0, dy: fast))?.action == .maximize
                && WindowEdgeSnapSupport.target(at: menuBarPoint, screens: [snapScreen, upperSnapScreen],
                                                velocity: CGVector(dx: 0, dy: fast)) == nil,
               "the menu bar maximizes at any speed with nothing above it, and waits for the pointer to slow below another display")

        var trail = WindowEdgeSnapPointerTrail()
        for step in 0...10 {
            trail.append(CGPoint(x: CGFloat(step) * 10, y: 0), at: TimeInterval(step) * 0.01)
        }
        let steady = trail.velocity(at: 0.1)
        suite.expect(abs(steady.dx - 1000) < 1 && steady.dy == 0,
                     "a pointer moving steadily reads its speed over the recent path")
        suite.expect(trail.velocity(at: 0.1 + WindowEdgeSnapPointerTrail.stillAfter + 0.01) == .zero,
                     "a pointer with no event for a moment reads as stopped")
        var nudged = trail
        nudged.append(CGPoint(x: 101, y: 0), at: 0.5)
        suite.expect(abs(nudged.velocity(at: 0.5).dx) <= WindowEdgeSnapSupport.crossingSpeed,
                     "a 1 pt nudge after resting, such as the button coming up, still reads as settled")
        var flicked = trail
        flicked.append(CGPoint(x: 130, y: 0), at: 0.5)
        suite.expect(flicked.velocity(at: 0.5).dx > WindowEdgeSnapSupport.crossingSpeed,
                     "a flick out of a rest reads fast from its first event")
        var polled = WindowEdgeSnapPointerTrail()
        polled.append(.zero, at: 1)
        polled.append(CGPoint(x: 1, y: 0), at: 1.001)
        suite.expect(abs(polled.velocity(at: 1.001).dx) <= WindowEdgeSnapSupport.crossingSpeed,
                     "a mouse polling every millisecond does not turn a 1 pt step into a crossing")
        var frozen = WindowEdgeSnapPointerTrail()
        frozen.append(CGPoint(x: 1000, y: 0), at: 2)
        for _ in 0..<WindowEdgeSnapPointerTrail.capacity {
            frozen.append(.zero, at: 2)
        }
        suite.expect(frozen.velocity(at: 2) == .zero && frozen.lastTime == 2,
                     "a trail whose events never move on in time keeps only its newest samples")
        suite.expect(WindowEdgeSnapSupport.systemTilingEnabled { _ in nil },
               "unwritten system tiling choices keep their enabled default")
        suite.expect(!WindowEdgeSnapSupport.systemTilingEnabled { _ in false },
               "edge snapping can start after every conflicting system choice is off")
        suite.expect(WindowEdgeSnapSupport.systemTilingEnabled {
                   $0 == "EnableTilingByEdgeDrag" ? true : false
               },
               "one enabled system edge gesture is enough to prevent competing previews")
        suite.expect(!WindowEdgeSnapSupport.systemTilingEnabled(
                   valueFor: { _ in nil }, displaysSpan: true)
                && !WindowEdgeSnapSupport.systemTilingEnabled(
                   valueFor: { _ in true }, displaysSpan: true)
                && !WindowEdgeSnapSupport.systemTilingEnabled(
                   valueFor: { $0 == "EnableTilingByEdgeDrag" ? true : nil },
                   displaysSpan: true),
               "spanning displays make system tiling inert with missing or enabled keys")
        suite.expect(WindowEdgeSnapSupport.systemTilingEnabled(
                   valueFor: { _ in true }, displaysSpan: false),
               "separate Spaces still honor a written system tiling switch")
        suite.expect(!WindowEdgeSnapSupport.displaysSpan(nil)
                && !WindowEdgeSnapSupport.displaysSpan(false)
                && WindowEdgeSnapSupport.displaysSpan(true),
               "an unwritten spans-displays preference keeps Apple's Separate Spaces default")

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
        suite.expect(WindowMaximizerSupport.maximizeTarget(visibleFrame: visibleFrame, screenGap: 0)
               == visibleFrame,
               "green-button maximize keeps the visible frame when Screen gap is off")
        suite.expect(WindowMaximizerSupport.maximizeTarget(visibleFrame: visibleFrame, screenGap: 32)
               == CGRect(x: 32, y: 72, width: 1376, height: 796),
               "green-button maximize applies the shared Screen gap on all four edges")
        suite.expect(WindowMaximizerSupport.maximizeTarget(
            visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 100), screenGap: 128)
               == CGRect(x: 10, y: 10, width: 80, height: 80),
               "green-button maximize shares the oversized-gap safe minimum")
        let gapTarget = WindowMaximizerSupport.maximizeTarget(visibleFrame: visibleFrame, screenGap: 32)
        let twoPointOvershoot = CGSize(width: gapTarget.width + 2, height: gapTarget.height)
        let recoveryOrigin = WindowMaximizerSupport.approachOrigin(for: gapTarget.origin, tolerance: 4)
        suite.expect(WindowMaximizerSupport.overshoots(twoPointOvershoot, target: gapTarget.size)
                && !WindowMaximizerSupport.overshoots(twoPointOvershoot, target: visibleFrame.size)
                && recoveryOrigin == CGPoint(x: gapTarget.minX - 4, y: gapTarget.minY - 4),
               "Dock recovery measures and approaches the Screen-gap target rather than the full visible frame")

        let toggleTarget32 = WindowMaximizerSupport.maximizeTarget(visibleFrame: visibleFrame, screenGap: 32)
        let toggleTarget64 = WindowMaximizerSupport.maximizeTarget(visibleFrame: visibleFrame, screenGap: 64)
        for original in [CGRect(x: 100, y: 100, width: 320, height: 80),
                         CGRect(x: 100, y: 100, width: 80, height: 320),
                         CGRect(x: 100, y: 100, width: 320, height: 60),
                         CGRect(x: -1600, y: -100, width: 640, height: 480)] {
            var toggleState = WindowMaximizerFrameState<CGRect>()
            suite.expect(WindowMaximizerSupport.toggleAction(
                current: original, maximized: toggleTarget32, original: nil, tolerance: 0)
                    == .maximize(toggleTarget32),
                "the production toggle first maximizes a valid original, including a small or negative-origin frame")
            let firstToggle = toggleState.beginMaximize(current: original, target: toggleTarget32, isClose: ==)
            _ = toggleState.complete(firstToggle, success: true)
            suite.expect(WindowMaximizerSupport.toggleAction(
                current: toggleTarget32, maximized: toggleTarget32,
                original: toggleState.original, tolerance: 0) == .restore(original),
                "the production toggle restores the exact original even when a dimension is 80pt or less")
            suite.expect(WindowMaximizerSupport.toggleAction(
                current: toggleTarget32, maximized: toggleTarget64,
                original: toggleState.original, tolerance: 0) == .maximize(toggleTarget64),
                "a changed Screen gap selects the new maximize target before restoring")
            let changedToggle = toggleState.beginMaximize(current: toggleTarget32,
                                                          target: toggleTarget64, isClose: ==)
            _ = toggleState.complete(changedToggle, success: true)
            suite.expect(WindowMaximizerSupport.toggleAction(
                current: toggleTarget64, maximized: toggleTarget64,
                original: toggleState.original, tolerance: 0) == .restore(original),
                "maximize, live gap change and the next toggle preserve the exact small original")
            let failedToggle = toggleState.beginRestore()
            _ = toggleState.complete(failedToggle, success: false)
            suite.expect(WindowMaximizerSupport.toggleAction(
                current: toggleTarget64, maximized: toggleTarget64,
                original: toggleState.original, tolerance: 0) == .restore(original),
                "a failed small-frame restore keeps the exact target for the next toggle")
            let completedToggle = toggleState.beginRestore()
            suite.expect(toggleState.complete(completedToggle, success: true) && toggleState.isEmpty,
                "a successful small-frame restore clears the completed state")
        }
        let manuallyMovedSmallFrame = CGRect(x: -1200, y: 50, width: 320, height: 60)
        var movedToggleState = WindowMaximizerFrameState<CGRect>()
        let beforeMoveToggle = movedToggleState.beginMaximize(
            current: CGRect(x: 100, y: 100, width: 600, height: 400), target: toggleTarget32, isClose: ==)
        _ = movedToggleState.complete(beforeMoveToggle, success: true)
        suite.expect(WindowMaximizerSupport.toggleAction(
            current: manuallyMovedSmallFrame, maximized: toggleTarget64,
            original: movedToggleState.original, tolerance: 0) == .maximize(toggleTarget64),
            "a deliberate move selects maximize instead of prematurely restoring an older frame")
        let afterMoveToggle = movedToggleState.beginMaximize(
            current: manuallyMovedSmallFrame, target: toggleTarget64, isClose: ==)
        _ = movedToggleState.complete(afterMoveToggle, success: true)
        suite.expect(WindowMaximizerSupport.toggleAction(
            current: toggleTarget64, maximized: toggleTarget64,
            original: movedToggleState.original, tolerance: 0) == .restore(manuallyMovedSmallFrame),
            "a deliberately moved small window becomes the exact restore target")
        for invalidFrame in [CGRect.zero,
                             CGRect(x: 0, y: 0, width: 0, height: 80),
                             CGRect(x: 0, y: 0, width: -1, height: 80),
                             CGRect(x: CGFloat.nan, y: 0, width: 80, height: 80),
                             CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 80),
                             CGRect(x: 0, y: 0, width: 80, height: CGFloat.nan)] {
            suite.expect(WindowMaximizerSupport.toggleAction(
                current: invalidFrame, maximized: toggleTarget32, original: nil, tolerance: 0) == nil
                    && WindowMaximizerSupport.toggleAction(
                        current: toggleTarget32, maximized: invalidFrame, original: nil, tolerance: 0) == nil,
                "the production toggle never selects an empty, negative or nonfinite current/maximize frame")
            suite.expect(WindowMaximizerSupport.toggleAction(
                current: toggleTarget32, maximized: toggleTarget32,
                original: invalidFrame, tolerance: 0) == .maximize(toggleTarget32),
                "an invalid remembered frame never becomes an AX restore target")
        }

        let maximizerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/WindowMaximizer.swift", encoding: .utf8)) ?? ""
        let maximizerCode = maximizerSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(maximizerCode.contains("WindowMaximizerSupport.overshoots(actual.size, target: target.size)")
                && maximizerCode.contains("size: target.size)")
                && maximizerCode.contains("restoreFrame(fallback, on: window)\n            completion(false)"),
               "settling recovers against the requested gap target and reports failure after restoring its fallback")
        suite.expect(maximizerCode.contains("let wanted = AppFeature.windowMaximizer.isAvailable")
                && maximizerCode.contains("!isExcluded(pid: candidate.pid)")
                && maximizerCode.contains("frameStates.removeAll()"),
               "disabled, excluded and stopped maximizers retain native handling and discard restore state")

        var maximizeState = WindowMaximizerFrameState<String>()
        let initial = maximizeState.beginMaximize(current: "O", target: "M0", isClose: ==)
        suite.expect(maximizeState.complete(initial, success: true)
                && maximizeState.original == "O" && maximizeState.maximized == "M0",
               "a successful first maximize remembers the original and effective target")
        let gapAttempt = maximizeState.beginMaximize(current: "M0", target: "M32", isClose: ==)
        suite.expect(maximizeState.original == "O" && maximizeState.maximized == "M32",
               "a live gap change keeps the pre-maximize restore frame")
        suite.expect(maximizeState.complete(gapAttempt, success: false)
                && maximizeState.original == "O" && maximizeState.maximized == "M0",
               "an asynchronous gap-change failure rolls both state values back")
        let gapRetry = maximizeState.beginMaximize(current: "M0", target: "M32", isClose: ==)
        _ = maximizeState.complete(gapRetry, success: true)
        let restoreOriginal = maximizeState.original
        let restoreAttempt = maximizeState.beginRestore()
        suite.expect(restoreOriginal == "O" && maximizeState.complete(restoreAttempt, success: true)
                && maximizeState.isEmpty,
               "a successful gap-change maximize still restores the original frame")

        var supersedingState = WindowMaximizerFrameState<String>()
        let firstInFlight = supersedingState.beginMaximize(current: "O", target: "M", isClose: ==)
        let secondInFlight = supersedingState.beginMaximize(current: "I", target: "M", isClose: ==)
        suite.expect(supersedingState.original == "O" && supersedingState.maximized == "M"
                && supersedingState.complete(secondInFlight, success: true)
                && !supersedingState.complete(firstInFlight, success: false)
                && !supersedingState.complete(firstInFlight, success: true),
               "a superseding maximize keeps O and ignores either completion from the old animation")
        let restoreAfterSupersession = supersedingState.beginRestore()
        suite.expect(supersedingState.original == "O"
                && supersedingState.complete(restoreAfterSupersession, success: true)
                && supersedingState.isEmpty,
               "a successful superseding maximize still restores O")

        var restoreSupersessionState = WindowMaximizerFrameState<String>()
        let completedMaximize = restoreSupersessionState.beginMaximize(current: "O", target: "M", isClose: ==)
        _ = restoreSupersessionState.complete(completedMaximize, success: true)
        let inFlightRestore = restoreSupersessionState.beginRestore()
        let maximizeDuringRestore = restoreSupersessionState.beginMaximize(current: "I", target: "M", isClose: ==)
        suite.expect(restoreSupersessionState.original == "O"
                && restoreSupersessionState.complete(maximizeDuringRestore, success: true)
                && !restoreSupersessionState.complete(inFlightRestore, success: true),
               "maximizing during an in-flight restore preserves O and supersedes its completion")
        let failedSupersession = restoreSupersessionState.beginRestore()
        let newerSupersession = restoreSupersessionState.beginMaximize(current: "J", target: "M", isClose: ==)
        suite.expect(restoreSupersessionState.complete(newerSupersession, success: false)
                && restoreSupersessionState.original == "O"
                && restoreSupersessionState.maximized == "M"
                && !restoreSupersessionState.complete(failedSupersession, success: false),
               "a failed newer attempt restores O/M bookkeeping and leaves the older completion stale")
        let lateAfterReset = restoreSupersessionState.beginMaximize(current: "I", target: "M", isClose: ==)
        restoreSupersessionState.reset()
        suite.expect(!restoreSupersessionState.complete(lateAfterReset, success: true)
                && !restoreSupersessionState.complete(inFlightRestore, success: false)
                && restoreSupersessionState.isEmpty,
               "reset makes every late maximize or restore completion inert")

        var manualState = WindowMaximizerFrameState<String>()
        let manualInitial = manualState.beginMaximize(current: "O", target: "M0", isClose: ==)
        _ = manualState.complete(manualInitial, success: true)
        let manualAttempt = manualState.beginMaximize(current: "X", target: "M32", isClose: ==)
        _ = manualState.complete(manualAttempt, success: true)
        suite.expect(manualState.original == "X" && manualState.maximized == "M32",
               "a deliberate move away from the last effective target becomes the restore frame")
        let restoreManual = manualState.beginRestore()
        suite.expect(manualState.original == "X" && manualState.complete(restoreManual, success: true)
                && manualState.isEmpty,
               "a manually moved window restores to its deliberate frame")

        var rejectedState = WindowMaximizerFrameState<String>()
        let rejectedInitial = rejectedState.beginMaximize(current: "O", target: "M0", isClose: ==)
        suite.expect(rejectedState.complete(rejectedInitial, success: false) && rejectedState.isEmpty,
               "a synchronous initial rejection leaves no false maximize state")
        let staleAttempt = rejectedState.beginMaximize(current: "O", target: "M0", isClose: ==)
        let newerAttempt = rejectedState.beginMaximize(current: "X", target: "M32", isClose: ==)
        _ = rejectedState.complete(newerAttempt, success: true)
        suite.expect(!rejectedState.complete(staleAttempt, success: false)
                && rejectedState.original == "O" && rejectedState.maximized == "M32",
               "a superseding attempt preserves O and a stale failure cannot roll it back")
        rejectedState.reset()
        suite.expect(!rejectedState.complete(newerAttempt, success: false) && rejectedState.isEmpty,
               "a completion arriving after stop/reset cannot resurrect frame state")
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
        suite.expect(GlobalShortcutRole.pointerNextDisplay.storageKey == DefaultsKey.pointerDisplayShortcut
                && GlobalShortcutRole.pointerNextDisplay.defaultShortcut == .pointerNextDisplayDefault
                && GlobalShortcutRole.pointerNextDisplay.requiredEnableKeys == [DefaultsKey.pointerDisplayEnabled]
                && GlobalShortcutRole.pointerNextDisplay.feature == .windowLayout,
               "the pointer display shortcut is wired to its own keys and Window Layout")
        suite.expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: [visibleFrame],
                                                         movingForward: false) == nil
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 3,
                                                             frames: horizontalDisplays,
                                                             movingForward: true) == nil,
               "window layout leaves one display and invalid selections unchanged")
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: horizontalDisplays,
                                                          direction: .right) == 2
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                        frames: horizontalDisplays,
                                                        direction: .left) == 1
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 2,
                                                        frames: horizontalDisplays,
                                                        direction: .left) == 0,
               "window layout finds the display starting on the asked side")
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 2,
                                                          frames: horizontalDisplays,
                                                          direction: .right) == nil
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 1,
                                                        frames: horizontalDisplays,
                                                        direction: .left) == nil,
               "window layout stops at the outermost display instead of wrapping sideways")
        let stackedDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 1440, height: 900),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: stackedDisplays,
                                                          direction: .right) == nil
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 1,
                                                        frames: stackedDisplays,
                                                        direction: .left) == nil,
               "window layout never answers a sideways push with a stacked display")
        let towerDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 800, width: 1000, height: 1000),
            CGRect(x: 1440, y: -100, width: 1000, height: 1000),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: towerDisplays,
                                                          direction: .right) == 2,
               "window layout picks the closest display when several share the same edge")
        let verticalNeighbours = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 240, y: 900, width: 1200, height: 900),
            CGRect(x: -180, y: -1000, width: 1440, height: 1000),
            CGRect(x: 0, y: 1800, width: 1440, height: 900),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: verticalNeighbours,
                                                          direction: .up) == 1
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                        frames: verticalNeighbours,
                                                        direction: .down) == 2,
               "window layout finds offset displays above and below, choosing the nearest")
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 3,
                                                          frames: verticalNeighbours,
                                                          direction: .up) == nil
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 2,
                                                        frames: verticalNeighbours,
                                                        direction: .down) == nil,
               "window layout stops at the topmost and bottommost displays")
        let unequalDownwardDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: -1200, width: 1440, height: 1200),
            CGRect(x: 1700, y: -950, width: 800, height: 800),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: unequalDownwardDisplays,
                                                          direction: .down) == 1,
               "window layout ranks downward displays by their top edge, not their far edge")
        let unequalUpwardDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 1440, height: 1200),
            CGRect(x: 1700, y: 950, width: 800, height: 800),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: unequalUpwardDisplays,
                                                          direction: .up) == 1,
               "window layout ranks upward displays by their bottom edge, not their far edge")
        let tiedDownwardDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 600, y: -900, width: 800, height: 900),
            CGRect(x: -1000, y: -900, width: 800, height: 900),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: tiedDownwardDisplays,
                                                          direction: .down) == 1,
               "window layout uses horizontal center distance to break equal downward-edge ties")
        let equallyCenteredDownwardDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: -900, width: 720, height: 900),
            CGRect(x: -720, y: -900, width: 720, height: 900),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: equallyCenteredDownwardDisplays,
                                                          direction: .down) == 1,
               "window layout keeps input order for exact downward center ties")
        let partiallyAlignedDownwardDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1200, y: -900, width: 800, height: 900),
            CGRect(x: -2000, y: -900, width: 800, height: 900),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: partiallyAlignedDownwardDisplays,
                                                          direction: .down) == 1,
               "window layout allows partially aligned downward displays and prefers their nearer center")
        let touchingDownwardDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: -900, width: 1440, height: 900),
        ]
        let fractionallySeparatedDownwardDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: -900.25, width: 1440, height: 900),
        ]
        let fractionallyOverlappingDownwardDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: -899.999, width: 1440, height: 900),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: touchingDownwardDisplays,
                                                          direction: .down) == 1
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                        frames: fractionallySeparatedDownwardDisplays,
                                                        direction: .down) == 1
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                        frames: fractionallyOverlappingDownwardDisplays,
                                                        direction: .down) == nil,
               "window layout accepts touching or fractionally separated displays but rejects any overlap")
        let overlappingVerticalDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 800, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 1440, height: 900),
            CGRect(x: 0, y: -900, width: 1440, height: 900),
            CGRect(x: 0, y: -800, width: 1440, height: 900),
        ]
        suite.expect(WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                          frames: overlappingVerticalDisplays,
                                                          direction: .up) == 2
                && WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                        frames: overlappingVerticalDisplays,
                                                        direction: .down) == 3,
               "window layout ignores vertically overlapping displays when crossing")
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
        suite.expect(Defaults.registeredDefaults[DefaultsKey.windowLayoutMarginPercent] as? Double == 5,
               "existing installations retain the five percent maximize margin")
        suite.expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow,
                                              visibleFrame: visibleFrame, marginPercent: 10)
                == CGRect(x: 144, y: 126, width: 1152, height: 688),
               "custom maximize margin uses each visible dimension independently")
        suite.expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow,
                                              visibleFrame: visibleFrame, marginPercent: 0) == visibleFrame,
               "zero maximize margin fills the usable display")
        let marginPortraitFrame = CGRect(x: -1000, y: -300, width: 1000, height: 1600)
        suite.expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow,
                                              visibleFrame: marginPortraitFrame, marginPercent: 25)
                == CGRect(x: -750, y: 100, width: 500, height: 800),
               "maximum margin stays centered on a portrait display with a negative origin")
        suite.expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow,
                                              visibleFrame: visibleFrame, windowGap: 64,
                                              screenGap: 32, marginPercent: 10)
                == CGRect(x: 144, y: 126, width: 1152, height: 688),
               "custom maximize margin is independent of tiling gaps")
        for action in WindowLayoutAction.allCases where action != .marginMaximize {
            suite.expect(WindowLayoutGeometry.rect(for: action, current: currentWindow,
                                                  visibleFrame: visibleFrame, marginPercent: 25)
                    == WindowLayoutGeometry.rect(for: action, current: currentWindow,
                                                 visibleFrame: visibleFrame),
                   "custom maximize margin leaves \(action.rawValue) unchanged")
        }
        for (input, expected) in [(-10.0, 0.0), (80.0, 25.0), (.nan, 5.0), (.infinity, 5.0)] {
            suite.expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow,
                                                  visibleFrame: visibleFrame, marginPercent: input)
                    == WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow,
                                                 visibleFrame: visibleFrame, marginPercent: expected),
                   "invalid stored maximize margin \(input) uses a supported size")
        }
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
                                                        previousAction: .rightHalf)?.direction == .right,
               "window layout right twice enters the display on the right from its left half")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .leftHalf,
                                                    previousAction: .leftHalf)?.action == .rightHalf
                && WindowLayoutGeometry.displayCrossing(for: .leftHalf,
                                                        previousAction: .leftHalf)?.direction == .left,
               "window layout left twice enters the display on the left from its right half")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .leftHalf, previousAction: nil) == nil
                && WindowLayoutGeometry.displayCrossing(for: .leftHalf, previousAction: .rightHalf) == nil,
               "window layout only crosses displays when the same side is used twice in a row")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .topHalf,
                                                          previousAction: .topHalf)?.action == .bottomHalf
                && WindowLayoutGeometry.displayCrossing(for: .topHalf,
                                                        previousAction: .topHalf)?.direction == .up
                && WindowLayoutGeometry.displayCrossing(for: .bottomHalf,
                                                        previousAction: .bottomHalf)?.action == .topHalf
                && WindowLayoutGeometry.displayCrossing(for: .bottomHalf,
                                                        previousAction: .bottomHalf)?.direction == .down,
               "window layout top and bottom twice cross to the opposite half vertically")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .leftThird,
                                                          previousAction: .leftThird) == nil,
               "window layout keeps thirds on their own display")
        let repeatedBottomHalfDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: -1200, width: 1440, height: 1200),
            CGRect(x: 1700, y: -950, width: 800, height: 800),
        ]
        let firstBottomHalf = WindowLayoutGeometry.rect(for: .bottomHalf,
                                                         current: currentWindow,
                                                         visibleFrame: repeatedBottomHalfDisplays[0])
        let repeatedBottomHalf = WindowLayoutGeometry.displayCrossing(for: .bottomHalf,
                                                                        previousAction: .bottomHalf)
        let repeatedBottomHalfDestination = repeatedBottomHalf.flatMap {
            WindowLayoutGeometry.neighbourIndex(currentIndex: 0,
                                                frames: repeatedBottomHalfDisplays,
                                                direction: $0.direction)
        }
        let secondBottomHalf = repeatedBottomHalfDestination.flatMap { destination in
            repeatedBottomHalf.map {
                WindowLayoutGeometry.rect(for: $0.action,
                                          current: firstBottomHalf,
                                          visibleFrame: repeatedBottomHalfDisplays[destination])
            }
        }
        suite.expect(repeatedBottomHalfDestination == 1
                && secondBottomHalf == CGRect(x: 0, y: -600, width: 1440, height: 600),
               "window layout moves a repeated bottom half to the top half of the nearest display below")
        suite.expect(WindowLayoutGeometry.displayCrossing(for: .topHalf,
                                                          previousAction: .topHalf,
                                                          sideRepeatCyclesThirds: true)?.direction == .up
                && WindowLayoutGeometry.displayCrossing(for: .bottomHalf,
                                                        previousAction: .bottomHalf,
                                                        sideRepeatCyclesThirds: true)?.direction == .down,
               "window layout top and bottom twice still cross vertically while the side cycle is on")
        for (side, twoThirds, third) in [(WindowLayoutAction.leftHalf, WindowLayoutAction.leftTwoThirds, WindowLayoutAction.leftThird),
                                         (.rightHalf, .rightTwoThirds, .rightThird)] {
            suite.expect(WindowLayoutGeometry.effectiveAction(for: side,
                                                        current: currentWindow,
                                                        visibleFrame: visibleFrame,
                                                        previousAction: side,
                                                        sideRepeatCyclesThirds: true) == twoThirds
                    && WindowLayoutGeometry.effectiveAction(for: side,
                                                            current: currentWindow,
                                                            visibleFrame: visibleFrame,
                                                            previousAction: twoThirds,
                                                            sideRepeatCyclesThirds: true) == third
                    && WindowLayoutGeometry.effectiveAction(for: side,
                                                            current: currentWindow,
                                                            visibleFrame: visibleFrame,
                                                            previousAction: third,
                                                            sideRepeatCyclesThirds: true) == side,
                   "window layout \(side.rawValue) repeated cycles half, two thirds, third on the same display")
            suite.expect(WindowLayoutGeometry.effectiveAction(for: side,
                                                        current: currentWindow,
                                                        visibleFrame: visibleFrame,
                                                        previousAction: nil,
                                                        sideRepeatCyclesThirds: true) == side
                    && WindowLayoutGeometry.effectiveAction(for: side,
                                                            current: currentWindow,
                                                            visibleFrame: visibleFrame,
                                                            previousAction: .topHalf,
                                                            sideRepeatCyclesThirds: true) == side,
                   "window layout \(side.rawValue) cycle starts from the half after any other action")
            suite.expect(WindowLayoutGeometry.effectiveAction(for: side,
                                                        current: currentWindow,
                                                        visibleFrame: visibleFrame,
                                                        previousAction: side) == side
                    && WindowLayoutGeometry.effectiveAction(for: side,
                                                            current: currentWindow,
                                                            visibleFrame: visibleFrame,
                                                            previousAction: twoThirds,
                                                            sideRepeatCyclesThirds: false) == side,
                   "window layout \(side.rawValue) repeated keeps the half unless the cycle is on")
            suite.expect(WindowLayoutGeometry.displayCrossing(for: side,
                                                        previousAction: side,
                                                        sideRepeatCyclesThirds: true) == nil
                    && WindowLayoutGeometry.displayCrossing(for: side,
                                                            previousAction: side,
                                                            sideRepeatCyclesThirds: false) != nil,
                   "window layout \(side.rawValue) repeated stays on its display while the cycle is on")
        }
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .rightThird,
                                                    sideRepeatCyclesThirds: true) == .leftHalf,
               "window layout left cycle ignores sizes reached from the other side")
        suite.expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf,
                                                    sideRepeatCyclesThirds: true) == .maximize,
               "window layout top twice still maximizes while the side cycle is on")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.windowLayoutSideRepeatCyclesThirds] as? Bool == false,
               "window layout side repeat cycling stays off by default")
        let sideRepeatSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/WindowLayoutSettings.swift",
            encoding: .utf8)) ?? ""
        let sideRepeatSettingsCode = sideRepeatSettingsSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(sideRepeatSettingsCode.contains("DefaultsKey.windowLayoutSideRepeatCyclesThirds")
                && sideRepeatSettingsCode.contains("text.sideRepeatCycle")
                && sideRepeatSettingsCode.contains("text.sideRepeatCycleCaption"),
               "window layout settings expose the side repeat cycle toggle with its caption")
        let sideRepeatServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift",
            encoding: .utf8)) ?? ""
        let sideRepeatPlacement = sideRepeatServiceSource.components(separatedBy: "private func applyPlacement")
            .dropFirst().first?.components(separatedBy: "WindowLayoutGeometry.effectiveAction").first ?? ""
        suite.expect(sideRepeatServiceSource.contains("WindowLayoutSideRepeat.cyclesThirds")
                && sideRepeatPlacement.contains("WindowLayoutGeometry.sideCycleContinues(")
                && sideRepeatPlacement.contains("settledFrames[target.key]")
                && !sideRepeatPlacement.contains("accepted(actual: target.frame"),
               "window layout service advances the side cycle only from the frame the previous step actually settled at")
        suite.expect(sideRepeatServiceSource.contains("settledFrames[windowKey] = ")
                && sideRepeatServiceSource.contains("settledFrames[context.windowKey] = ")
                && sideRepeatServiceSource.contains("settledFrames.removeValue(forKey: context.windowKey)"),
               "window layout service records the settled frame after immediate and delayed placements and drops it on a refusal")
        let sideRepeatImmediate = sideRepeatServiceSource.components(separatedBy: "settledFrames[windowKey] = ")
            .dropFirst().first?.components(separatedBy: "return true").first ?? ""
        suite.expect(sideRepeatImmediate.contains("scheduleSettledFrameRefresh(")
                && sideRepeatServiceSource.contains("private func scheduleSettledFrameRefresh("),
               "window layout service re-reads a leniently accepted frame later so a late, clamped resize still counts as settled")
        let settledHalf = WindowLayoutFrame(origin: CGPoint(x: 0, y: 40), size: CGSize(width: 720, height: 860))
        let widenedHalf = WindowLayoutFrame(origin: settledHalf.origin, size: CGSize(width: 1080, height: 860))
        let nudgedHalf = WindowLayoutFrame(origin: CGPoint(x: 2, y: 41), size: CGSize(width: 719, height: 858))
        let clampedHalf = WindowLayoutFrame(origin: settledHalf.origin, size: CGSize(width: 900, height: 860))
        let settledTwoThirds = WindowLayoutFrame(origin: settledHalf.origin, size: CGSize(width: 960, height: 860))
        let landedHalf = WindowLayoutSettledFrame(requested: settledHalf, actual: settledHalf)
        let lateTwoThirds = WindowLayoutSettledFrame(requested: settledTwoThirds, actual: settledHalf)
        suite.expect(WindowLayoutGeometry.sideCycleContinues(current: widenedHalf, settled: landedHalf, tolerance: 4) == false,
               "window layout side cycle restarts after the half was widened by hand")
        suite.expect(WindowLayoutGeometry.sideCycleContinues(current: settledHalf, settled: landedHalf, tolerance: 4)
                && WindowLayoutGeometry.sideCycleContinues(current: nudgedHalf, settled: landedHalf, tolerance: 4),
               "window layout side cycle continues from a window still at the settled frame, within tolerance")
        suite.expect(WindowLayoutGeometry.sideCycleContinues(current: clampedHalf,
                                                             settled: WindowLayoutSettledFrame(requested: settledHalf, actual: clampedHalf),
                                                             tolerance: 4)
                && WindowLayoutGeometry.sideCycleContinues(current: settledHalf, settled: nil, tolerance: 4) == false,
               "window layout side cycle honours an app minimum size once settled and never starts without a settled frame")
        suite.expect(WindowLayoutGeometry.sideCycleContinues(current: settledTwoThirds, settled: lateTwoThirds, tolerance: 4)
                && WindowLayoutGeometry.sideCycleContinues(current: settledHalf, settled: lateTwoThirds, tolerance: 4)
                && WindowLayoutGeometry.sideCycleContinues(current: widenedHalf, settled: lateTwoThirds, tolerance: 4) == false,
               "window layout side cycle survives an app that commits the two thirds after it was read back at the half")
        let lateReadAtOldFrame = WindowLayoutSettledFrame(
            requested: settledHalf,
            actual: WindowLayoutFrame(origin: CGPoint(x: 300, y: 200), size: CGSize(width: 1200, height: 800)))
        let clampedByApp = WindowLayoutSettledFrame(requested: settledHalf, actual: clampedHalf)
        let movedClampedHalf = WindowLayoutFrame(origin: CGPoint(x: 20, y: 40), size: CGSize(width: 900, height: 860))
        let driftedClampedHalf = WindowLayoutFrame(origin: settledHalf.origin, size: CGSize(width: 904, height: 862))
        let refreshSource = sideRepeatServiceSource.components(separatedBy: "private func scheduleSettledFrameRefresh(")
            .dropFirst().first?.components(separatedBy: "private func scheduleSettle(").first ?? ""
        suite.expect(refreshSource.contains("WindowLayoutGeometry.settledFrameRefreshAccepts(")
                && refreshSource.contains("self.accepted(actual: actual"),
               "window layout settled frame refresh keeps a change by hand from becoming the settled frame")
        suite.expect(WindowLayoutGeometry.settledFrameRefreshAccepts(actual: clampedHalf, settled: lateReadAtOldFrame, tolerance: 4)
                && WindowLayoutGeometry.settledFrameRefreshAccepts(actual: settledHalf, settled: lateReadAtOldFrame, tolerance: 4),
               "window layout settled frame refresh records a late commit, clamped by the app or landed exactly")
        suite.expect(WindowLayoutGeometry.settledFrameRefreshAccepts(actual: widenedHalf, settled: clampedByApp, tolerance: 4) == false
                && WindowLayoutGeometry.settledFrameRefreshAccepts(actual: movedClampedHalf, settled: clampedByApp, tolerance: 4) == false,
               "window layout settled frame refresh rejects a clamped half widened or moved by hand before it ran")
        suite.expect(WindowLayoutGeometry.settledFrameRefreshAccepts(actual: driftedClampedHalf, settled: clampedByApp, tolerance: 4)
                && WindowLayoutGeometry.settledFrameRefreshAccepts(actual: clampedHalf, settled: clampedByApp, tolerance: 4),
               "window layout settled frame refresh tolerates a clamped half that only drifted within tolerance")
        suite.expect(WindowLayoutGeometry.sideCyclePress(for: .leftHalf, cyclesThirds: true) == .leftHalf
                && WindowLayoutGeometry.sideCyclePress(for: .rightHalf, cyclesThirds: true) == .rightHalf
                && WindowLayoutGeometry.sideCyclePress(for: .leftHalf, cyclesThirds: false) == nil
                && WindowLayoutGeometry.sideCyclePress(for: .leftTwoThirds, cyclesThirds: true) == nil
                && WindowLayoutGeometry.sideCyclePress(for: .topHalf, cyclesThirds: true) == nil,
               "window layout records a side key for the cycle only for left or right halves while the cycle is on")
        let pressedLeft = WindowLayoutSettledFrame(requested: settledHalf, actual: settledHalf, pressedAction: .leftHalf)
        suite.expect(WindowLayoutGeometry.sideCycleResumes(pressing: .leftHalf, settled: pressedLeft)
                && WindowLayoutGeometry.sideCycleResumes(pressing: .rightHalf, settled: pressedLeft) == false
                && WindowLayoutGeometry.sideCycleResumes(pressing: .leftHalf, settled: landedHalf) == false
                && WindowLayoutGeometry.sideCycleResumes(pressing: .leftHalf, settled: nil) == false,
               "window layout side cycle resumes only after the same side key")
        for (side, twoThirds) in [(WindowLayoutAction.leftHalf, WindowLayoutAction.leftTwoThirds),
                                  (.rightHalf, .rightTwoThirds)] {
            // The two thirds shortcut records no side key, so the next side
            // press finds nothing to resume from and places the half.
            let afterTwoThirdsShortcut = WindowLayoutGeometry.sideCyclePress(for: twoThirds, cyclesThirds: true).map {
                WindowLayoutSettledFrame(requested: settledTwoThirds, actual: settledTwoThirds, pressedAction: $0)
            }
            let resumes = WindowLayoutGeometry.sideCycleResumes(pressing: side, settled: afterTwoThirdsShortcut)
                && WindowLayoutGeometry.sideCycleContinues(current: settledTwoThirds,
                                                           settled: afterTwoThirdsShortcut,
                                                           tolerance: 4)
            suite.expect(resumes == false
                    && WindowLayoutGeometry.effectiveAction(for: side,
                                                            current: currentWindow,
                                                            visibleFrame: visibleFrame,
                                                            previousAction: twoThirds,
                                                            sideRepeatCyclesThirds: resumes) == side,
                   "window layout \(side.rawValue) after the two thirds shortcut places the half with the cycle on")
        }
        let sideRepeatSetFrame = sideRepeatServiceSource.components(separatedBy: "cyclePress: WindowLayoutAction? = nil) -> Bool {")
            .dropFirst().first?.components(separatedBy: "scheduleSettle(SettleContext(").first ?? ""
        let sideRepeatConclude = sideRepeatServiceSource.components(separatedBy: "private func concludeSettle(")
            .dropFirst().first?.components(separatedBy: "return\n").first ?? ""
        suite.expect(sideRepeatPlacement.contains("WindowLayoutGeometry.sideCycleResumes(")
                && sideRepeatPlacement.contains("WindowLayoutGeometry.sideCyclePress("),
               "window layout service continues the side cycle only after the same side key")
        suite.expect(sideRepeatSetFrame.components(separatedBy: "if let cyclePress").count == 2
                && sideRepeatSetFrame.components(separatedBy: "if let cyclePress")[0].contains("self.frame(of: window) ?? frame") == false
                && sideRepeatConclude.contains("if let cyclePress = context.cyclePress"),
               "window layout service reads back the settled frame and schedules its refresh only while the cycle is on")
        let leftHalfRect = WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame)
        suite.expect(WindowLayoutGeometry.accepts(actualRect: leftHalfRect.offsetBy(dx: 200, dy: 0),
                                            targetRect: leftHalfRect,
                                            action: .leftHalf,
                                            anchorTolerance: 36) == false
                && WindowLayoutGeometry.accepts(actualRect: leftHalfRect,
                                                targetRect: leftHalfRect,
                                                action: .leftHalf,
                                                anchorTolerance: 36),
               "a window dragged away from its half no longer counts as sitting at the previous placement")
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
