// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics

/// Rewrites mouse wheel events only, leaving the trackpad on macOS natural
/// scrolling: a modifying tap at the HID level (before the window server
/// derives pixel deltas from the wheel ticks), appended at the tail. It caps
/// every event at one notch for linear scrolling, redirects modifier-held
/// vertical ticks when requested and flips the selected axis deltas; any of
/// those features keeps the tap alive.
///
/// Wheel detection: discrete events (`isContinuous == 0`) are wheels; events
/// flagged continuous are wheels only when they carry no gesture phase at all.
/// Toggling takes effect immediately. Requires Accessibility.
///
/// Apps on this feature's own exception list (issue #358) keep the direction
/// macOS gives them. The list is separate from the smooth scrolling one on
/// purpose, so excepting an app from the glide never leaves it scrolling
/// backwards; when both features are on, the flip happens inside the smooth
/// scrolling tap and honors this same list. Linear scrolling keeps a list of
/// its own, honored the same way in both taps, so a game or a 3D tool that
/// counts the notches itself can be left out of the cap alone.
final class ScrollInverter: ObservableObject {
    static let shared = ScrollInverter()

    /// True while the wheel tap is installed, for any feature it serves.
    @Published private(set) var isRunning = false

    /// This process's own id, compared against the one every event carries.
    private static let ownProcessID = Int64(getpid())

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Guards the two above: the callback runs on the pointer thread while the
    /// main thread arms and tears the tap down.
    private let tapStateLock = NSLock()
    /// Timestamp (ns, event clock) of the last event carrying a gesture phase —
    /// only touch devices emit those. Read/written solely on the tap callback,
    /// which is the pointer thread and nothing else.
    private var lastGesturePhaseTimestamp: UInt64?
    private let pinchZoomLock = NSLock()
    private var zoomState = ScrollZoomGestureState()
    private var zoomStepLimiter = ScrollZoomStepLimiter()
    private let zoomTargetQueue = DispatchQueue(label: "com.vorssaint.mouse.zoom-target", qos: .userInitiated)
    private var zoomTarget: (modifier: ScrollHorizontalModifier, window: WindowServerWindowCandidate)?
    private var zoomTargetPending: (modifier: ScrollHorizontalModifier, point: CGPoint)?
    private var zoomTargetMiss: (modifier: ScrollHorizontalModifier, point: CGPoint, at: TimeInterval)?
    private var zoomTargetGeneration: UInt64 = 0
    private var zoomInKeyStroke: (keyCode: CGKeyCode, needsShift: Bool)?
    private var zoomOutKeyStroke: (keyCode: CGKeyCode, needsShift: Bool)?
    private var zoomKeyboardObserver: NSObjectProtocol?
    /// Fractions of a line linear scrolling has yet to deliver, one per axis.
    /// Tap callback only, like the timestamp above.
    private var linearCarryVertical: Double = 0
    private var linearCarryHorizontal: Double = 0
    private var tapCreationRetryUsed = false
    private var tapCreationRetryWork: DispatchWorkItem?

    private init() {
        // Fast user switching: the tap goes back while this session is off
        // screen and is built again from the preferences on the way in.
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let direction = ScrollDirectionPreferences()
        pinchZoomLock.withLock {
            if zoomState.update(direction.zoom) {
                postPinch(phase: 4, magnification: 0)
            }
            invalidateZoomTargetLocked()
        }
        if SessionActivitySupport.tapShouldRun(featureWanted: direction.isEnabled || Self.linearScrollWanted,
                                               accessibilityGranted: Permissions.shared.accessibility,
                                               sessionIsActive: SessionActivity.shared.isActive) {
            ScrollWheelTarget.shared.setEnabled(direction.horizontalModifier != nil)
            start(zoom: direction.zoom)
        } else {
            stop()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() { stop() }

    /// Linear scrolling keeps the tap alive on its own, next to the direction
    /// features; its keys survive the hub uninstalling it.
    private static var linearScrollWanted: Bool {
        AppFeature.linearScroll.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.linearScrollEnabled)
    }

    /// Each list's source apps are tracked only while its feature is one the
    /// tap is up for, so a list left behind by the other feature costs nothing.
    private func setSourceTracking(_ running: Bool) {
        let exceptions = MouseAppExceptions.shared
        exceptions.setSourceTracking(running && ScrollDirectionPreferences().isEnabled, for: .scrollDirection)
        exceptions.setSourceTracking(running && Self.linearScrollWanted, for: .linearScroll)
    }

    private func start(zoom: ScrollZoomPreferences) {
        if let port = tapStateLock.withLock({ tap }) {
            CGEvent.tapEnable(tap: port, enable: true)
            setSourceTracking(true)
            syncZoomKeyboardLayout(zoom: zoom)
            pinchZoomLock.withLock { zoomState.start() }
            isRunning = true
            return
        }
        setSourceTracking(true)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: (CGEventMask(1 << CGEventType.scrollWheel.rawValue)
                | CGEventMask(1 << CGEventType.flagsChanged.rawValue)),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let inverter = Unmanaged<ScrollInverter>.fromOpaque(userInfo).takeUnretainedValue()
                return inverter.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            ScrollWheelTarget.shared.setEnabled(false)
            setSourceTracking(false)
            isRunning = false
            // A create that fails during the session handoff gets one more look once the switch settles.
            guard !tapCreationRetryUsed else { return }
            tapCreationRetryUsed = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.tapCreationRetryWork = nil
                self.syncWithPreferences()
            }
            tapCreationRetryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            return
        }

