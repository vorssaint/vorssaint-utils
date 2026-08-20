// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Takes a switcher or dock-preview selection to a window that lives on a
/// Space the user is not looking at (issue #339). Accessibility cannot focus
/// what it cannot see, so the hop runs in stages, each one verified against
/// the window server and escalating only when the previous stage did not make
/// the window's Space visible:
///
///  1. The window server is asked to front the exact window and the app is
///     activated cooperatively. When the app has no window on any visible
///     Space, macOS itself travels to one that has (standard system behavior),
///     and older macOS also honors the Space of the fronted window. When the
///     app does have a window here, that travel cannot happen, so this stage
///     is not waited on at all.
///  2. If the Space still is not visible, the user's own "move a space"
///     shortcut is replayed (key and modifiers read from the system, honoring
///     remaps; skipped entirely when the user disabled it), one step at a
///     time, checking after each press that the Space actually changed.
///  3. Once the window's Space is visible, Accessibility can finally see the
///     window and the regular focus pass raises it.
///
/// Waiting is done by watching the window server, never by sleeping a fixed
/// amount. The new Space is only reported once its animation finishes, so a
/// single check at a chosen moment either fires before the arrival or costs
/// more time than the switch actually took.
///
/// Every stage degrades to plain app activation, which is what happened before
/// these windows were listed at all. The object only exists for the couple of
/// seconds an activation takes and cancels itself when a newer activation
/// starts.
final class SpaceHop {
    private static var current: SpaceHop?

    /// How often the window server is asked whether the Space arrived, and how
    /// long a single switch is given before the hop escalates or gives up. The
    /// switch animation is reported after roughly half a second, so the window
    /// leaves room for a slower machine without ever pressing again mid flight.
    private static let arrivalPollInterval: TimeInterval = 0.05
    private static let arrivalTimeout: TimeInterval = 1.2

    /// Hands the activation over to a hop when the selected window sits on a
    /// hidden Space. Returns false when the regular activation path should
    /// proceed.
    static func beginIfNeeded(windowID: CGWindowID,
                              appPID: pid_t,
                              windowOwnerPID: pid_t,
                              app: NSRunningApplication) -> Bool {
        guard let topology = SpaceWindowBridge.topology(),
              SpaceWindowBridge.isParkedOnHiddenSpace(windowID, visibleSpaces: topology.visibleSpaces)
        else { return false }
        cancelPending()
        let hop = SpaceHop(windowID: windowID, appPID: appPID, windowOwnerPID: windowOwnerPID, app: app)
        current = hop
        hop.start()
        return true
    }

    static func cancelPending() {
        current?.restoreCursorIfNeeded()
        current?.cancelled = true
        current = nil
    }

    private let windowID: CGWindowID
    private let appPID: pid_t
    private let windowOwnerPID: pid_t
    private let app: NSRunningApplication
    private var cancelled = false
    private var arrowPressesLeft = SpaceHopSupport.maximumArrowSteps
    private var originalCursorLocation: CGPoint?
    private var warpedCursorLocation: CGPoint?

    private init(windowID: CGWindowID, appPID: pid_t, windowOwnerPID: pid_t, app: NSRunningApplication) {
        self.windowID = windowID
        self.appPID = appPID
        self.windowOwnerPID = windowOwnerPID
        self.app = app
    }

    private func start() {
        app.unhide()
        SpaceWindowBridge.frontWindow(windowID, ownerPID: windowOwnerPID)
        // Activating every window would drag the app's windows on the current
        // Space forward too; when the app has one here, activate quietly and
        // let the travel decide what comes up.
        let appIsAlreadyHere = appHasWindowOnVisibleSpace()
        NSApp.yieldActivation(to: app)
        if !app.activate(from: NSRunningApplication.current,
                         options: appIsAlreadyHere ? [] : [.activateAllWindows]) {
            app.activate(options: appIsAlreadyHere ? [] : [.activateAllWindows])
        }
        switch SpaceHopSupport.firstStage(appHasWindowOnVisibleSpace: appIsAlreadyHere) {
        case .moveASpace:
            stepWithSpaceShortcut()
        case .waitForActivationTravel:
            let visibleBefore = SpaceWindowBridge.topology()?.visibleSpaces ?? []
            waitForTravel(from: visibleBefore) { outcome in
                if outcome == .arrived {
                    self.focusOnArrival()
                } else {
                    self.stepWithSpaceShortcut()
                }
            }
        }
    }

    /// How a travel attempt ended.
    private enum TravelOutcome {
        /// The window's Space is the one showing now.
        case arrived
        /// Another Space came up, so the attempt worked but landed short.
        case landedShort
        /// Nothing moved in the time a switch takes.
        case stalled
    }

