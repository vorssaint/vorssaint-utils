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
///     and older macOS also honors the Space of the fronted window.
///  2. If the Space still is not visible, the user's own "move a space"
///     shortcut is replayed (key and modifiers read from the system, honoring
///     remaps; skipped entirely when the user disabled it), one step at a
///     time, checking after each press that the Space actually changed.
///  3. Once the window's Space is visible, Accessibility can finally see the
///     window and the regular focus pass raises it.
///
/// Every stage degrades to plain app activation, which is what happened before
/// these windows were listed at all. The object only exists for the couple of
/// seconds an activation takes and cancels itself when a newer activation
/// starts.
final class SpaceHop {
    private static var current: SpaceHop?

    /// Hands the activation over to a hop when the selected window sits on a
    /// hidden Space and Accessibility cannot resolve it (a minimized window
    /// keeps its Accessibility element even when it came from another Space,
    /// and stays on the regular path). Returns false when the regular
    /// activation path should proceed.
    static func beginIfNeeded(windowID: CGWindowID,
                              appPID: pid_t,
                              windowOwnerPID: pid_t,
                              app: NSRunningApplication) -> Bool {
        guard let topology = SpaceWindowBridge.topology(),
              SpaceWindowBridge.isParkedOnHiddenSpace(windowID, visibleSpaces: topology.visibleSpaces),
              !WindowActivator.canResolveAXWindow(windowID: windowID, pid: windowOwnerPID)
        else { return false }
        cancelPending()
        let hop = SpaceHop(windowID: windowID, appPID: appPID, windowOwnerPID: windowOwnerPID, app: app)
        current = hop
        hop.start()
        return true
    }

    static func cancelPending() {
        current?.cancelled = true
        current = nil
    }

    private let windowID: CGWindowID
    private let appPID: pid_t
    private let windowOwnerPID: pid_t
    private let app: NSRunningApplication
    private var cancelled = false
    private var arrowPressesLeft = SpaceHopSupport.maximumArrowSteps

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
        let activateAllWindows = !appHasWindowOnVisibleSpace()
        NSApp.yieldActivation(to: app)
        if !app.activate(from: NSRunningApplication.current,
                         options: activateAllWindows ? [.activateAllWindows] : []) {
            app.activate(options: activateAllWindows ? [.activateAllWindows] : [])
        }
        // Native travel (and older-macOS window-server travel) animates for
        // roughly half a second; check twice before replaying shortcuts.
        schedule(after: 0.5) { self.verifyTravel(remainingChecks: 1) }
    }

    private func verifyTravel(remainingChecks: Int) {
        guard !cancelled else { return }
        if windowSpaceIsVisible() {
            focusOnArrival()
            return
        }
        if remainingChecks > 0 {
            schedule(after: 0.45) { self.verifyTravel(remainingChecks: remainingChecks - 1) }
            return
        }
        stepWithSpaceShortcut()
    }

    /// The hop is over (arrived, gave up or was replaced); drop the keep-alive.
    private func finish() {
        if SpaceHop.current === self { SpaceHop.current = nil }
    }

    /// One press of the user's "move a space" shortcut toward the target,
    /// re-deciding the direction from a fresh topology every step and stopping
    /// the moment a press changes nothing (shortcut intercepted, edge of the
    /// row, topology changed under us).
    private func stepWithSpaceShortcut() {
        guard !cancelled, arrowPressesLeft > 0 else { finish(); return }
        arrowPressesLeft -= 1
        guard let topology = SpaceWindowBridge.topology(),
              let targetSpace = SpaceWindowBridge.spaces(of: windowID).first,
              let steps = SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: topology.orderedSpacesPerDisplay,
                                                    visibleSpaces: topology.visibleSpaces,
                                                    target: targetSpace),
              let shortcut = SpaceWindowBridge.spaceShortcut(steps > 0 ? .right : .left)
        else { finish(); return }
        let visibleBefore = topology.visibleSpaces
        SpaceWindowBridge.pressSpaceShortcut(shortcut)
        schedule(after: 0.5) {
            guard !self.cancelled else { return }
            if self.windowSpaceIsVisible() {
                self.focusOnArrival()
                return
            }
            guard SpaceWindowBridge.topology()?.visibleSpaces != visibleBefore else {
                self.finish()
                return
            }
            self.stepWithSpaceShortcut()
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
