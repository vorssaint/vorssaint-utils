// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

final class FocusFollowsMouseService {
    static let shared = FocusFollowsMouseService()

    private let queryQueue = DispatchQueue(label: "com.vorssaint.focus-follows-mouse")
    private var timer: Timer?
    private var mouseMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var state = FocusFollowsMouseState()
    private var delayMilliseconds = FocusFollowsMouseSupport.defaultDelayMilliseconds
    private var isRunning = false

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let wanted = AppFeature.focusFollowsMouse.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.focusFollowsMouseEnabled)
        if SessionActivitySupport.tapShouldRun(
            featureWanted: wanted,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    func preferencesDidChange() {
        delayMilliseconds = Self.savedDelay()
    }

    func stop() {
        resetMovement()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        isRunning = false
    }

    private func start() {
        guard !isRunning else {
            preferencesDidChange()
            return
        }
        delayMilliseconds = Self.savedDelay()
        guard let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
            handler: { [weak self] event in
                guard let point = event.cgEvent?.location else { return }
                self?.recordMovement(to: point)
            }
        ) else { return }
        self.mouseMonitor = mouseMonitor

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            self?.resetMovement()
        })
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            self?.resetMovement()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.resetMovement() })
        isRunning = true
    }

    private func recordMovement(to point: CGPoint) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.recordMovement(to: point)
            }
            return
        }
        guard isRunning else { return }
        state.recordMovement(to: point, at: ProcessInfo.processInfo.systemUptime)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.evaluateIfSettled() }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func resetMovement() {
        state.reset()
        timer?.invalidate()
        timer = nil
    }

    /// Nothing held down: no mouse button pressed and no modifier. Asked
    /// again when the window query answers, because the query takes long
    /// enough for a click or a shortcut to begin while it runs, and a pointer
    /// that never moved keeps the answer looking current.
    private var nothingIsHeldDown: Bool {
        NSEvent.pressedMouseButtons == 0
            && NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }

    private func evaluateIfSettled() {
        defer {
            if !state.hasPendingEvaluation {
                timer?.invalidate()
                timer = nil
            }
        }
        guard AXIsProcessTrusted(),
              nothingIsHeldDown,
              let evaluation = state.nextEvaluation(
                  at: ProcessInfo.processInfo.systemUptime,
                  delayMilliseconds: delayMilliseconds),
              !MouseAppExceptions.shared.excludesPointerTarget(
                  .focusFollowsMouse, at: evaluation.point)
        else { return }

        // The window server's own answer to "what would a click here hit",
        // which the on-screen window list cannot express: it honours other
        // applications' click-through windows and the transparent parts of
        // shaped ones. It is AppKit, so it is asked here on the main thread.
        // The evaluation point is CoreGraphics (top-left origin) and this
        // wants Cocoa global coordinates, flipped against the primary screen
        // the way ``AssistiveKeyboard/ownsCocoaPoint(_:)`` flips them back.
        let cocoaPoint = NSPoint(x: evaluation.point.x,
                                 y: (NSScreen.screens.first?.frame.maxY ?? 0) - evaluation.point.y)
        let hitWindowNumber = NSWindow.windowNumber(at: cocoaPoint, belowWindowWithWindowNumber: 0)
        queryQueue.async { [weak self] in
            guard let self,
                  let target = self.target(at: evaluation.point,
                                           hitWindowNumber: hitWindowNumber)
            else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, self.nothingIsHeldDown,
                      self.state.isCurrent(evaluation),
                      let app = NSRunningApplication(processIdentifier: target.processID),
                      app.activationPolicy == .regular, !app.isTerminated,
                      FocusFollowsMouseSupport.shouldActivate(
                          targetWindowID: target.windowID,
                          focusedWindowID: target.focusedWindowID,
                          targetAppIsFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier
                              == target.processID)
                else { return }
                WindowActivator.activate(pid: target.processID,
                                         windowID: target.windowID,
                                         appName: app.localizedName ?? "",
                                         retry: false)
            }
        }
    }

    private func target(at point: CGPoint, hitWindowNumber: Int) -> Target? {
        // A system-wide hit test is served inside this process whenever the
        // pointer rests on one of its own windows, and that re-entry is the
        // deadlock (#1420). Only the application owning the window a click
        // would hit is asked, so this process never is. Turning the number
        // into its owner is a window server read: no main thread, no
        // Accessibility lock, so it belongs on this queue. The process check
        // further down stays as the invariant it now documents.
        //
        // The number is clamped because `CGWindowID` is unsigned; 0, which is
        // what the click target reads as over no window, describes nothing.
        let hitWindow = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow], CGWindowID(max(hitWindowNumber, 0))) as? [[String: Any]] ?? []
        guard let ownerProcessID = FocusFollowsMouseSupport.hitTestOwner(
            of: hitWindow,
            ownProcessID: ProcessInfo.processInfo.processIdentifier)
        else { return nil }

        // No cap here: the application element inherits the wait this process
        // installs for every element it asks (#938), as the system-wide one
        // this replaced did.
        let applicationElement = AXUIElementCreateApplication(ownerProcessID)
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(applicationElement, Float(point.x), Float(point.y), &rawElement) == .success,
              let rawElement
        else { return nil }
        AXUIElementSetMessagingTimeout(rawElement, 0.25)
        guard let window = topLevelWindow(from: rawElement) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.25)
        guard stringAttribute(window, kAXRoleAttribute as String) == (kAXWindowRole as String),
              let windowID = AXWindowResolver.windowID(for: window)
        else { return nil }

        var processID: pid_t = 0
        guard AXUIElementGetPid(window, &processID) == .success,
              processID != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return Target(processID: processID,
                      windowID: windowID,
                      focusedWindowID: WindowActivator.focusedWindowID(for: processID))
    }

    private func topLevelWindow(from element: AXUIElement) -> AXUIElement? {
        if stringAttribute(element, kAXRoleAttribute as String) == (kAXWindowRole as String) {
            return element
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func savedDelay() -> Int {
        FocusFollowsMouseSupport.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.focusFollowsMouseDelay))
    }

    private struct Target {
        let processID: pid_t
        let windowID: CGWindowID
        let focusedWindowID: CGWindowID?
    }
}
