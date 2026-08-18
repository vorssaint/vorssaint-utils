// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import CoreVideo

/// Turns the mouse wheel's discrete jumps into a longer coast: a tap swallows
/// each wheel tick and replays its distance as a stream of continuous pixel
/// events that ease out toward a target buffer, matching Mos' feel model
/// (Step / Speed / Duration, DisplayLink frames, annotated-session tap,
/// `postToPid` on a copied source event).
///
/// Wheel detection matches the scroll inverter (`ScrollWheelSupport`), so
/// mice whose drivers report the wheel as continuous pixel events (issue
/// #267) glide too; trackpads, Magic Mouse and momentum are passed through
/// untouched. The tap sits at the annotated session tail — after the
/// inverter's HID-tail tap — so direction flips are already applied and this
/// service must not invert again. Requires Accessibility.
///
/// Tap lifecycle lives on a dedicated scroll thread; DisplayLink frames run
/// on the display-link callback under the same engine lock. Preferences
/// arrive as immutable snapshots; the tap path never reads UserDefaults.
final class SmoothScrollService: ObservableObject {
    static let shared = SmoothScrollService()

    /// True while the event tap is installed.
    @Published private(set) var isRunning = false

    private let lifecycleLock = NSLock()
    private let engineLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    private var frameTimer: Timer?
    private var displayLink: CVDisplayLink?
    private var glideGeneration: UInt64 = 0
    private var engine = SmoothScrollSupport.Engine()
    /// Copy of the last swallowed wheel event — Mos posts mutated clones of
    /// this template to the target pid so apps see the same event shape.
    private var eventTemplate: CGEvent?
    /// Timestamp (ns, event clock) of the last event carrying a gesture phase —
    /// only touch devices emit those. Read/written solely on the tap callback.
    private var lastGesturePhaseTimestamp: UInt64?
    /// Caps automatic re-arms after WindowServer disables the tap, so a
    /// saturated main/scroll path cannot fight the system forever.
    private var tapTimeoutCount = 0
    private var tapTimeoutWindowStart: TimeInterval = 0
    private static let ownProcessID = Int64(getpid())
    private static let maxTapTimeoutsPerWindow = 3
    private static let tapTimeoutWindow: TimeInterval = 60

