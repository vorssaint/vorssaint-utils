// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum AlwaysOnTopTests {
    static func run(_ suite: TestSuite) {
        reveal(suite)
        hover(suite)
        coverageChanges(suite)
        coverage(suite)
        handOver(suite)
        wiring(suite)
    }

    private typealias Support = AlwaysOnTopSupport

    private static func reveal(_ suite: TestSuite) {
        let (covered, coverEffects) = Support.reduce(.uncovered, .coverage(.covered), reveal: .click)
        suite.expect(covered == .mirroring && coverEffects == [.startCapture, .showMirror],
               "a covered pin starts its capture and shows the mirror")
        let (clear, clearEffects) = Support.reduce(.mirroring, .coverage(.clear), reveal: .click)
        suite.expect(clear == .uncovered && clearEffects == [.hideMirror(fade: false), .stopCapture],
               "an uncovered pin hides the mirror and stops capturing")
        let (offSpace, _) = Support.reduce(.uncovered, .coverage(.offSpace), reveal: .click)
        suite.expect(offSpace == .mirroring, "a pin follows the user onto another Space as a mirror")

        let (handing, handEffects) = Support.reduce(.mirroring, .click, reveal: .click)
        suite.expect(handing == .handingOver(peek: false) && handEffects == [.beginHandOver],
               "a click on the mirror asks the real window forward and keeps the mirror up")
        let (stillHanding, ignored) = Support.reduce(handing, .coverage(.clear), reveal: .click)
        suite.expect(stillHanding == handing && ignored.isEmpty,
               "coverage changes during a hand-over are left to the hand-over")
        let (revealed, revealEffects) = Support.reduce(handing, .handOverConfirmed, reveal: .click)
        suite.expect(revealed == .revealed(peek: false)
                && revealEffects == [.hideMirror(fade: true), .coolCapture],
               "a confirmed reveal fades the mirror and keeps capture warm briefly, with no peek watch")
        let (failed, failEffects) = Support.reduce(handing, .handOverTimedOut, reveal: .click)
        suite.expect(failed == .mirroring && failEffects == [.cancelHandOver, .showNotForward],
               "a window that does not come forward keeps the mirror and says so")
        let (backToMirror, backEffects) = Support.reduce(revealed, .coverage(.covered), reveal: .click)
        suite.expect(backToMirror == .mirroring && backEffects == [.startCapture, .showMirror],
               "a revealed window covered again goes back to the mirror")
        let (stays, stayEffects) = Support.reduce(revealed, .coverage(.clear), reveal: .click)
        suite.expect(stays == revealed && stayEffects.isEmpty,
               "a revealed window stays revealed while nothing covers it")
        let (clickMode, clickModeEffects) = Support.reduce(.mirroring, .pointerEntered(onViewedSpace: true),
                                                          reveal: .click)
        suite.expect(clickMode == .mirroring && clickModeEffects.isEmpty,
               "in click mode a hover does nothing")
        let (uncoveredClick, uncoveredEffects) = Support.reduce(.uncovered, .click, reveal: .click)
        suite.expect(uncoveredClick == .uncovered && uncoveredEffects.isEmpty,
               "with no mirror up there is nothing to reveal")
    }

    private static func hover(_ suite: TestSuite) {
        let (waiting, waitEffects) = Support.reduce(.mirroring, .pointerEntered(onViewedSpace: true), reveal: .hover)
        suite.expect(waiting == .waitingForHover && waitEffects == [.startHoverDelay],
               "a hover waits for the delay before it reveals")
        let (passed, passEffects) = Support.reduce(waiting, .pointerExited, reveal: .hover)
        suite.expect(passed == .mirroring && passEffects == [.cancelHoverDelay],
               "a pointer passing through before the delay does nothing")
        let (offSpace, offEffects) = Support.reduce(.mirroring, .pointerEntered(onViewedSpace: false), reveal: .hover)
        suite.expect(offSpace == .mirroring && offEffects.isEmpty,
               "a hover never travels to another Space")
        let (peeking, peekStart) = Support.reduce(waiting, .hoverDelayElapsed, reveal: .hover)
        suite.expect(peeking == .handingOver(peek: true) && peekStart == [.beginHandOver],
               "the hover delay starts a peek")
        let (cancelled, cancelEffects) = Support.reduce(peeking, .pointerExited, reveal: .hover)
        suite.expect(cancelled == .mirroring && cancelEffects == [.cancelHandOver],
               "leaving during a peek's hand-over cancels it without a message")
        let (committed, commitEffects) = Support.reduce(peeking, .click, reveal: .hover)
        suite.expect(committed == .handingOver(peek: false) && commitEffects.isEmpty,
               "a click during a peek's hand-over makes it a full reveal")
        let (clickedWhileWaiting, clickEffects) = Support.reduce(waiting, .click, reveal: .hover)
        suite.expect(clickedWhileWaiting == .handingOver(peek: false)
                && clickEffects == [.cancelHoverDelay, .beginHandOver],
               "a click before the hover delay reveals at once")
        let (peek, peekEffects) = Support.reduce(peeking, .handOverConfirmed, reveal: .hover)
        suite.expect(peek == .revealed(peek: true)
                && peekEffects == [.hideMirror(fade: true), .coolCapture, .watchPeek],
               "a confirmed peek watches for the pointer leaving or for input")
        let (left, leftEffects) = Support.reduce(peek, .peekPointerLeft, reveal: .hover)
        suite.expect(left == .revealed(peek: false) && leftEffects == [.stopWatchingPeek, .returnFocus],
               "leaving a peek without input gives focus back")
        let (kept, keptEffects) = Support.reduce(peek, .peekInput, reveal: .hover)
        suite.expect(kept == .revealed(peek: false) && keptEffects == [.stopWatchingPeek],
               "a click or a keypress during a peek keeps the window in front")
        let (coveredPeek, coveredEffects) = Support.reduce(peek, .coverage(.covered), reveal: .hover)
        suite.expect(coveredPeek == .mirroring
                && coveredEffects == [.stopWatchingPeek, .startCapture, .showMirror],
               "a peek covered by switching apps ends its watch and mirrors again")
        let (clearedWhileWaiting, clearedEffects) = Support.reduce(waiting, .coverage(.clear), reveal: .hover)
        suite.expect(clearedWhileWaiting == .uncovered
                && clearedEffects == [.cancelHoverDelay, .hideMirror(fade: false), .stopCapture],
               "a pin uncovered while a hover waits drops the hover")
    }

    private static func coverageChanges(_ suite: TestSuite) {
        let (parked, parkEffects) = Support.reduce(.mirroring, .coverage(.parked), reveal: .click)
        suite.expect(parked == .parked && parkEffects == [.hideMirror(fade: false), .stopCapture],
               "a minimized or hidden window is not mirrored")
        let (restored, restoreEffects) = Support.reduce(.parked, .coverage(.covered), reveal: .click)
        suite.expect(restored == .mirroring && restoreEffects == [.startCapture, .showMirror],
               "a restored window that is covered is mirrored again")
        let (restoredClear, restoredClearEffects) = Support.reduce(.parked, .coverage(.clear), reveal: .click)
        suite.expect(restoredClear == .uncovered && restoredClearEffects.isEmpty,
               "a restored window in plain view needs nothing")
        let (parkedPeek, parkedPeekEffects) = Support.reduce(.revealed(peek: true), .coverage(.parked), reveal: .hover)
        suite.expect(parkedPeek == .parked
                && parkedPeekEffects == [.stopWatchingPeek, .hideMirror(fade: false), .stopCapture],
               "minimizing during a peek ends the peek watch")
    }

    private static func coverage(_ suite: TestSuite) {
        let own: pid_t = 10
        let dock: pid_t = 20
        let app: pid_t = 30
        let other: pid_t = 40
        let target = AlwaysOnTopWindowEntry(id: 100, pid: app, layer: 0,
                                            bounds: CGRect(x: 100, y: 100, width: 600, height: 400), alpha: 1)
        func coverage(_ above: [AlwaysOnTopWindowEntry], parked: Bool = false,
                      list: [AlwaysOnTopWindowEntry]? = nil) -> AlwaysOnTopCoverage {
            Support.coverage(of: target.id, onScreen: list ?? above + [target], isParked: parked,
                             ownPID: own, ignoredPIDs: [dock], systemLevel: 20)
        }
        func window(_ id: CGWindowID, _ pid: pid_t, _ rect: CGRect, layer: Int = 0, alpha: Double = 1)
            -> AlwaysOnTopWindowEntry {
            AlwaysOnTopWindowEntry(id: id, pid: pid, layer: layer, bounds: rect, alpha: alpha)
        }

        suite.expect(coverage([]) == .clear, "a window at the front is clear")
        suite.expect(coverage([window(1, other, CGRect(x: 650, y: 450, width: 300, height: 300))]) == .covered,
               "another app's window overlapping a corner covers it")
        suite.expect(coverage([window(1, other, CGRect(x: 800, y: 100, width: 300, height: 300))]) == .clear,
               "a window beside it does not cover it")
        suite.expect(coverage([window(1, dock, CGRect(x: 0, y: 0, width: 1800, height: 1169), layer: 20)]) == .clear
                && coverage([window(1, dock, CGRect(x: 0, y: 0, width: 1800, height: 1169))]) == .clear,
               "the Dock's transparent full-screen window never covers a pin")
        suite.expect(coverage([window(1, own, target.bounds)]) == .clear,
               "Vorssaint's own overlay never covers the window it stands in for")
        suite.expect(coverage([window(1, other, target.bounds, layer: 25)]) == .clear,
               "menu bar and system levels are not covering windows")
        suite.expect(coverage([window(1, other, target.bounds, layer: 3)]) == .covered,
               "another app's floating panel over it covers it")
        suite.expect(coverage([window(1, other, target.bounds, alpha: 0)]) == .clear,
               "an invisible window does not cover it")
        suite.expect(coverage([window(1, app, CGRect(x: 106, y: 106, width: 66, height: 20))]) == .clear,
               "a small window of the same app inside it, like a title chip or tooltip, belongs to it")
        suite.expect(coverage([window(1, app, CGRect(x: 400, y: 300, width: 600, height: 400))]) == .covered,
               "another window of the same app overlapping it covers it")
        suite.expect(coverage([], list: [window(1, other, target.bounds)]) == .offSpace,
               "a window missing from the on-screen list lives on another Space")
        suite.expect(coverage([], parked: true, list: []) == .parked,
               "a minimized or hidden window is parked, not on another Space")
    }

    private static func handOver(_ suite: TestSuite) {
        func confirmed(front: pid_t?, focused: CGWindowID?, _ coverage: AlwaysOnTopCoverage) -> Bool {
            Support.handOverConfirmed(frontmostPID: front, appPID: 30, ownerPID: 31,
                                      focusedWindowID: focused, windowID: 100, coverage: coverage)
        }
        suite.expect(!confirmed(front: 40, focused: 100, .clear),
               "a reveal is not done while another app is frontmost")
        suite.expect(confirmed(front: 30, focused: nil, .clear) && confirmed(front: 31, focused: nil, .clear),
               "the app, or the helper that owns its window, frontmost with the window clear is done")
        suite.expect(confirmed(front: 30, focused: 100, .covered),
               "the app reporting the pinned window as focused is done even if a child window sits on it")
        suite.expect(!confirmed(front: 30, focused: 101, .covered),
               "a sibling window focused over it is not done")
        suite.expect(!confirmed(front: 30, focused: 100, .offSpace),
               "a reveal still travelling to another Space is not done")

        let appKit = Support.appKitFrame(windowServerFrame: CGRect(x: 100, y: 50, width: 400, height: 300),
                                         primaryScreenMaxY: 1000)
        suite.expect(appKit == CGRect(x: 100, y: 650, width: 400, height: 300),
               "window-server frames flip to AppKit's bottom-left origin")
        let pixels = Support.streamPixelSize(for: CGRect(x: 0, y: 0, width: 611, height: 438), scale: 2)
        suite.expect(pixels.width == 1222 && pixels.height == 876, "the stream matches the window in pixels")
    }

    private static func wiring(_ suite: TestSuite) {
        let feature = AppFeature.alwaysOnTop
        suite.expect(feature.group == .windowsDock
                && feature.permissions == [.accessibility, .screenRecording]
                && !feature.installedByDefault
                && feature.enabledKeys == [DefaultsKey.alwaysOnTopEnabled],
               "Always On Top is an opt-in Windows feature that needs Accessibility and Screen Recording")
        suite.expect(feature.settingsDestination == FeatureSettingsDestination(.alwaysOnTop)
                && FeatureVisibilitySupport.features(for: .alwaysOnTop) == [.alwaysOnTop],
               "Always On Top has its own Settings page")
        suite.expect(GlobalShortcutRole.alwaysOnTop.feature == .alwaysOnTop
                && GlobalShortcutRole.alwaysOnTop.storageKey == DefaultsKey.alwaysOnTopShortcut
                && GlobalShortcutRole.alwaysOnTop.defaultShortcut == .alwaysOnTopDefault
                && GlobalShortcutRole.alwaysOnTop.requiredEnableKeys == [DefaultsKey.alwaysOnTopEnabled],
               "the pin shortcut is a role of its own, live only while the feature is on")
        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.alwaysOnTopEnabled] as? Bool == false
                && registered[DefaultsKey.alwaysOnTopReveal] as? String == AlwaysOnTopReveal.click.rawValue
                && registered[DefaultsKey.alwaysOnTopBorder] as? String == AlwaysOnTopBorder.medium.rawValue
                && registered[DefaultsKey.alwaysOnTopBorderColor] as? String == ""
                && registered[DefaultsKey.alwaysOnTopShortcut] as? String == GlobalShortcut.alwaysOnTopDefault.storageValue
                && (registered[DefaultsKey.alwaysOnTopExcludedApps] as? [String])?.isEmpty == true,
               "Always On Top starts off, revealing on click, with a medium border and nothing excluded")
        suite.expect(AlwaysOnTopBorder.allCases.map(\.width) == [0, 1, 2, 4],
               "the border goes from none to thick, getting wider each step")
        suite.expect(AlwaysOnTopBorder.colorHex(nil) == nil
                && AlwaysOnTopBorder.colorHex("") == nil
                && AlwaysOnTopBorder.colorHex("not a colour") == nil
                && AlwaysOnTopBorder.colorHex("#ff9f0a") == "#FF9F0A",
               "the border follows the accent colour until a valid colour is picked")
        let backupKeys = SettingsBackupSupport.exportKeys()
        suite.expect([DefaultsKey.alwaysOnTopEnabled, DefaultsKey.alwaysOnTopShortcut,
                      DefaultsKey.alwaysOnTopReveal, DefaultsKey.alwaysOnTopBorder, DefaultsKey.alwaysOnTopBorderColor,
                      DefaultsKey.alwaysOnTopExcludedApps]
                        .allSatisfy(backupKeys.contains),
               "Always On Top choices travel with the settings backup")
    }
}
