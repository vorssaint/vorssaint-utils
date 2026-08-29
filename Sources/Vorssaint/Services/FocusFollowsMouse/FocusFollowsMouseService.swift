// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

final class FocusFollowsMouseService {
    static let shared = FocusFollowsMouseService()

    /// No cap is written on this element: it is the system-wide object, and a
    /// timeout there is the process-wide default (#938). This service is the
    /// one that can least afford to set it — its queries run on `queryQueue`,
    /// so a slow answer costs it nothing but a focus change deferred to the
    /// next tick, while three features that stall the main thread inside an
    /// event tap were inheriting whatever it wrote. The elements this hit test
    /// returns are capped below.
    private let systemElement = AXUIElementCreateSystemWide()
    private let queryQueue = DispatchQueue(label: "com.vorssaint.focus-follows-mouse")
    private var timer: Timer?
    private var mouseMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var state = FocusFollowsMouseState()
    private var delayMilliseconds = FocusFollowsMouseSupport.defaultDelayMilliseconds
    private var isRunning = false

    private init() {}

    func syncWithPreferences() {
        let wanted = AppFeature.focusFollowsMouse.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.focusFollowsMouseEnabled)
        if wanted, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    func preferencesDidChange() {
        delayMilliseconds = Self.savedDelay()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        state.reset()
        isRunning = false
    }

    private func start() {
        guard !isRunning else {
            preferencesDidChange()
            return
        }
        delayMilliseconds = Self.savedDelay()
        guard let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .mouseMoved,
            handler: { [weak self] event in
                guard let point = event.cgEvent?.location else { return }
                self?.recordMovement(to: point)
            }
        ) else { return }
        self.mouseMonitor = mouseMonitor

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            self?.state.reset()
        })
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            self?.state.reset()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.state.reset() })

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.evaluateIfSettled() }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    private func recordMovement(to point: CGPoint) {
        if Thread.isMainThread {
            state.recordMovement(to: point, at: ProcessInfo.processInfo.systemUptime)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.state.recordMovement(to: point, at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private func evaluateIfSettled() {
        guard AXIsProcessTrusted(), !buttonsArePressed,
              NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              let evaluation = state.nextEvaluation(
                  at: ProcessInfo.processInfo.systemUptime,
                  delayMilliseconds: delayMilliseconds)
        else { return }

        queryQueue.async { [weak self] in
            guard let self, let target = self.target(at: evaluation.point) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, self.state.isCurrent(evaluation),
                      let app = NSRunningApplication(processIdentifier: target.processID),
                      app.activationPolicy == .regular, !app.isTerminated,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processID
                          || !target.isFocused
                else { return }
                WindowActivator.activate(pid: target.processID,
                                         windowID: target.windowID,
                                         appName: app.localizedName ?? "",
                                         retry: false)
            }
        }
    }

    private var buttonsArePressed: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
            || CGEventSource.buttonState(.combinedSessionState, button: .center)
    }

    private func target(at point: CGPoint) -> Target? {
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &rawElement) == .success,
              let rawElement
        else { return nil }
        AXUIElementSetMessagingTimeout(rawElement, 0.25)
        guard let window = topLevelWindow(from: rawElement, cappedAt: 0.25) else { return nil }
        guard stringAttribute(window, kAXRoleAttribute as String) == (kAXWindowRole as String),
              let windowID = AXWindowResolver.windowID(for: window)
        else { return nil }

        var processID: pid_t = 0
        guard AXUIElementGetPid(window, &processID) == .success,
              processID != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return Target(processID: processID,
                      windowID: windowID,
                      isFocused: boolAttribute(window, kAXFocusedAttribute as String))
    }

    /// The cap is the caller's, and written here rather than where the result
    /// is used: an element read out of another one is a fresh element and takes
    /// the process-wide default, so a caller that forgets puts every read off it
    /// on the global.
    private func topLevelWindow(from element: AXUIElement, cappedAt timeout: Float) -> AXUIElement? {
        if stringAttribute(element, kAXRoleAttribute as String) == (kAXWindowRole as String) {
            return element
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, timeout)
        return window
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func savedDelay() -> Int {
        FocusFollowsMouseSupport.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.focusFollowsMouseDelay))
    }

    private struct Target {
        let processID: pid_t
        let windowID: CGWindowID
        let isFocused: Bool
    }
}
