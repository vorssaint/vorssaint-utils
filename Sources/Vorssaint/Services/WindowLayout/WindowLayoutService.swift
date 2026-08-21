// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import QuartzCore

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
/// optional pointer gesture. The active taps only perform Accessibility work
/// after a deliberate gesture. Edge snapping changes an event only after the
/// same window has visibly followed the pointer to the top of a screen.
final class WindowLayoutService: ObservableObject {
    static let shared = WindowLayoutService()

    @Published private(set) var lastResult: WindowLayoutResult?
    /// Bumped on every published result, so a late settle failure can tell
    /// whether it still owns the feedback slot.
    private var resultGeneration = 0
    @Published private(set) var failedShortcutActions: Set<WindowLayoutAction> = []
    @Published private(set) var directionalShortcutRegistrationFailed = false
    @Published private(set) var isGestureRunning = false

    private var frameHistory = WindowLayoutHistory()
    private var lastActions: [WindowLayoutWindowKey: WindowLayoutAction] = [:]
    private var hotKeyRefs: [WindowLayoutAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var registeredShortcuts: [WindowLayoutAction: GlobalShortcut] = [:]
    private var directionalHotKeyRef: EventHotKeyRef?
    private var registeredDirectionalShortcut: GlobalShortcut?
    private var directionalSession: WindowDirectionalSession?
    private var directionalTimer: Timer?
    private var directionalIndicatorPanel: NSPanel?
    private var directionalTap: CFMachPort?
    private var directionalTapSource: CFRunLoopSource?
    private var gestureTap: CFMachPort?
    private var gestureRunLoopSource: CFRunLoopSource?
    private var edgeSnapTap: CFMachPort?
    private var edgeSnapRunLoopSource: CFRunLoopSource?
    private var activeGesture: WindowPointerGesture?
    private var pendingGesture: PendingWindowGesture?
    private var edgeSnapPressOrigin: CGPoint?
    private var edgeSnapPressCandidate: WindowServerWindowCandidate?
    private var edgeSnapSequenceSuppressed = false
    private var edgeSnapResolveAttempts = 0
    private var edgeSnapLastResolveAt: TimeInterval = 0
    private var edgeSnapDrag: WindowEdgeSnapDrag?
    private var edgeSnapSequenceGeneration = 0
    private var edgeSnapPreviewPanel: NSPanel?
    private var edgeSnapPreviewGeneration = 0
    private var assistiveModeSuspensions: [CGWindowID: EnhancedUserInterfaceSuspension] = [:]
    private var settleTimers: [CGWindowID: Timer] = [:]
    private var gestureAssistiveMode: EnhancedUserInterfaceSuspension?
    /// Stamped on the press this service gives back to the system so none of
    /// our own taps mistake it for a fresh one.
    private static let syntheticEventMarker: Int64 = 0x564F5253
    /// Read on every pointer event, so it is resolved once instead of per
    /// click.
    private static let ownProcessID = Int64(getpid())
    private let frameTolerance: CGFloat = 8
    private let anchorTolerance: CGFloat = 36
    private let moveGestureUpdateInterval: TimeInterval = 1.0 / 120.0
    // AX frame mutations are not atomic. Complex windows can visibly render
    // the intermediate size and position when they receive resize writes at
    // pointer-reporting speed, so resize is deliberately coalesced to 60 Hz.
    private let resizeGestureUpdateInterval: TimeInterval = 1.0 / 60.0
    private let edgeSnapSampleInterval: TimeInterval = 1.0 / 30.0

    private init() {}

    func syncWithPreferences() {
        let available = AppFeature.windowLayout.isAvailable
        let trusted = AXIsProcessTrusted()
        let wantsShortcuts = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.windowLayoutShortcutsEnabled)
            && trusted
        wantsShortcuts ? registerHotkeys() : unregisterHotkeys()

        let wantsDirectional = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.windowDirectionalEnabled)
            && trusted
        wantsDirectional ? registerDirectionalHotkey() : unregisterDirectionalHotkey()

