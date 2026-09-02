// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure math for smooth mouse-wheel scrolling, kept free of AppKit so the
/// unit harness can pin it.
///
/// Each wheel impulse grows a per-axis target buffer. Every display frame
/// then lerps the delivered distance toward that buffer (`(buffer - current)
/// * α`), optionally through a short peak filter, so notches coast out
/// instead of jumping. Step floors weak ticks, speed scales the impulse and
/// duration maps to α.
enum SmoothScrollSupport {
    struct Axes: Equatable {
        let vertical: Double
        let horizontal: Double
    }

    /// Per-axis glide state: target buffer, already delivered distance and
    /// the last impulse sign used to detect an instant reverse.
    struct AxisState: Equatable {
        var buffer: Double = 0
        var current: Double = 0
        var lastImpulse: Double = 0

        var remaining: Double { buffer - current }

        mutating func reset() {
            buffer = 0
            current = 0
            lastImpulse = 0
        }
    }

    /// Leading-edge curve filter matching Mos' scroll polish: each raw frame
    /// rebuilds a short nonlinear window and the head sample is emitted, so
    /// the first notch eases in instead of jumping. Independent reimplementation
    /// of that shape (same 0.23 / 0.50 / 0.77 knots); not a copy of Mos' source.
    struct PeakFilter: Equatable {
        private var samples: [Double] = [0, 0]

        mutating func reset() {
            samples = [0, 0]
        }

        /// Smooths `next` against the previous window and returns the head.
        mutating func push(_ next: Double) -> Double {
            guard next.isFinite else { return 0 }
            let anchor = samples.count > 1 ? samples[1] : 0
            let delta = next - anchor
            samples = [
                anchor,
                anchor + 0.23 * delta,
                anchor + 0.50 * delta,
                anchor + 0.77 * delta,
                next
            ]
            return samples[0]
        }

        var isSettled: Bool {
            samples.allSatisfy { abs($0) <= SmoothScrollSupport.deadZone }
        }

        /// Clears the window and returns any head sample still worth posting.
        mutating func flush() -> Double {
            let leftover = samples.first ?? 0
            reset()
            guard leftover.isFinite, abs(leftover) > SmoothScrollSupport.deadZone else { return 0 }
            return leftover
        }
    }

    /// Residuals smaller than this stop the glide so float dust never keeps
    /// the frame timer alive. Matches Mos' default dead zone.
    static let deadZone: Double = 1.0

    /// Must sit a hair above the duration slider's maximum so α never hits
    /// zero at the top of the range (`5.0 + 0.2`, same mapping Mos uses).
    static let durationUpperLimit: Double = 5.2

    /// Minimum stride of one wheel tick before speed is applied, in pixels.
    /// Bounds match Mos' scroll options; Vorssaint's tuned default is 39.69.
    /// Keep Settings sliders continuous — a 0.01 discrete step over this
    /// range freezes SwiftUI's Mouse page for a very long time.
    static let stepRange: ClosedRange<Double> = 0.01...100
    static let defaultStep: Double = 39.69
    static var stepRangeText: String { rangeText(stepRange) }

    /// Multiplier on each impulse. Higher means more distance per notch.
    /// Bounds match Mos (1…10); Vorssaint's tuned default is 3.00.
    static let speedRange: ClosedRange<Double> = 1.0...10.0
    static let defaultSpeed: Double = 3.00
    static var speedRangeText: String { rangeText(speedRange) }

    /// How long the coast feels. Higher → smaller α → softer, longer glide.
    /// Bounds match Mos (1…5); Vorssaint's tuned default is 3.00.
    static let durationRange: ClosedRange<Double> = 1.0...5.0
    static let defaultDuration: Double = 3.00
    static var durationRangeText: String { rangeText(durationRange) }

    /// Blend between raw wheel movement and macOS' accelerated point delta.
    /// Zero disables acceleration; one uses the full accelerated distance.
    static let scrollAccelerationRange: ClosedRange<Double> = 0.0...1.0
    static let defaultScrollAcceleration: Double = 0.0

    private static func rangeText(_ range: ClosedRange<Double>) -> String {
        String(format: "%.2f – %.2f", range.lowerBound, range.upperBound)
    }

    /// Frame length for the glide timer. Sixty steps a second reads as
    /// continuous and stays far below what event posting can sustain.
    static let frameInterval: TimeInterval = 1.0 / 60.0

