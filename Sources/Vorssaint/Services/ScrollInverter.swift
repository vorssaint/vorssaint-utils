// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
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
/// Apps on the shared scrolling exception list (issue #358) keep the direction
/// macOS gives them and receive no glide. When both features are on, this HID
/// tap flips first and the later smooth-scroll tap coasts those final deltas
/// without inverting them again.
///
/// Tap callbacks run on a dedicated thread with an immutable preference
/// snapshot, matching Smooth Scroll so Settings layout never shares a run
/// loop with wheel inversion.
final class ScrollInverter: ObservableObject {
    static let shared = ScrollInverter()

    /// True while the event tap is installed and inverting.
    @Published private(set) var isRunning = false

    private static let ownProcessID = Int64(getpid())
    private static let maxTapTimeoutsPerWindow = 3
    private static let tapTimeoutWindow: TimeInterval = 60

    private let lifecycleLock = NSLock()
    private let configLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    private var invertVertical = false
    private var invertHorizontal = false
    private var tapTimeoutCount = 0
    private var tapTimeoutWindowStart: TimeInterval = 0
    /// Timestamp (ns, event clock) of the last event carrying a gesture phase —
    /// only touch devices emit those. Read/written solely on the tap callback.
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
        refreshPreferences()
        let defaults = UserDefaults.standard
        let wanted = AppFeature.scrollInverter.isAvailable
            && (defaults.bool(forKey: DefaultsKey.scrollInverterEnabled)
                || defaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled))
        // Live trust: a cached Permissions flag can lag a System Settings revoke.
        // Session must be on console too, or a switched-away login keeps a live
        // filter tap and stalls the account on screen (issue #1075).
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    /// Pushes axis toggles into the tap thread without tearing the tap down.
    func refreshPreferences() {
        let defaults = UserDefaults.standard
        let vertical = defaults.bool(forKey: DefaultsKey.scrollInverterEnabled)
        let horizontal = defaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled)
        configLock.withLock {
            invertVertical = vertical
            invertHorizontal = horizontal
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() { stop() }

    private func start() {
        refreshPreferences()
        MouseAppExceptions.shared.setSourceTracking(true, for: .scrollDirection)
        let startState = lifecycleLock.withLock {
            () -> (thread: Thread?, publishRunning: Bool, generation: UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, false, lifecycleGeneration)
                }
                return (nil, true, lifecycleGeneration)
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vorssaint Scroll Inverter"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, false, generation)
        }

        if let thread = startState.thread {
            thread.start()
        } else if startState.publishRunning {
            publishRunning(true, generation: startState.generation)
        }
    }

    private func stop() {
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        tapCreationRetryUsed = false
        MouseAppExceptions.shared.setSourceTracking(false, for: .scrollDirection)
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        publishRunning(false, generation: snapshot.generation)
    }

    private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock { shouldStopTapThread }
            guard !shouldStopBeforeCreatingTap else {
                let shouldRestart = clearEventTapThread()
                if shouldRestart {
                    start()
                } else {
                    publishRunning(false, generation: generation)
                }
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
                _ = clearEventTapThread()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let isCurrent = self.lifecycleLock.withLock {
                        generation == self.lifecycleGeneration
                    }
                    guard isCurrent else { return }
                    MouseAppExceptions.shared.setSourceTracking(false, for: .scrollDirection)
                }
                publishRunning(false, generation: generation)
                DispatchQueue.main.async { [weak self] in
                    self?.scheduleTapCreationRetry()
                }
                return
            }

            tapCreationRetryUsed = false
            tapCreationRetryWork?.cancel()
            tapCreationRetryWork = nil
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
                tapTimeoutCount = 0
                tapTimeoutWindowStart = 0
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            let shouldStop = lifecycleLock.withLock { shouldStopTapThread }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishRunning(true, generation: generation)
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            let shouldRestart = clearEventTapThread()
            if shouldRestart {
                start()
            } else {
                publishRunning(false, generation: generation)
            }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    private func scheduleTapCreationRetry() {
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
    }

    private func publishRunning(_ running: Bool, generation: UInt) {
        let update = { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock {
                generation == self.lifecycleGeneration
            }
            guard isCurrent else { return }
            self.isRunning = running
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Do not re-arm into a switched-away session: the stall is why the
            // tap was disabled, and feeding it stalls the account on screen.
            guard SessionActivity.shared.isActive else {
                return Unmanaged.passUnretained(event)
            }
            return handleTapDisabled(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        // Smooth Scroll runs later at the annotated-session tap, so ordinary
        // wheel events are inverted here before it turns them into a glide.
        // Its synthetic frames normally cannot reach this HID tap; the tag and
        // process id remain a defensive recursion guard.
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

        let targetProcessID = event.getIntegerValueField(.eventTargetUnixProcessID)
        let config = configLock.withLock {
            (vertical: invertVertical, horizontal: invertHorizontal)
        }
        if ScrollWheelSupport.isMouseWheel(traits,
                                           secondsSinceLastGesturePhase: secondsSinceGesturePhase),
           !MouseAppExceptions.shared.excludesPointerTarget(
                .scrollDirection,
                at: event.location,
                sourceProcessID: sourceProcessID,
                targetProcessID: targetProcessID) {
            // Capture both axes before any set: writing a line delta makes the
            // system rederive its point and fixed-point fields.
            let verticalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let verticalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let horizontalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let horizontalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let hasVerticalMovement = verticalLine != 0 || verticalPoint != 0 || verticalFixedPoint != 0
            let hasHorizontalMovement = horizontalLine != 0
                || horizontalPoint != 0
                || horizontalFixedPoint != 0
            let plan = ScrollWheelSupport.inversionPlan(
                hasVerticalMovement: hasVerticalMovement,
                hasHorizontalMovement: hasHorizontalMovement,
                shiftRedirectsVertical: !traits.isContinuous && event.flags.contains(.maskShift),
                invertVertical: config.vertical,
                invertHorizontal: config.horizontal
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

    private func handleTapDisabled(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return Unmanaged.passUnretained(event)
        }

        let now = ProcessInfo.processInfo.systemUptime
        let decision = lifecycleLock.withLock { () -> (rearm: Bool, rebuild: Bool, tap: CFMachPort?) in
            if tapTimeoutWindowStart == 0 || now - tapTimeoutWindowStart >= Self.tapTimeoutWindow {
                tapTimeoutWindowStart = now
                tapTimeoutCount = 0
            }
            tapTimeoutCount += 1
            if tapTimeoutCount > Self.maxTapTimeoutsPerWindow {
                return (false, true, tap)
            }
            return (true, false, tap)
        }

        if decision.rebuild {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stop()
                self.syncWithPreferences()
            }
        } else if decision.rearm, SessionActivity.shared.isActive, let tap = decision.tap {
            // Do not re-arm into a switched-away session: the stall is why the
            // tap was disabled, and feeding it stalls the account on screen.
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
}