        let wantsGesture = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureEnabled)
            && trusted
        wantsGesture ? startGestureTap() : stopGestureTap()

        let wantsEdgeSnap = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.windowEdgeSnapEnabled)
            && !WindowEdgeSnapSupport.isSystemTilingEnabled
            && trusted
        wantsEdgeSnap ? startEdgeSnapTap() : stopEdgeSnapTap()
    }

    /// Stops every Window Layout input hook before Accessibility is revoked or
    /// the process terminates. Idempotent so permission and feature changes can
    /// call it freely.
    func suspend() {
        unregisterHotkeys()
        unregisterDirectionalHotkey()
        stopGestureTap()
        stopEdgeSnapTap()
        for timer in settleTimers.values { timer.invalidate() }
        settleTimers.removeAll()
        let suspensions = assistiveModeSuspensions.values
        assistiveModeSuspensions.removeAll()
        // With the grant already revoked there is no safe way to touch the
        // apps again; the flag comes back when the assistive client sets it.
        guard AXIsProcessTrusted() else { return }
        for suspension in suspensions { suspension.resume() }
    }

    func shortcutConflictTitle(_ shortcut: GlobalShortcut) -> String? {
        shortcutConflictTitle(shortcut, excluding: nil)
    }

    func shortcutConflictTitle(_ shortcut: GlobalShortcut, excluding excluded: WindowLayoutAction?) -> String? {
        guard AppFeature.windowLayout.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.windowLayoutShortcutsEnabled) else { return nil }
        let text = FeatureStrings.windowLayout(L10n.shared.language)
        return WindowLayoutAction.shortcutActions.first {
            $0 != excluded && $0.savedShortcut == shortcut
        }?.title(text)
    }

    func directionalShortcutConflictTitle(_ shortcut: GlobalShortcut) -> String? {
        if let role = GlobalShortcutRole.conflict(for: shortcut, excluding: nil) {
            return role.title(L10n.shared.s)
        }
        return shortcutConflictTitle(shortcut)
    }

    @discardableResult
    func apply(_ action: WindowLayoutAction) -> WindowLayoutResult {
        guard AXIsProcessTrusted() else {
            return finish(.failure(.missingAccessibility))
        }
        guard let target = focusedTarget(for: action) else {
            return finish(.failure(.noWindow))
        }
        pruneWindowState(keeping: target.key)

        if action == .restore {
            guard let previous = frameHistory.popPrevious(for: target.key,
                                                          current: target.frame) else {
                return finish(.failure(.noRestore))
            }
            if setFrame(previous, on: target.window, windowKey: target.key) {
                lastActions.removeValue(forKey: target.key)
                return finish(.success(restored: true))
            }
            frameHistory.record(previous, for: target.key)
            return finish(.failure(.failed))
        }

        if action == .fullScreen {
            // A placement still settling must never write its old frame over
            // the native full-screen transition that replaces it.
            cancelSettle(for: target.windowID)
            assistiveModeSuspensions.removeValue(forKey: target.windowID)?.resume()
            // The native full screen the green button gives, toggled through
            // the same attribute the button writes. The system owns the frame
            // from here, so nothing is remembered for restore.
            var raw: CFTypeRef?
            AXUIElementCopyAttributeValue(target.window, "AXFullScreen" as CFString, &raw)
            let isFullScreen = (raw as? NSNumber)?.boolValue ?? false
            let flipped = (isFullScreen ? kCFBooleanFalse : kCFBooleanTrue) as CFTypeRef
            let applied = AXUIElementSetAttributeValue(target.window,
                                                       "AXFullScreen" as CFString,
                                                       flipped) == .success
            // Remembered like any other placement, or the "same half twice
            // means maximize" rule would still be looking at whatever the
            // window did before it went full screen.
            if applied {
                if isFullScreen {
                    lastActions.removeValue(forKey: target.key)
                } else {
                    lastActions[target.key] = .fullScreen
                }
            }
            return applied ? finish(.success(restored: false)) : finish(.failure(.failed))
        }
        let screens = NSScreen.screens
        guard let screen = bestScreen(for: target.frame, screens: screens) else {
            return finish(.failure(.failed))
        }
        let currentRect = appKitFrame(fromAX: target.frame)
        if action == .previousDisplay || action == .nextDisplay {
            guard let destination = adjacentScreen(to: screen,
                                                   screens: screens,
                                                   movingForward: action == .nextDisplay) else {
                return finish(.failure(.failed))
            }
            let rect = WindowLayoutGeometry.rectForDisplay(current: currentRect,
                                                           sourceVisibleFrame: screen.visibleFrame,
                                                           destinationVisibleFrame: destination.visibleFrame)
            frameHistory.record(target.frame, for: target.key)
            if setFrame(axFrame(fromAppKit: rect),
                        targetRect: rect,
                        screenVisibleFrame: destination.visibleFrame,
                        action: action,
                        on: target.window,
                        windowKey: target.key) {
                lastActions[target.key] = action
                return finish(.success(restored: false))
            }
            frameHistory.discardLatest(for: target.key)
            return finish(.failure(.failed))
        }
        return applyPlacement(action,
                              to: target,
                              visibleFrame: screen.visibleFrame)
    }

    /// Applies a pointer-selected snap target to one exact external window.
    /// Dock Preview resolves the target from the drop location; the frame still
    /// goes through the same settling and recovery path as every Window Layout
    /// placement instead of maintaining a second AX mutation algorithm.
    @discardableResult
    func place(windowID: CGWindowID,
               pid: pid_t,
               at snapTarget: WindowEdgeSnapTarget) -> Bool {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated,
              let onScreenWindowIDs = onScreenWindowIDs()
        else { return false }

        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let windows = windowsAttribute(axApp),
              let window = windows.first(where: {
            AXWindowResolver.windowID(for: $0) == windowID
        }),
              let target = target(from: window,
                                  app: app,
                                  onScreenWindowIDs: onScreenWindowIDs,
                                  capability: .frame)
        else { return false }

        pruneWindowState(keeping: target.key)
        let result = applyPlacement(snapTarget.action,
                                    to: target,
                                    visibleFrame: snapTarget.visibleFrame,
                                    cyclesRepeatedAction: false)
        if case .success = result { return true }
        return false
    }

    private func finish(_ result: WindowLayoutResult) -> WindowLayoutResult {
        resultGeneration += 1
        lastResult = result
        return result
    }

    private func applyPlacement(_ action: WindowLayoutAction,
                                to target: WindowLayoutTarget,
                                visibleFrame: NSRect,
                                historyFrame: WindowLayoutFrame? = nil,
                                cyclesRepeatedAction: Bool = true) -> WindowLayoutResult {
        let currentRect = appKitFrame(fromAX: target.frame)
        let previousAction = cyclesRepeatedAction ? lastActions[target.key] : nil
        let effectiveAction = WindowLayoutGeometry.effectiveAction(for: action,
                                                                   current: currentRect,
                                                                   visibleFrame: visibleFrame,
                                                                   previousAction: previousAction)
        let placement = placement(for: effectiveAction,
                                  current: target.frame,
                                  visibleFrame: visibleFrame)
        if placement.frame == target.frame {
            lastActions[target.key] = effectiveAction
            return finish(.success(restored: false))
        }
        frameHistory.record(historyFrame ?? target.frame, for: target.key)
        if setFrame(placement.frame,
                    targetRect: placement.rect,
                    screenVisibleFrame: visibleFrame,
                    action: effectiveAction,
                    on: target.window,
                    windowKey: target.key) {
            lastActions[target.key] = effectiveAction
            return finish(.success(restored: false))
        }
        frameHistory.discardLatest(for: target.key)
        return finish(.failure(.failed))
    }

    private func focusedTarget(for action: WindowLayoutAction) -> WindowLayoutTarget? {
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownKeyWindow = NSApp.keyWindow
        let hasFocusedResizableOwnWindow = NSApp.isActive
            && ownKeyWindow?.styleMask.contains(.resizable) == true
            && !(ownKeyWindow is NSPanel)
        let frontmost = hasFocusedResizableOwnWindow
            ? ownPID
            : NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pids = ([frontmost].compactMap { $0 } + WindowUseTracker.shared.apps).reduce(into: [pid_t]()) { result, pid in
            if !result.contains(pid) { result.append(pid) }
        }

        guard let onScreenWindowIDs = onScreenWindowIDs() else { return nil }
        for pid in pids {
            let isFocusedOwnApp = pid == ownPID && hasFocusedResizableOwnWindow
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }),
                  isFocusedOwnApp
                    || (app.activationPolicy == .regular && !app.isHidden
                        && app.bundleIdentifier != ownBundleID)
            else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            // Bounded AX: a hung app in the MRU list must not stall the main
            // thread (and every event tap) for the 6 second default timeout.
            AXUIElementSetMessagingTimeout(axApp, 0.35)
            for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                if let window = windowAttribute(axApp, attribute as String),
                   let target = target(from: window,
                                       app: app,
                                       onScreenWindowIDs: onScreenWindowIDs,
                                       capability: action.targetCapability) {
                    return target
                }
            }
            if let windows = windowsAttribute(axApp),
               let first = windows.compactMap({ target(from: $0,
                                                        app: app,
                                                        onScreenWindowIDs: onScreenWindowIDs,
                                                        capability: action.targetCapability) }).first {
                return first
            }
        }
        return nil
    }

    private func target(from window: AXUIElement,
                        app: NSRunningApplication,
                        onScreenWindowIDs: Set<CGWindowID>,
                        capability: WindowLayoutTargetCapability) -> WindowLayoutTarget? {
        guard role(of: window) == (kAXWindowRole as String),
              !boolAttribute(window, kAXMinimizedAttribute as String),
              stringAttribute(window, kAXSubroleAttribute as String) != "AXFloatingWindow",
              let windowID = AXWindowResolver.windowID(for: window),
              onScreenWindowIDs.contains(windowID),
              let frame = frame(of: window),
              frame.size.width > 80,
              frame.size.height > 80
        else { return nil }
        let isFullScreen = boolAttribute(window, "AXFullScreen")
        guard capability == .fullScreen || !isFullScreen else { return nil }
        let hasRequiredCapability: Bool
        switch capability {
        case .position:
            hasRequiredCapability = canSetPosition(on: window)
        case .frame:
            hasRequiredCapability = canSetFrame(on: window)
        case .fullScreen:
            hasRequiredCapability = canSetFullScreen(on: window)
        }
        guard hasRequiredCapability else { return nil }
        let key = WindowLayoutWindowKey(
            processID: app.processIdentifier,
            processLaunchTime: app.launchDate?.timeIntervalSinceReferenceDate ?? 0,
            windowID: windowID
        )
        return WindowLayoutTarget(window: window, key: key, frame: frame)
    }

    private func onScreenWindowIDs() -> Set<CGWindowID>? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return Set(windows.compactMap {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
    }

    /// Removes histories whose process or window no longer exists. This runs
    /// only for an explicit layout action, never from a timer or input tap.
    private func pruneWindowState(keeping current: WindowLayoutWindowKey) {
        guard var activeWindows = activeWindowKeys() else { return }
        activeWindows.insert(current)
        frameHistory.removeStaleWindows(keeping: activeWindows)
        lastActions = lastActions.filter { activeWindows.contains($0.key) }
    }

    private func activeWindowKeys() -> Set<WindowLayoutWindowKey>? {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        var launchTimes: [pid_t: TimeInterval] = [:]
        var keys = Set<WindowLayoutWindowKey>()
        for window in windows {
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            if launchTimes[pid] == nil {
                guard let app = NSRunningApplication(processIdentifier: pid),
                      app.activationPolicy == .regular else { continue }
                launchTimes[pid] = app.launchDate?.timeIntervalSinceReferenceDate ?? 0
            }
            guard let launchTime = launchTimes[pid] else { continue }
            keys.insert(WindowLayoutWindowKey(processID: pid,
                                              processLaunchTime: launchTime,
                                              windowID: windowID))
        }
        return keys.isEmpty ? nil : keys
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

    private func setFrame(_ frame: WindowLayoutFrame,
                          on window: AXUIElement,
                          windowKey: WindowLayoutWindowKey) -> Bool {
        setFrame(frame,
                 targetRect: appKitFrame(fromAX: frame),
                 screenVisibleFrame: appKitFrame(fromAX: frame),
                 action: .restore,
                 on: window,
                 windowKey: windowKey)
    }

    private func setFrame(_ frame: WindowLayoutFrame,
                          targetRect: NSRect,
                          screenVisibleFrame: NSRect,
                          action: WindowLayoutAction,
                          on window: AXUIElement,
                          windowKey: WindowLayoutWindowKey) -> Bool {
        let windowID = windowKey.windowID
        cancelSettle(for: windowID)
        assistiveModeSuspensions.removeValue(forKey: windowID)?.resume()
        assistiveModeSuspensions[windowID] = EnhancedUserInterfaceSuspension.suspend(forAppOf: window)

        let original = self.frame(of: window)
        if attempt(frame, targetRect: targetRect, action: action, on: window) {
            assistiveModeSuspensions.removeValue(forKey: windowID)?.resume()
            return true
        }

        // Some apps commit Accessibility size changes with a short delay, so
        // the reads above can still see the old frame. Judging failure now and
        // restoring the original is what used to leave windows moved but never
        // resized (issue #334): let the window settle before deciding.
        scheduleSettle(SettleContext(window: window,
                                     windowID: windowID,
                                     frame: frame,
                                     targetRect: targetRect,
                                     screenVisibleFrame: screenVisibleFrame,
                                     action: action,
                                     original: original,
                                     previousAction: lastActions[windowKey],
                                     windowKey: windowKey,
                                     resultGeneration: resultGeneration + 1),
                       attempt: 0)
        return true
    }

    private func scheduleSettle(_ context: SettleContext, attempt: Int) {
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.settleTimers[context.windowID] = nil
            self.continueSettle(context, attempt: attempt)
        }
        settleTimers[context.windowID] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func continueSettle(_ context: SettleContext, attempt: Int) {
        if verified(context) {
            concludeSettle(context, success: true)
            return
        }
        if self.attempt(context.frame,
                        targetRect: context.targetRect,
                        action: context.action,
                        on: context.window) {
            concludeSettle(context, success: true)
            return
        }
        if attempt == 0 {
            scheduleSettle(context, attempt: 1)
            return
        }
        if let original = context.original, shouldUseMaximizeFallback(for: context.action) {
            let currentRect = appKitFrame(fromAX: original)
            let maxFrame = axFrame(fromAppKit: WindowLayoutGeometry.rect(for: .maximize,
                                                                         current: currentRect,
                                                                         visibleFrame: context.screenVisibleFrame))
            applyFrame(maxFrame, on: context.window)
            if self.attempt(context.frame,
                            targetRect: context.targetRect,
                            action: context.action,
                            on: context.window) {
                concludeSettle(context, success: true)
                return
            }
        }
        concludeSettle(context, success: false)
    }

    private func verified(_ context: SettleContext) -> Bool {
        guard let actual = frame(of: context.window) else { return false }
        return actual.isClose(to: context.frame, tolerance: frameTolerance)
            || accepted(actual: actual, targetRect: context.targetRect, action: context.action)
    }

    // The action already reported success while the window was settling, so a
    // refusal this late restores the window, undoes the bookkeeping and
    // republishes the result the panel feedback listens to.
    private func concludeSettle(_ context: SettleContext, success: Bool) {
        assistiveModeSuspensions.removeValue(forKey: context.windowID)?.resume()
        guard !success else { return }
        if let original = context.original {
            applyFrame(original, on: context.window)
        }
        if context.action == .restore {
            frameHistory.record(context.frame, for: context.windowKey)
        } else {
            frameHistory.discardLatest(for: context.windowKey)
        }
        if let previousAction = context.previousAction {
            lastActions[context.windowKey] = previousAction
        } else {
            lastActions.removeValue(forKey: context.windowKey)
        }
        // A second action already published a fresh result; this stale
        // failure must not overwrite the feedback the person is reading.
        if context.resultGeneration == resultGeneration {
            lastResult = .failure(.failed)
        }
    }

    private func cancelSettle(for windowID: CGWindowID) {
        settleTimers.removeValue(forKey: windowID)?.invalidate()
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
                .topLeft, .topRight, .bottomLeft, .bottomRight, .marginMaximize:
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

        ensureHotKeyEventHandler()

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

    private func ensureHotKeyEventHandler() {
        if eventHandler == nil {
            var specs = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                let service = Unmanaged<WindowLayoutService>.fromOpaque(userData).takeUnretainedValue()
                let kind = event.map(GetEventKind) ?? 0
                if id.signature == 0x5655_5744 { // 'VUWD'
                    DispatchQueue.main.async {
                        kind == UInt32(kEventHotKeyPressed)
                            ? service.beginDirectionalGesture()
                            : service.finishDirectionalGesture()
                    }
                    return noErr
                }
                guard id.signature == 0x5655_574C,
                      kind == UInt32(kEventHotKeyPressed),
                      let action = WindowLayoutAction(shortcutID: id.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async { service.apply(action) }
                return noErr
            }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
    }

    /// Lets go of the layout keys while a shortcut field is listening, so the
    /// user can record a combination the layout actions already use. The
    /// gesture tap is left alone: it watches the mouse, not the keyboard. The
    /// next `syncWithPreferences` takes the keys back.
    func suspendShortcuts() { unregisterHotkeys() }

    private func unregisterHotkeys() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredShortcuts.removeAll()
        failedShortcutActions.removeAll()
    }

    private func registerDirectionalHotkey() {
        guard let shortcut = UserDefaults.standard.string(forKey: DefaultsKey.windowDirectionalShortcut)
            .flatMap(GlobalShortcut.init(storageValue:)) else {
            directionalShortcutRegistrationFailed = true
            return
        }
        if directionalHotKeyRef != nil, registeredDirectionalShortcut == shortcut { return }
        unregisterDirectionalHotkey()
        ensureHotKeyEventHandler()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x5655_5744, id: 56)
        let status = RegisterEventHotKey(shortcut.carbonKeyCode, shortcut.carbonModifiers, id,
                                         GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            directionalHotKeyRef = ref
            registeredDirectionalShortcut = shortcut
            directionalShortcutRegistrationFailed = false
        } else {
            directionalShortcutRegistrationFailed = true
        }
    }

    private func unregisterDirectionalHotkey() {
        if let directionalHotKeyRef { UnregisterEventHotKey(directionalHotKeyRef) }
        directionalHotKeyRef = nil
        registeredDirectionalShortcut = nil
        directionalShortcutRegistrationFailed = false
        cancelDirectionalGesture()
    }

    private func beginDirectionalGesture() {
        guard directionalSession == nil,
              let target = focusedTarget(for: .leftHalf),
              let screen = bestScreen(for: target.frame) else { return }
        directionalSession = WindowDirectionalSession(target: target,
                                                      visibleFrame: screen.visibleFrame,
                                                      pointerOrigin: NSEvent.mouseLocation,
                                                      action: nil,
                                                      manualOverride: nil)
        showDirectionalIndicator(at: NSEvent.mouseLocation, action: nil)
        directionalTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in self?.updateDirectionalGesture()
        }
        startDirectionalTap()
    }

    private func startDirectionalTap() {
        guard directionalTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<WindowLayoutService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.observeDirectionalEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        directionalTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        directionalTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func observeDirectionalEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard var session = directionalSession else { return Unmanaged.passUnretained(event) }

        if type == .scrollWheel {
            let deltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let fixedDeltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let scrollY = deltaY != 0 ? deltaY : Double(fixedDeltaY)

            if scrollY > 0.5 {
                session.manualOverride = .maximize
                directionalSession = session
                updateDirectionalIndicator(action: .maximize)
                let preview = placement(for: .maximize, current: session.target.frame,
                                        visibleFrame: session.visibleFrame).rect
                showEdgeSnapPreview(frame: preview)
            } else if scrollY < -0.5 {
                session.manualOverride = .minimize
                directionalSession = session
                updateDirectionalIndicator(action: .minimize)
                hideEdgeSnapPreview(immediately: true)
            }
            return nil
        }

        if type == .leftMouseDown {
            session.manualOverride = .maximize
            directionalSession = session
            updateDirectionalIndicator(action: .maximize)
            let preview = placement(for: .maximize, current: session.target.frame,
                                    visibleFrame: session.visibleFrame).rect
            showEdgeSnapPreview(frame: preview)
            return nil
        }

        if type == .rightMouseDown {
            session.manualOverride = .minimize
            directionalSession = session
            updateDirectionalIndicator(action: .minimize)
            hideEdgeSnapPreview(immediately: true)
            return nil
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 49 || keyCode == 36 || keyCode == 126 { // Space, Return, Up
                session.manualOverride = .maximize
                directionalSession = session
                updateDirectionalIndicator(action: .maximize)
                let preview = placement(for: .maximize, current: session.target.frame,
                                        visibleFrame: session.visibleFrame).rect
                showEdgeSnapPreview(frame: preview)
                return nil
            } else if keyCode == 46 || keyCode == 125 { // M, Down
                session.manualOverride = .minimize
                directionalSession = session
                updateDirectionalIndicator(action: .minimize)
                hideEdgeSnapPreview(immediately: true)
                return nil
            } else if keyCode == 53 { // Escape
                cancelDirectionalGesture()
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func updateDirectionalGesture() {
        guard var session = directionalSession else { return }
        let currentMouse = NSEvent.mouseLocation
        let distance = hypot(currentMouse.x - session.pointerOrigin.x,
                             currentMouse.y - session.pointerOrigin.y)

        let directionalAction = WindowDirectionalGestureSupport.action(
            from: session.pointerOrigin,
            to: currentMouse
        )

        if distance >= WindowDirectionalGestureSupport.activationDistance {
            session.manualOverride = nil
        }

        let action = session.manualOverride ?? directionalAction
        guard action != session.action else { return }

        session.action = action
        directionalSession = session
        updateDirectionalIndicator(action: action)

        guard let action else {
            hideEdgeSnapPreview(immediately: false)
            return
        }

        if let layoutAction = action.layoutAction {
            let preview = placement(for: layoutAction, current: session.target.frame,
                                    visibleFrame: session.visibleFrame).rect
            showEdgeSnapPreview(frame: preview)
        } else {
            hideEdgeSnapPreview(immediately: true)
        }
    }

    private func finishDirectionalGesture() {
        stopDirectionalTap()
        guard let session = directionalSession else { return }
        directionalTimer?.invalidate()
        directionalTimer = nil
        directionalSession = nil
        hideEdgeSnapPreview(immediately: true)
        hideDirectionalIndicator()

        guard let action = session.action else { return }
        if let layoutAction = action.layoutAction {
            _ = applyPlacement(layoutAction, to: session.target, visibleFrame: session.visibleFrame,
                               cyclesRepeatedAction: false)
        } else if action == .minimize {
            _ = minimize(target: session.target)
        }
    }

    private func cancelDirectionalGesture() {
        stopDirectionalTap()
        directionalTimer?.invalidate()
        directionalTimer = nil
        directionalSession = nil
        hideEdgeSnapPreview(immediately: true)
        hideDirectionalIndicator()
    }

    private func stopDirectionalTap() {
        if let directionalTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), directionalTapSource, .commonModes)
        }
        directionalTapSource = nil
        if let directionalTap {
            CGEvent.tapEnable(tap: directionalTap, enable: false)
            CFMachPortInvalidate(directionalTap)
        }
        directionalTap = nil
    }

    @discardableResult
    private func minimize(target: WindowLayoutTarget) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let status = AXUIElementSetAttributeValue(target.window,
                                                  kAXMinimizedAttribute as CFString,
                                                  kCFBooleanTrue)
        return status == .success
    }

    private func showDirectionalIndicator(at pointer: CGPoint, action: WindowDirectionalAction?) {
        let size = CGSize(width: 180, height: 180)
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(pointer) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2)
        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        origin.y = min(max(origin.y, screenFrame.minY + 8), screenFrame.maxY - size.height - 8)
        let panel: NSPanel
        if let directionalIndicatorPanel {
            panel = directionalIndicatorPanel
        } else {
            panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                        .transient, .ignoresCycle]
            panel.animationBehavior = .none
            panel.contentView = WindowDirectionalIndicatorView(frame: CGRect(origin: .zero, size: size))
            directionalIndicatorPanel = panel
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        updateDirectionalIndicator(action: action)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func updateDirectionalIndicator(action: WindowDirectionalAction?) {
        guard let view = directionalIndicatorPanel?.contentView as? WindowDirectionalIndicatorView else { return }
        view.action = action
    }

    private func hideDirectionalIndicator() {
        directionalIndicatorPanel?.orderOut(nil)
    }

    // MARK: - Drag to screen edge

    /// The callback copies scalar values and gets out of the input path before
    /// any Accessibility or UI work. It only adjusts the exact top coordinate
    /// after a window move has already been confirmed on the main queue.
    private func startEdgeSnapTap() {
        guard edgeSnapTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<WindowLayoutService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.observeEdgeSnapEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        edgeSnapTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        edgeSnapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEdgeSnapTap() {
        edgeSnapSequenceGeneration += 1
        edgeSnapPressOrigin = nil
        edgeSnapPressCandidate = nil
        edgeSnapSequenceSuppressed = false
        edgeSnapResolveAttempts = 0
        edgeSnapDrag = nil
        hideEdgeSnapPreview(immediately: true)
        if let edgeSnapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), edgeSnapRunLoopSource, .commonModes)
        }
        if let edgeSnapTap {
            CGEvent.tapEnable(tap: edgeSnapTap, enable: false)
            CFMachPortInvalidate(edgeSnapTap)
        }
        edgeSnapTap = nil
        edgeSnapRunLoopSource = nil
        edgeSnapPreviewPanel = nil
    }

    private func observeEdgeSnapEvent(type: CGEventType,
                                      event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let edgeSnapTap { CGEvent.tapEnable(tap: edgeSnapTap, enable: true) }
            DispatchQueue.main.async { [weak self] in self?.cancelEdgeSnapTracking() }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticEventMarker,
              event.getIntegerValueField(.eventSourceUnixProcessID) != Self.ownProcessID
        else { return Unmanaged.passUnretained(event) }

        if type == .leftMouseDown {
            edgeSnapSequenceSuppressed = WindowEdgeSnapSupport.isSystemTilingEnabled
        } else if edgeSnapSequenceSuppressed {
            if type == .leftMouseUp { edgeSnapSequenceSuppressed = false }
            return Unmanaged.passUnretained(event)
        }
        guard !edgeSnapSequenceSuppressed else { return Unmanaged.passUnretained(event) }

        let input: WindowEdgeSnapPointerInput
        switch type {
        case .leftMouseDown:
            input = .down(location: event.location, flags: event.flags)
        case .leftMouseDragged:
            let originalLocation = event.location
            input = .dragged(location: originalLocation)
            if let drag = edgeSnapDrag,
               drag.isMoving,
               drag.protectsSystemTopEdge {
                event.location = WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(
                    originalLocation,
                    screenFrames: drag.quartzScreenFrames
                )
            }
        case .leftMouseUp:
            input = .up(location: event.location)
        default:
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async { [weak self] in self?.handleEdgeSnapInput(input) }
        return Unmanaged.passUnretained(event)
    }

    private func handleEdgeSnapInput(_ input: WindowEdgeSnapPointerInput) {
        switch input {
        case .down(let location, let flags):
            cancelEdgeSnapTracking()
            edgeSnapSequenceSuppressed = false
            guard AppFeature.windowLayout.isAvailable,
                  UserDefaults.standard.bool(forKey: DefaultsKey.windowEdgeSnapEnabled),
                  !WindowEdgeSnapSupport.isSystemTilingEnabled,
                  AXIsProcessTrusted(),
                  !edgeSnapConflictsWithWindowGesture(flags: flags)
            else {
                edgeSnapSequenceSuppressed = true
                return
            }
            guard let candidate = WindowServerWindowHitTest.candidate(at: location, pidIsEligible: {
                guard let app = NSRunningApplication(processIdentifier: $0) else { return false }
                return !app.isTerminated && app.activationPolicy == .regular
            }),
            !WindowEdgeSnapSupport.startsAtResizeHandle(location, frame: candidate.frame)
            else {
                edgeSnapSequenceSuppressed = true
                return
            }
            edgeSnapPressOrigin = location
            edgeSnapPressCandidate = candidate
            edgeSnapResolveAttempts = 0
            edgeSnapLastResolveAt = 0

        case .dragged(let location):
            guard let pressOrigin = edgeSnapPressOrigin,
                  let pressCandidate = edgeSnapPressCandidate,
                  activeGesture == nil, pendingGesture == nil
            else {
                cancelEdgeSnapTracking()
                return
            }
            if edgeSnapDrag == nil,
               WindowGestureSupport.exceedsDragSlop(from: pressOrigin, to: location) {
                let now = ProcessInfo.processInfo.systemUptime
                if edgeSnapResolveAttempts < 4, now - edgeSnapLastResolveAt >= 0.08 {
                    edgeSnapResolveAttempts += 1
                    edgeSnapLastResolveAt = now
                    edgeSnapDrag = makeEdgeSnapDrag(pointerStart: pressOrigin,
                                                    pressCandidate: pressCandidate)
                }
            }
            updateEdgeSnapDrag(at: location, forceSample: false)

        case .up(let location):
            let pressOrigin = edgeSnapPressOrigin
            let pressCandidate = edgeSnapPressCandidate
            if edgeSnapDrag == nil,
               let pressOrigin, let pressCandidate,
               WindowGestureSupport.exceedsDragSlop(from: pressOrigin, to: location) {
                edgeSnapDrag = makeEdgeSnapDrag(pointerStart: pressOrigin,
                                                pressCandidate: pressCandidate)
            }
            updateEdgeSnapDrag(at: location, forceSample: true)
            let completed = edgeSnapDrag
            edgeSnapPressOrigin = nil
            edgeSnapPressCandidate = nil
            edgeSnapResolveAttempts = 0
            edgeSnapDrag = nil
            hideEdgeSnapPreview(immediately: false)
            let generation = edgeSnapSequenceGeneration
            guard let completed else {
                guard let pressOrigin, let pressCandidate,
                      WindowGestureSupport.exceedsDragSlop(from: pressOrigin, to: location)
                else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    guard let self, generation == self.edgeSnapSequenceGeneration,
                          let delayed = self.makeEdgeSnapDrag(pointerStart: pressOrigin,
                                                              pressCandidate: pressCandidate)
                    else { return }
                    self.applyDelayedEdgeSnapIfMoved(delayed, releaseLocation: location)
                }
                return
            }
            if !completed.isMoving {
                guard let pressOrigin,
                      WindowGestureSupport.exceedsDragSlop(from: pressOrigin, to: location)
                else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    guard let self, generation == self.edgeSnapSequenceGeneration else { return }
                    self.applyDelayedEdgeSnapIfMoved(completed, releaseLocation: location)
                }
                return
            }
            guard let target = completed.target else { return }
            // The callback has already forwarded this mouse-up. One
            // more main-loop turn lets the target app finish its own drag
            // before the placement writes the final frame.
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.edgeSnapSequenceGeneration else { return }
                self.applyEdgeSnap(completed, target: target)
            }
        }
    }

    private func applyDelayedEdgeSnapIfMoved(_ drag: WindowEdgeSnapDrag,
                                             releaseLocation: CGPoint) {
        guard let current = frame(of: drag.window),
              WindowEdgeSnapSupport.classify(
                initialFrame: drag.initialFrame,
                currentFrame: CGRect(origin: current.origin, size: current.size),
                pointerStart: drag.pointerStart,
                pointerNow: releaseLocation
              ) == .moving,
              let target = edgeSnapTarget(atQuartzPoint: releaseLocation)
        else { return }
        applyEdgeSnap(drag, target: target)
    }

    private func edgeSnapConflictsWithWindowGesture(flags: CGEventFlags) -> Bool {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureEnabled) else { return false }
        let move = WindowGestureSupport.modifiers(
            from: UserDefaults.standard.string(forKey: DefaultsKey.windowGestureModifiers)
        )
        return WindowGestureSupport.modifiersMatch(eventFlags: flags, expected: move)
            || WindowGestureSupport.modifiersMatch(
                eventFlags: flags,
                expected: WindowGestureSupport.resizeModifiers(from: move)
            )
    }

    private func makeEdgeSnapDrag(pointerStart: CGPoint,
                                  pressCandidate: WindowServerWindowCandidate) -> WindowEdgeSnapDrag? {
        guard let app = NSRunningApplication(processIdentifier: pressCandidate.pid),
              !app.isTerminated, app.activationPolicy == .regular else { return nil }
        let axApp = AXUIElementCreateApplication(pressCandidate.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let window = windowsAttribute(axApp)?.first(where: {
                  AXWindowResolver.windowID(for: $0) == pressCandidate.windowID
              }) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.25)
        guard let onScreenWindowIDs = onScreenWindowIDs(),
              let target = target(from: window,
                                  app: app,
                                  onScreenWindowIDs: onScreenWindowIDs,
                                  capability: .frame) else { return nil }
        return WindowEdgeSnapDrag(window: target.window,
                                  key: target.key,
                                  initialFrame: pressCandidate.frame,
                                  pointerStart: pointerStart,
                                  protectsSystemTopEdge: WindowEdgeSnapSupport.isSystemTopWindowOverviewDragEnabled,
                                  quartzScreenFrames: edgeSnapQuartzScreenFrames(),
                                  lastSampleAt: 0,
                                  mismatchCount: 0,
                                  isMoving: false,
                                  target: nil)
    }

    private func updateEdgeSnapDrag(at location: CGPoint, forceSample: Bool) {
        guard var drag = edgeSnapDrag else { return }
        if !drag.isMoving {
            let now = ProcessInfo.processInfo.systemUptime
            guard forceSample || now - drag.lastSampleAt >= edgeSnapSampleInterval else { return }
            drag.lastSampleAt = now
            guard let current = frame(of: drag.window) else {
                cancelEdgeSnapTracking()
                return
            }
            let currentFrame = CGRect(origin: current.origin, size: current.size)
            switch WindowEdgeSnapSupport.classify(initialFrame: drag.initialFrame,
                                                  currentFrame: currentFrame,
                                                  pointerStart: drag.pointerStart,
                                                  pointerNow: location) {
            case .waiting:
                edgeSnapDrag = drag
                return
            case .moving:
                drag.isMoving = true
                drag.mismatchCount = 0
            case .resizing:
                cancelEdgeSnapTracking()
                return
            case .unrelated:
                drag.mismatchCount += 1
                if drag.mismatchCount >= 3 {
                    cancelEdgeSnapTracking()
                } else {
                    edgeSnapDrag = drag
                }
                return
            }
        }

        let target = edgeSnapTarget(atQuartzPoint: location)
        if target != drag.target {
            drag.target = target
            if let target {
                showEdgeSnapPreview(frame: target.frame)
            } else {
                hideEdgeSnapPreview(immediately: false)
            }
        }
        edgeSnapDrag = drag
    }

    private func edgeSnapTarget(atQuartzPoint point: CGPoint) -> WindowEdgeSnapTarget? {
        let appKitPoint = CGPoint(x: point.x, y: menuBarScreenTopY - point.y)
        let screens = NSScreen.screens.map {
            WindowEdgeSnapScreen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        return WindowEdgeSnapSupport.target(at: appKitPoint,
                                            screens: screens)
    }

    private func edgeSnapQuartzScreenFrames() -> [CGRect] {
        let top = menuBarScreenTopY
        return NSScreen.screens.map {
            CGRect(x: $0.frame.minX,
                   y: top - $0.frame.maxY,
                   width: $0.frame.width,
                   height: $0.frame.height)
        }
    }

    private func applyEdgeSnap(_ drag: WindowEdgeSnapDrag,
                               target: WindowEdgeSnapTarget) {
        guard AppFeature.windowLayout.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.windowEdgeSnapEnabled),
              !WindowEdgeSnapSupport.isSystemTilingEnabled,
              AXIsProcessTrusted(),
              canSetFrame(on: drag.window),
              AXWindowResolver.windowID(for: drag.window) == drag.key.windowID,
              let currentFrame = frame(of: drag.window)
        else { return }
        var processID = pid_t(0)
        guard AXUIElementGetPid(drag.window, &processID) == .success,
              processID == drag.key.processID else { return }

        let layoutTarget = WindowLayoutTarget(window: drag.window,
                                              key: drag.key,
                                              frame: currentFrame)
        pruneWindowState(keeping: drag.key)
        let history = WindowLayoutFrame(origin: drag.initialFrame.origin,
                                        size: drag.initialFrame.size)
        _ = applyPlacement(target.action,
                           to: layoutTarget,
                           visibleFrame: target.visibleFrame,
                           historyFrame: history,
                           cyclesRepeatedAction: false)
    }

    private func cancelEdgeSnapTracking() {
        edgeSnapSequenceGeneration += 1
        edgeSnapPressOrigin = nil
        edgeSnapPressCandidate = nil
        edgeSnapSequenceSuppressed = true
        edgeSnapResolveAttempts = 0
        edgeSnapDrag = nil
        hideEdgeSnapPreview(immediately: false)
    }

    private func showEdgeSnapPreview(frame: CGRect) {
        edgeSnapPreviewGeneration += 1
        let panel: NSPanel
        if let existing = edgeSnapPreviewPanel {
            panel = existing
        } else {
            panel = makeEdgeSnapPreviewPanel()
            edgeSnapPreviewPanel = panel
        }
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideEdgeSnapPreview(immediately: Bool) {
        guard let panel = edgeSnapPreviewPanel, panel.isVisible else { return }
        edgeSnapPreviewGeneration += 1
        let generation = edgeSnapPreviewGeneration
        if immediately {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, let panel,
                  generation == self.edgeSnapPreviewGeneration else { return }
            panel.orderOut(nil)
        }
    }

    private func makeEdgeSnapPreviewPanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentView = WindowEdgeSnapPreviewView(frame: .zero)
        return panel
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
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<WindowLayoutService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleGestureEvent(proxy: proxy, type: type, event: event)
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
        // A press still under custody has to go back to the app before the
        // tap that is holding it disappears, or that click is simply lost.
        flushPending(proxy: nil, at: nil)
        if let gestureRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureRunLoopSource, .commonModes)
        }
        if let gestureTap {
            CGEvent.tapEnable(tap: gestureTap, enable: false)
            CFMachPortInvalidate(gestureTap)
        }
        gestureTap = nil
        gestureRunLoopSource = nil
        activeGesture = nil
        pendingGesture = nil
        endGestureAssistiveMode()
        isGestureRunning = false
    }

    private var gestureState: WindowGestureState {
        if activeGesture != nil { return .active }
        if pendingGesture != nil { return .pending }
        return .idle
    }

    private var trackedGestureButton: WindowPointerGesture.Button? {
        activeGesture?.button ?? pendingGesture?.button
    }

    /// Whether the button that started the press is still down. Only worth
    /// asking when the tap was switched off, because that is the one moment
    /// the release can reach the app without passing through here.
    private func isTrackedButtonDown() -> Bool {
        guard let button = trackedGestureButton else { return false }
        return CGEventSource.buttonState(.combinedSessionState,
                                         button: button == .primary ? .left : .right)
    }

    /// A press that carries the chord is held back, not taken: the app only
    /// loses it once the pointer moves far enough to mean a window gesture.
    /// A press that ends where it started is handed straight back, so an
    /// ordinary modifier click keeps working in every app.
    private func handleGestureEvent(proxy: CGEventTapProxy?,
                                    type: CGEventType,
                                    event: CGEvent) -> Unmanaged<CGEvent>? {
        // The press this service gave back to the system. Looking at it again
        // would take it right back and never let go.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker
            || event.getIntegerValueField(.eventSourceUnixProcessID) == Self.ownProcessID {
            return Unmanaged.passUnretained(event)
        }

        let tapDisabled = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
        if tapDisabled, let gestureTap {
            CGEvent.tapEnable(tap: gestureTap, enable: true)
        }

        var chord: (button: WindowPointerGesture.Button, wantsResize: Bool)?
        let input: WindowGestureInput
        if tapDisabled {
            input = .tapDisabled(buttonStillDown: isTrackedButtonDown())
        } else if !AXIsProcessTrusted() {
            // Never enter Accessibility from a live tap after the grant is
            // revoked. A blocked AX call here would stall system input.
            input = .accessibilityLost
        } else {
            switch type {
            case .leftMouseDown, .rightMouseDown:
                let button: WindowPointerGesture.Button =
                    type == .leftMouseDown ? .primary : .secondary
                chord = gestureChord(type: type, flags: event.flags)
                input = .buttonDown(sameButton: button == trackedGestureButton,
                                    chordMatched: chord != nil)
            case .leftMouseDragged, .rightMouseDragged:
                let button: WindowPointerGesture.Button =
                    type == .leftMouseDragged ? .primary : .secondary
                let pastSlop = pendingGesture.map {
                    WindowGestureSupport.exceedsDragSlop(from: $0.origin, to: event.location)
                } ?? false
                input = .buttonDragged(tracked: button == trackedGestureButton, pastSlop: pastSlop)
            case .leftMouseUp, .rightMouseUp:
                let button: WindowPointerGesture.Button =
                    type == .leftMouseUp ? .primary : .secondary
                input = .buttonUp(tracked: button == trackedGestureButton)
            default:
                input = .otherEvent
            }
        }

        var decision = WindowGestureSupport.decide(state: gestureState, input: input)
        switch decision {
        case .restartAsIdle:
            pendingGesture = nil
            decision = WindowGestureSupport.decide(state: .idle, input: input)
        case .flushThenRestart:
            flushPending(proxy: proxy, at: event.location)
            decision = WindowGestureSupport.decide(state: .idle, input: input)
        default:
            break
        }

        switch decision {
        case .passThrough, .restartAsIdle, .flushThenRestart:
            return Unmanaged.passUnretained(event)

        case .hold:
            return nil

        case .arm:
            guard let chord else { return Unmanaged.passUnretained(event) }
            return arm(chord: chord, event: event)

        case .promote:
            guard let pending = pendingGesture else { return nil }
            promote(pending, pointer: event.location)
            return nil

        case .applyMove:
            guard var gesture = activeGesture else { return nil }
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

        case .applyFinish:
            if let gesture = activeGesture {
                apply(gesture, pointer: event.location)
            }
            activeGesture = nil
            endGestureAssistiveMode()
            return nil

        case .replayThenPass:
            // The held press goes back first and this release closes the pair,
            // so the app sees one ordinary click and never half of one.
            flushPending(proxy: proxy, at: event.location)
            return Unmanaged.passUnretained(event)

        case .flushThenPass:
            // A disabled tap carries no position, and its proxy is no longer a
            // dependable way back into the stream.
            flushPending(proxy: tapDisabled ? nil : proxy,
                         at: tapDisabled ? nil : event.location)
            return Unmanaged.passUnretained(event)

        case .dropState:
            activeGesture = nil
            pendingGesture = nil
            endGestureAssistiveMode()
            return Unmanaged.passUnretained(event)
        }
    }

    private func endGestureAssistiveMode() {
        let suspension = gestureAssistiveMode
        gestureAssistiveMode = nil
        // With the grant revoked there is no safe way to touch the app again;
        // the flag comes back when the assistive client sets it.
        guard AXIsProcessTrusted() else { return }
        suspension?.resume()
    }

    private func gestureChord(type: CGEventType,
                              flags: CGEventFlags) -> (button: WindowPointerGesture.Button,
                                                       wantsResize: Bool)? {
        let moveModifiers = WindowGestureSupport.modifiers(
            from: UserDefaults.standard.string(forKey: DefaultsKey.windowGestureModifiers)
        )
        let resizeModifiers = WindowGestureSupport.resizeModifiers(from: moveModifiers)
        if type == .leftMouseDown,
           WindowGestureSupport.modifiersMatch(eventFlags: flags, expected: moveModifiers) {
            return (.primary, false)
        }
        if type == .leftMouseDown,
           WindowGestureSupport.modifiersMatch(eventFlags: flags, expected: resizeModifiers) {
            return (.primary, true)
        }
        if type == .rightMouseDown,
           WindowGestureSupport.modifiersMatch(eventFlags: flags, expected: moveModifiers) {
            return (.secondary, true)
        }
        return nil
    }

    /// Takes custody of a press that matches the chord over a window this
    /// service can actually move. Anything it cannot move keeps its click.
    private func arm(chord: (button: WindowPointerGesture.Button, wantsResize: Bool),
                     event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let target = gestureTarget(at: event.location,
                                         requiresResize: chord.wantsResize)
        else { return Unmanaged.passUnretained(event) }

        let resolvedKind: WindowPointerGesture.Kind
        if chord.wantsResize {
            let frame = CGRect(origin: target.frame.origin, size: target.frame.size)
            let edges = WindowGestureSupport.resizeEdges(at: event.location, in: frame)
            guard !edges.isEmpty else { return Unmanaged.passUnretained(event) }
            resolvedKind = .resize(edges)
        } else {
            resolvedKind = .move
        }

        // Without a copy there is nothing to give back, and keeping a press
        // that can never be returned is worse than not holding it at all.
        guard let down = event.copy() else { return Unmanaged.passUnretained(event) }
        pendingGesture = PendingWindowGesture(down: down,
                                              button: chord.button,
                                              kind: resolvedKind,
                                              window: target.window,
                                              app: target.app,
                                              originalFrame: CGRect(origin: target.frame.origin,
                                                                    size: target.frame.size),
                                              origin: event.location)
        return nil
    }

    /// The press became a gesture. Raising happens here and not at the press,
    /// so a plain modifier click never activates or reorders a window.
    private func promote(_ pending: PendingWindowGesture, pointer: CGPoint) {
        pendingGesture = nil
        // Suspended for the whole gesture, not per frame write: the writes come
        // at pointer speed and the flag only needs to move twice.
        gestureAssistiveMode?.resume()
        gestureAssistiveMode = EnhancedUserInterfaceSuspension.suspend(forAppOf: pending.window)
        if UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureRaiseWindow) {
            _ = pending.app.activate(options: [])
            AXUIElementPerformAction(pending.window, kAXRaiseAction as CFString)
        }
        // The press point stays the anchor: measuring from where the slop was
        // crossed would leave the window trailing the pointer for good.
        var gesture = WindowPointerGesture(window: pending.window,
                                           kind: pending.kind,
                                           button: pending.button,
                                           originalFrame: pending.originalFrame,
                                           pointerStart: pending.origin,
                                           lastAppliedAt: ProcessInfo.processInfo.systemUptime)
        apply(gesture, pointer: pointer)
        gesture.lastAppliedAt = ProcessInfo.processInfo.systemUptime
        activeGesture = gesture
    }

    /// Puts a held press back into the stream. It carries the release point
    /// and the current time so the app reads the pair as one short click on
    /// one element, however long the button was held.
    private func flushPending(proxy: CGEventTapProxy?, at point: CGPoint?) {
        guard let pending = pendingGesture else { return }
        pendingGesture = nil
        let down = pending.down
        down.location = point ?? pending.origin
        down.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        if let proxy {
            // Posted through the tap it is leaving, which places it ahead of
            // the event this callback is about to return.
            down.tapPostEvent(proxy)
        } else {
            down.post(tap: .cgSessionEventTap)
        }
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

    private func canSetFullScreen(on window: AXUIElement) -> Bool {
        var fullScreenSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window,
                                              "AXFullScreen" as CFString,
                                              &fullScreenSettable) == .success
            && fullScreenSettable.boolValue
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

    private func bestScreen(for frame: WindowLayoutFrame,
                            screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        let appKitFrame = appKitFrame(fromAX: frame)
        return screens.max { lhs, rhs in
            lhs.frame.intersection(appKitFrame).area < rhs.frame.intersection(appKitFrame).area
        } ?? NSScreen.main ?? screens.first
    }

    private func adjacentScreen(to current: NSScreen,
                                screens: [NSScreen],
                                movingForward: Bool) -> NSScreen? {
        guard let currentIndex = screens.firstIndex(where: { $0 === current }),
              let destinationIndex = WindowLayoutGeometry.adjacentDisplayIndex(
                currentIndex: currentIndex,
                frames: screens.map(\.frame),
                movingForward: movingForward
              )
        else { return nil }
        return screens[destinationIndex]
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

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
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
    let key: WindowLayoutWindowKey
    let frame: WindowLayoutFrame

    var windowID: CGWindowID { key.windowID }
}

private struct WindowDirectionalSession {
    let target: WindowLayoutTarget
    let visibleFrame: NSRect
    let pointerOrigin: CGPoint
    var action: WindowDirectionalAction?
    var manualOverride: WindowDirectionalAction?
}

/// Native glass-ring container; no upstream artwork or media is bundled.
private final class WindowDirectionalIndicatorView: NSView {
    private let canvas: WindowDirectionalIndicatorCanvasView

    var action: WindowDirectionalAction? {
        didSet { canvas.action = action }
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: frameRect.size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        canvas = WindowDirectionalIndicatorCanvasView(
            frame: CGRect(origin: .zero, size: frameRect.size))
        canvas.autoresizingMask = [.width, .height]
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = frameRect.width / 2
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        addSubview(effect)
        addSubview(canvas, positioned: .above, relativeTo: effect)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

/// The canvas stays separate from `NSVisualEffectView`: AppKit may composite
/// the material after a visual-effect subclass draws, hiding custom artwork.
private final class WindowDirectionalIndicatorCanvasView: NSView {
    var action: WindowDirectionalAction? { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        let outerRadius: CGFloat = 84
        let innerRadius: CGFloat = 46
        let track = annulus(center: center, outer: outerRadius, inner: innerRadius)

        // 1. Subtle frosted track background
        context.saveGState()
        context.addPath(track)
        context.setFillColor(NSColor(white: 0.10, alpha: 0.35).cgColor)
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        // 2. Soft borders for track
        context.saveGState()
        context.addPath(track)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(0.75)
        context.strokePath()
        context.restoreGState()

        // 3. Highlight active sector if one of the 8 directions is active
        if let direction = Direction(action: action) {
            let highlight = sector(center: center,
                                   outer: outerRadius - 1.5,
                                   inner: innerRadius + 1.5,
                                   centerAngle: direction.angle)
            context.saveGState()
            context.addPath(highlight)
            context.clip()

            let accent = NSColor.controlAccentColor
            let lighterAccent = accent.blended(withFraction: 0.30, of: .white) ?? accent
            let colors = [
                lighterAccent.withAlphaComponent(0.85).cgColor,
                accent.withAlphaComponent(0.75).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0, 1]) {
                let rad = direction.angle * .pi / 180
                let startPoint = CGPoint(x: center.x + cos(rad) * innerRadius,
                                         y: center.y + sin(rad) * innerRadius)
                let endPoint = CGPoint(x: center.x + cos(rad) * outerRadius,
                                       y: center.y + sin(rad) * outerRadius)
                context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
            }
            context.restoreGState()
        }

        // 4. Subtle dividers between the 8 sectors
        drawDividers(center: center, inner: innerRadius + 4, outer: outerRadius - 4, context: context)

        // 5. Directional pips on the outer ring
        drawDirectionPips(center: center, radius: (innerRadius + outerRadius) / 2, activeDirection: Direction(action: action), context: context)

        // 6. Center Hub & Glyph
        drawCenterHub(center: center, action: action, context: context)
    }

    private func annulus(center: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer,
                                   width: outer * 2, height: outer * 2))
        path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner,
                                   width: inner * 2, height: inner * 2))
        return path
    }

    private func sector(center: CGPoint, outer: CGFloat, inner: CGFloat,
                        centerAngle: CGFloat) -> CGPath {
        let start = (centerAngle - 22.5) * .pi / 180
        let end = (centerAngle + 22.5) * .pi / 180
        let path = CGMutablePath()
        path.addArc(center: center, radius: outer, startAngle: start,
                    endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end,
                    endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    private func drawDividers(center: CGPoint, inner: CGFloat, outer: CGFloat,
                              context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(0.6)
        for angle in stride(from: CGFloat(22.5), to: 360, by: 45) {
            let radians = angle * .pi / 180
            context.move(to: CGPoint(x: center.x + cos(radians) * inner,
                                     y: center.y + sin(radians) * inner))
            context.addLine(to: CGPoint(x: center.x + cos(radians) * outer,
                                        y: center.y + sin(radians) * outer))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawDirectionPips(center: CGPoint, radius: CGFloat,
                                   activeDirection: Direction?, context: CGContext) {
        for direction in Direction.allCases {
            let isActive = direction == activeDirection
            let rad = direction.angle * .pi / 180
            let pipCenter = CGPoint(x: center.x + cos(rad) * radius,
                                    y: center.y + sin(rad) * radius)
            let pipRadius: CGFloat = isActive ? 3.5 : 2.0
            let pipRect = CGRect(x: pipCenter.x - pipRadius,
                                 y: pipCenter.y - pipRadius,
                                 width: pipRadius * 2,
                                 height: pipRadius * 2)
            context.saveGState()
            if isActive {
                context.setShadow(offset: .zero, blur: 8,
                                  color: NSColor.white.withAlphaComponent(0.8).cgColor)
                context.setFillColor(NSColor.white.cgColor)
            } else {
                context.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            }
            context.fillEllipse(in: pipRect)
            context.restoreGState()
        }
    }

    private func drawCenterHub(center: CGPoint, action: WindowDirectionalAction?, context: CGContext) {
        let radius: CGFloat = 38
        let hub = CGRect(x: center.x - radius, y: center.y - radius,
                         width: radius * 2, height: radius * 2)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 10,
                          color: NSColor.black.withAlphaComponent(0.25).cgColor)

        if action == .maximize {
            let accent = NSColor.controlAccentColor
            context.setFillColor(accent.withAlphaComponent(0.30).cgColor)
            context.fillEllipse(in: hub)
            context.restoreGState()

            context.setStrokeColor(accent.withAlphaComponent(0.80).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: hub.insetBy(dx: 0.5, dy: 0.5))
        } else if action == .minimize {
            context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.22).cgColor)
            context.fillEllipse(in: hub)
            context.restoreGState()

            context.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: hub.insetBy(dx: 0.5, dy: 0.5))
        } else {
            context.setFillColor(NSColor(white: 0.14, alpha: 0.80).cgColor)
            context.fillEllipse(in: hub)
            context.restoreGState()

            context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: hub.insetBy(dx: 0.5, dy: 0.5))
        }

        // Miniature macOS window frame
        let window = CGRect(x: center.x - 16, y: center.y - 12, width: 32, height: 24)
        let outline = CGPath(roundedRect: window, cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)

        context.saveGState()
        context.addPath(outline)
        if action == .maximize {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        } else if action == .minimize {
            context.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.90).cgColor)
        } else if action != nil {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        } else {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.50).cgColor)
        }
        context.setLineWidth(1.4)
        context.strokePath()
        context.restoreGState()

        // Content area inside window
        if action == .minimize {
            let arrowPath = CGMutablePath()
            arrowPath.move(to: CGPoint(x: center.x, y: center.y + 4.5))
            arrowPath.addLine(to: CGPoint(x: center.x, y: center.y - 3.5))
            arrowPath.move(to: CGPoint(x: center.x - 4, y: center.y - 0.5))
            arrowPath.addLine(to: CGPoint(x: center.x, y: center.y - 4.5))
            arrowPath.addLine(to: CGPoint(x: center.x + 4, y: center.y - 0.5))

            context.saveGState()
            context.addPath(arrowPath)
            context.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(1.8)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            context.restoreGState()
        } else if action == .maximize {
            let inner = window.insetBy(dx: 2.5, dy: 2.5)
            context.saveGState()
            let fillPath = CGPath(roundedRect: inner, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            context.addPath(fillPath)
            context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.95).cgColor)
            context.fillPath()
            context.restoreGState()
        } else if let action, let region = glyphRegion(for: action, in: window.insetBy(dx: 2.5, dy: 2.5)) {
            context.saveGState()
            let fillPath = CGPath(roundedRect: region, cornerWidth: 2, cornerHeight: 2, transform: nil)
            context.addPath(fillPath)
            context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.95).cgColor)
            context.fillPath()
            context.restoreGState()
        }
    }

    private func glyphRegion(for action: WindowDirectionalAction, in rect: CGRect) -> CGRect? {
        switch action {
        case .leftHalf: return CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .rightHalf: return CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .topHalf: return CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
        case .bottomHalf: return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
        case .topLeft: return CGRect(x: rect.minX, y: rect.midY, width: rect.width / 2, height: rect.height / 2)
        case .topRight: return CGRect(x: rect.midX, y: rect.midY, width: rect.width / 2, height: rect.height / 2)
        case .bottomLeft: return CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height / 2)
        case .bottomRight: return CGRect(x: rect.midX, y: rect.midY, width: rect.width / 2, height: rect.height / 2)
        case .maximize: return rect
        case .minimize: return nil
        }
    }

    private enum Direction: CaseIterable {
        case right, topRight, top, topLeft, left, bottomLeft, bottom, bottomRight

        var angle: CGFloat {
            switch self {
            case .right: return 0
            case .topRight: return 45
            case .top: return 90
            case .topLeft: return 135
            case .left: return 180
            case .bottomLeft: return 225
            case .bottom: return 270
            case .bottomRight: return 315
            }
        }

        var action: WindowDirectionalAction {
            switch self {
            case .right: return .rightHalf
            case .topRight: return .topRight
            case .top: return .topHalf
            case .topLeft: return .topLeft
            case .left: return .leftHalf
            case .bottomLeft: return .bottomLeft
            case .bottom: return .bottomHalf
            case .bottomRight: return .bottomRight
            }
        }

        init?(action: WindowDirectionalAction?) {
            guard let action, let value = Self.allCases.first(where: { $0.action == action }) else {
                return nil
            }
            self = value
        }
    }
}