    /// Safety fuse: even corrupt input or a future interpolation regression
    /// can never leave a frame driver consuming CPU indefinitely.
    static let maximumCoastAfterInput: TimeInterval = 8

    /// Immutable feel and axis policy captured once per preference change so
    /// the tap and frame path never touch UserDefaults.
    struct Preferences: Equatable {
        var step: Double = SmoothScrollSupport.defaultStep
        var speed: Double = SmoothScrollSupport.defaultSpeed
        var duration: Double = SmoothScrollSupport.defaultDuration
        var smoothVertical: Bool = true
        var smoothHorizontal: Bool = true
        var scrollAcceleration: Double = SmoothScrollSupport.defaultScrollAcceleration

        static func sanitized(step: Double,
                              speed: Double,
                              duration: Double,
                              smoothVertical: Bool,
                              smoothHorizontal: Bool,
                              scrollAcceleration: Double = SmoothScrollSupport.defaultScrollAcceleration)
        -> Preferences {
            Preferences(step: SmoothScrollSupport.sanitizedStep(step),
                        speed: SmoothScrollSupport.sanitizedSpeed(speed),
                        duration: SmoothScrollSupport.sanitizedDuration(duration),
                        smoothVertical: smoothVertical,
                        smoothHorizontal: smoothHorizontal,
                        scrollAcceleration: SmoothScrollSupport
                            .sanitizedScrollAcceleration(scrollAcceleration))
        }
    }

    /// One wheel reading reduced to smooth impulses and raw pass-through flags.
    struct AxisPlan: Equatable {
        var verticalImpulse: Double = 0
        var horizontalImpulse: Double = 0
        var passThroughVertical: Bool = false
        var passThroughHorizontal: Bool = false

        var hasSmoothImpulse: Bool { verticalImpulse != 0 || horizontalImpulse != 0 }
        var hasPassThrough: Bool { passThroughVertical || passThroughHorizontal }
        var swallowEntirely: Bool { hasSmoothImpulse && !hasPassThrough }
    }

    /// Reasons a live coast must abandon its leftover before accepting a new
    /// impulse. Pointer movement alone is intentionally not among them.
    enum TailResetReason: Equatable {
        case shiftChanged
        case continuousModeChanged
        case targetProcessChanged
    }

    /// Pure glide state machine: preferences, buffers, filters and carries.
    /// Touched only from the scroll tap thread.
    struct Engine: Equatable {
        var preferences = Preferences()
        var vertical = AxisState()
        var horizontal = AxisState()
        var verticalFilter = PeakFilter()
        var horizontalFilter = PeakFilter()
        var currentFlagsRaw: UInt64 = 0
        var currentTargetProcessID: Int32 = 0
        var glideFromContinuous = false
        var shiftPressed = false
        var lastFrameTimestamp: TimeInterval?
        var lastInputTimestamp: TimeInterval = 0
        var isGliding = false

        mutating func resetTail() {
            vertical.reset()
            horizontal.reset()
            verticalFilter.reset()
            horizontalFilter.reset()
        }

        mutating func stop() {
            resetTail()
            currentTargetProcessID = 0
            lastFrameTimestamp = nil
            lastInputTimestamp = 0
            isGliding = false
        }

        /// Applies axis preference changes mid-coast so a disabled buffer
        /// cannot keep the driver alive.
        mutating func applyAxisPreferenceGuards() {
            if !preferences.smoothVertical {
                vertical.reset()
                verticalFilter.reset()
            }
            if !preferences.smoothHorizontal {
                horizontal.reset()
                horizontalFilter.reset()
            }
        }
    }

    struct FrameEmission: Equatable {
        var vertical: Double
        var horizontal: Double
        var landing: Bool
        var shouldStop: Bool
        var targetProcessID: Int32
        var flagsRaw: UInt64
    }

    /// Maps the duration slider onto the per-frame lerp factor α.
    /// `α = 1 - sqrt(duration / upperLimit)`, rounded to three decimals —
    /// same mapping Mos uses (`generateDurationTransition`).
    static func transition(forDuration duration: Double) -> Double {
        let d = sanitizedDuration(duration)
        let alpha = 1 - (d / durationUpperLimit).squareRoot()
        guard alpha.isFinite else { return transition(forDuration: defaultDuration) }
        return (alpha * 1000).rounded() / 1000
    }

