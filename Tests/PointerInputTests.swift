// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum PointerInputTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Mouse click debounce

        let clickConfig = MouseClickDebounceConfig(enabled: true, windowMilliseconds: 25)
        var clickState = MouseClickDebounceState()
        func click(_ button: Int64,
                   _ event: MouseClickDebounceEvent,
                   at milliseconds: UInt64,
                   config: MouseClickDebounceConfig = clickConfig) -> Bool {
            clickState.shouldSuppress(button: button,
                                      event: event,
                                      timestampNanoseconds: milliseconds * 1_000_000,
                                      config: config)
        }
        expect(MouseClickDebounceInput.resolve(type: .leftMouseDown, buttonNumber: 0)
                == MouseClickDebounceInput(button: 0, event: .down)
                && MouseClickDebounceInput.resolve(type: .rightMouseUp, buttonNumber: 1)
                    == MouseClickDebounceInput(button: 1, event: .up)
                && MouseClickDebounceInput.resolve(type: .otherMouseDown, buttonNumber: 2)
                    == MouseClickDebounceInput(button: 2, event: .down)
                && MouseClickDebounceInput.resolve(type: .otherMouseDown, buttonNumber: 3) == nil
                && MouseClickDebounceInput.resolve(type: .leftMouseDragged, buttonNumber: 0)
                    == MouseClickDebounceInput(button: 0, event: .dragged)
                && MouseClickDebounceInput.resolve(type: .otherMouseDragged, buttonNumber: 3) == nil,
               "click debounce owns only primary, secondary and middle button events")
        expect(!click(0, .down, at: 100)
                && !click(0, .dragged, at: 103)
                && !click(0, .up, at: 105),
               "a healthy click passes Down, drag and its final Up without delay")
        expect(click(0, .down, at: 120)
                && click(0, .dragged, at: 122)
                && click(0, .up, at: 125),
               "a bounce click suppresses its Down, drag and matching Up")
        expect(!click(0, .down, at: 130),
               "a click on the filter boundary starts a new accepted press")
        expect(click(0, .down, at: 132),
               "a duplicate Down cannot create a second accepted press")
        expect(!click(0, .up, at: 140),
               "the Up after a duplicate Down still releases the accepted press")
        expect(!click(1, .down, at: 145) && !click(1, .up, at: 150),
               "each standard mouse button owns independent debounce state")
        expect(click(1, .down, at: 160),
               "a second button click inside its own release window is filtered")
        clickState.reset()
        expect(!click(1, .up, at: 165),
               "reset passes an unmatched final Up instead of leaving a button stuck")
        expect(!click(0, .down, at: 200) && !click(0, .up, at: 205),
               "a fresh click is accepted before an out-of-order event")
        expect(!click(0, .down, at: 190),
               "a timestamp moving backwards resets stale button ownership")
        let disabledClickConfig = MouseClickDebounceConfig(enabled: false, windowMilliseconds: 25)
        clickState.reset()
        expect(!click(2, .down, at: 250)
                && !click(2, .up, at: 255)
                && click(2, .down, at: 265)
                && !click(2, .up, at: 266, config: disabledClickConfig),
               "turning the filter off preserves the final release of a suppressed click")
        clickState.reset()
        expect(!click(0, .down, at: 300, config: disabledClickConfig)
                && !click(0, .up, at: 301, config: disabledClickConfig)
                && !click(0, .down, at: 302, config: disabledClickConfig),
               "disabled click debounce is a complete pass-through")
        expect(Defaults.sanitizedMouseClickDebounceWindow(5) == 5
                && Defaults.sanitizedMouseClickDebounceWindow(100) == 100
                && Defaults.sanitizedMouseClickDebounceWindow(0)
                    == Defaults.defaultMouseClickDebounceWindowMs,
               "mouse click debounce keeps only its conservative settings range")
        let clickDebounceServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/MouseClickDebounce/MouseClickDebounceService.swift",
            encoding: .utf8)) ?? ""
        let clickDebounceServiceCode = clickDebounceServiceSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(clickDebounceServiceCode.contains("SessionActivity.shared.onChange")
                && clickDebounceServiceCode.contains("willSleepNotification")
                && clickDebounceServiceCode.contains("didWakeNotification"),
               "click debounce wires session, sleep and tap teardown lifecycle hooks")
        let clickDebounceStop = clickDebounceServiceCode.components(separatedBy: "private func stop()")
            .dropFirst().first?.components(separatedBy: "private func runEventTap").first ?? ""
        expect(clickDebounceStop.contains("state.reset()")
                && clickDebounceStop.contains("CFMachPortInvalidate")
                && !clickDebounceStop.contains("tapThread = nil"),
               "click debounce resets ownership without erasing a newer tap thread")
        let clickDebounceFinish = clickDebounceServiceCode.components(
            separatedBy: "private func finishEventTapThread"
        ).dropFirst().first?.components(separatedBy: "private func clearEventTapThread").first ?? ""
        expect(clickDebounceFinish.contains("DispatchQueue.main.async")
                && clickDebounceFinish.contains("restart.generation == self.lifecycleGeneration")
                && clickDebounceFinish.contains("self.syncWithPreferences()")
                && !clickDebounceFinish.contains("start("),
               "click debounce serializes current restarts on main and drops stale ones")
        let clickDebounceRearm = clickDebounceServiceCode.components(separatedBy: "tapDisabledByTimeout")
            .dropFirst().first?.components(separatedBy: "return").first ?? ""
        expect(clickDebounceRearm.contains("state.reset()")
                && clickDebounceRearm.contains("SessionActivity.shared.isActive"),
               "click debounce resets before any safe tap re-arm")
        expect(clickDebounceServiceCode.contains(
            "recoveryGeneration == self.lifecycleGeneration"
        ), "click debounce drops disabled-tap recovery after a newer lifecycle change")
        expect(!clickDebounceServiceCode.contains("Timer(")
                && !clickDebounceServiceCode.contains("asyncAfter"),
               "legacy click filtering adds no timer or delayed release to healthy clicks")
        let featureRuntimeSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/FeatureRuntime.swift",
            encoding: .utf8)) ?? ""
        expect(featureRuntimeSource.contains(
            ".mouseClickDebounce: { MouseClickDebounceService.shared.syncWithPreferences() }"
        ), "the Features hub owns the click debounce runtime lifecycle")

        expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: false, momentumPhase: 0, scrollPhase: 0, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "classic mouse wheel ticks classify as a wheel")
        expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "phase-less continuous wheel events classify as a wheel")
        expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 2, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "touch scrolling phases classify as touch")
        expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 3, scrollPhase: 0, scrollCount: 1),
            secondsSinceLastGesturePhase: 0.1
        ), "momentum scrolling classifies as touch")
        expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: 0.05
        ), "touch transition events (phaseless, counted, right after a phased event) classify as touch")
        expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: 5.0
        ), "counted wheel events long after any gesture classify as a wheel")
        expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: nil
        ), "counted wheel events classify as a wheel when no gesture was ever seen")
        expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: false, shiftRedirectsVertical: false,
            invertVertical: true, invertHorizontal: false
        ) == ScrollWheelInversionPlan(vertical: true, horizontal: false),
        "vertical wheel movement follows only the vertical direction setting")
        expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: false, hasHorizontalMovement: true, shiftRedirectsVertical: false,
            invertVertical: true, invertHorizontal: false
        ) == ScrollWheelInversionPlan(vertical: false, horizontal: false),
        "a horizontal wheel stays unchanged when only vertical inversion is on")
        expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: false, shiftRedirectsVertical: true,
            invertVertical: true, invertHorizontal: false
        ) == ScrollWheelInversionPlan(vertical: false, horizontal: false),
        "Shift-directed wheel movement follows the horizontal setting")
        expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: false, shiftRedirectsVertical: true,
            invertVertical: false, invertHorizontal: true
        ) == ScrollWheelInversionPlan(vertical: true, horizontal: false),
        "horizontal inversion flips the vertical source tick while Shift redirects it")
        expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: true, shiftRedirectsVertical: true,
            invertVertical: true, invertHorizontal: false
        ) == ScrollWheelInversionPlan(vertical: true, horizontal: false),
        "a genuine two-axis event keeps each axis independent even with Shift held")
        expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: false, shiftRedirectsVertical: false,
            invertVertical: false, invertHorizontal: true
        ) == ScrollWheelInversionPlan(vertical: false, horizontal: false),
        "a continuous wheel stays vertical because Shift does not redirect that event type")

        // A modifying tap belongs in the chain only while this login session is
        // the one on screen: fast user switching leaves the process running
        // behind another account, where the tap still takes every scroll event
        // and stalls it (issue #1075).
        expect(SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                   accessibilityGranted: true,
                                                   sessionIsActive: true),
               "a wanted modifying tap runs in the session on screen")
        expect(!SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                    accessibilityGranted: true,
                                                    sessionIsActive: false),
               "a wanted modifying tap is handed back while its session is switched away")
        expect(!SessionActivitySupport.tapShouldRun(featureWanted: false,
                                                    accessibilityGranted: true,
                                                    sessionIsActive: true),
               "an unwanted modifying tap stays off in the session on screen")
        expect(!SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                    accessibilityGranted: false,
                                                    sessionIsActive: true),
               "a modifying tap needs Accessibility even in the session on screen")

        // Launching into a session that is already switched away is announced
        // before the tap owners exist to hear it, so the state is read rather
        // than assumed. Anything unreadable counts as on screen because a
        // wrong off state would never be corrected.
        let onConsoleKey = kCGSessionOnConsoleKey as String
        expect(SessionActivitySupport.isOnConsole([onConsoleKey: true]),
               "a session dictionary saying it holds the console reads as on screen")
        expect(!SessionActivitySupport.isOnConsole([onConsoleKey: false]),
               "a session dictionary saying it does not hold the console reads as off screen")
        expect(SessionActivitySupport.isOnConsole([onConsoleKey: NSNumber(value: 1)]),
               "the console flag is read when it arrives as a number")
        expect(SessionActivitySupport.isOnConsole(nil),
               "an unreadable session reads as on screen because a wrong off would never be corrected")
        expect(SessionActivitySupport.isOnConsole([:]),
               "a session without the console flag reads as on screen because a wrong off would never be corrected")
        expect(SessionActivitySupport.isOnConsole([onConsoleKey: "unexpected"]),
               "an unexpected console flag reads as on screen because a wrong off would never be corrected")

        let privateCenter = NotificationCenter()
        let activity = SessionActivity(center: privateCenter, initialIsActive: { true })
        var observedTransitions: [Bool] = []
        activity.onChange { observedTransitions.append($0) }
        expect(activity.isActive, "session activity starts with the injected initial state")
        privateCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        expect(!activity.isActive, "session activity transitions to inactive on resign")
        privateCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        privateCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        expect(activity.isActive, "session activity transitions to active on become-active")
        expect(observedTransitions == [false, true],
               "the session activity handler records each state change and ignores duplicate notifications")

        expect(MouseNavigationSupport.direction(
            forButtonNumber: MouseNavigationSupport.backButtonNumber) == .back,
               "the first standard mouse side button maps to Back")
        expect(MouseNavigationSupport.direction(
            forButtonNumber: MouseNavigationSupport.forwardButtonNumber) == .forward,
               "the second standard mouse side button maps to Forward")
        expect(MouseNavigationSupport.direction(forButtonNumber: 2) == nil,
               "the middle mouse button is never consumed as navigation")
        expect(MouseNavigationSupport.direction(forButtonNumber: 9) == nil,
               "unrelated extra mouse buttons pass through")
        expect(MouseNavigationSupport.commandCharacter(for: .back) == "[",
               "Back uses the standard Command left bracket menu command")
        expect(MouseNavigationSupport.commandCharacter(for: .forward) == "]",
               "Forward uses the standard Command right bracket menu command")
        expect(MouseNavigationSupport.sanitizedCommandCharacter("ö") == "ö",
               "a key equivalent the system moved the command to is taken as it is")
        expect(MouseNavigationSupport.sanitizedCommandCharacter("[") == "[",
               "a keyboard that types brackets keeps the declared command")
        expect(MouseNavigationSupport.sanitizedCommandCharacter("") == nil,
               "an empty key equivalent means no answer came back")
        expect(MouseNavigationSupport.sanitizedCommandCharacter("ab") == nil,
               "a key equivalent is a single key, never a string of them")
        expect(MouseNavigationSupport.sanitizedCommandCharacter(" ") == nil,
               "a blank key equivalent is not something to look for in a menu")
        expect(MouseNavigationDirection.allCases.count == 2,
               "the side buttons navigate in exactly two directions")
        expect(MouseNavigationSupport.sanitizedCommandCharacter("\t") == nil,
               "a control character is never a key to look for in a menu")
        // Menus spell their shortcut key in upper case whatever the app wrote,
        // and an upper case letter carries Shift on its own: both measured on
        // a real menu, and both decide whether the command is found at all.
        expect(MouseNavigationSupport.matchesCommand(menuCharacter: "Ö", menuModifiers: 0,
                                                     character: "ö", modifiers: 0),
               "a command the system moved onto a letter is found despite the menu's upper case")
        expect(MouseNavigationSupport.matchesCommand(menuCharacter: "[", menuModifiers: 0,
                                                     character: "[", modifiers: 0),
               "the declared bracket keeps being found where the keyboard types it")
        expect(!MouseNavigationSupport.matchesCommand(menuCharacter: "Ö", menuModifiers: 1,
                                                      character: "ö", modifiers: 0),
               "the same key with another modifier is a different command")
        expect(!MouseNavigationSupport.matchesCommand(menuCharacter: "Ä", menuModifiers: 0,
                                                      character: "ö", modifiers: 0),
               "a different key is never the command being looked for")
        expect(!MouseNavigationSupport.matchesCommand(menuCharacter: nil, menuModifiers: 0,
                                                      character: "[", modifiers: 0),
               "a menu item with no shortcut at all is never a match")
        expect(MouseNavigationSupport.menuModifiers(shift: false, option: false, control: false,
                                                    command: true, character: "ö") == 0,
               "Command with a lower case key is the plain shortcut a menu reports as zero")
        expect(MouseNavigationSupport.menuModifiers(shift: false, option: false, control: false,
                                                    command: true, character: "Ö") == 1,
               "an upper case key carries Shift even when nobody asked for it")
        expect(MouseNavigationSupport.menuModifiers(shift: true, option: false, control: false,
                                                    command: true, character: "f") == 1,
               "Shift asked for reads the same as Shift implied by the key")
        expect(MouseNavigationSupport.menuModifiers(shift: false, option: true, control: true,
                                                    command: false, character: "[") == 14,
               "Option, Control and no Command each add their own bit")
        expect(MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "org.mozilla.firefox"),
               "the pass-through browser family keeps the raw side button events")
        expect(MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "org.mozilla.firefoxdeveloperedition"),
               "every channel of the browser family passes through via the prefix rule")
        let registeredWebHandlers: Set<String> = ["com.example.browser", "com.apple.WebViewer"]
        expect(MouseNavigationSupport.nativeWebHandlers(
            urlHandlers: ["com.example.browser", "com.example.linkOnly"],
            documentHandlers: ["com.example.browser", "com.example.documentOnly"]
        ) == ["com.example.browser"],
               "only apps registered for web URLs and web documents are treated as browsers")
        expect(MouseNavigationSupport.shouldRefreshWebHandlers(
            isApplicationActivation: false, activatedPID: nil, ownPID: 41),
               "launch, termination and mounted-volume changes refresh registered web handlers")
        expect(MouseNavigationSupport.shouldRefreshWebHandlers(
            isApplicationActivation: true, activatedPID: 41, ownPID: 41),
               "activating Vorssaint refreshes registered web handlers")
        expect(!MouseNavigationSupport.shouldRefreshWebHandlers(
            isApplicationActivation: true, activatedPID: 42, ownPID: 41),
               "activating another app does not repeat the handler lookup")
        expect(!MouseNavigationSupport.shouldRefreshWebHandlers(
            isApplicationActivation: true, activatedPID: nil, ownPID: 41),
               "an activation without an app does not repeat the handler lookup")
        expect(MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "com.example.browser", webURLHandlers: registeredWebHandlers),
               "a third-party web handler keeps its native side button events")
        expect(!MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "com.apple.WebViewer", webURLHandlers: registeredWebHandlers),
               "a system web handler stays on the menu-command navigation path")
        expect(MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "com.parallels.desktop.console"),
               "virtual machines keep the raw side buttons for the guest system")
        expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "com.apple.finder"),
               "Finder stays on the menu-command navigation path")
        expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "org.mozillafoundation.x"),
               "prefix matching stops at the org.mozilla. namespace boundary")
        expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: nil),
               "an unknown frontmost app keeps the navigation behavior")
    }
}