        tapCreationRetryUsed = false
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapStateLock.withLock {
            self.tap = tap
            runLoopSource = source
        }
        if let source {
            PointerTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        syncZoomKeyboardLayout(zoom: zoom)
        pinchZoomLock.withLock { zoomState.start() }
        isRunning = true
    }

    private func stop() {
        syncZoomKeyboardLayout(zoom: nil)
        pinchZoomLock.withLock {
            if zoomState.stop() { postPinch(phase: 4, magnification: 0) }
            invalidateZoomTargetLocked()
        }
        ScrollWheelTarget.shared.setEnabled(false)
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        tapCreationRetryUsed = false
        setSourceTracking(false)
        let (port, source) = tapStateLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        // Hand the tap back rather than only switching it off: a disabled tap
        // keeps its place in the chain, and a session that is switched away
        // has to stop being an event tap owner outright (issue #1075).
        if let source {
            PointerTapRunLoop.remove(source, invalidating: port)
        }
        linearCarryVertical = 0
        linearCarryHorizontal = 0
        isRunning = false
    }

    private func syncZoomKeyboardLayout(zoom: ScrollZoomPreferences?) {
        guard zoom?.verticalZoom != nil || zoom?.horizontalZoom != nil else {
            if let zoomKeyboardObserver {
                NotificationCenter.default.removeObserver(zoomKeyboardObserver)
                self.zoomKeyboardObserver = nil
            }
            pinchZoomLock.withLock {
                zoomInKeyStroke = nil
                zoomOutKeyStroke = nil
            }
            return
        }
        refreshZoomKeyboardLayout()
        if zoomKeyboardObserver == nil {
            zoomKeyboardObserver = NotificationCenter.default.addObserver(
                forName: GlobalShortcut.keyboardLayoutDidChange, object: nil, queue: .main
            ) { [weak self] _ in self?.refreshZoomKeyboardLayout() }
        }
    }

    private func refreshZoomKeyboardLayout() {
        guard Thread.isMainThread else { return }
        let zoomIn = MouseNavigationKeys.keyStroke(for: "+")
        let zoomOut = MouseNavigationKeys.keyStroke(for: "-")
        pinchZoomLock.withLock {
            zoomInKeyStroke = zoomIn
            zoomOutKeyStroke = zoomOut
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when the session locks; re-arm,
        // unless this session is the one that was switched away from, where
        // the stall is the reason the tap was disabled and re-arming feeds it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, let port = tapStateLock.withLock({ tap }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            pinchZoomLock.withLock {
                if let modifier = zoomState.pinchModifier,
                   event.flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand]) != modifier.flag {
                    endPinchZoomLocked()
                }
                prepareZoomTargetLocked(for: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        // Smooth scrolling swallows the wheel before this tap and already
        // turned its glide around, so flipping the glide here would cancel
        // that out and inverting would look broken while both are on. The
        // process id is checked too: the only scroll events this app posts
        // are those glide frames.
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              sourceProcessID != Self.ownProcessID else {
            return Unmanaged.passUnretained(event)
        }

        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let timestamp = EventTimestamp.nanoseconds(of: event)
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            lastGesturePhaseTimestamp = timestamp
        }

