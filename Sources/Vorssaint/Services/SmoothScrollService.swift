// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import QuartzCore

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
    private var displayLink: CADisplayLink?
    private var frameTimer: Timer?
    private var schedulerDisplayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    /// Pure per-axis distance engine. The tap callback and timer both live on
    /// the main run loop, so no lock is needed around its state.
    private var engine = SmoothScrollSupport.Engine()
    private var lastFrameTimestamp: TimeInterval?
    private var currentResponse = SmoothScrollSupport.defaultResponse
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
        let wanted = AppFeature.smoothScroll.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.smoothScrollEnabled)
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
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
        guard tap == nil else {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            installScreenObserver()
            installSleepObserver()
            MouseAppExceptions.shared.setSourceTracking(true, for: .smoothScroll)
            isRunning = true
            return
        }
        MouseAppExceptions.shared.setSourceTracking(true, for: .smoothScroll)
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
            MouseAppExceptions.shared.setSourceTracking(false, for: .smoothScroll)
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
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        // Its isRunning is read from the tap callback, so it is built off the event path.
        _ = ScrollInverter.shared
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        installScreenObserver()
        installSleepObserver()
        isRunning = true
    }

    private func stop() {
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        tapCreationRetryUsed = false
        MouseAppExceptions.shared.setSourceTracking(false, for: .smoothScroll)
        removeScreenObserver()
        removeSleepObserver()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        // Hand the tap back rather than only switching it off: a disabled tap
        // keeps its place in the chain, and a session that is switched away
        // has to stop being an event tap owner outright (issue #1075).
        if let tap {
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        stopGlide()
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when the session locks; re-arm,
        // unless this session is the one that was switched away from, where
        // the stall is the reason the tap was disabled and re-arming feeds it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stopGlide()
            let wanted = AppFeature.smoothScroll.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.smoothScrollEnabled)
            let shouldRearm = SessionActivitySupport.tapShouldRun(
                featureWanted: wanted,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            if shouldRearm, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.syncWithPreferences()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        // Our own glide stream coming back through the tap.
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              sourceProcessID != Self.ownProcessID else {
            return Unmanaged.passUnretained(event)
        }
        // A stepped capture-loupe notch is a discrete command, so it must
        // reach the overlay now rather than being expanded into a delayed
        // glide. The opposite (fast) loupe mode intentionally keeps that
        // glide, including when Option temporarily swaps the two modes.
        if ScreenshotSelectionController.steppedLoupeNeedsRawWheel(
            optionPressed: event.flags.contains(.maskAlternate)) {
            stopGlide()
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
        // Control-scroll drives screen zoom; keep its stepping predictable.
        guard !event.flags.contains(.maskControl) else {
            return Unmanaged.passUnretained(event)
        }
        // Apps on this feature's exception list get their wheel raw: the
        // glide would arrive as a much longer move inside apps that read the
        // wheel themselves (issue #358).
        let exceptions = MouseAppExceptions.shared
        guard !exceptions.excludesPointerTarget(
                .smoothScroll,
                at: event.location,
                sourceProcessID: sourceProcessID) else {
            return Unmanaged.passUnretained(event)
        }

        // The head tap swallows the tick before the inverter's tail tap can
        // reach it, so when inverting is on the wheel's vertical flip is
        // applied here; the glide is marked so the inverter leaves it alone.
        // The flip is the inverter's, so it follows the inverter's own
        // exception list: an app excepted there must keep the system's
        // direction even while its wheel glides.
        let invertHere = ScrollInverter.shared.isRunning
            && !exceptions.excludesPointerTarget(
                .scrollDirection,
                at: event.location,
                sourceProcessID: sourceProcessID)
        let defaults = UserDefaults.standard
        let invertVertical = invertHere
            && defaults.bool(forKey: DefaultsKey.scrollInverterEnabled) ? -1.0 : 1.0
        let invertHorizontal = invertHere
            && defaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled) ? -1.0 : 1.0
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
                defaults.integer(forKey: DefaultsKey.smoothScrollStep)))
            vertical = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                pointDelta: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
                step: userStep) * invertVertical
            horizontal = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                pointDelta: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                step: userStep) * invertHorizontal
            // The distance is already in pixels; the budget must not scale it
            // a second time.
            step = 1
        } else {
            // The fixed-point field carries the fractional ticks that
            // high-resolution wheels report while the integer field reads 0.
            let axes = SmoothScrollSupport.axes(
                vertical: SmoothScrollSupport.ticks(
                    line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                    fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)),
                horizontal: SmoothScrollSupport.ticks(
                    line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                    fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)),
                shiftPressed: shiftPressed
            )
            vertical = axes.vertical * invertVertical
            horizontal = axes.horizontal * invertHorizontal
            step = Double(SmoothScrollSupport.sanitizedStep(
                defaults.integer(forKey: DefaultsKey.smoothScrollStep)))
        }
        guard vertical != 0 || horizontal != 0 else {
            return Unmanaged.passUnretained(event)
        }

        // Switching Shift while a glide is active changes the intended axis,
        // and switching between a discrete and a continuous wheel changes the
        // sign handling. Drop the old tail instead of fighting it.
        if currentFlags.contains(.maskShift) != shiftPressed
            || glideFromContinuous != traits.isContinuous {
            engine.reset()
            carryVertical = 0
            carryHorizontal = 0
        }
        let verticalDistance = vertical * step
        let horizontalDistance = horizontal * step
        carryVertical = SmoothScrollSupport.carry(carryVertical, continuing: verticalDistance)
        carryHorizontal = SmoothScrollSupport.carry(carryHorizontal, continuing: horizontalDistance)
        engine.add(vertical: verticalDistance, horizontal: horizontalDistance)
        currentFlags = event.flags
        currentResponse = SmoothScrollSupport.sanitizedResponse(
            defaults.integer(forKey: DefaultsKey.smoothScrollResponse)
        )
        glideFromContinuous = traits.isContinuous
        startGlideIfNeeded()
        // The tick itself is swallowed; the glide replays its distance.
        return nil
    }

    // MARK: - Glide

    private func startGlideIfNeeded() {
        let screen = NSScreen.withMouse
        var displayID: CGDirectDisplayID?
        if let candidate = screen?.displayID, candidate != 0 {
            displayID = candidate
        }
        if displayLink != nil, displayID == schedulerDisplayID { return }
        if frameTimer != nil, displayID == nil { return }

        stopFrameScheduler()
        if let screen, let displayID {
            let displayLink = screen.displayLink(
                target: self,
                selector: #selector(displayLinkDidFire(_:))
            )
            self.displayLink = displayLink
            schedulerDisplayID = displayID
            displayLink.add(to: .main, forMode: .common)
            return
        }

        lastFrameTimestamp = ProcessInfo.processInfo.systemUptime - SmoothScrollSupport.frameInterval
        let timer = Timer(timeInterval: SmoothScrollSupport.frameInterval, repeats: true) { [weak self] _ in
            self?.emitTimerFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        emitTimerFrame()
    }

    private func stopGlide() {
        stopFrameScheduler()
        engine.reset()
        carryVertical = 0
        carryHorizontal = 0
    }

    private func stopFrameScheduler() {
        // A scheduled display link retains its target until invalidated.
        displayLink?.invalidate()
        displayLink = nil
        frameTimer?.invalidate()
        frameTimer = nil
        schedulerDisplayID = nil
        lastFrameTimestamp = nil
    }

    @objc private func displayLinkDidFire(_ sender: CADisplayLink) {
        guard let displayLink, sender === displayLink else { return }
        let firstElapsed = sender.duration > 0 ? sender.duration : SmoothScrollSupport.frameInterval
        emitFrame(at: sender.timestamp, firstElapsed: firstElapsed)
    }

    private func emitTimerFrame() {
        emitFrame(
            at: ProcessInfo.processInfo.systemUptime,
            firstElapsed: SmoothScrollSupport.frameInterval
        )
    }

    private func emitFrame(at timestamp: TimeInterval, firstElapsed: TimeInterval) {
        let elapsed: TimeInterval
        if let lastFrameTimestamp {
            elapsed = timestamp - lastFrameTimestamp
        } else {
            elapsed = firstElapsed
        }
        lastFrameTimestamp = timestamp
        let frame = engine.advance(elapsed: elapsed, response: currentResponse)

        // The frame that empties the budget is the glide's last, so it spends
        // the leftovers rather than saving them for a frame that never comes.
        if frame.vertical != 0 || frame.horizontal != 0 {
            post(vertical: frame.vertical, horizontal: frame.horizontal, landing: frame.finished)
        }
        if frame.finished {
            stopFrameScheduler()
            carryVertical = 0
            carryHorizontal = 0
        }
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard self?.engine.isActive == true else { return }
            self?.startGlideIfNeeded()
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    private func installSleepObserver() {
        guard sleepObserver == nil else { return }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopGlide()
        }
    }

    private func removeSleepObserver() {
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        sleepObserver = nil
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
