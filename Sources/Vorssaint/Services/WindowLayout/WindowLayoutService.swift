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
    /// Bumped on every published result, so a late settle failure can tell
    /// whether it still owns the feedback slot.
    private var resultGeneration = 0
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
    private var pendingGesture: PendingWindowGesture?
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
            return setFrame(previous, on: target.window, windowID: target.windowID)
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
                        on: target.window,
                        windowID: target.windowID) {
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
                    on: target.window,
                    windowID: target.windowID) {
            lastActions[target.windowID] = effectiveAction
            return finish(.success(restored: false))
        }
        previousFrames.removeValue(forKey: target.windowID)
        return finish(.failure(.failed))
    }

    private func finish(_ result: WindowLayoutResult) -> WindowLayoutResult {
        resultGeneration += 1
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

    private func setFrame(_ frame: WindowLayoutFrame, on window: AXUIElement, windowID: CGWindowID) -> Bool {
        setFrame(frame,
                 targetRect: appKitFrame(fromAX: frame),
                 screenVisibleFrame: appKitFrame(fromAX: frame),
                 action: .restore,
                 on: window,
                 windowID: windowID)
    }

    private func setFrame(_ frame: WindowLayoutFrame,
                          targetRect: NSRect,
                          screenVisibleFrame: NSRect,
                          action: WindowLayoutAction,
                          on window: AXUIElement,
                          windowID: CGWindowID) -> Bool {
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
        if context.action != .restore {
            previousFrames.removeValue(forKey: context.windowID)
            lastActions.removeValue(forKey: context.windowID)
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
        if let gestureTap {
            CGEvent.tapEnable(tap: gestureTap, enable: false)
        }
        if let gestureRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureRunLoopSource, .commonModes)
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
