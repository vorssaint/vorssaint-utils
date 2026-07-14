// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

/// Turns the mouse wheel's discrete jumps into short glides: a tap swallows
/// each wheel tick and replays its distance as a stream of continuous pixel
/// events that ease out, like a touch device would produce.
///
/// Only real wheel ticks are touched (`isContinuous == 0`); trackpads, Magic
/// Mouse and momentum are passed through untouched. The tap sits at the head
/// so the scroll inverter (appended at the tail) still sees the synthetic
/// stream and can flip it — both features compose. Nothing (tap or timer)
/// exists while the feature is off. Requires Accessibility.
final class SmoothScrollService: ObservableObject {
    static let shared = SmoothScrollService()

    /// True while the event tap is installed.
    @Published private(set) var isRunning = false

    /// Marks the synthetic events so the tap never re-processes its own output.
    private static let syntheticTag: Int64 = 0x564F5253  // "VORS"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var frameTimer: Timer?
    /// Remaining glide distance per axis, in pixels. Touched only on the main
    /// thread (tap callback and timer both live on the main run loop).
    private var remainingVertical: Double = 0
    private var remainingHorizontal: Double = 0
    /// Modifiers of the wheel event that started or fed the glide, replayed on
    /// the synthetic events so apps can still react to them.
    private var currentFlags: CGEventFlags = []
    /// Sign correction for the system's natural scroll direction, sampled
    /// when a glide starts.
    private var postSign: Double = 1

    private init() {}

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let wanted = AppFeature.smoothScroll.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.smoothScrollEnabled)
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
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<SmoothScrollService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
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
        stopGlide()
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when the session locks; re-arm.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        // Our own glide stream coming back through the tap.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticTag else {
            return Unmanaged.passUnretained(event)
        }
        // Touch devices and continuous wheels are already smooth.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0
        else { return Unmanaged.passUnretained(event) }
        // Control-scroll drives screen zoom; keep its stepping predictable.
        guard !event.flags.contains(.maskControl) else {
            return Unmanaged.passUnretained(event)
        }

        // A process's own posted events skip its own taps (verified), so the
        // scroll inverter never sees the glide stream: when it is on, the
        // wheel's vertical flip is applied here instead.
        let invert = ScrollInverter.shared.isRunning ? -1.0 : 1.0
        let shiftPressed = event.flags.contains(.maskShift)
        let axes = SmoothScrollSupport.axes(
            vertical: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * invert,
            horizontal: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            shiftPressed: shiftPressed
        )
        let vertical = axes.vertical
        let horizontal = axes.horizontal
        guard vertical != 0 || horizontal != 0 else {
            return Unmanaged.passUnretained(event)
        }

        let step = Double(SmoothScrollSupport.sanitizedStep(
            UserDefaults.standard.integer(forKey: DefaultsKey.smoothScrollStep)))
        // Switching Shift while a glide is active changes the intended axis.
        // Drop the old tail instead of briefly scrolling diagonally.
        if currentFlags.contains(.maskShift) != shiftPressed {
            remainingVertical = 0
            remainingHorizontal = 0
        }
        remainingVertical = SmoothScrollSupport.remaining(afterTicks: vertical,
                                                          step: step,
                                                          current: remainingVertical)
        remainingHorizontal = SmoothScrollSupport.remaining(afterTicks: horizontal,
                                                            step: step,
                                                            current: remainingHorizontal)
        currentFlags = event.flags
        if frameTimer == nil {
            postSign = SmoothScrollSupport.postedDelta(1, naturalScrolling: Self.naturalScrollingOn())
        }
        startGlideIfNeeded()
        // The tick itself is swallowed; the glide replays its distance.
        return nil
    }

    // MARK: - Glide

    private func startGlideIfNeeded() {
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: SmoothScrollSupport.frameInterval, repeats: true) { [weak self] _ in
            self?.emitFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        emitFrame()
    }

    private func stopGlide() {
        frameTimer?.invalidate()
        frameTimer = nil
        remainingVertical = 0
        remainingHorizontal = 0
    }

    private func emitFrame() {
        let vertical = SmoothScrollSupport.frameDelta(remaining: remainingVertical)
        let horizontal = SmoothScrollSupport.frameDelta(remaining: remainingHorizontal)
        remainingVertical -= vertical
        remainingHorizontal -= horizontal

        if vertical != 0 || horizontal != 0 {
            post(vertical: vertical, horizontal: horizontal)
        }
        if remainingVertical == 0, remainingHorizontal == 0 {
            frameTimer?.invalidate()
            frameTimer = nil
        }
    }

    private func post(vertical: Double, horizontal: Double) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Int32((vertical * postSign).rounded()),
                                  wheel2: Int32((horizontal * postSign).rounded()),
                                  wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        event.flags = currentFlags
        event.post(tap: .cghidEventTap)
    }

    /// The user's "natural scrolling" system preference (macOS default: on).
    private static func naturalScrollingOn() -> Bool {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] as? Bool) ?? true
    }
}