    /// Mos field priority for one axis: point → fixed-point → line.
    /// Fixed-point is used as-is (no points-per-line scaling) so Step/Speed
    /// land on the same magnitude Mos uses for the same wheel reading.
    static func usableValue(line: Double, fixedPoint: Double, point: Double) -> Double {
        guard line.isFinite, fixedPoint.isFinite, point.isFinite else { return 0 }
        if point != 0 { return point }
        if fixedPoint != 0 { return fixedPoint }
        if line != 0 { return line }
        return 0
    }

    /// Blends the normalized raw wheel distance with macOS' accelerated point
    /// distance. Blending after applying Step makes the entire 0…1 range
    /// useful instead of letting Step flatten most intermediate values.
    static func wheelValue(line: Double,
                           fixedPoint: Double,
                           point: Double,
                           step: Double,
                           scrollAcceleration: Double) -> Double {
        guard line.isFinite, fixedPoint.isFinite, point.isFinite else { return 0 }
        let raw = fixedPoint != 0 ? fixedPoint : (line != 0 ? line : point)
        let accelerated = usableValue(line: line, fixedPoint: fixedPoint, point: point)
        guard raw != 0, accelerated != 0 else { return raw != 0 ? raw : accelerated }

        let rawNormalized = normalized(delta: raw, step: step)
        let acceleratedNormalized = normalized(delta: accelerated, step: step)
        guard (rawNormalized < 0) == (acceleratedNormalized < 0) else {
            return rawNormalized
        }
        let amount = sanitizedScrollAcceleration(scrollAcceleration)
        let result = rawNormalized + (acceleratedNormalized - rawNormalized) * amount
        return result.isFinite ? result : rawNormalized
    }

    /// Distance added to the glide buffer for one wheel reading. Values
    /// smaller than `step` are raised to it (`max(magnitude, step)`), then
    /// speed stretches the result — same order as Mos normalize → `* speed`.
    static func impulse(delta: Double, step: Double, speed: Double) -> Double {
        guard delta.isFinite, delta != 0 else { return 0 }
        let stepValue = sanitizedStep(step)
        let speedValue = sanitizedSpeed(speed)
        let magnitude = abs(delta) < stepValue ? stepValue : abs(delta)
        let usable = delta > 0 ? magnitude : -magnitude
        let result = usable * speedValue
        return result.isFinite ? result : 0
    }

    /// Applies one impulse to an axis. Same-direction ticks accumulate;
    /// reversing abandons the leftover so the new direction reacts instantly.
    static func apply(impulse: Double, to state: AxisState) -> AxisState {
        guard impulse != 0 else { return state }
        var next = state
        if next.lastImpulse != 0, (impulse < 0) != (next.lastImpulse < 0) {
            next.buffer = impulse
            next.current = 0
        } else {
            next.buffer += impulse
        }
        next.lastImpulse = impulse
        return next
    }

    /// One display frame of the buffer chase: `frame = (buffer - current) * α`.
    static func frameDelta(buffer: Double, current: Double, transition: Double) -> Double {
        let remaining = buffer - current
        guard remaining != 0, transition.isFinite, transition > 0 else { return 0 }
        let emitted = remaining * transition
        return emitted.isFinite ? emitted : 0
    }

    /// Advances `current` by a frame delta and reports whether the axis has
    /// settled inside the dead zone.
    static func advance(state: AxisState, frame: Double) -> (state: AxisState, landed: Bool) {
        var next = state
        next.current += frame
        if !next.current.isFinite { next.current = next.buffer }
        let landed = abs(next.buffer - next.current) <= deadZone && abs(frame) <= deadZone
        if landed {
            next.current = next.buffer
        }
        return (next, landed)
    }

    /// A vertical wheel tick with Shift held scrolls sideways instead. That
    /// redirect happens above the event tap, so once the original tick is
    /// swallowed the glide has to perform it. A wheel that already reports
    /// a horizontal axis is left alone so its native direction is preserved.
    static func axes(vertical: Double, horizontal: Double, shiftPressed: Bool) -> Axes {
        guard shiftPressed, vertical != 0, horizontal == 0 else {
            return Axes(vertical: vertical, horizontal: horizontal)
        }
        return Axes(vertical: 0, horizontal: vertical)
    }

