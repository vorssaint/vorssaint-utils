// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import os

/// Keeps external displays in step with the built-in screen, and with the
/// ambient light sensor when the lid is closed (clamshell mode, where there is
/// no built-in screen to follow).
///
/// The built-in panel is the reference channel: macOS already moves it for both
/// the ambient light sensor and manual brightness keys, so whatever it settles
/// on is the level the externals should echo. Each external display carries an
/// additive offset calibrated against real-world luminance, and its target is
/// `clamp(reference + offset)` — the exact relative model the feature asks for.
///
/// The whole driver is a single low-frequency timer (the DDC/CI and software
/// writes funnel through `BrightnessService.setBrightness`, so their pacing,
/// coalescing and OSD handling are reused unchanged). It is a light consumer of
/// the ambient light sensor rather than a heavy one: a 1 Hz reference poll is
/// all a laptop driving a monitor ever needs, and there is no DDC traffic while
/// the reference has not actually moved past a small hysteresis step.
final class AmbientBrightnessSynchronizer: ObservableObject {
    static let shared = AmbientBrightnessSynchronizer()

    /// Whether synchronization is running right now.
    @Published private(set) var isActive = false
    /// The reference level (built-in screen, or sensor in clamshell) last
    /// propagated to the externals, 0...1.
    @Published private(set) var referenceValue: Double?
    /// True when this Mac exposes an ambient light sensor usable for clamshell.
    @Published private(set) var sensorAvailable: Bool
    /// Bumped whenever an offset is edited, so the per-monitor rows re-read.
    @Published private(set) var revision = 0

    private let sensor: AmbientLightSensor?
    private var timer: Timer?
    /// Steers in-flight transitions toward their targets at a smooth cadence.
    private var rampTimer: Timer?
    /// One display's in-flight easing from its previous settled level to a newly
    /// derived target, over `smoothTransitionDuration`.
    private struct Ramp {
        let from: Double
        let to: Double
        let start: TimeInterval
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var lastAppliedReference: Double?
    private var lastAppliedTargets: [CGDirectDisplayID: Double] = [:]
    /// The transitions currently easing each external display toward its most
    /// recent target. Keyed by display so a retarget picks up from the
    /// interpolated position when the reference moves again mid-transition.
    private var ramps: [CGDirectDisplayID: Ramp] = [:]

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-ambient")

    private init() {
        let defaults = UserDefaults.standard
        let floor = defaults.double(forKey: DefaultsKey.ambientBrightnessFloor)
        let ceiling = defaults.double(forKey: DefaultsKey.ambientBrightnessCeiling)
        if let client = SMCClient() {
            let sensor = AmbientLightSensor(client: client, floor: floor, ceiling: ceiling)
            self.sensor = sensor
            self.sensorAvailable = sensor.isAvailable
        } else {
            self.sensor = nil
            self.sensorAvailable = false
        }
    }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let wanted = AppFeature.brightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.ambientBrightnessSyncEnabled)
        if wanted { start() } else { stop() }
    }

    private func start() {
        guard !isActive else { return }
        isActive = true
        lastAppliedReference = nil
        lastAppliedTargets = [:]
        ramps = [:]
        sensor?.start()
        Self.log.log("ambient brightness synchronization started (sensor available: \(self.sensorAvailable))")
        syncNow()
        let timer = Timer(timeInterval: AmbientBrightnessSupport.refreshInterval,
                          repeats: true) { [weak self] _ in self?.syncNow() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        stopRamps()
        sensor?.stop()
        lastAppliedReference = nil
        lastAppliedTargets = [:]
        ramps = [:]
        referenceValue = nil
        Self.log.log("ambient brightness synchronization stopped")
    }

    // MARK: - Propagation

    private func syncNow(force: Bool = false) {
        guard isActive else { return }
        let displays = BrightnessService.shared.displays
        guard !displays.isEmpty else { referenceValue = nil; return }

        var reference = builtInReference(in: displays)
        if reference == nil, let sensorLevel = sensor?.level { reference = sensorLevel }
        guard let reference else { referenceValue = nil; return }

        referenceValue = reference
        let moved = AmbientBrightnessSupport.shouldPropagate(
            previous: lastAppliedReference ?? -1, current: reference,
            step: AmbientBrightnessSupport.minimumReferenceStep)
        guard force || moved || lastAppliedReference == nil else { return }
        lastAppliedReference = reference
        if force { lastAppliedTargets = [:] }
        applyTargets(reference: reference, displays: displays)
    }

    /// The built-in panel's current system brightness, if there is an active
    /// built-in display to read.
    private func builtInReference(in displays: [BrightnessDisplay]) -> Double? {
        guard let builtIn = displays.first(where: { $0.isBuiltIn && $0.isActive }) else {
            return nil
        }
        return BrightnessService.shared.systemBrightness(for: builtIn.id)
            ?? lastAppliedReference
    }

    private func applyTargets(reference: Double, displays: [BrightnessDisplay]) {
        for display in displays where !display.isBuiltIn && display.isActive && display.method != nil {
            let offset = offset(for: display.id)
            let target = AmbientBrightnessSupport.clampedTarget(reference: reference, offset: offset)
            if let last = lastAppliedTargets[display.id],
               abs(last - target) < AmbientBrightnessSupport.minimumReferenceStep {
                continue
            }
            lastAppliedTargets[display.id] = target
            if abs(display.brightness - target) < AmbientBrightnessSupport.minimumReferenceStep {
                continue
            }
            Self.log.log("ambient sync display \(display.id) reference \(reference) offset \(offset) -> \(target)")
            beginRamp(to: target, for: display.id)
        }
    }
    // MARK: - Smooth transitions

    /// Starts the 60 Hz steering timer for the first in-flight ramp. Runs in
    /// `.common` mode so the transition keeps gliding while menus or trackers
    /// own the main run loop.
    private func startRampTimer() {
        guard rampTimer == nil else { return }
        let interval = 1 / AmbientBrightnessSupport.smoothTransitionFramesPerSecond
        rampTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tickRamps()
        }
        RunLoop.main.add(rampTimer!, forMode: .common)
    }

    private func invalidateRampTimer() {
        rampTimer?.invalidate()
        rampTimer = nil
    }

    /// Tears down every in-flight transition: no ramp may outlive the
    /// synchronizer, or a stale timer would keep commanding displays.
    private func stopRamps() {
        invalidateRampTimer()
        ramps = [:]
    }


