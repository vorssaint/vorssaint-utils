// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

/// Inverts the scroll direction of mouse wheels only, leaving the trackpad on
/// macOS natural scrolling: a modifying tap at the HID level (before the window
/// server derives pixel deltas from the
/// wheel ticks), appended at the tail, flipping only the line delta.
///
/// Wheel detection: discrete events (`isContinuous == 0`) are wheels; events
/// flagged continuous are wheels only when they carry no gesture phase at all.
/// Toggling takes effect immediately. Requires Accessibility.
final class ScrollInverter: ObservableObject {
    static let shared = ScrollInverter()

    /// True while the event tap is installed and inverting.
    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Timestamp (ns, event clock) of the last event carrying a gesture phase —
    /// only touch devices emit those. Read/written solely on the tap callback.
    private var lastGesturePhaseTimestamp: UInt64?

    private init() {}

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let wanted = AppFeature.scrollInverter.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.scrollInverterEnabled)
        if wanted, Permissions.shared.accessibility {
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
        guard tap == nil else {
            isRunning = true
            return
        }
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
            isRunning = false
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when the session locks; re-arm.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

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

        if ScrollInverterSupport.shouldInvertMouseWheel(traits,
                                                        secondsSinceLastGesturePhase: secondsSinceGesturePhase) {
            // All three deltas must be captured BEFORE any set: writing the
            // line delta makes the system rederive the point and fixed-point
            // fields from it, so negating a re-read value flips it back to
            // positive and the inversion silently cancels itself on exactly
            // the fields apps use for continuous events. Vertical only.
            let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let point = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let fixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -line)
            if traits.isContinuous {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -point)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedPoint)
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