    private init() {}

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        refreshPreferences()
        let wanted = AppFeature.smoothScroll.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.smoothScrollEnabled)
        // Live trust, not the cached `@Published` flag: revoke can land before
        // the permissions poll notices, and a stale cache would leave the tap up.
        if wanted, AXIsProcessTrusted() {
            start()
        } else {
            stop()
        }
    }

    /// Pushes the latest feel/axis snapshot into the scroll thread without
    /// tearing the tap down. Settings calls this after slider saves and axis
    /// toggles.
    func refreshPreferences() {
        let defaults = UserDefaults.standard
        let preferences = SmoothScrollSupport.Preferences.sanitized(
            step: defaults.double(forKey: DefaultsKey.smoothScrollStep),
            speed: defaults.double(forKey: DefaultsKey.smoothScrollSpeed),
            duration: defaults.double(forKey: DefaultsKey.smoothScrollDuration),
            smoothVertical: defaults.bool(forKey: DefaultsKey.smoothScrollVertical),
            smoothHorizontal: defaults.bool(forKey: DefaultsKey.smoothScrollHorizontal),
            scrollAcceleration: defaults.double(forKey: DefaultsKey.smoothScrollAcceleration)
        )
        engineLock.withLock {
            engine.preferences = preferences
            engine.applyAxisPreferenceGuards()
        }
        // Only track exception sources while the tap is actually allowed to
        // run — otherwise a revoked Accessibility grant still kept observers
        // alive for a feature that must stay inert.
        MouseAppExceptions.shared.setSourceTracking(
            AppFeature.smoothScroll.isAvailable
                && defaults.bool(forKey: DefaultsKey.smoothScrollEnabled)
                && AXIsProcessTrusted(),
            for: .smoothScroll)
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() { stop() }

    private func start() {
        refreshPreferences()
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
            thread.name = "Vorssaint Smooth Scroll"
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
        stopGlideLocked()
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
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                self?.tearDownGlideDriverOnScrollThread()
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
            tearDownDisplayLink()
        }
        MouseAppExceptions.shared.setSourceTracking(false, for: .smoothScroll)
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

            // Same placement Mos uses: annotated session + tail. By then the
            // inverter (HID tail) has already applied reverse scrolling, and
            // the event carries a real target pid for postToPid delivery.
            guard let tap = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<SmoothScrollService>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                publishRunning(false, generation: generation)
                return
            }

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

            tearDownGlideDriverOnScrollThread()
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
            return handleTapDisabled(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

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
        guard ScrollWheelSupport.isMouseWheel(traits,
                                              secondsSinceLastGesturePhase: secondsSinceGesturePhase)
        else { return Unmanaged.passUnretained(event) }

        if MouseButtonShortcutService.hasActiveSideWheelInterest,
           let input = MouseButtonShortcutSupport.sideWheelInput(
            isContinuous: traits.isContinuous,
            vertical: (
                line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                point: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            ),
            horizontal: (
                line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                point: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            )),
           MouseButtonShortcutService.claimsSideWheel(
               input,
               at: event.location,
               sourceProcessID: sourceProcessID,
               eventTimestamp: UInt64(event.timestamp)
           ) {
            return Unmanaged.passUnretained(event)
        }

        guard !event.flags.contains(.maskControl) else {
            return Unmanaged.passUnretained(event)
        }

        let targetProcessID = event.getIntegerValueField(.eventTargetUnixProcessID)
        let exceptions = MouseAppExceptions.shared
        guard !exceptions.excludesPointerTarget(
                .smoothScroll,
                at: event.location,
                sourceProcessID: sourceProcessID,
                targetProcessID: targetProcessID) else {
            return Unmanaged.passUnretained(event)
        }

        let preferences = engineLock.withLock { engine.preferences }
        guard preferences.smoothVertical || preferences.smoothHorizontal else {
            return Unmanaged.passUnretained(event)
        }

        // Invert is owned by ScrollInverter (HID tail). This tap is later in
        // the chain, so usable deltas are already flipped when reverse is on.
        let shiftPressed = event.flags.contains(.maskShift)

        // The point field contains macOS wheel acceleration. Blend it with the
        // raw fixed-point/line movement according to Scroll acceleration.
        let verticalUsable = SmoothScrollSupport.wheelValue(
            line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
            fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            point: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
            step: preferences.step,
            scrollAcceleration: preferences.scrollAcceleration)
        let horizontalUsable = SmoothScrollSupport.wheelValue(
            line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            point: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
            step: preferences.step,
            scrollAcceleration: preferences.scrollAcceleration)

        // Shift → horizontal happens at post time (like Mos' poster.shift),
        // so the buffer/filter still see the original axis. For planning we
        // only care which axes carry energy after the redirect.
        let redirected = SmoothScrollSupport.axes(vertical: verticalUsable,
                                                  horizontal: horizontalUsable,
                                                  shiftPressed: shiftPressed)
        let plan = SmoothScrollSupport.axisPlan(
            verticalDelta: redirected.vertical,
            horizontalDelta: redirected.horizontal,
            step: preferences.step,
            speed: preferences.speed,
            smoothVertical: preferences.smoothVertical,
            smoothHorizontal: preferences.smoothHorizontal,
            invertVertical: 1,
            invertHorizontal: 1
        )
        guard plan.hasSmoothImpulse else {
            return Unmanaged.passUnretained(event)
        }

        // Accessibility can be revoked while the tap is still installed; the
        // permissions poll may lag a few seconds. Never swallow in that
        // window — pass the original wheel through so scrolling keeps working
        // (just not smoothed), then tear the tap down.
        guard AXIsProcessTrusted() else {
            abandonForLostAccessibility()
            return Unmanaged.passUnretained(event)
        }

        let now = ProcessInfo.processInfo.systemUptime
        let pid = targetProcessID > 0 ? Int32(clamping: targetProcessID) : Int32(0)
        let template = event.copy()
        engineLock.withLock {
            if let template {
                eventTemplate = template
            }
            engine = SmoothScrollSupport.ingest(
                plan: plan,
                into: engine,
                targetProcessID: pid,
                shiftPressed: shiftPressed,
                isContinuous: traits.isContinuous,
                flagsRaw: event.flags.rawValue,
                now: now)
        }
        startGlideIfNeeded()

        if plan.swallowEntirely {
            return nil
        }
        // Mixed axes: zero the smoothed side so the raw side still reaches
        // the target app.
        if !plan.passThroughVertical {
            zeroAxis(event, vertical: true)
        }
        if !plan.passThroughHorizontal {
            zeroAxis(event, vertical: false)
        }
        return Unmanaged.passUnretained(event)
    }

    /// Stops the coast on the scroll thread and asks main to tear the tap
    /// down. The current event must already have been passed through.
    private func abandonForLostAccessibility() {
        stopGlideLocked()
        tearDownGlideDriverOnScrollThread()
        DispatchQueue.main.async { [weak self] in
            self?.stop()
        }
    }

    private func handleTapDisabled(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        stopGlideLocked()
        tearDownGlideDriverOnScrollThread()

        guard AXIsProcessTrusted() else {
            abandonForLostAccessibility()
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
        } else if decision.rearm, let tap = decision.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    private func zeroAxis(_ event: CGEvent, vertical: Bool) {
        if vertical {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        } else {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        }
    }

    // MARK: - Glide

    private func startGlideIfNeeded() {
        let alreadyRunning = engineLock.withLock {
            displayLink != nil || frameTimer != nil
        }
        if alreadyRunning { return }

        glideGeneration &+= 1
        let generation = glideGeneration
        engineLock.withLock {
            engine.lastFrameTimestamp = nil
        }

        if startDisplayLink(generation: generation) {
            return
        }

        // Fallback when DisplayLink cannot be created: 60 Hz timer on the
        // scroll thread (α is still applied raw per tick).
        let runLoop = lifecycleLock.withLock { tapRunLoop }
        guard runLoop != nil else { return }
        let timer = Timer(timeInterval: SmoothScrollSupport.frameInterval, repeats: true) { [weak self] _ in
            self?.emitFrame(generation: generation)
        }
        timer.tolerance = SmoothScrollSupport.frameInterval * 0.1
        engineLock.withLock {
            frameTimer = timer
        }
        RunLoop.current.add(timer, forMode: .common)
        emitFrame(generation: generation)
    }

    private func startDisplayLink(generation: UInt64) -> Bool {
        var link: CVDisplayLink?
        let create = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard create == kCVReturnSuccess, let link else { return false }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
            guard let context else { return kCVReturnSuccess }
            let service = Unmanaged<SmoothScrollService>.fromOpaque(context).takeUnretainedValue()
            service.emitFrameFromDisplayLink()
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        engineLock.withLock {
            displayLink = link
        }
        // Store generation on the service for the callback to read.
        glideGeneration = generation
        let start = CVDisplayLinkStart(link)
        if start != kCVReturnSuccess {
            engineLock.withLock {
                displayLink = nil
            }
            return false
        }
        return true
    }

    private func emitFrameFromDisplayLink() {
        emitFrame(generation: glideGeneration)
    }

    private func stopGlideLocked() {
        glideGeneration &+= 1
        engineLock.withLock {
            engine.stop()
            eventTemplate = nil
        }
    }

    private func tearDownGlideDriverOnScrollThread() {
        glideGeneration &+= 1
        tearDownDisplayLink()
        let timer = engineLock.withLock { () -> Timer? in
            let current = frameTimer
            frameTimer = nil
            engine.stop()
            eventTemplate = nil
            return current
        }
        timer?.invalidate()
    }

    private func tearDownDisplayLink() {
        let link = engineLock.withLock { () -> CVDisplayLink? in
            let current = displayLink
            displayLink = nil
            return current
        }
        guard let link else { return }
        if CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }

    private func emitFrame(generation: UInt64) {
        guard generation == glideGeneration else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let (emission, stillGliding): (SmoothScrollSupport.FrameEmission?, Bool) =
            engineLock.withLock {
                guard displayLink != nil || frameTimer != nil else { return (nil, false) }
                let target = engine.currentTargetProcessID
                let alive = target == 0 || SmoothScrollSupport.isProcessAlive(target)
                let result = SmoothScrollSupport.emitFrame(engine: engine,
                                                           now: now,
                                                           targetAlive: alive)
                engine = result.engine
                if result.emission?.shouldStop == true || !engine.isGliding {
                    if let timer = frameTimer {
                        timer.invalidate()
                        frameTimer = nil
                    }
                    // DisplayLink is stopped outside the lock.
                }
                return (result.emission, engine.isGliding)
            }

        if let emission {
            post(emission)
        }
        if emission?.shouldStop == true || !stillGliding {
            tearDownDisplayLink()
            engineLock.withLock {
                if frameTimer != nil {
                    frameTimer?.invalidate()
                    frameTimer = nil
                }
                eventTemplate = nil
            }
        }
    }

    private func post(_ emission: SmoothScrollSupport.FrameEmission) {
        if emission.targetProcessID > 0,
           !SmoothScrollSupport.isProcessAlive(emission.targetProcessID) {
            stopGlideLocked()
            tearDownGlideDriverOnScrollThread()
            return
        }

        let vertical = emission.vertical
        let horizontal = emission.horizontal
        // Shift was applied at plan time so buffers already sit on the final
        // axis (equivalent distance to Mos' post-time shift).
        let magnitude = max(abs(vertical), abs(horizontal))
        guard magnitude > SmoothScrollSupport.deadZone || emission.landing else { return }
        guard vertical != 0 || horizontal != 0 else { return }

        let (template, pid) = engineLock.withLock {
            (eventTemplate?.copy(), emission.targetProcessID)
        }

        if pid > 0, let event = template {
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: vertical)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal)
            event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
            event.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
            event.flags = CGEventFlags(rawValue: emission.flagsRaw)
            event.postToPid(pid)
            return
        }

        // No usable target pid (rare at annotated session): fall back to a
        // fresh continuous pixel event under the pointer.
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Self.pixelField(vertical),
                                  wheel2: Self.pixelField(horizontal),
                                  wheel3: 0) else {
            return
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal)
        event.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
        event.flags = CGEventFlags(rawValue: emission.flagsRaw)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func pixelField(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        return Int32(clamping: Int(min(max(value, -1_000_000), 1_000_000)))
    }
}