// MARK: - Smooth transitions

    /// Starts easing one display from its current brightness to a newly
    /// derived target. When the reference moves again mid-flight the new ramp
    /// picks up from where the easing actually is, not from a last settled
    /// value the eye would see as a brief flicker backward. Every intermediate
    /// write still funnels through `BrightnessService.setBrightness`, so its
    /// DDC/CI pacing, coalescing and OSD handling are reused unchanged.
    private func beginRamp(to target: Double, for id: CGDirectDisplayID) {
        guard isActive else { return }
        let currentUptime = now
        let from: Double
        if let active = ramps[id] {
            let progress = min(max(currentUptime - active.start, 0) / AmbientBrightnessSupport.smoothTransitionDuration, 1)
            from = AmbientBrightnessSupport.transitionedValue(
                from: active.from, to: active.to, progress: progress)
        } else {
            from = BrightnessService.shared.displays.first { $0.id == id }?.brightness ?? target
        }
        ramps[id] = Ramp(from: from, to: target, start: currentUptime)
        startRampTimer()
    }

    /// Steers every in-flight display toward its target once per frame. A ramp
    /// that reaches its completion publishes its exact final value, then hands
    /// off. When nothing is animating, the timer shuts off altogether,
    /// so a steady reference costs no idle timer traffic.
    private func tickRamps() {
        let currentUptime = now
        var finishedIDs: [CGDirectDisplayID] = []
        for (id, ramp) in ramps {
            let progress = min(max(currentUptime - ramp.start, 0) / AmbientBrightnessSupport.smoothTransitionDuration, 1)
            if progress < 1 {
                let value = AmbientBrightnessSupport.transitionedValue(
                    from: ramp.from, to: ramp.to, progress: progress)
                BrightnessService.shared.setBrightness(value, for: id)
            } else {
                finishedIDs.append(id)
                BrightnessService.shared.setBrightness(ramp.to, for: id)
            }
        }
        guard !finishedIDs.isEmpty else { return }
        for id in finishedIDs { ramps.removeValue(forKey: id) }
        if ramps.isEmpty { invalidateRampTimer() }
    }

    // MARK: - Offsets (per physical monitor)

    func offset(for id: CGDirectDisplayID) -> Double {
        storedOffsets()[Self.fingerprint(for: id)] ?? 0
    }

    func setOffset(_ offset: Double, for id: CGDirectDisplayID) {
        var offsets = storedOffsets()
        offsets[Self.fingerprint(for: id)] = min(max(offset, -1), 1)
        UserDefaults.standard.set(offsets, forKey: DefaultsKey.ambientBrightnessOffsets)
        revision &+= 1
        syncNow(force: true)
    }

    /// Pins the current gap between an external display and the built-in screen
    /// as that display's offset, so real-world luminance stays matched.
    func setOffsetFromCurrent(display: BrightnessDisplay) {
        let displays = BrightnessService.shared.displays
        guard let builtIn = displays.first(where: { $0.isBuiltIn && $0.isActive }),
              let reference = BrightnessService.shared.systemBrightness(for: builtIn.id)
                ?? lastAppliedReference else { return }
        let offset = AmbientBrightnessSupport.offset(reference: reference, external: display.brightness)
        setOffset(offset, for: display.id)
    }

    private func storedOffsets() -> [String: Double] {
        let stored = UserDefaults.standard.object(forKey: DefaultsKey.ambientBrightnessOffsets)
            as? [String: Double] ?? [:]
        var clean: [String: Double] = [:]
        for (key, value) in stored {
            guard value.isFinite else { continue }
            clean[key] = min(max(value, -1), 1)
        }
        return clean
    }

    private static func fingerprint(for id: CGDirectDisplayID) -> String {
        AmbientBrightnessSupport.fingerprint(vendor: CGDisplayVendorNumber(id),
                                             model: CGDisplayModelNumber(id),
                                             serial: CGDisplaySerialNumber(id))
    }
}