    static func sanitizedStep(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultStep }
        return min(max(value, stepRange.lowerBound), stepRange.upperBound)
    }

    static func sanitizedSpeed(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultSpeed }
        return min(max(value, speedRange.lowerBound), speedRange.upperBound)
    }

    static func sanitizedDuration(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultDuration }
        return min(max(value, durationRange.lowerBound), durationRange.upperBound)
    }

    static func sanitizedScrollAcceleration(_ value: Double) -> Double {
        guard value.isFinite else { return defaultScrollAcceleration }
        return min(max(value, scrollAccelerationRange.lowerBound),
                   scrollAccelerationRange.upperBound)
    }

    private static func normalized(delta: Double, step: Double) -> Double {
        guard delta.isFinite, delta != 0 else { return 0 }
        let magnitude = max(abs(delta), sanitizedStep(step))
        return delta > 0 ? magnitude : -magnitude
    }

    /// True when a new wheel reading must abandon the leftover coast before
    /// accepting its impulse. Same-PID pointer moves do not reset.
    static func shouldResetTail(currentTargetProcessID: Int32,
                                newTargetProcessID: Int32,
                                currentShift: Bool,
                                newShift: Bool,
                                currentContinuous: Bool,
                                newContinuous: Bool) -> [TailResetReason] {
        var reasons: [TailResetReason] = []
        if currentTargetProcessID != 0,
           newTargetProcessID != 0,
           currentTargetProcessID != newTargetProcessID {
            reasons.append(.targetProcessChanged)
        }
        if currentShift != newShift {
            reasons.append(.shiftChanged)
        }
        if currentContinuous != newContinuous {
            reasons.append(.continuousModeChanged)
        }
        return reasons
    }

    /// Splits one wheel reading into smooth impulses and raw pass-through
    /// axes. A disabled smooth axis keeps its original delta so the inverter
    /// and the app still see it.
    static func axisPlan(verticalDelta: Double,
                         horizontalDelta: Double,
                         step: Double,
                         speed: Double,
                         smoothVertical: Bool,
                         smoothHorizontal: Bool,
                         invertVertical: Double,
                         invertHorizontal: Double) -> AxisPlan {
        var plan = AxisPlan()
        let hasVertical = verticalDelta != 0
        let hasHorizontal = horizontalDelta != 0
        if hasVertical {
            if smoothVertical {
                plan.verticalImpulse = impulse(delta: verticalDelta,
                                               step: step,
                                               speed: speed) * invertVertical
            } else {
                plan.passThroughVertical = true
            }
        }
        if hasHorizontal {
            if smoothHorizontal {
                plan.horizontalImpulse = impulse(delta: horizontalDelta,
                                                 step: step,
                                                 speed: speed) * invertHorizontal
            } else {
                plan.passThroughHorizontal = true
            }
        }
        return plan
    }

    /// Ingests one axis plan into the engine. Resets the tail when the target
    /// process, Shift state or continuous/discrete mode changes.
    static func ingest(plan: AxisPlan,
                       into engine: Engine,
                       targetProcessID: Int32,
                       shiftPressed: Bool,
                       isContinuous: Bool,
                       flagsRaw: UInt64,
                       now: TimeInterval) -> Engine {
        guard plan.hasSmoothImpulse else { return engine }
        var next = engine
        let resets = shouldResetTail(currentTargetProcessID: next.currentTargetProcessID,
                                     newTargetProcessID: targetProcessID,
                                     currentShift: next.shiftPressed,
                                     newShift: shiftPressed,
                                     currentContinuous: next.glideFromContinuous,
                                     newContinuous: isContinuous)
        if !resets.isEmpty {
            next.resetTail()
        }
        next.vertical = apply(impulse: plan.verticalImpulse, to: next.vertical)
        next.horizontal = apply(impulse: plan.horizontalImpulse, to: next.horizontal)
        next.currentFlagsRaw = flagsRaw
        next.currentTargetProcessID = targetProcessID > 0 ? targetProcessID : 0
        next.glideFromContinuous = isContinuous
        next.shiftPressed = shiftPressed
        next.lastInputTimestamp = now
        next.isGliding = true
        return next
    }

    /// Advances one frame. `targetAlive` false lands and stops instead of
    /// falling back to a global HID post that could leak into another app.
    static func emitFrame(engine: Engine,
                          now: TimeInterval,
                          targetAlive: Bool) -> (engine: Engine, emission: FrameEmission?) {
        var next = engine
        guard next.isGliding else { return (next, nil) }
        next.applyAxisPreferenceGuards()

        if next.currentTargetProcessID > 0, !targetAlive {
            let emission = FrameEmission(vertical: 0,
                                         horizontal: 0,
                                         landing: true,
                                         shouldStop: true,
                                         targetProcessID: next.currentTargetProcessID,
                                         flagsRaw: next.currentFlagsRaw)
            next.stop()
            return (next, emission)
        }

        if next.lastInputTimestamp > 0,
           now - next.lastInputTimestamp >= maximumCoastAfterInput {
            let emission = landingEmission(from: &next, now: now, forceFlush: true)
            next.stop()
            return (next, emission)
        }

        next.lastFrameTimestamp = now

        // Mos applies α once per DisplayLink frame with no wall-clock rescale.
        let alpha = transition(forDuration: next.preferences.duration)
        let rawVertical = frameDelta(buffer: next.vertical.buffer,
                                     current: next.vertical.current,
                                     transition: alpha)
        let rawHorizontal = frameDelta(buffer: next.horizontal.buffer,
                                       current: next.horizontal.current,
                                       transition: alpha)
        let verticalAdvance = advance(state: next.vertical, frame: rawVertical)
        let horizontalAdvance = advance(state: next.horizontal, frame: rawHorizontal)
        next.vertical = verticalAdvance.state
        next.horizontal = horizontalAdvance.state

        let residualLanded = verticalAdvance.landed && horizontalAdvance.landed
        let filteredVertical = next.verticalFilter.push(rawVertical)
        let filteredHorizontal = next.horizontalFilter.push(rawHorizontal)
        let outputMagnitude = max(abs(filteredVertical), abs(filteredHorizontal))
        let outputSettled = outputMagnitude <= deadZone
        // Match Mos stop gate: residual inside the dead zone and polished
        // output settled — no artificial flush of the curve window.
        let landing = residualLanded && outputSettled

        guard outputMagnitude > deadZone || landing else {
            if residualLanded && next.verticalFilter.isSettled && next.horizontalFilter.isSettled {
                next.stop()
            }
            return (next, nil)
        }

        let emission = FrameEmission(vertical: filteredVertical,
                                     horizontal: filteredHorizontal,
                                     landing: landing,
                                     shouldStop: landing,
                                     targetProcessID: next.currentTargetProcessID,
                                     flagsRaw: next.currentFlagsRaw)
        if landing {
            next.stop()
        }
        return (next, emission)
    }

    /// True when a process id is still live enough to receive posted events.
    static func isProcessAlive(_ processID: Int32) -> Bool {
        guard processID > 0 else { return false }
        let result = kill(processID, 0)
        return result == 0 || errno == EPERM
    }

    /// Sum of posted whole/final pixels across a sequence of frames. Used by
    /// tests to pin distance conservation under different cadences.
    static func conservedDistance(impulse: Double,
                                  duration: Double,
                                  frameIntervals: [TimeInterval]) -> Double {
        var engine = Engine(preferences: Preferences.sanitized(step: defaultStep,
                                                               speed: defaultSpeed,
                                                               duration: duration,
                                                               smoothVertical: true,
                                                               smoothHorizontal: true))
        let plan = AxisPlan(verticalImpulse: impulse,
                            horizontalImpulse: 0,
                            passThroughVertical: false,
                            passThroughHorizontal: false)
        engine = ingest(plan: plan,
                        into: engine,
                        targetProcessID: 1,
                        shiftPressed: false,
                        isContinuous: false,
                        flagsRaw: 0,
                        now: 0)
        var posted: Double = 0
        var now = 0.0
        for interval in frameIntervals {
            now += interval
            let result = emitFrame(engine: engine, now: now, targetAlive: true)
            engine = result.engine
            guard let emission = result.emission else { continue }
            // Posted as point deltas (floats), the same way Mos delivers frames.
            posted += emission.vertical
            if emission.shouldStop { break }
        }
        return posted
    }

    private static func landingEmission(from engine: inout Engine,
                                        now: TimeInterval,
                                        forceFlush: Bool) -> FrameEmission {
        _ = now
        var vertical = forceFlush ? engine.verticalFilter.flush() : 0
        var horizontal = forceFlush ? engine.horizontalFilter.flush() : 0
        if forceFlush {
            // Spend any residual buffer that never made it through the filter.
            vertical += engine.vertical.remaining
            horizontal += engine.horizontal.remaining
        }
        return FrameEmission(vertical: vertical,
                             horizontal: horizontal,
                             landing: true,
                             shouldStop: true,
                             targetProcessID: engine.currentTargetProcessID,
                             flagsRaw: engine.currentFlagsRaw)
    }
}
