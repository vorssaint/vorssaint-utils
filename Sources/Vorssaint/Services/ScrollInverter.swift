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
/// flagged continuous are wheels only when they carry no gesture phase at all
/// (covers drivers that synthesize continuous wheel scrolling). Toggling takes
/// effect immediately. Requires Accessibility.
final class ScrollInverter: ObservableObject {
    static let shared = ScrollInverter()

    /// True while the event tap is installed and inverting.
    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.scrollInverterEnabled)
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

        if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
            // Classic wheel tick: flip the line delta and let the window
            // server derive the rest. Vertical only.
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1,
                                       value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        } else if event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
                  event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
                  event.getDoubleValueField(.scrollWheelEventScrollCount) == 0 {
            // Continuous but phase-less: a driver-synthesized wheel event
            // (Logitech & friends). Touch devices always carry phases.
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1,
                                       value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1,
                                       value: -event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1,
                                      value: -event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        }
        return Unmanaged.passUnretained(event)
    }
}
