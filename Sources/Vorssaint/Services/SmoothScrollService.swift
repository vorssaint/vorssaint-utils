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
/// are passed through untouched. The tap sits at the head, so the original
/// tick is swallowed before the inverter (appended at the tail) can see it
/// and the flip is applied here instead; the glide carries a mark that keeps
/// the inverter off it. Nothing (tap or timer)
/// exists while the feature is off. Requires Accessibility.
final class SmoothScrollService: ObservableObject {
    static let shared = SmoothScrollService()

    /// True while the event tap is installed.
    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var frameTimer: Timer?
    /// Remaining glide distance per axis, in pixels. Touched only on the main
    /// thread (tap callback and timer both live on the main run loop).
    private var remainingVertical: Double = 0
    private var remainingHorizontal: Double = 0
    /// Sub-pixel leftovers kept between frames, so a wheel that moves in
    /// fractions of a pixel still travels its full distance.
    private var carryVertical: Double = 0
    private var carryHorizontal: Double = 0
    /// Modifiers of the wheel event that started or fed the glide, replayed on
    /// the synthetic events so apps can still react to them.
    private var currentFlags: CGEventFlags = []
    /// Whether the glide is being fed by continuous wheel events. The two
    /// kinds measure their distance differently, so switching devices
    /// mid-glide drops the tail rather than mixing the two budgets.
    private var glideFromContinuous = false
    /// This process's own id, compared against the one every event carries.
    /// The glide's mark is the first thing that keeps a replayed frame out of
    /// this tap; this is the second lock on the same door, because the only
    /// scroll events this app posts are glide frames, and one that got back
    /// in would be swallowed and re-added at its full distance, leaving a
    /// glide that never ends.
    private static let ownProcessID = Int64(getpid())
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
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              event.getIntegerValueField(.eventSourceUnixProcessID) != Self.ownProcessID else {
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

        // The head tap swallows the tick before the inverter's tail tap can
        // reach it, so when inverting is on the wheel's vertical flip is
        // applied here; the glide is marked so the inverter leaves it alone.
        let invert = ScrollInverter.shared.isRunning ? -1.0 : 1.0
        let shiftPressed = event.flags.contains(.maskShift)
        let vertical: Double
        let horizontal: Double
        let step: Double
        if traits.isContinuous {
            // The distance comes from the same fixed-point field the discrete
            // path reads, which counts lines, so it converts to pixels and
            // the step scales it from there. No Shift redirect: the system
            // never translates continuous events, apps react to the replayed
            // Shift flag.
            let userStep = Double(SmoothScrollSupport.sanitizedStep(
                UserDefaults.standard.integer(forKey: DefaultsKey.smoothScrollStep)))
            vertical = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                pointDelta: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
                step: userStep) * invert
            horizontal = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                pointDelta: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                step: userStep)
            // The distance is already in pixels; the budget must not scale it
            // a second time.
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
            carryVertical = 0
            carryHorizontal = 0
        }
        carryVertical = SmoothScrollSupport.carry(carryVertical, continuing: vertical)
        carryHorizontal = SmoothScrollSupport.carry(carryHorizontal, continuing: horizontal)
        remainingVertical = SmoothScrollSupport.remaining(afterTicks: vertical,
                                                          step: step,
                                                          current: remainingVertical)
        remainingHorizontal = SmoothScrollSupport.remaining(afterTicks: horizontal,
                                                            step: step,
                                                            current: remainingHorizontal)
        currentFlags = event.flags
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
        carryVertical = 0
        carryHorizontal = 0
    }

    private func emitFrame() {
        let vertical = SmoothScrollSupport.frameDelta(remaining: remainingVertical)
        let horizontal = SmoothScrollSupport.frameDelta(remaining: remainingHorizontal)
        remainingVertical -= vertical
        remainingHorizontal -= horizontal

        // The frame that empties the budget is the glide's last, so it spends
        // the leftovers rather than saving them for a frame that never comes.
        let landing = remainingVertical == 0 && remainingHorizontal == 0
        if vertical != 0 || horizontal != 0 {
            post(vertical: vertical, horizontal: horizontal, landing: landing)
        }
        if landing {
            frameTimer?.invalidate()
            frameTimer = nil
            carryVertical = 0
            carryHorizontal = 0
        }
    }

    private func post(vertical: Double, horizontal: Double, landing: Bool) {
        let up = landing
            ? (pixels: SmoothScrollSupport.finalPixels(vertical, carry: carryVertical), carry: 0)
            : SmoothScrollSupport.wholePixels(vertical, carry: carryVertical)
        let across = landing
            ? (pixels: SmoothScrollSupport.finalPixels(horizontal, carry: carryHorizontal), carry: 0)
            : SmoothScrollSupport.wholePixels(horizontal, carry: carryHorizontal)
        carryVertical = up.carry
        carryHorizontal = across.carry
        guard up.pixels != 0 || across.pixels != 0 else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Self.pixelField(up.pixels),
                                  wheel2: Self.pixelField(across.pixels),
                                  wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
        event.flags = currentFlags
        event.post(tap: .cghidEventTap)
    }

    /// A frame's distance as the event field wants it, never trapping on a
    /// value the math could not have produced.
    private static func pixelField(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        return Int32(clamping: Int(min(max(value, -1_000_000), 1_000_000)))
    }

}
