// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

/// Turns the mouse wheel's discrete jumps into short glides: a tap swallows
/// each wheel tick and replays its distance as a stream of continuous pixel
/// events that ease out, like a touch device would produce.
///
/// Wheel detection matches the scroll inverter (`ScrollWheelSupport`), so
/// mice whose drivers report the wheel as continuous pixel events (issue
/// #267) glide too; trackpads, Magic Mouse and momentum
/// are passed through untouched. The tap sits at the head
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
    /// when a glide starts or the feeding device type changes.
    private var postSign: Double = 1
    /// Whether the glide is being fed by continuous wheel events; discrete
    /// and continuous sources need different sign handling, so switching
    /// devices mid-glide drops the tail and resamples.
    private var glideFromContinuous = false
    /// Timestamp (ns, event clock) of the last event carrying a gesture phase —
    /// only touch devices emit those. Read/written solely on the tap callback.
    private var lastGesturePhaseTimestamp: UInt64?

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
        // Touch devices are already smooth; only mouse wheels glide. The
        // classification is shared with the scroll inverter, so mice that
        // report the wheel as continuous events (issue #267) are wheels too.
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
        guard ScrollWheelSupport.isMouseWheel(traits,
                                              secondsSinceLastGesturePhase: secondsSinceGesturePhase)
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
        let vertical: Double
        let horizontal: Double
        let step: Double
        if traits.isContinuous {
            // The event already measures pixels; the glide replays that same
            // distance, only re-timed, so the step setting does not scale it.
            // No Shift redirect either: the system never translates
            // continuous events, apps react to the replayed Shift flag.
            vertical = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) * invert
            horizontal = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            step = 1
        } else {
            // The fixed-point field carries the fractional ticks that
            // high-resolution wheels report while the integer field reads 0.
            let axes = SmoothScrollSupport.axes(
                vertical: SmoothScrollSupport.ticks(
                    line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                    fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)) * invert,
                horizontal: SmoothScrollSupport.ticks(
                    line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                    fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)),
                shiftPressed: shiftPressed
            )
            vertical = axes.vertical
            horizontal = axes.horizontal
            step = Double(SmoothScrollSupport.sanitizedStep(
                UserDefaults.standard.integer(forKey: DefaultsKey.smoothScrollStep)))
        }
        guard vertical != 0 || horizontal != 0 else {
            return Unmanaged.passUnretained(event)
        }

        // Switching Shift while a glide is active changes the intended axis,
        // and switching between a discrete and a continuous wheel changes the
        // sign handling. Drop the old tail instead of fighting it.
        if currentFlags.contains(.maskShift) != shiftPressed
            || glideFromContinuous != traits.isContinuous {
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
        if frameTimer == nil || glideFromContinuous != traits.isContinuous {
            // The system applies the natural scroll direction to continuous
            // events only, so a swallowed discrete tick needs the pre-flip
            // while a swallowed continuous event, replayed as the same kind,
            // does not.
            postSign = traits.isContinuous
                ? 1
                : SmoothScrollSupport.postedDelta(1, naturalScrolling: Self.naturalScrollingOn())
        }
        glideFromContinuous = traits.isContinuous
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
