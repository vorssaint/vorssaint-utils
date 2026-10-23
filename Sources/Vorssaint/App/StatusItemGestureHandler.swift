// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import os.log

/// Watches only the main status button. Returning every local event intact
/// preserves AppKit's own button tracking, Command-drag and every other
/// status item.
///
/// Left clicks use the button's frame, with the original click path as a
/// fallback when that frame cannot be trusted. The session-wide middle tap
/// also asks who owns the point, so a stale frame cannot claim another icon.
/// Where macOS 27 strands this item's frame at its birth slot (see
/// `StatusItemAnchorSupport`), the frame check refuses the drawn icon: the
/// gestures stay inactive there and a left click opens the panel as usual.
final class StatusItemGestureHandler {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                   category: "statusgesture")

    /// Some macOS versions report the press rather than the release. Watch
    /// the physical button every 40 ms while a hold is in flight.
    private static let releaseWatchInterval: TimeInterval = 0.04
    /// How long a press the watcher ended still waits for its own button
    /// action. A busy main thread can deliver that action late, but one that
    /// never comes (a release just off the button) must not hold back an
    /// accessibility press for long.
    private static let lateActionWindow: TimeInterval = 2
    weak var owner: StatusItemController?
    private var gesture = StatusItemGesture()
    private var settings: StatusItemGesture.Settings
    private var monitor: Any?
    private var timer: Timer?
    private var generation = 0
    /// When the left press in flight went down.
    private var leftPressStart: TimeInterval?
    /// Where that press was last seen while the button was still down. The
    /// watcher notices a release on its next tick, when the pointer may
    /// already be on its way elsewhere.
    private var lastHeldPoint: CGPoint?
    /// Whether the latest left press's button action has arrived. Until it
    /// has, a late action for that press is still its own.
    private var leftActionSeen = true
    /// The latest Command or Control press the monitor turned away. Where the
    /// button reports its press, that press's action carries the same time.
    private var rejectedLeftDown: TimeInterval?
    /// Latest release handled by any path. Kept across cancellation so a
    /// delayed AppKit action cannot replay a click after its callback runs.
    private var handledLeftRelease: TimeInterval?
    /// The status button is an `NSStatusItem`, and macOS never delivers a
    /// middle-click on one to the owning app — no local monitor can see it.
    /// A passive session tap is therefore the only way to serve this gesture.
    private var middleTap: CFMachPort?
    private var middleRunLoopSource: CFRunLoopSource?
    private var accessibilityObserver: AnyCancellable?

    init(owner: StatusItemController, settings: StatusItemGesture.Settings) {
        self.owner = owner
        self.settings = settings
        // A local monitor runs before the event reaches the button, so it
        // records the real down timestamp a held button needs. It never
        // consumes anything: the event continues to AppKit untouched. Key
        // events and activation are left alone: this accessory app is rarely
        // active while its icon is pressed, and the release watcher ends every
        // press without them.
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                       .rightMouseDown]) { [weak self] event in
            self?.observe(event)
            return event
        }
        log("handler created middle=\(settings.middle.rawValue) hold=\(settings.hold.rawValue)")
        watchAccessibility()
        syncMiddleTap()
    }

    // MARK: - Middle-click tap

    private func watchAccessibility() {
        accessibilityObserver = Permissions.shared.$accessibility
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] granted in
                self?.syncMiddleTap(accessibilityGranted: granted)
            }
    }

    /// Installed only while a middle-click action is assigned, so a Mac that
    /// never uses this gesture pays neither the permission nor the tap.
    private func syncMiddleTap(accessibilityGranted: Bool = AXIsProcessTrusted()) {
        guard settings.needsAccessibility else {
            tearDownMiddleTap()
            return
        }
        guard accessibilityGranted else {
            tearDownMiddleTap()
            // Launch, settings sync and grant changes are passive. Only the
            // middle-click picker (or an explicit permission button) asks.
            return
        }
        // A revoke/regrant between permission polls can leave the published
        // grant unchanged while the system has disabled the old tap.
        if let middleTap, !CGEvent.tapIsEnabled(tap: middleTap) {
            tearDownMiddleTap()
        }
        guard middleTap == nil else { return }
        installMiddleTap()
    }

    private func installMiddleTap() {
        // A listen-only tap never holds another app's event back, but the
        // system can still disable it; handleMiddleTap re-arms it.
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let handler = Unmanaged<StatusItemGestureHandler>.fromOpaque(userInfo).takeUnretainedValue()
                handler.handleMiddleTap(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("middle tap could not be created (permission?)")
            return
        }
        middleTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        middleRunLoopSource = source
        // Served on the main run loop, the same as the project's other
        // button-shortcut tap: the callback must read AppKit geometry, and a
        // listen-only tap never blocks the events it observes.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("middle tap installed")
    }

    private func tearDownMiddleTap() {
        gesture.cancelMiddle()
        if let middleTap {
            CGEvent.tapEnable(tap: middleTap, enable: false)
            CFMachPortInvalidate(middleTap)
        }
        if let middleRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), middleRunLoopSource, .commonModes)
        }
        middleTap = nil
        middleRunLoopSource = nil
    }

    /// Middle-click geometry arrives in display coordinates (origin at the top
    /// left of the primary display); AppKit screens put the origin at its
    /// bottom left. One flip maps between them for every display.
    private func handleMiddleTap(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            gesture.cancelMiddle() // An observation gap breaks the down/up pair.
            if settings.needsAccessibility, AXIsProcessTrusted(), let middleTap {
                CGEvent.tapEnable(tap: middleTap, enable: true)
            } else {
                // Do not invalidate the port from its own callback stack.
                DispatchQueue.main.async { [weak self] in self?.syncMiddleTap() }
            }
            return
        }
        guard type == .otherMouseDown || type == .otherMouseUp,
              event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return }
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height ?? 0
        let appKitPoint = StatusItemGesture.appKitPoint(displayPoint: event.location,
                                                        primaryHeight: primaryHeight)
        let frame = mainButtonFrame()
        guard StatusItemGesture.claims(appKitPoint, frame: frame),
              ownsClick(at: event.location) else {
            gesture.cancelMiddle()
            return
        }
        if type == .otherMouseDown {
            gesture.middleDown(settings: settings, within: hitArea ?? .null)
        } else {
            emit(gesture.middleUp(at: appKitPoint, settings: settings))
        }
        schedule()
    }

    /// Whether the item under `point` (display coordinates, as the tap
    /// reports them) is this icon. A reported frame can stay at the item's
    /// old slot after a move, so the frame alone cannot say.
    ///
    /// Where the button's own window takes the click, the window server names
    /// it. Where the system draws the menu bar itself, as macOS 27 does, that
    /// window is no window-server window and the point belongs to the
    /// system's bar; Accessibility, which the middle click already needs,
    /// then names the app whose item is there. Another window of this app,
    /// such as the Cleaning Mode overlay, is never the icon.
    private func ownsClick(at point: CGPoint) -> Bool {
        guard let number = mainButtonWindowNumber else { return false }
        if let receiving = WindowServerSupport.receivingWindow(at: point) {
            if receiving == CGWindowID(exactly: number) { return true }
            if WindowServerSupport.ownerProcessID(ofWindowID: receiving) == getpid() { return false }
        }
        return accessibilityOwner(at: point) == getpid()
    }

    /// The process whose element is at `point`, within the app-wide
    /// Accessibility wait limit. Asking about this app's own item is answered
    /// in-process.
    private func accessibilityOwner(at point: CGPoint) -> pid_t? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                               Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    /// The main button's window, or nil when the item is hidden or unplaced.
    private var mainButtonWindowNumber: Int? {
        guard let item = owner?.statusItem, item.isVisible,
              let number = item.button?.window?.windowNumber, number > 0 else { return nil }
        return number
    }

    private func log(_ message: String) {
        Self.log.notice("\(message, privacy: .public)")
    }

    deinit {
        tearDownMiddleTap()
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func sync(settings new: StatusItemGesture.Settings) {
        let changed = new != settings
        if changed {
            cancel()
            settings = new
        }
        syncMiddleTap()
    }

    func cancel() {
        gesture.cancel()
        timer?.invalidate()
        timer = nil
        generation &+= 1
        leftPressStart = nil
        lastHeldPoint = nil
    }

    /// Whether a button action belongs to the latest left press. After a busy
    /// main thread its event arrives late, and handing it to the plain click
    /// path would give that one press a second outcome. That holds after the
    /// watcher has ended the press too, until the press's own action arrives.
    func tracksPress(of event: NSEvent) -> Bool {
        guard let leftPressStart, event.timestamp >= leftPressStart else { return false }
        if gesture.watchesForRelease { return true }
        guard !leftActionSeen, let handledLeftRelease,
              ProcessInfo.processInfo.systemUptime - handledLeftRelease <= Self.lateActionWindow
        else { return false }
        return event.timestamp <= handledLeftRelease
    }

    /// Returns false when the click is not on the button, or when the button's
    /// frame cannot be trusted, so the caller can run the normal click instead
    /// of swallowing it.
    ///
    /// This is the guaranteed second path: AppKit's button action always fires
    /// once per left press, so a monitor event this handler never saw still
    /// produces exactly one outcome instead of a lost click.
    @discardableResult
    func buttonClick(_ event: NSEvent) -> Bool {
        guard settings.hold != .none else { return false }
        leftActionSeen = true
        if let handledLeftRelease, event.timestamp <= handledLeftRelease { return true }
        // The monitor turns a Command or Control press away; starting it
        // again here would let that press run the hold after all.
        let rejected = rejectedLeftDown.map { event.timestamp <= $0 } ?? false
        guard !rejected, event.modifierFlags.intersection([.command, .control]).isEmpty,
              let point = point(event, in: hitArea) else {
            // The normal click runs instead, so nothing may finish here too.
            cancel()
            return false
        }
        // A pending middle press is not a left press, so it cannot stand in
        // for the down this click's monitor event never delivered.
        let inFlight = gesture.watchesForRelease
        if !inFlight {
            beginLeftPress(at: point, time: event.timestamp)
        }
        // A missed monitor down must still start the release watcher. Do not
        // finish a press while the physical button is held.
        if NSEvent.pressedMouseButtons & 0x1 != 0 {
            schedule()
            return true
        }
        // Where the button reports its press, a late action carries the press
        // time, while the press it belongs to ended when the button came up.
        let released = inFlight
            ? max(event.timestamp, releaseTime(now: ProcessInfo.processInfo.systemUptime))
            : event.timestamp
        handledLeftRelease = released
        emit(gesture.leftUp(at: point, time: released, settings: settings))
        schedule()
        return true
    }

    private func beginLeftPress(at point: NSPoint, time: TimeInterval) {
        leftPressStart = time
        lastHeldPoint = point
        emit(gesture.leftDown(at: point, time: time, within: hitArea ?? .null))
    }
    // MARK: - Geometry

    /// The main button's frame in screen coordinates, or nil when the item is
    /// hidden or has not been placed yet.
    private func mainButtonFrame() -> NSRect? {
        guard let item = owner?.statusItem, item.isVisible,
              let button = item.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    /// Where a press on the button may stray and still count: the icon plus
    /// a little slack, whatever the item's title makes its width.
    private var hitArea: CGRect? {
        StatusItemGesture.hitArea(of: mainButtonFrame())
    }

    /// The pointer's screen position for this event.
    ///
    /// `NSEvent.mouseLocation` is the authoritative screen coordinate for a
    /// live mouse event. Deriving it from `locationInWindow` looks equivalent
    /// but breaks for menu bar clicks that AppKit delivers with no window:
    /// `locationInWindow` is then not the screen space it is documented to be,
    /// the point misses the icon, and the whole gesture is discarded.
    private func screenPoint(_ event: NSEvent) -> NSPoint {
        NSEvent.mouseLocation
    }

    /// The event's point when it lands in `area`: the button's frame for a
    /// press, its hit area for a release, so a release just off the edge is
    /// still the same click. The decision itself is the pure `claims`
    /// predicate, so the tests exercise the real branch that decides whether a
    /// click is swallowed or runs normally.
    private func point(_ event: NSEvent, in area: CGRect?) -> NSPoint? {
        let point = screenPoint(event)
        guard StatusItemGesture.claims(point, frame: area) else { return nil }
        return point
    }

    // MARK: - Local monitor

    private func observe(_ event: NSEvent) {
        guard settings.hold != .none else { return }
        switch event.type {
        case .rightMouseDown:
            cancel()
        case .leftMouseDown where !event.modifierFlags.intersection([.command, .control]).isEmpty:
            // Command-drag reorders the icon; Control-click is a context menu.
            rejectedLeftDown = event.timestamp
            cancel()
        case .leftMouseDown:
            // A press on another window of this app, such as the Cleaning
            // Mode overlay above the menu bar, never reaches the button. A
            // windowless event is still a menu bar click.
            if let number = event.window?.windowNumber, number != mainButtonWindowNumber {
                cancel()
                return
            }
            guard let point = point(event, in: mainButtonFrame()) else { cancel(); return }
            leftActionSeen = false
            beginLeftPress(at: point, time: event.timestamp)
            schedule()
        case .leftMouseDragged:
            held(at: screenPoint(event))
        case .leftMouseUp:
            guard let point = point(event, in: hitArea) else {
                cancel()
                return
            }
            // A watcher may have already finished this press. Preserve its
            // release marker; an unobserved newer click can still fall back
            // through the button action.
            guard gesture.watchesForRelease else { return }
            handledLeftRelease = event.timestamp
            emit(gesture.leftUp(at: point, time: event.timestamp, settings: settings))
            schedule()
        default:
            break
        }
    }

    private func emit(_ results: [StatusItemGesture.Result]) {
        for result in results {
            switch result {
            case .single(let point):
                owner?.onDelayedLeftClick?(point)
            case .quick(let action):
                owner?.onQuickAction?(action)
            }
        }
    }

    /// Watch the physical button while a hold is in flight, including on
    /// macOS versions whose status button action does not report the release.
    private func schedule() {
        timer?.invalidate()
        timer = nil
        generation &+= 1
        guard gesture.watchesForRelease else { return }
        let scheduledGeneration = generation
        let watch = Timer(timeInterval: Self.releaseWatchInterval, repeats: true) { [weak self] _ in
            guard let self, self.generation == scheduledGeneration else { return }
            self.observeRelease()
        }
        timer = watch
        RunLoop.main.add(watch, forMode: .common)
    }

    /// Record a handled release before calling out: AppKit may send its
    /// release action later, with a timestamp no newer than this sample.
    private func observeRelease() {
        guard gesture.watchesForRelease else { return }
        let stillHeld = NSEvent.pressedMouseButtons & 0x1 != 0
        if stillHeld {
            held(at: NSEvent.mouseLocation)
            emit(gesture.expired(at: ProcessInfo.processInfo.systemUptime, settings: settings))
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        handledLeftRelease = now
        emit(gesture.leftUp(at: lastHeldPoint ?? NSEvent.mouseLocation, time: releaseTime(now: now),
                            settings: settings))
        schedule()
    }

    /// The pointer of a press still held. Leaving the icon cancels the press
    /// at once, the same from a drag event or from the watcher.
    private func held(at point: CGPoint) {
        guard gesture.watchesForRelease else { return }
        lastHeldPoint = point
        gesture.moved(to: point)
        if !gesture.watchesForRelease { cancel() }
    }

    /// When the button came up, as the event source recorded it, kept between
    /// the press and this tick. A tick runs up to 40 ms after the release, and
    /// later still when the main thread is busy; judging the press by the
    /// tick would turn a short click into a hold.
    private func releaseTime(now: TimeInterval) -> TimeInterval {
        let start = leftPressStart ?? now
        var released = eventTime(.leftMouseUp, now: now) ?? -.infinity
        // A press that began since this one makes the last release possibly
        // its own; this press came up before that one went down.
        if let down = eventTime(.leftMouseDown, now: now), down > start + 0.001 {
            released = min(released, down)
        }
        return min(now, max(start, released))
    }

    /// When the hardware last reported an event of `type`, or nil when the
    /// event source cannot say.
    private func eventTime(_ type: CGEventType, now: TimeInterval) -> TimeInterval? {
        let since = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
        return since.isFinite && since >= 0 ? now - since : nil
    }
}
