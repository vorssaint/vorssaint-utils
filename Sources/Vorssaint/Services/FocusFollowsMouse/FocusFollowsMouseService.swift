// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

final class FocusFollowsMouseService {
    static let shared = FocusFollowsMouseService()

    /// No cap on this one: on the system-wide element a timeout is the default
    /// for every question this process asks, whoever asks it (#938).
    private let systemElement = AXUIElementCreateSystemWide()
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
        guard AXIsProcessTrusted(),
              NSEvent.pressedMouseButtons == 0,
              NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              let evaluation = state.nextEvaluation(
                  at: ProcessInfo.processInfo.systemUptime,
                  delayMilliseconds: delayMilliseconds),
              !MouseAppExceptions.shared.excludesPointerTarget(
                  .focusFollowsMouse, at: evaluation.point)
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

    private func target(at point: CGPoint) -> Target? {
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &rawElement) == .success,
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
                      isFocused: boolAttribute(window, kAXFocusedAttribute as String))
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
