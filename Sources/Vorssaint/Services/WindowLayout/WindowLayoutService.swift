// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics

enum WindowLayoutError: Equatable {
    case missingAccessibility
    case noWindow
    case noRestore
    case failed
}

enum WindowLayoutResult: Equatable {
    case success(restored: Bool)
    case failure(WindowLayoutError)
}

/// Window placement through explicit panel actions, global shortcuts and an
/// optional pointer gesture. The event tap only performs Accessibility work
/// after the user presses an exact shown chord over a compatible window.
final class WindowLayoutService: ObservableObject {
    static let shared = WindowLayoutService()

    @Published private(set) var lastResult: WindowLayoutResult?
    @Published private(set) var failedShortcutActions: Set<WindowLayoutAction> = []
    @Published private(set) var isGestureRunning = false

    private var previousFrames: [CGWindowID: WindowLayoutFrame] = [:]
    private var lastActions: [CGWindowID: WindowLayoutAction] = [:]
    private var hotKeyRefs: [WindowLayoutAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var registeredShortcuts: [WindowLayoutAction: GlobalShortcut] = [:]
    private var gestureTap: CFMachPort?
    private var gestureRunLoopSource: CFRunLoopSource?
    private var activeGesture: WindowPointerGesture?
    private let frameTolerance: CGFloat = 8
    private let anchorTolerance: CGFloat = 36
    private let moveGestureUpdateInterval: TimeInterval = 1.0 / 120.0
    // AX frame mutations are not atomic. Complex windows can visibly render
    // the intermediate size and position when they receive resize writes at
    // pointer-reporting speed, so resize is deliberately coalesced to 60 Hz.
    private let resizeGestureUpdateInterval: TimeInterval = 1.0 / 60.0

    private init() {}

    func syncWithPreferences() {
        let available = AppFeature.windowLayout.isAvailable
        let trusted = AXIsProcessTrusted()
        let wantsShortcuts = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.windowLayoutShortcutsEnabled)
            && trusted
        wantsShortcuts ? registerHotkeys() : unregisterHotkeys()

        let wantsGesture = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureEnabled)
            && trusted
        wantsGesture ? startGestureTap() : stopGestureTap()
    }

    /// Stops every Window Layout input hook before Accessibility is revoked or
    /// the process terminates. Idempotent so permission and feature changes can
    /// call it freely.
    func suspend() {
        unregisterHotkeys()
        stopGestureTap()
    }

    func shortcutConflictTitle(_ shortcut: GlobalShortcut) -> String? {
        shortcutConflictTitle(shortcut, excluding: nil)
    }

    func shortcutConflictTitle(_ shortcut: GlobalShortcut, excluding excluded: WindowLayoutAction?) -> String? {
        let text = FeatureStrings.windowLayout(L10n.shared.language)
        return WindowLayoutAction.shortcutActions.first {
            $0 != excluded && $0.savedShortcut == shortcut
        }?.title(text)
    }

    @discardableResult
    func apply(_ action: WindowLayoutAction) -> WindowLayoutResult {
        guard AXIsProcessTrusted() else {
            return finish(.failure(.missingAccessibility))
        }
        guard let target = focusedTarget() else {
            return finish(.failure(.noWindow))
        }

        if action == .restore {
            guard let previous = previousFrames[target.windowID] else {
                return finish(.failure(.noRestore))
            }
            return setFrame(previous, on: target.window)
                ? finish(.success(restored: true))
                : finish(.failure(.failed))
        }

        guard let screen = bestScreen(for: target.frame) else {
            return finish(.failure(.failed))
        }
        let currentRect = appKitFrame(fromAX: target.frame)
        if action == .nextDisplay {
            guard let destination = nextScreen(after: screen) else {
                return finish(.failure(.failed))
            }
            let rect = WindowLayoutGeometry.rectForNextDisplay(current: currentRect,
                                                               sourceVisibleFrame: screen.visibleFrame,
                                                               destinationVisibleFrame: destination.visibleFrame)
            previousFrames[target.windowID] = target.frame
            if setFrame(axFrame(fromAppKit: rect),
                        targetRect: rect,
                        screenVisibleFrame: destination.visibleFrame,
                        action: .nextDisplay,
                        on: target.window) {
                lastActions[target.windowID] = .nextDisplay
                return finish(.success(restored: false))
            }
            previousFrames.removeValue(forKey: target.windowID)
            return finish(.failure(.failed))
        }
        let previousAction = lastActions[target.windowID]
        let effectiveAction = WindowLayoutGeometry.effectiveAction(for: action,
                                                                   current: currentRect,
                                                                   visibleFrame: screen.visibleFrame,
                                                                   previousAction: previousAction)
        let placement = placement(for: effectiveAction,
                                  current: target.frame,
                                  visibleFrame: screen.visibleFrame)
        previousFrames[target.windowID] = target.frame
        if setFrame(placement.frame,
                    targetRect: placement.rect,
                    screenVisibleFrame: screen.visibleFrame,
                    action: effectiveAction,
                    on: target.window) {
            lastActions[target.windowID] = effectiveAction
            return finish(.success(restored: false))
        }
        previousFrames.removeValue(forKey: target.windowID)
        return finish(.failure(.failed))
    }

    private func finish(_ result: WindowLayoutResult) -> WindowLayoutResult {
        lastResult = result
        return result
    }

    private func focusedTarget() -> WindowLayoutTarget? {
        let ownBundleID = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pids = ([frontmost].compactMap { $0 } + AppActivationTracker.shared.mru).reduce(into: [pid_t]()) { result, pid in
            if !result.contains(pid) { result.append(pid) }
        }

        for pid in pids {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }),
                  app.activationPolicy == .regular,
                  app.bundleIdentifier != ownBundleID
            else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            // Bounded AX: a hung app in the MRU list must not stall the main
            // thread (and every event tap) for the 6 second default timeout.
            AXUIElementSetMessagingTimeout(axApp, 0.35)
            for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                if let window = windowAttribute(axApp, attribute as String),
                   let target = target(from: window) {
                    return target
                }
            }
            if let windows = windowsAttribute(axApp),
               let first = windows.compactMap(target(from:)).first {
                return first
            }
        }
        return nil
    }

    private func target(from window: AXUIElement) -> WindowLayoutTarget? {
        guard role(of: window) == (kAXWindowRole as String),
              !boolAttribute(window, "AXFullScreen"),
              canSetFrame(on: window),
              let windowID = AXWindowResolver.windowID(for: window),
              let frame = frame(of: window),
              frame.size.width > 80,
              frame.size.height > 80
        else { return nil }
        return WindowLayoutTarget(window: window, windowID: windowID, frame: frame)
    }

    private func placement(for action: WindowLayoutAction,
                           current: WindowLayoutFrame,
                           visibleFrame: NSRect) -> WindowLayoutPlacement {
        let rect = WindowLayoutGeometry.rect(for: action,
                                             current: appKitFrame(fromAX: current),
                                             visibleFrame: visibleFrame)
        let integral = rect.integral
        return WindowLayoutPlacement(frame: axFrame(fromAppKit: integral), rect: integral)
    }

    private func setFrame(_ frame: WindowLayoutFrame, on window: AXUIElement) -> Bool {
        setFrame(frame,
                 targetRect: appKitFrame(fromAX: frame),
                 screenVisibleFrame: appKitFrame(fromAX: frame),
                 action: .restore,
                 on: window)
    }

    private func setFrame(_ frame: WindowLayoutFrame,
                          targetRect: NSRect,
                          screenVisibleFrame: NSRect,
                          action: WindowLayoutAction,
                          on window: AXUIElement) -> Bool {
        let original = self.frame(of: window)
        if attempt(frame, targetRect: targetRect, action: action, on: window) {
            return true
        }

        if let original, shouldUseMaximizeFallback(for: action) {
            let currentRect = appKitFrame(fromAX: original)
            let maxFrame = axFrame(fromAppKit: WindowLayoutGeometry.rect(for: .maximize,
                                                                         current: currentRect,
                                                                         visibleFrame: screenVisibleFrame))
            applyFrame(maxFrame, on: window)
            if attempt(frame, targetRect: targetRect, action: action, on: window) {
                return true
            }
        }

        if let original {
            applyFrame(original, on: window)
        }
        return false
    }

    private func attempt(_ frame: WindowLayoutFrame,
                         targetRect: NSRect,
                         action: WindowLayoutAction,
                         on window: AXUIElement) -> Bool {
        let visibleFrame = bestScreen(for: frame)?.visibleFrame ?? targetRect
        for _ in 0..<3 {
            applyFrame(frame,
                       targetRect: targetRect,
                       visibleFrame: visibleFrame,
                       action: action,
                       on: window)
            guard let actual = self.frame(of: window) else { continue }
            if actual.isClose(to: frame, tolerance: frameTolerance)
                || accepted(actual: actual, targetRect: targetRect, action: action) {
                return true
            }
        }
        return false
    }

    private func shouldUseMaximizeFallback(for action: WindowLayoutAction) -> Bool {
        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf,
                .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds,
                .topLeftSixth, .topCenterSixth, .topRightSixth,
                .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
                .topLeft, .topRight, .bottomLeft, .bottomRight:
            return true
        default:
            return false
        }
    }

    private func applyFrame(_ frame: WindowLayoutFrame, on window: AXUIElement) {
        _ = setSize(frame.size, on: window)
        _ = setPosition(frame.origin, on: window)
        _ = setSize(frame.size, on: window)
        _ = setPosition(frame.origin, on: window)
    }

    private func applyFrame(_ frame: WindowLayoutFrame,
                            targetRect: NSRect,
                            visibleFrame: NSRect,
                            action: WindowLayoutAction,
                            on window: AXUIElement) {
        let requestedRect = WindowLayoutGeometry.anchoredRect(for: action,
                                                              targetRect: targetRect,
                                                              actualSize: frame.size,
                                                              visibleFrame: visibleFrame)
        let requestedFrame = axFrame(fromAppKit: requestedRect)
        _ = setPosition(requestedFrame.origin, on: window)
        _ = setSize(frame.size, on: window)
        let acceptedSize = self.frame(of: window)?.size ?? frame.size
        let anchoredRect = WindowLayoutGeometry.anchoredRect(for: action,
                                                            targetRect: targetRect,
                                                            actualSize: acceptedSize,
                                                            visibleFrame: visibleFrame)
        let anchoredFrame = axFrame(fromAppKit: anchoredRect)
        _ = setPosition(anchoredFrame.origin, on: window)
        _ = setSize(frame.size, on: window)
        let finalSize = self.frame(of: window)?.size ?? acceptedSize
        let finalRect = WindowLayoutGeometry.anchoredRect(for: action,
                                                         targetRect: targetRect,
                                                         actualSize: finalSize,
                                                         visibleFrame: visibleFrame)
        _ = setPosition(axFrame(fromAppKit: finalRect).origin, on: window)
    }

    private func accepted(actual: WindowLayoutFrame,
                          targetRect: NSRect,
                          action: WindowLayoutAction) -> Bool {
        let actualRect = appKitFrame(fromAX: actual)
        return WindowLayoutGeometry.accepts(actualRect: actualRect,
                                            targetRect: targetRect,
                                            action: action,
                                            anchorTolerance: anchorTolerance)
    }

    // MARK: - Shortcuts

    private func registerHotkeys() {
        // Cleared shortcuts are simply absent: their key combo stays free for
        // other apps, which is the whole point of clearing them (issue #169).
        let shortcuts = Dictionary(uniqueKeysWithValues: WindowLayoutAction.shortcutActions.compactMap { action in
            action.savedShortcut.map { (action, $0) }
        })
        if !hotKeyRefs.isEmpty, shortcuts == registeredShortcuts { return }
        unregisterHotkeys()

        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.signature == 0x5655_574C,
                      let action = WindowLayoutAction(shortcutID: id.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                let service = Unmanaged<WindowLayoutService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.apply(action) }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }

        var failures = Set<WindowLayoutAction>()
        for action in WindowLayoutAction.shortcutActions {
            guard let shortcut = shortcuts[action] else { continue }
            let id = EventHotKeyID(signature: 0x5655_574C, id: action.shortcutID) // 'VUWL'
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                             shortcut.carbonModifiers,
                                             id,
                                             GetEventDispatcherTarget(),
                                             0,
                                             &ref)
            if status == noErr, let ref {
                hotKeyRefs[action] = ref
            } else {
                failures.insert(action)
            }
        }
        registeredShortcuts = shortcuts
        failedShortcutActions = failures
    }

    private func unregisterHotkeys() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredShortcuts.removeAll()
        failedShortcutActions.removeAll()
    }

    // MARK: - Move and resize gesture

    private func startGestureTap() {
        guard gestureTap == nil else {
            isGestureRunning = true
            return
        }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<WindowLayoutService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleGestureEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isGestureRunning = false
            return
        }

        gestureTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        gestureRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isGestureRunning = true
    }

    private func stopGestureTap() {
        if let gestureTap {
            CGEvent.tapEnable(tap: gestureTap, enable: false)
        }
        if let gestureRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureRunLoopSource, .commonModes)
        }
        gestureTap = nil
        gestureRunLoopSource = nil
        activeGesture = nil
        isGestureRunning = false
    }

    private func handleGestureEvent(type: CGEventType,
                                    event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            activeGesture = nil
            if let gestureTap { CGEvent.tapEnable(tap: gestureTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Never enter Accessibility from a live tap after the grant is
        // revoked. A blocked AX call here would stall system input.
        guard AXIsProcessTrusted() else {
            activeGesture = nil
            return Unmanaged.passUnretained(event)
        }

        if var gesture = activeGesture {
            switch (gesture.button, type) {
            case (.primary, .leftMouseDragged), (.secondary, .rightMouseDragged):
                let now = ProcessInfo.processInfo.systemUptime
                let updateInterval: TimeInterval
                switch gesture.kind {
                case .move:
                    updateInterval = moveGestureUpdateInterval
                case .resize:
                    updateInterval = resizeGestureUpdateInterval
                }
                if now - gesture.lastAppliedAt >= updateInterval {
                    apply(gesture, pointer: event.location)
                    gesture.lastAppliedAt = now
                    activeGesture = gesture
                }
                return nil
            case (.primary, .leftMouseUp), (.secondary, .rightMouseUp):
                apply(gesture, pointer: event.location)
                activeGesture = nil
                return nil
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        guard type == .leftMouseDown || type == .rightMouseDown else {
            return Unmanaged.passUnretained(event)
        }
        let moveModifiers = WindowGestureSupport.modifiers(
            from: UserDefaults.standard.string(forKey: DefaultsKey.windowGestureModifiers)
        )
        let resizeModifiers = WindowGestureSupport.resizeModifiers(from: moveModifiers)
        let wantsResize: Bool
        let button: WindowPointerGesture.Button
        if type == .leftMouseDown,
           WindowGestureSupport.modifiersMatch(eventFlags: event.flags, expected: moveModifiers) {
            wantsResize = false
            button = .primary
        } else if type == .leftMouseDown,
                  WindowGestureSupport.modifiersMatch(eventFlags: event.flags,
                                                      expected: resizeModifiers) {
            wantsResize = true
            button = .primary
        } else if type == .rightMouseDown,
                  WindowGestureSupport.modifiersMatch(eventFlags: event.flags,
                                                      expected: moveModifiers) {
            wantsResize = true
            button = .secondary
        } else {
            return Unmanaged.passUnretained(event)
        }

        guard let target = gestureTarget(at: event.location,
                                         requiresResize: wantsResize)
        else { return Unmanaged.passUnretained(event) }

        let resolvedKind: WindowPointerGesture.Kind
        if wantsResize {
            let frame = CGRect(origin: target.frame.origin, size: target.frame.size)
            let edges = WindowGestureSupport.resizeEdges(at: event.location, in: frame)
            guard !edges.isEmpty else { return Unmanaged.passUnretained(event) }
            resolvedKind = .resize(edges)
        } else {
            resolvedKind = .move
        }

        if UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureRaiseWindow) {
            _ = target.app.activate(options: [])
            AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        }
        activeGesture = WindowPointerGesture(window: target.window,
                                             kind: resolvedKind,
                                             button: button,
                                             originalFrame: CGRect(origin: target.frame.origin,
                                                                   size: target.frame.size),
                                             pointerStart: event.location,
                                             lastAppliedAt: ProcessInfo.processInfo.systemUptime)
        return nil
    }

    private func apply(_ gesture: WindowPointerGesture, pointer: CGPoint) {
        switch gesture.kind {
        case .move:
            let origin = WindowGestureSupport.movedOrigin(from: gesture.originalFrame.origin,
                                                          pointerStart: gesture.pointerStart,
                                                          pointerNow: pointer)
            _ = setPosition(origin, on: gesture.window)
        case .resize(let edges):
            let frame = WindowGestureSupport.resizedFrame(from: gesture.originalFrame,
                                                          pointerStart: gesture.pointerStart,
                                                          pointerNow: pointer,
                                                          edges: edges)
            // Size must be written first. Moving a full-size window to the
            // requested top or left origin exposes a large intermediate frame
            // before AX applies the size, which appears as a jump or blank
            // content in windows with asynchronous layout.
            guard setSize(frame.size, on: gesture.window) else { return }

            let acceptedFrame = self.frame(of: gesture.window)
            let acceptedSize = acceptedFrame?.size ?? frame.size
            // Right and bottom resizing keeps the original origin, so the
            // helper returns nil instead of adding a non-atomic position write.
            guard let anchoredOrigin = WindowGestureSupport.anchoredOriginIfNeeded(
                original: gesture.originalFrame,
                requestedOrigin: frame.origin,
                acceptedSize: acceptedSize,
                edges: edges
            ) else { return }
            if let currentOrigin = acceptedFrame?.origin {
                if abs(currentOrigin.x - anchoredOrigin.x) > 0.5
                    || abs(currentOrigin.y - anchoredOrigin.y) > 0.5 {
                    _ = setPosition(anchoredOrigin, on: gesture.window)
                }
            } else {
                _ = setPosition(anchoredOrigin, on: gesture.window)
            }
        }
    }

    private func gestureTarget(at point: CGPoint,
                               requiresResize: Bool) -> WindowGestureTarget? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &rawElement) == .success,
              let element = rawElement
        else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.25)

        let window: AXUIElement?
        if role(of: element) == (kAXWindowRole as String) {
            window = element
        } else {
            window = windowAttribute(element, kAXWindowAttribute as String)
                ?? windowAttribute(element, kAXTopLevelUIElementAttribute as String)
        }
        guard let window else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.25)

        var pid = pid_t(0)
        guard role(of: window) == (kAXWindowRole as String),
              !boolAttribute(window, "AXFullScreen"),
              canSetPosition(on: window),
              (!requiresResize || canSetSize(on: window)),
              AXUIElementGetPid(window, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated,
              app.activationPolicy == .regular,
              let frame = frame(of: window),
              frame.size.width > 80,
              frame.size.height > 80
        else { return nil }
        return WindowGestureTarget(window: window, app: app, frame: frame)
    }

    private func canSetFrame(on window: AXUIElement) -> Bool {
        canSetPosition(on: window) && canSetSize(on: window)
    }

    private func canSetPosition(on window: AXUIElement) -> Bool {
        var positionSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window,
                                              kAXPositionAttribute as CFString,
                                              &positionSettable) == .success
            && positionSettable.boolValue
    }

    private func canSetSize(on window: AXUIElement) -> Bool {
        var sizeSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window,
                                              kAXSizeAttribute as CFString,
                                              &sizeSettable) == .success
            && sizeSettable.boolValue
    }

    private func setPosition(_ point: CGPoint, on element: AXUIElement) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    private func setSize(_ size: CGSize, on element: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    private func frame(of element: AXUIElement) -> WindowLayoutFrame? {
        guard let origin = pointAttribute(element, kAXPositionAttribute as String),
              let size = sizeAttribute(element, kAXSizeAttribute as String),
              size.width > 0,
              size.height > 0
        else { return nil }
        return WindowLayoutFrame(origin: origin, size: size)
    }

    private func bestScreen(for frame: WindowLayoutFrame) -> NSScreen? {
        let appKitFrame = appKitFrame(fromAX: frame)
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(appKitFrame).area < rhs.frame.intersection(appKitFrame).area
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func nextScreen(after current: NSScreen) -> NSScreen? {
        let screens = NSScreen.screens.sorted {
            if abs($0.frame.minX - $1.frame.minX) > 0.5 {
                return $0.frame.minX < $1.frame.minX
            }
            return $0.frame.minY < $1.frame.minY
        }
        guard screens.count > 1,
              let index = screens.firstIndex(where: { $0 === current })
        else { return nil }
        return screens[(index + 1) % screens.count]
    }

    private func axFrame(fromAppKit rect: NSRect) -> WindowLayoutFrame {
        WindowLayoutFrame(origin: CGPoint(x: rect.minX, y: menuBarScreenTopY - rect.maxY),
                          size: rect.size)
    }

    private func appKitFrame(fromAX frame: WindowLayoutFrame) -> NSRect {
        NSRect(x: frame.origin.x,
               y: menuBarScreenTopY - frame.origin.y - frame.size.height,
               width: frame.size.width,
               height: frame.size.height)
    }

    private var menuBarScreenTopY: CGFloat {
        let menuBarScreen = NSScreen.screens.first {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        }
        return (menuBarScreen ?? NSScreen.main ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return false }
        return (value as? Bool) ?? false
    }

    private func windowAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func windowsAttribute(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let values = value as? [AXUIElement]
        else { return nil }
        return values
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}

private struct WindowLayoutTarget {
    let window: AXUIElement
    let windowID: CGWindowID
    let frame: WindowLayoutFrame
}

private struct WindowLayoutPlacement {
    let frame: WindowLayoutFrame
    let rect: NSRect
}

private struct WindowGestureTarget {
    let window: AXUIElement
    let app: NSRunningApplication
    let frame: WindowLayoutFrame
}

private struct WindowPointerGesture {
    enum Button {
        case primary
        case secondary
    }

    enum Kind {
        case move
        case resize(WindowGestureResizeEdges)
    }

    let window: AXUIElement
    let kind: Kind
    let button: Button
    let originalFrame: CGRect
    let pointerStart: CGPoint
    var lastAppliedAt: TimeInterval
}

private struct WindowLayoutFrame: Equatable {
    var origin: CGPoint
    var size: CGSize

    func isClose(to other: WindowLayoutFrame, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
