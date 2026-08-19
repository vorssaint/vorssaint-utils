// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// Swift implementation inspired by AutoRaise by sbmpost. It deliberately uses
/// public Accessibility, AppKit and CoreGraphics APIs only.
final class AutoRaiseService: ObservableObject {
    static let shared = AutoRaiseService()

    @Published private(set) var isRunning = false

    private let systemElement = AXUIElementCreateSystemWide()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var hoverState = AutoRaiseHoverState()
    private var cachedConfiguration: AutoRaiseConfiguration?
    private var ignoredTitleRegexes: [NSRegularExpression] = []
    private var lastMousePoint: CGPoint?
    private var suppressUntil = Date.distantPast
    private var taskSwitchPending = false

    private init() {}

    func syncWithPreferences() {
        let wanted = AppFeature.autoRaise.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.autoRaiseEnabled)
        if wanted, Permissions.shared.accessibility { start() } else { stop() }
    }

    func preferencesDidChange() {
        guard isRunning else { syncWithPreferences(); return }
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        hoverState.reset()
        lastMousePoint = nil
        taskSwitchPending = false
        cachedConfiguration = nil
        ignoredTitleRegexes.removeAll()
        isRunning = false
    }

    private func start() {
        guard !isRunning else { restartTimer(); return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.hoverState.reset()
            if self.configuration.ignoreAfterSpaceChange {
                self.suppressUntil = Date().addingTimeInterval(0.65)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            self?.applicationActivated(note)
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.hoverState.reset()
        })
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command), event.keyCode == 48 || event.keyCode == 50 else { return }
            self?.taskSwitchPending = true
        }
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        let configuration = configuration
        cachedConfiguration = configuration
        ignoredTitleRegexes = configuration.ignoredTitlePatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
        let interval = Double(configuration.pollMilliseconds) / 1_000
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = min(interval * 0.25, 0.02)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var configuration: AutoRaiseConfiguration {
        let defaults = UserDefaults.standard
        return .sanitized(delay: defaults.integer(forKey: DefaultsKey.autoRaiseDelay),
                          poll: defaults.integer(forKey: DefaultsKey.autoRaisePollInterval),
                          requireMouseStop: defaults.bool(forKey: DefaultsKey.autoRaiseRequireMouseStop),
                          movementThreshold: defaults.double(forKey: DefaultsKey.autoRaiseMovementThreshold),
                          pauseModifier: defaults.string(forKey: DefaultsKey.autoRaisePauseModifier),
                          invertPauseModifier: defaults.bool(forKey: DefaultsKey.autoRaiseInvertPauseModifier),
                          ignoreAfterSpaceChange: defaults.bool(forKey: DefaultsKey.autoRaiseIgnoreAfterSpaceChange),
                          includeOnlyApps: defaults.bool(forKey: DefaultsKey.autoRaiseIncludeOnlyApps),
                          appBundleIDs: defaults.stringArray(forKey: DefaultsKey.autoRaiseAppBundleIDs) ?? [],
                          ignoredTitlePatterns: defaults.stringArray(forKey: DefaultsKey.autoRaiseIgnoredTitlePatterns) ?? [],
                          stayFocusedBundleIDs: defaults.stringArray(forKey: DefaultsKey.autoRaiseStayFocusedBundleIDs) ?? [],
                          warpAfterTaskSwitch: defaults.bool(forKey: DefaultsKey.autoRaiseWarpAfterTaskSwitch),
                          warpX: defaults.double(forKey: DefaultsKey.autoRaiseWarpX),
                          warpY: defaults.double(forKey: DefaultsKey.autoRaiseWarpY))
    }

    private func poll() {
        guard AXIsProcessTrusted(), Date() >= suppressUntil else { hoverState.reset(); return }
        guard let config = cachedConfiguration else { return }
        guard !isPaused(config), !CGEventSource.buttonState(.combinedSessionState, button: .left) else {
            hoverState.reset()
            return
        }

        guard let point = CGEvent(source: nil)?.location else { return }
        let moved = lastMousePoint.map { hypot(point.x - $0.x, point.y - $0.y) > config.movementThreshold } ?? true
        lastMousePoint = point
        guard let target = target(at: point, configuration: config) else {
            hoverState.reset()
            return
        }
        if hoverState.sample(windowID: target.windowID, mouseMoved: moved, configuration: config) {
            activate(target)
        }
    }

    private func isPaused(_ config: AutoRaiseConfiguration) -> Bool {
        let held: Bool
        switch config.pauseModifier {
        case .control: held = NSEvent.modifierFlags.contains(.control)
        case .option: held = NSEvent.modifierFlags.contains(.option)
        case .disabled: return false
        }
        return config.invertPauseModifier ? !held : held
    }

    private func target(at point: CGPoint, configuration: AutoRaiseConfiguration) -> Target? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &element) == .success,
              let element, let window = topLevelWindow(from: element),
              stringAttribute(window, kAXRoleAttribute) == (kAXWindowRole as String),
              !boolAttribute(window, "AXFullScreen"),
              let windowID = AXWindowResolver.windowID(for: window)
        else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              configuration.allows(bundleID: app.bundleIdentifier),
              !configuration.stayFocusedBundleIDs.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""),
              !ignores(title: stringAttribute(window, kAXTitleAttribute)),
              !isFocused(window: window, pid: pid)
        else { return nil }
        return Target(window: window, windowID: windowID, app: app)
    }

    private func ignores(title: String?) -> Bool {
        guard let title else { return false }
        let range = NSRange(title.startIndex..., in: title)
        return ignoredTitleRegexes.contains { $0.firstMatch(in: title, range: range) != nil }
    }

    private func activate(_ target: Target) {
        AXUIElementSetAttributeValue(target.window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        target.app.activate()
    }

    private func applicationActivated(_ note: Notification) {
        guard taskSwitchPending else { return }
        taskSwitchPending = false
        let config = configuration
        guard config.warpAfterTaskSwitch,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID(),
                  let frame = self.frame(of: value as! AXUIElement) else { return }
            let point = config.warpPoint(in: frame)
            CGWarpMouseCursorPosition(point)
        }
    }

    private func topLevelWindow(from element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<12 {
            if stringAttribute(current, kAXRoleAttribute) == (kAXWindowRole as String) { return current }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXWindowAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() { return (value as! AXUIElement) }
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            current = value as! AXUIElement
        }
        return nil
    }

    private func isFocused(window: AXUIElement, pid: pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        return boolAttribute(window, kAXFocusedAttribute as String)
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

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private struct Target {
        let window: AXUIElement
        let windowID: CGWindowID
        let app: NSRunningApplication
    }
}