    /// Watches the window server after a travel attempt. The new Space is only
    /// reported once its animation ends, so this waits for the outcome instead
    /// of guessing how long that takes.
    private func waitForTravel(from visibleBefore: Set<UInt64>,
                                deadline: DispatchTime? = nil,
                                then completion: @escaping (TravelOutcome) -> Void) {
        let deadline = deadline ?? .now() + Self.arrivalTimeout
        schedule(after: Self.arrivalPollInterval) {
            guard !self.cancelled else { return }
            guard let visibleNow = SpaceWindowBridge.topology()?.visibleSpaces else {
                completion(.stalled)
                return
            }
            if !SpaceWindowBridge.isParkedOnHiddenSpace(self.windowID, visibleSpaces: visibleNow) {
                completion(.arrived)
            } else if visibleNow != visibleBefore {
                completion(.landedShort)
            } else if .now() < deadline {
                self.waitForTravel(from: visibleBefore, deadline: deadline, then: completion)
            } else {
                completion(.stalled)
            }
        }
    }

    /// The hop is over (arrived, gave up or was replaced); drop the keep-alive.
    private func finish() {
        restoreCursorIfNeeded()
        if SpaceHop.current === self { SpaceHop.current = nil }
    }

    private func restoreCursorIfNeeded() {
        guard let original = originalCursorLocation,
              let warped = warpedCursorLocation else { return }
        originalCursorLocation = nil
        warpedCursorLocation = nil
        if let current = CGEvent(source: nil)?.location,
           abs(current.x - warped.x) < 2 && abs(current.y - warped.y) < 2 {
            CGWarpMouseCursorPosition(original)
        }
    }

    /// One press of the user's "move a space" shortcut toward the target,
    /// re-deciding the direction from a fresh topology every step and stopping
    /// the moment a press changes nothing (shortcut intercepted, edge of the
    /// row, topology changed under us).
    private func stepWithSpaceShortcut() {
        guard !cancelled else { return }
        if windowSpaceIsVisible() {
            focusOnArrival()
            return
        }
        guard arrowPressesLeft > 0 else { finish(); return }
        arrowPressesLeft -= 1
        guard let topology = SpaceWindowBridge.topology(),
              let targetSpace = SpaceWindowBridge.spaces(of: windowID).first,
              let steps = SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: topology.orderedSpacesPerDisplay,
                                                    visibleSpaces: topology.visibleSpaces,
                                                    target: targetSpace),
              let shortcut = SpaceWindowBridge.spaceShortcut(steps > 0 ? .right : .left)
        else {
            // When system Spaces shortcuts are disabled, try direct Accessibility activation as fallback
            focusOnArrival()
            return
        }
        if topology.displays.count > 1,
           let targetDisplay = topology.displays.first(where: { $0.spaces.contains(targetSpace) }),
           let displayID = targetDisplay.displayID {
            let bounds = CGDisplayBounds(displayID)
            let currentMouse = NSEvent.mouseLocation
            let screenFrame = NSScreen.screens.first(where: {
                (($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value) == displayID
            })?.frame
            if let screenFrame, !screenFrame.contains(currentMouse) {
                if originalCursorLocation == nil {
                    originalCursorLocation = CGEvent(source: nil)?.location
                }
                let targetPoint = CGPoint(x: bounds.midX, y: bounds.midY)
                warpedCursorLocation = targetPoint
                CGWarpMouseCursorPosition(targetPoint)
            }
        }
        let visibleBefore = topology.visibleSpaces
        SpaceWindowBridge.pressSpaceShortcut(shortcut)
        waitForTravel(from: visibleBefore) { outcome in
            switch outcome {
            case .arrived:
                self.focusOnArrival()
            case .landedShort:
                self.stepWithSpaceShortcut()
            case .stalled:
                // A press that moved nothing means the shortcut went elsewhere
                // or the row ended; stop instead of drumming on the keyboard.
                self.finish()
            }
        }
    }

    /// Accessibility starts describing the window shortly after its Space
    /// becomes visible; a couple of pulses cover the settling time.
    private func focusOnArrival() {
        for delay in [0.15, 0.45, 0.9] {
            schedule(after: delay) {
                guard !self.cancelled, !self.app.isTerminated else { return }
                WindowActivator.focusAfterSpaceHop(windowID: self.windowID,
                                                   appPID: self.appPID,
                                                   windowOwnerPID: self.windowOwnerPID)
            }
        }
        schedule(after: 1.0) { self.finish() }
    }

    /// Whether some visible Space now contains the target window.
    private func windowSpaceIsVisible() -> Bool {
        !SpaceWindowBridge.isParkedOnHiddenSpace(windowID)
    }

    /// An on-screen window (layer 0, visible) means the app is present on a
    /// visible Space, so activating it will not travel anywhere by itself.
    private func appHasWindowOnVisibleSpace() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { info in
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == appPID || ownerPID == windowOwnerPID,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0
            else { return false }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return alpha > 0
        }
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