        guard ScrollWheelSupport.isMouseWheel(traits,
                                              secondsSinceLastGesturePhase: secondsSinceGesturePhase)
        else { return Unmanaged.passUnretained(event) }

        let defaults = UserDefaults.standard
        let direction = ScrollDirectionPreferences(defaults: defaults)
        let directionApplies = direction.isEnabled
            && !MouseAppExceptions.shared.excludesPointerTarget(
                .scrollDirection, at: event.location, sourceProcessID: sourceProcessID)
        if directionApplies, direction.zoom.action(for: event) != nil {
            return consumeZoom(event, direction: direction) ? nil : Unmanaged.passUnretained(event)
        }
        // Control-wheel is native zoom. Only the explicit Control-to-horizontal
        // shortcut turns it into scrolling; a direction exception or one of
        // our own windows leaves it as zoom too.
        let controlRedirects = directionApplies
            && direction.horizontalModifier == .control
            && event.flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand]) == .maskControl
            && ScrollWheelSupport.isVerticalOnly(event)
            && !ScrollWheelTarget.shared.contains(event.location)
        let nativeZoom = event.flags.contains(.maskControl) && !controlRedirects
        if let linesPerNotch = nativeZoom ? nil : ScrollWheelSupport.linearLinesPerNotch(
            defaults: defaults,
            isAvailable: AppFeature.linearScroll.isAvailable,
            isExcepted: {
                MouseAppExceptions.shared.excludesPointerTarget(
                    .linearScroll,
                    at: event.location,
                    sourceProcessID: sourceProcessID)
            }) {
            // Capture both axes before any set: writing a line delta makes the
            // system rederive its point and fixed-point fields.
            let rawVertical = ScrollWheelAxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
            let rawHorizontal = ScrollWheelAxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
            let linearVertical = ScrollWheelSupport.linearDelta(
                rawVertical, isContinuous: traits.isContinuous,
                linesPerNotch: linesPerNotch, carry: linearCarryVertical)
            let linearHorizontal = ScrollWheelSupport.linearDelta(
                rawHorizontal, isContinuous: traits.isContinuous,
                linesPerNotch: linesPerNotch, carry: linearCarryHorizontal)
            linearCarryVertical = linearVertical.carry
            linearCarryHorizontal = linearHorizontal.carry
            // A fraction of a notch is carried into the next event rather
            // than delivered as an event that moves nothing.
            if rawVertical.hasMovement || rawHorizontal.hasMovement,
               !linearVertical.delta.hasMovement, !linearHorizontal.delta.hasMovement {
                return nil
            }
            // Every axis that moves is written back, even when the capped line
            // matches the one already there: a discrete event's line is what
            // the system rederives the other fields from, so writing it is
            // what takes a high-resolution wheel's leftover fraction out.
            ScrollWheelSupport.writeLinear(
                vertical: rawVertical.hasMovement ? linearVertical.delta : nil,
                horizontal: rawHorizontal.hasMovement ? linearHorizontal.delta : nil,
                to: event, isContinuous: traits.isContinuous)
        } else {
            // A fraction belongs to the active linear stream. Do not let it
            // reappear after an excepted app or an off/uninstalled interval.
            linearCarryVertical = 0
            linearCarryHorizontal = 0
        }

        // The direction features read their own availability here: linear
        // scrolling may be what keeps this tap alive, so the tap running says
        // nothing about whether the wheel should be turned or redirected.
        if directionApplies {
            ScrollWheelSupport.applyDirection(
                to: event, isContinuous: traits.isContinuous,
                invertVertical: direction.invertVertical,
                invertHorizontal: direction.invertHorizontal,
                horizontalModifier: direction.horizontalModifier,
                targetsOwnWindow: ScrollWheelTarget.shared.contains(event.location)
            )
        }
        return Unmanaged.passUnretained(event)
    }

    /// Consumes a configured zoom wheel action. Called by both scroll taps so
    /// Smooth Scrolling cannot turn a zoom command into a synthetic glide.
    func consumeZoom(_ event: CGEvent, direction: ScrollDirectionPreferences) -> Bool {
        guard !AppSwitcher.shared.scrollNavigationActive else { return false }
        guard let action = direction.zoom.action(for: event) else { return false }
        let delta = ScrollWheelSupport.zoomDelta(action.delta, axis: action.axis,
                                                  invertVertical: direction.invertVertical,
                                                  invertHorizontal: direction.invertHorizontal)
        return pinchZoomLock.withLock {
            guard zoomState.accepts(direction.zoom) else { return false }
            if action.effect == .pinch {
                postPinchZoomLocked(delta, modifier: action.modifier)
                return true
            }
            guard let zoomTarget,
                  zoomTarget.modifier == action.modifier,
                  zoomTarget.window.frame.contains(event.location) else {
                requestZoomTargetLocked(at: event.location, modifier: action.modifier)
                return false
            }
            if !zoomStepLimiter.allows(delta, at: EventTimestamp.nanoseconds(of: event)) {
                return true
            }
            guard postKeyboardZoom(delta, targetProcessID: zoomTarget.window.pid) else {
                zoomStepLimiter.reset()
                return false
            }
            endPinchZoomLocked()
            return true
        }
    }

    private func prepareZoomTargetLocked(for event: CGEvent) {
        let held = event.flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand])
        if let zoom = zoomState.preferences, zoomState.accepts(zoom),
           let modifier = [zoom.verticalZoom, zoom.horizontalZoom].compactMap({ $0 }).first(where: { $0.flag == held }) {
            requestZoomTargetLocked(at: event.location, modifier: modifier)
        } else {
            invalidateZoomTargetLocked()
        }
    }

    private func invalidateZoomTargetLocked() {
        zoomTargetGeneration &+= 1
        zoomTarget = nil
        zoomTargetPending = nil
        zoomTargetMiss = nil
        zoomStepLimiter.reset()
    }

    private func requestZoomTargetLocked(at point: CGPoint, modifier: ScrollHorizontalModifier) {
        if let zoomTarget, zoomTarget.modifier == modifier,
           zoomTarget.window.frame.contains(point) { return }
        if let zoomTargetPending, zoomTargetPending.modifier == modifier,
           zoomTargetPending.point == point { return }
        if let zoomTargetMiss, zoomTargetMiss.modifier == modifier,
           zoomTargetMiss.point == point,
           ProcessInfo.processInfo.systemUptime - zoomTargetMiss.at < 0.5 { return }
        invalidateZoomTargetLocked()
        zoomTargetPending = (modifier, point)
        let generation = zoomTargetGeneration
        zoomTargetQueue.async { [weak self] in
            guard let self else { return }
            guard self.pinchZoomLock.withLock({ self.zoomTargetGeneration == generation }) else { return }
            let window = WindowServerSupport.keyboardZoomTarget(
                in: WindowServerSupport.onScreenWindowInfo(), at: point,
                ownProcessID: getpid(), focusedWindowID: WindowActivator.focusedWindowID(for:))
            self.pinchZoomLock.withLock {
                guard self.zoomTargetGeneration == generation else { return }
                self.zoomTargetPending = nil
                if let window {
                    self.zoomTarget = (modifier, window)
                } else {
                    self.zoomTargetMiss = (modifier, point, ProcessInfo.processInfo.systemUptime)
                }
            }
        }
    }

    private func postKeyboardZoom(_ delta: Double, targetProcessID: pid_t) -> Bool {
        guard let keyStroke = delta > 0 ? zoomInKeyStroke : zoomOutKeyStroke else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyStroke.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyStroke.keyCode, keyDown: false) else { return false }
        down.flags = keyStroke.needsShift ? [.maskCommand, .maskShift] : .maskCommand
        up.flags = down.flags
        down.postToPid(targetProcessID)
        up.postToPid(targetProcessID)
        return true
    }

    private func postPinchZoomLocked(_ delta: Double, modifier: ScrollHorizontalModifier) {
        let transition = zoomState.beginPinch(modifier)
        if transition.endPrevious { postPinch(phase: 4, magnification: 0) }
        if transition.begin { postPinch(phase: 1, magnification: 0) }
        postPinch(phase: 2, magnification: delta * 0.005)
    }

    private func endPinchZoomLocked() {
        if zoomState.endPinch() { postPinch(phase: 4, magnification: 0) }
    }

    private func postPinch(phase: Int64, magnification: Double) {
        guard let gesture = CGEvent(source: nil) else { return }
        gesture.type = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
        gesture.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8)
        gesture.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
        gesture.setDoubleValueField(CGEventField(rawValue: 113)!, value: magnification)
        gesture.post(tap: .cgSessionEventTap)
    }
}