/// Everything the deferred settle verification needs to finish judging a
/// discrete layout action after the grace period.
private struct SettleContext {
    let window: AXUIElement
    let windowID: CGWindowID
    let frame: WindowLayoutFrame
    let targetRect: NSRect
    let screenVisibleFrame: NSRect
    let action: WindowLayoutAction
    let original: WindowLayoutFrame?
    let previousAction: WindowLayoutAction?
    let windowKey: WindowLayoutWindowKey
    /// Which published result this settle belongs to; a late failure only
    /// speaks when no newer action has published since.
    let resultGeneration: Int
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

private enum WindowEdgeSnapPointerInput {
    case down(location: CGPoint, flags: CGEventFlags)
    case dragged(location: CGPoint)
    case up(location: CGPoint)
}

private struct WindowEdgeSnapDrag {
    let window: AXUIElement
    let key: WindowLayoutWindowKey
    let initialFrame: CGRect
    let pointerStart: CGPoint
    let protectsSystemTopEdge: Bool
    let quartzScreenFrames: [CGRect]
    var lastSampleAt: TimeInterval
    var mismatchCount: Int
    var isMoving: Bool
    var target: WindowEdgeSnapTarget?
}

/// A press the tap is holding while it is still undecided. It keeps the
/// original event so the click can be handed back untouched, with its
/// modifiers and its click count intact.
private struct PendingWindowGesture {
    let down: CGEvent
    let button: WindowPointerGesture.Button
    let kind: WindowPointerGesture.Kind
    let window: AXUIElement
    let app: NSRunningApplication
    let originalFrame: CGRect
    let origin: CGPoint
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

private final class WindowEdgeSnapPreviewView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateAppearance()
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        updateAppearance()
        setAccessibilityElement(false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let accent = NSColor.controlAccentColor
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.backgroundColor = accent.withAlphaComponent(0.16).cgColor
        layer.borderColor = accent.withAlphaComponent(0.88).cgColor
        layer.borderWidth = 2
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
