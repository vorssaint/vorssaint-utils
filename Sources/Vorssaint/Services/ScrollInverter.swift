// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

/// Inverts the scroll direction of mouse wheels only, leaving the trackpad on
/// macOS natural scrolling: a modifying tap at the HID level (before the window
/// server derives pixel deltas from the
/// wheel ticks), appended at the tail, flipping the selected axis deltas.
///
/// Wheel detection: discrete events (`isContinuous == 0`) are wheels; events
/// flagged continuous are wheels only when they carry no gesture phase at all.
/// Toggling takes effect immediately. Requires Accessibility.
///
/// Apps on this feature's own exception list (issue #358) keep the direction
/// macOS gives them. The list is separate from the smooth scrolling one on
/// purpose, so excepting an app from the glide never leaves it scrolling
/// backwards; when both features are on, the flip happens inside the smooth
/// scrolling tap and honors this same list.
final class ScrollInverter: ObservableObject {
    static let shared = ScrollInverter()

    /// True while the event tap is installed and inverting.
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
        let defaults = UserDefaults.standard
        let wanted = AppFeature.scrollInverter.isAvailable
            && (defaults.bool(forKey: DefaultsKey.scrollInverterEnabled)
                || defaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled))
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: Permissions.shared.accessibility,
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() { stop() }

    private func start() {
        if let port = tapStateLock.withLock({ tap }) {
            CGEvent.tapEnable(tap: port, enable: true)
            MouseAppExceptions.shared.setSourceTracking(true, for: .scrollDirection)
            isRunning = true
            return
        }
        MouseAppExceptions.shared.setSourceTracking(true, for: .scrollDirection)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let inverter = Unmanaged<ScrollInverter>.fromOpaque(userInfo).takeUnretainedValue()
                return inverter.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            MouseAppExceptions.shared.setSourceTracking(false, for: .scrollDirection)
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
        isRunning = true
    }

    private func stop() {
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        tapCreationRetryUsed = false
        MouseAppExceptions.shared.setSourceTracking(false, for: .scrollDirection)
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
        isRunning = false
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
        let timestamp = UInt64(event.timestamp)
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            lastGesturePhaseTimestamp = timestamp
        }

        if ScrollWheelSupport.isMouseWheel(traits,
                                           secondsSinceLastGesturePhase: secondsSinceGesturePhase),
           !MouseAppExceptions.shared.excludesPointerTarget(
                .scrollDirection,
                at: event.location,
                sourceProcessID: sourceProcessID) {
            // Capture both axes before any set: writing a line delta makes the
            // system rederive its point and fixed-point fields.
            let verticalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let verticalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let horizontalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let horizontalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let defaults = UserDefaults.standard
            let hasVerticalMovement = verticalLine != 0 || verticalPoint != 0 || verticalFixedPoint != 0
            let hasHorizontalMovement = horizontalLine != 0
                || horizontalPoint != 0
                || horizontalFixedPoint != 0
            let plan = ScrollWheelSupport.inversionPlan(
                hasVerticalMovement: hasVerticalMovement,
                hasHorizontalMovement: hasHorizontalMovement,
                shiftRedirectsVertical: !traits.isContinuous && event.flags.contains(.maskShift),
                invertVertical: defaults.bool(forKey: DefaultsKey.scrollInverterEnabled),
                invertHorizontal: defaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled)
            )
            if plan.vertical {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -verticalLine)
                if traits.isContinuous {
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -verticalPoint)
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -verticalFixedPoint)
                }
            }
            if plan.horizontal {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -horizontalLine)
                if traits.isContinuous {
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -horizontalPoint)
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -horizontalFixedPoint)
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
