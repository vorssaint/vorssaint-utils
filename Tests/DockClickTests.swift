// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin
import Foundation

enum DockClickTests {
    static func run(expect: (Bool, String) -> Void) {

        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .minimize,
               "dock click minimizes the frontmost app with visible windows")
        expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .passThrough,
               "dock click lets the Dock activate apps that are not frontmost")
        // The tap swallows a restoring click so the Dock will not open a new
        // window, which leaves raising the app to this service. Since macOS 14
        // that only lands if the request is cooperative, so pin the sequence
        // rather than the bare call it replaced. Asserted positively: the call
        // it must not use is named in the doc comment right above it.
        let dockClickSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/DockClick/DockClickService.swift",
            encoding: .utf8)) ?? ""
        expect(dockClickSource.contains("ActivationHandoff.yield(to: app)"),
               "a Dock click restore yields this app's activation first")
        expect(dockClickSource.contains("app.activate(from: NSRunningApplication.current, options: [])"),
               "a Dock click restore asks cooperatively before falling back")
        // A yield only hands over activation this app holds, and it usually
        // holds none when a switch commits, so the helper self-activates first
        // and every yield goes through it. A bare yield added on a new path
        // would bring the refused-handoff bug back on that path alone.
        let activationHandoffSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/ActivationHandoff.swift",
            encoding: .utf8)) ?? ""
        let selfActivation = activationHandoffSource.range(of: "NSApp.activate(ignoringOtherApps: true)")
        let yieldOnward = activationHandoffSource.range(of: "NSApp.yieldActivation(to: app)")
        expect(selfActivation != nil && yieldOnward != nil
                && selfActivation!.lowerBound < yieldOnward!.lowerBound,
               "the activation handoff self-activates before it yields onward")
        let handoffStamp = activationHandoffSource.range(of: "lastSelfActivation = CFAbsoluteTimeGetCurrent()")
        expect(handoffStamp != nil && selfActivation != nil
                && handoffStamp!.lowerBound < selfActivation!.lowerBound,
               "the activation handoff stamps the self-activation before asking for it")
        // Only the activation the handoff caused stays out of the history; the
        // Dock icon, Settings and Vorssaint's own windows are real uses.
        let useTrackerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowUseTracker.swift",
            encoding: .utf8)) ?? ""
        expect(useTrackerSource.contains(
                   "pid == ProcessInfo.processInfo.processIdentifier && ActivationHandoff.isHandingOff"),
               "only an activation the handoff caused is left out of the use history")
        var bareActivationYields: [String] = []
        var scannedActivationFiles = 0
        if let sources = FileManager.default.enumerator(atPath: "Sources") {
            for case let path as String in sources where path.hasSuffix(".swift") {
                scannedActivationFiles += 1
                guard (path as NSString).lastPathComponent != "ActivationHandoff.swift" else { continue }
                let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
                if text.contains("yieldActivation") {
                    bareActivationYields.append((path as NSString).lastPathComponent)
                }
            }
        }
        expect(scannedActivationFiles > 0 && bareActivationYields.isEmpty,
               "activation is yielded only through ActivationHandoff, "
               + "found a bare yield in \(bareActivationYields.sorted()) "
               + "across \(scannedActivationFiles) scanned files")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       ownsMinimize: true) == .restore,
               "dock click restores when every window is minimized")
        expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       ownsMinimize: true) == .restore,
               "dock click restores minimized windows of background apps too")
        expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       ownsMinimize: false) == .passThrough,
               "dock click leaves windows minimized by other means to the Dock")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       ownsMinimize: false) == .passThrough,
               "the frontmost app's own minimize is the Dock's to undo as well")
        expect(DockClickSupport.capturedMinimizeStillHolds(captured: [7, 8], stillMinimized: [8, 9]),
               "a capture holds while one of the windows it named is still down")
        expect(!DockClickSupport.capturedMinimizeStillHolds(captured: [7, 8], stillMinimized: [9]),
               "a capture whose windows all came back another way is stale")
        expect(!DockClickSupport.capturedMinimizeStillHolds(captured: [], stillMinimized: [9]),
               "a capture that named nothing claims nothing")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .passThrough,
               "dock click passes through for windowless apps")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: true,
                                       hasModifiers: false) == .passThrough,
               "dock click stays hands-off while the app has a fullscreen window")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: true) == .passThrough,
               "dock click keeps the Dock's native modifier shortcuts")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 3) == .cycleWindows,
               "dock click cycles instead of minimizing when both are on and there are windows to cycle")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 1) == .minimize,
               "dock click still minimizes a single-window app with cycling on")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 1) == .passThrough,
               "cycling alone never minimizes a single-window app")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .hide,
               "dock click hides the frontmost app when hiding is enabled")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .hide,
               "hiding also works for a frontmost app with no windows")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .hide,
               "hiding is app-level even when every window is minimized")
        expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .passThrough,
               "hiding lets the Dock activate a background app")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: true,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .hide,
               "hiding follows the app-level command even with a fullscreen window")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: true,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .passThrough,
               "hiding preserves every native modifier click")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       hideEnabled: true) == .hide,
               "hiding wins safely if imported preferences enable both actions")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true,
                                       cycleWindowsEnabled: false,
                                       cycleCandidateCount: 3) == .hide,
               "hiding treats a multi-window app as one app when cycling is off")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 3) == .cycleWindows,
               "window cycling stays ahead of hiding when several windows are available")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 0) == .passThrough,
               "cycling alone never restores minimized windows")
        expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 3) == .passThrough,
               "cycling lets the Dock activate apps that are not frontmost")
        // The two assertions above and below are what lets the service skip
        // counting candidates unless the app is frontmost and has no
        // fullscreen window: on those paths the ladder ignores the count, so
        // paying for it inside the event tap buys nothing.
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: true,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 3) == .passThrough,
               "cycling stays out of an app with a fullscreen window however many candidates there are")
        // Issue #1204's report: one app, four unminimized windows spread over
        // three desktops, two of them on the desktop being looked at. The AX
        // window list holds all four; the window server's on-screen list holds
        // only the two.
        let windowsAcrossDesktops: [CGWindowID?] = [1, 2, 3, 4]
        expect(DockClickSupport.cycleCandidateIndices(windowIDs: windowsAcrossDesktops,
                                                      onScreenFrontToBack: [1, 2]) == [0, 1],
               "cycling only considers the windows on the desktop being looked at")
        expect(DockClickSupport.cycleCandidateIndices(windowIDs: windowsAcrossDesktops,
                                                      onScreenFrontToBack: [1, 2]).last == 1,
               "the click raises the rearmost window of the current desktop")
        expect(DockClickSupport.cycleCandidateIndices(windowIDs: windowsAcrossDesktops,
                                                      onScreenFrontToBack: [2, 1]).last == 0,
               "the next click raises the other one back, rotating in place")
        expect(DockClickSupport.cycleCandidateIndices(windowIDs: windowsAcrossDesktops,
                                                      onScreenFrontToBack: [3]).count == 1,
               "a desktop holding one window offers nothing to cycle, so the click cannot jump to another desktop")
        expect(DockClickSupport.cycleCandidateIndices(windowIDs: [1, 2, 3],
                                                      onScreenFrontToBack: [3, 1, 2]).last == 1,
               "three windows on one desktop rotate through all of them, not just the front two")
        expect(DockClickSupport.cycleCandidateIndices(windowIDs: [nil, nil],
                                                      onScreenFrontToBack: [1, 2]).isEmpty,
               "windows whose ids cannot be resolved are never guessed at")
        expect(DockClickSupport.repeatDecision(lastAction: .cycleWindows, elapsed: 0.5) == .deriveFromState,
               "a repeated click after a cycle keeps cycling from live state")
        expect(DockClickSupport.repeatDecision(lastAction: .hide, elapsed: 0.5) == .deriveFromState,
               "a click after hiding lets the Dock bring the app back")
        expect(DockClickSupport.repeatDecision(lastAction: .hide, elapsed: 0.1) == .swallow,
               "an accidental double-click never hides and immediately reopens the app")
        expect(DockClickSupport.isOwnBundleIdentifier("com.vorssaint.utils")
                && DockClickSupport.isOwnBundleIdentifier("com.vorssaint.utils.dev")
                && !DockClickSupport.isOwnBundleIdentifier("com.example.editor")
                && !DockClickSupport.isOwnBundleIdentifier(nil),
               "Dock clicks never target either build of this app")

        expect(DockClickSupport.repeatDecision(lastAction: nil, elapsed: nil) == .deriveFromState,
               "dock click derives the first click from window state")
        expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 0.1) == .swallow,
               "dock click swallows accidental double-clicks")
        expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 0.5) == .toggle(.restore),
               "dock click right after a minimize toggles straight back to restore")
        expect(DockClickSupport.repeatDecision(lastAction: .restore, elapsed: 0.5) == .toggle(.minimize),
               "dock click right after a restore toggles back to minimize")
        expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 2.0) == .deriveFromState,
               "dock click trusts settled window state once the intent window passes")

        expect(DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                       modifiers: 2,
                                                       identifier: "miniaturizeAll:"),
               "dock click recognizes the standard Minimize All menu action")
        expect(!DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                        modifiers: 2,
                                                        identifier: "toggleCompactWindow:"),
               "dock click rejects an unrelated action that shares the Minimize All shortcut")
        expect(!DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                        modifiers: 2,
                                                        identifier: nil),
               "dock click never guesses when an Option-Command-M action has no identifier")

        // Bottom Dock reserving ~70 pt: only the reserved strip counts, so a
        // click on a preview panel floating just above the Dock passes through.
        let dockScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let bottomDockVisible = CGRect(x: 0, y: 24, width: 1512, height: 888)
        expect(DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: bottomDockVisible),
               "dock strip accepts clicks inside the reserved bottom strip")
        expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 880),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: bottomDockVisible),
               "dock strip rejects clicks hovering above the Dock, like a preview panel")
        expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 20),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: bottomDockVisible),
               "dock strip ignores the top edge where the Dock never lives")
        let leftDockVisible = CGRect(x: 70, y: 24, width: 1442, height: 958)
        expect(DockClickSupport.dockStripContains(CGPoint(x: 40, y: 500),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: leftDockVisible),
               "dock strip accepts clicks inside a left Dock's reserved strip")
        expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: leftDockVisible),
               "dock strip rejects bottom clicks when the Dock lives on the left")
        expect(DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: CGRect(x: 0, y: 24, width: 1512, height: 958)),
               "dock strip falls back to an edge band when auto-hide reserves nothing")
        let dockStripWindow = MouseAppExceptionSupport.Window(frame: dockScreen, layer: 20,
                                                              processID: 1267)
        let coveringWindow = MouseAppExceptionSupport.Window(frame: dockScreen, layer: 24,
                                                             processID: 4242)
        let dockPoint = CGPoint(x: 90, y: 930)
        var dockAccessibilityLookups = 0
        func unexpectedDockAccessibilityLookup() -> pid_t? {
            dockAccessibilityLookups += 1
            return 1267
        }
        expect(DockClickSupport.dockOwnsPoint(dockPoint,
                                              windows: [dockStripWindow],
                                              dockProcessID: 1267,
                                              dockLayer: 20,
                                              ownProcessID: 501,
                                              accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "Dock click accepts a visible unobstructed Dock strip")
        expect(!DockClickSupport.dockOwnsPoint(dockPoint,
                                               windows: [coveringWindow, dockStripWindow],
                                               dockProcessID: 1267,
                                               dockLayer: 20,
                                               ownProcessID: 501,
                                               accessibilityHitProcessID: { 4242 }),
               "Dock click leaves a point covered by fullscreen content untouched")
        expect(DockClickSupport.dockOwnsPoint(
            dockPoint,
            windows: [MouseAppExceptionSupport.Window(frame: dockScreen, layer: 24,
                                                       processID: 501), dockStripWindow],
            dockProcessID: 1267,
            dockLayer: 20,
            ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "this app's own panel never hides the Dock below it from the ownership check")
        // A screen recording overlay reports a full-display, opaque layer-24
        // window even while Accessibility reaches the Dock underneath it.
        // Its window-server geometry is identical to real fullscreen content.
        expect(DockClickSupport.dockOwnsPoint(
            dockPoint, windows: [coveringWindow, dockStripWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: { 1267 }),
               "Dock actions and previews work through an input-transparent recording overlay")
        expect(!DockClickSupport.dockOwnsPoint(
            dockPoint, windows: [coveringWindow, dockStripWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: { nil }),
               "an unavailable Accessibility answer cannot allow actions through a covering window")
        expect(!DockClickSupport.dockOwnsPoint(
            dockPoint, windows: [coveringWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "a hidden Dock never accepts a click through the parked icon layout")
        expect(!DockClickSupport.dockOwnsPoint(
            CGPoint(x: dockScreen.maxX + 100, y: dockPoint.y),
            windows: [coveringWindow, dockStripWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "the Dock on another display does not accept a pointer outside its visible bounds")
        expect(DockClickSupport.dockOwnsPoint(
            dockPoint, windows: [dockStripWindow, coveringWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "a window behind the Dock cannot block it")
        expect(DockClickSupport.dockOwnsPoint(
            dockPoint,
            windows: [MouseAppExceptionSupport.Window(frame: dockScreen, layer: 24,
                                                       alpha: 0, processID: 4242), dockStripWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "an invisible window does not trigger an Accessibility lookup")
        expect(dockAccessibilityLookups == 0,
               "Dock ownership only asks Accessibility for an overlapping window above a visible Dock")
        expect(DockPreviewSupport.mouseMoveSampleInterval > 0
               && DockPreviewSupport.mouseMoveSampleInterval <= 1.0 / 60
               && DockPreviewSupport.mouseMoveSampleInterval < DockPreviewSupport.switchDelay,
               "Dock Preview samples high-rate mouse movement faster than hover intent")
        let dockPreviewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/DockPreview/DockPreviewService.swift",
            encoding: .utf8)) ?? ""
        expect(dockPreviewSource.contains("DockClickSupport.dockOwnsPoint("),
               "Dock Preview does not open through fullscreen content covering the Dock")

        // Both window server scans read the same list and must keep
        // disagreeing where they disagree today. A point exactly on a
        // window's far edge is inside for the click lookup and outside for
        // the traffic lights, and a window whose app the traffic lights are
        // told to leave alone ends that scan instead of handing the click to
        // whatever sits behind it.
        func windowServerEntry(_ frame: CGRect, pid: Int32, number: UInt32) -> [String: Any] {
            [kCGWindowBounds as String: ["X": NSNumber(value: Double(frame.minX)),
                                         "Y": NSNumber(value: Double(frame.minY)),
                                         "Width": NSNumber(value: Double(frame.width)),
                                         "Height": NSNumber(value: Double(frame.height))] as [String: Any],
             kCGWindowLayer as String: NSNumber(value: 0),
             kCGWindowAlpha as String: NSNumber(value: 1.0),
             kCGWindowOwnerPID as String: NSNumber(value: pid),
             kCGWindowNumber as String: NSNumber(value: number)]
        }
        let scannedWindow = CGRect(x: 0, y: 0, width: 200, height: 200)
        let scannedNeighbour = CGRect(x: 200, y: 96, width: 200, height: 200)
        let scannedEdgePoint = CGPoint(x: 200, y: 100)
        let scannedNeighbours = [windowServerEntry(scannedWindow, pid: 1001, number: 11),
                                 windowServerEntry(scannedNeighbour, pid: 1002, number: 12)]
        expect(WindowServerSupport.bounds(from: scannedNeighbours[0]) == scannedWindow
                && WindowServerSupport.bounds(from: [:]) == nil,
               "a window's rectangle comes from its bounds entry and from nothing else")
        expect(WindowServerSupport.windowCandidate(in: scannedNeighbours, at: scannedEdgePoint,
                                                   ownProcessID: 501,
                                                   pidIsEligible: { _ in true })?.pid == 1001,
               "a click on a window's far edge still belongs to that window")
        expect(WindowServerSupport.trafficLightCandidate(in: scannedNeighbours, at: scannedEdgePoint,
                                                         button: .close,
                                                         ownProcessID: 501,
                                                         pidIsEligible: { _ in true })?.pid == 1002,
               "a traffic light on a window's far edge belongs to the window that owns the pixel")
        let scannedStack = [windowServerEntry(scannedWindow, pid: 1001, number: 11),
                            windowServerEntry(scannedWindow, pid: 1002, number: 12)]
        let scannedCloseButtonPoint = CGPoint(x: 20, y: 20)
        expect(WindowServerSupport.trafficLightCandidate(in: scannedStack, at: scannedCloseButtonPoint,
                                                         button: .close,
                                                         ownProcessID: 501,
                                                         pidIsEligible: { $0 != 1001 }) == nil,
               "a traffic light click stops at the window in front, never reaching one behind it")
        expect(WindowServerSupport.windowCandidate(in: scannedStack, at: scannedCloseButtonPoint,
                                                   ownProcessID: 501,
                                                   pidIsEligible: { $0 != 1001 })?.pid == 1002,
               "the click lookup carries on behind a window it was told to leave alone")

        // Unlike the click scan, hover must stop at our interactive surfaces
        // before making any Accessibility call, even for a tiny raised panel.
        let focusHitPoint = CGPoint(x: -200, y: -100)
        let focusHitFrame = CGRect(x: -300, y: -200, width: 400, height: 400)
        let foreignFocusWindow = windowServerEntry(focusHitFrame, pid: 1001, number: 11)
        let ownFocusWindow = windowServerEntry(focusHitFrame, pid: 501, number: 12)
        var focusQueryPIDs: [pid_t] = []
        func queryFocusWindow(_ windows: [[String: Any]],
                              pointerWindowID: CGWindowID = 11,
                              clickThroughWindowIDs: Set<CGWindowID> = [],
                              querySucceeds: Bool = true) -> pid_t? {
            focusQueryPIDs.removeAll()
            return FocusFollowsMouseSupport.queryWindow(
                in: windows, at: focusHitPoint, pointerWindowID: pointerWindowID,
                ownProcessID: 501,
                clickThroughWindowIDs: clickThroughWindowIDs
            ) { pid in
                focusQueryPIDs.append(pid)
                return querySucceeds ? pid : nil
            }
        }
        for layer in [0, 3, 25, 1_000] {
            var panel = windowServerEntry(
                CGRect(x: -210, y: -110, width: 20, height: 20), pid: 501, number: 12)
            panel[kCGWindowLayer as String] = NSNumber(value: layer)
            expect(queryFocusWindow([panel, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
                   "hover issues no Accessibility query through an own panel at layer \(layer)")
        }
        expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
               "hover leaves both its own ordinary window and the app behind it untouched")
        expect(queryFocusWindow([foreignFocusWindow, ownFocusWindow]) == 1001 && focusQueryPIDs == [1001],
               "a foreign window covering our panel receives exactly one scoped query on an offset display")
        expect(queryFocusWindow([]) == nil && focusQueryPIDs.isEmpty,
               "an empty or unavailable window list never falls back to a global Accessibility query")
        var unknownOwner = foreignFocusWindow
        unknownOwner.removeValue(forKey: kCGWindowOwnerPID as String)
        expect(queryFocusWindow([unknownOwner, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
               "an unknown surface owner blocks hover without querying an app behind it")
        for invalidPID: Int32 in [0, -1] {
            let invalidWindow = windowServerEntry(focusHitFrame, pid: invalidPID, number: 13)
            expect(queryFocusWindow([invalidWindow, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
                   "hover never queries an invalid process identifier")
        }
        var transparentPanel = ownFocusWindow
        transparentPanel[kCGWindowAlpha as String] = NSNumber(value: 0.0)
        expect(queryFocusWindow([transparentPanel, foreignFocusWindow]) == 1001 && focusQueryPIDs == [1001],
               "a fully invisible own surface does not block the app under the pointer")
        transparentPanel[kCGWindowAlpha as String] = NSNumber(value: 0.1)
        expect(queryFocusWindow([transparentPanel, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
               "a translucent own panel still blocks hover before Accessibility")
        let distantPanel = windowServerEntry(CGRect(x: 0, y: 0, width: 400, height: 400), pid: 501, number: 14)
        expect(queryFocusWindow([distantPanel, foreignFocusWindow]) == 1001 && focusQueryPIDs == [1001],
               "our panel elsewhere on the displays does not disable hover")
        expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow], clickThroughWindowIDs: [12]) == 1001
                && focusQueryPIDs == [1001],
               "a known own click-through overlay passes hover to the foreign app without querying itself")
        expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow], clickThroughWindowIDs: [14]) == nil
                && focusQueryPIDs.isEmpty,
               "only the exact own window marked click-through may be skipped")
        var ownPanelWithoutID = ownFocusWindow
        ownPanelWithoutID.removeValue(forKey: kCGWindowNumber as String)
        expect(queryFocusWindow([ownPanelWithoutID, foreignFocusWindow], clickThroughWindowIDs: [12]) == nil
                && focusQueryPIDs.isEmpty,
               "an unidentified own panel is never assumed to be click-through")
        let brightnessOverlay = windowServerEntry(focusHitFrame, pid: 501, number: 15)
        expect(queryFocusWindow([brightnessOverlay, ownFocusWindow, foreignFocusWindow],
                                clickThroughWindowIDs: [15]) == nil && focusQueryPIDs.isEmpty,
               "a click-through overlay does not hide an interactive own panel from the guard")
        expect(queryFocusWindow([brightnessOverlay, ownFocusWindow, foreignFocusWindow],
                                clickThroughWindowIDs: [12, 15]) == 1001 && focusQueryPIDs == [1001],
               "stacked own click-through overlays still allow normal hover focus")
        expect(queryFocusWindow([foreignFocusWindow, ownFocusWindow], clickThroughWindowIDs: [11]) == 1001
                && focusQueryPIDs == [1001],
               "the click-through allowlist never skips another app's surface")
        let secondForeignWindow = windowServerEntry(focusHitFrame, pid: 1002, number: 16)
        var recordingOverlay = windowServerEntry(focusHitFrame, pid: 1003, number: 17)
        recordingOverlay[kCGWindowLayer as String] = NSNumber(value: 24)
        expect(queryFocusWindow([recordingOverlay, foreignFocusWindow]) == 1001
                && focusQueryPIDs == [1001],
               "hover follows the native mouse target through a recording overlay without querying the overlay")
        expect(queryFocusWindow([recordingOverlay, foreignFocusWindow], pointerWindowID: 17) == nil
                && focusQueryPIDs.isEmpty,
               "a recording overlay that actually receives input still blocks hover")
        expect(queryFocusWindow([foreignFocusWindow, secondForeignWindow], pointerWindowID: 16) == 1002
                && focusQueryPIDs == [1002],
               "an input-transparent ordinary window does not obscure the native target either")
        expect(queryFocusWindow([foreignFocusWindow], pointerWindowID: 0) == nil
                && focusQueryPIDs.isEmpty,
               "an unavailable native target never falls back to visual window order")
        expect(queryFocusWindow([foreignFocusWindow], pointerWindowID: 16) == nil
                && focusQueryPIDs.isEmpty,
               "a native target missing from the current window list never selects another window")
        expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow], pointerWindowID: 12) == nil
                && focusQueryPIDs.isEmpty,
               "a native target owned by this app is never queried through Accessibility")
        expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow], pointerWindowID: 12,
                                clickThroughWindowIDs: [12]) == nil && focusQueryPIDs.isEmpty,
               "a mismatched native target and own overlay list never redirects focus behind it")
        expect(queryFocusWindow([foreignFocusWindow, secondForeignWindow], querySucceeds: false) == nil
                && focusQueryPIDs == [1001],
               "an unanswered scoped query never falls through to another app")
        for foreignLayer in [-2_147_483_623, 4, 20, 24, 25] {
            var furniture = foreignFocusWindow
            furniture[kCGWindowLayer as String] = NSNumber(value: foreignLayer)
            expect(queryFocusWindow([furniture, secondForeignWindow]) == nil && focusQueryPIDs.isEmpty,
                   "hover stops at a surface outside the app window layers, at layer \(foreignLayer)")
        }
        var unknownDepth = foreignFocusWindow
        unknownDepth.removeValue(forKey: kCGWindowLayer as String)
        expect(queryFocusWindow([unknownDepth, secondForeignWindow]) == nil && focusQueryPIDs.isEmpty,
               "a surface of unknown depth is never taken for an app window")
    }

    static func runRestoreOrder(expect: (Bool, String) -> Void) {
        // MARK: Dock click with AX-blind apps (issue #200)

        expect(DockClickSupport.effectiveHasUnminimized(unminimizedCount: 2,
                                                        minimizedCount: 0,
                                                        windowServerSeesWindows: false),
               "AX-visible windows count as always")
        expect(DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                        minimizedCount: 0,
                                                        windowServerSeesWindows: true),
               "an AX-blind app with on-screen windows still minimizes")
        expect(!DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                         minimizedCount: 3,
                                                         windowServerSeesWindows: true),
               "minimized-only apps keep the restore path")
        expect(!DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                         minimizedCount: 0,
                                                         windowServerSeesWindows: false),
               "a truly windowless app passes the click through")
        expect(!DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                                to: CGPoint(x: 103, y: 103)),
               "click jitter stays a click")
        expect(!DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                                to: CGPoint(x: 106, y: 100)),
               "movement at the slop boundary still counts as a click")
        expect(DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                               to: CGPoint(x: 105, y: 105)),
               "a real drag crosses the slop and hands the press to the Dock")
        expect(DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                               to: CGPoint(x: 100, y: 93)),
               "vertical pulls count as drags too")

        // MARK: Dock click restore order (issue #357)

        // The AX array order is deliberately unhelpful in these cases: the
        // captured WindowServer stacking is what has to decide the outcome.
        expect(DockClickSupport.restoreSequence(ids: [10, 20], frontToBack: [10, 20]) == [1, 0],
               "the window that was frontmost is restored last so it lands on top")
        expect(DockClickSupport.restoreSequence(ids: [10, 20], frontToBack: [20, 10]) == [0, 1],
               "the batch follows the captured stacking, not the order it arrived in")
        expect(DockClickSupport.restoreSequence(ids: [10, 20, 30], frontToBack: [20, 30, 10]) == [0, 2, 1],
               "a three window batch rebuilds the captured stacking bottom up")
        expect(DockClickSupport.restoreSequence(ids: [10, 20, 10, 20], frontToBack: [10, 20]) == [1, 0],
               "the same window captured twice is restored once, in its captured slot")
        expect(DockClickSupport.restoreSequence(ids: [10, 40], frontToBack: [10, 20]) == [1, 0],
               "a window missing from the capture counts as rearmost and restores first")
        expect(DockClickSupport.restoreSequence(ids: [10], frontToBack: [10]) == [0],
               "a single window restores as itself")
        expect(DockClickSupport.restoreSequence(ids: [], frontToBack: []).isEmpty,
               "an empty batch stays empty")
        expect(DockClickSupport.restoreSequence(ids: [10, 20, 30],
                                                frontToBack: [],
                                                preferredFront: 20) == [0, 2, 1],
               "with no capture the app's main window is moved to the end")
        expect(DockClickSupport.restoreSequence(ids: [10, 20], frontToBack: [], preferredFront: nil) == [0, 1],
               "with nothing to go on the batch keeps the order it arrived in")
        expect(DockClickSupport.restoreSequence(ids: [nil, nil], frontToBack: []) == [0, 1],
               "unresolvable windows are never deduped away")
    }
}
