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
/// also checks window identity, so a stale frame cannot claim another icon.
/// Where macOS 27 strands this item's frame at its birth slot (see
/// `StatusItemAnchorSupport`), both checks refuse the drawn icon: the
/// gestures stay inactive there and a left click opens the panel as usual.
final class StatusItemGestureHandler {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                   category: "statusgesture")

    /// Some macOS versions report the press rather than the release. Watch
    /// the physical button every 40 ms while a hold is in flight.
    private static let releaseWatchInterval: TimeInterval = 0.04
    weak var owner: StatusItemController?
    private var gesture = StatusItemGesture()
    private var settings: StatusItemGesture.Settings
    private var monitor: Any?
    private var timer: Timer?
    private var generation = 0
    /// When the left press in flight went down.
    private var leftPressStart: TimeInterval?
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
              isMainButtonWindow(at: event.location) else {
            gesture.cancelMiddle()
            return
        }
        if type == .otherMouseDown {
            gesture.middleDown(at: appKitPoint, settings: settings)
        } else {
            emit(gesture.middleUp(at: appKitPoint, settings: settings, tolerance: dragMargin))
        }
        schedule()
    }

    /// A reported frame can remain at the item's old slot after a move.
    /// Ask the window server who would receive this click before claiming it.
    /// `point` is in display coordinates, as the tap reports it.
    private func isMainButtonWindow(at point: CGPoint) -> Bool {
        guard let number = mainButtonWindowNumber else { return false }
        return WindowServerSupport.receivingWindow(at: point) == CGWindowID(exactly: number)
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
    }

    /// Whether a button action belongs to the left press still in flight.
    /// After a busy main thread its event arrives late, and handing it to the
    /// plain click path would give that one press a second outcome.
    func tracksPress(of event: NSEvent) -> Bool {
        guard gesture.watchesForRelease, let leftPressStart else { return false }
        return event.timestamp >= leftPressStart
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
        if let handledLeftRelease, event.timestamp <= handledLeftRelease { return true }
        // The monitor cancels a Command or Control press; starting it again
        // here would let that press run the hold after all.
        guard event.modifierFlags.intersection([.command, .control]).isEmpty,
              let point = point(event, inset: dragMargin) else {
            // The normal click runs instead, so nothing may finish here too.
            cancel()
            return false
        }
        // A pending middle press is not a left press, so it cannot stand in
        // for the down this click's monitor event never delivered.
        if !gesture.watchesForRelease {
            leftPressStart = event.timestamp
            emit(gesture.leftDown(at: point, time: event.timestamp))
        }
        // A missed monitor down must still start the release watcher. Do not
        // finish a press while the physical button is held.
        if NSEvent.pressedMouseButtons & 0x1 != 0 {
            schedule()
            return true
        }
        handledLeftRelease = event.timestamp
        emit(gesture.leftUp(at: point, time: event.timestamp, settings: settings,
                            tolerance: dragMargin))
        schedule()
        return true
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

    /// The margin a held press may drift within: the icon's own half-width, so
    /// the drift of a finger resting on a trackpad cannot cancel a long press.
    private var dragMargin: CGFloat {
        StatusItemGesture.dragMargin(iconWidth: mainButtonFrame()?.width ?? 0)
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

    /// The event's point when it lands on the main button, expanded by `inset`
    /// so a release just off the edge is still the same click. The decision
    /// itself is the pure `claims` predicate, so the tests exercise the real
    /// branch that decides whether a click is swallowed or runs normally.
    private func point(_ event: NSEvent, inset: CGFloat) -> NSPoint? {
        let point = screenPoint(event)
        guard StatusItemGesture.claims(point, frame: mainButtonFrame(), inset: inset) else {
            return nil
        }
        return point
    }

    // MARK: - Local monitor

    private func observe(_ event: NSEvent) {
        guard settings.hold != .none else { return }
        switch event.type {
        case .rightMouseDown:
            cancel()
        case .leftMouseDown where !event.modifierFlags.intersection([.command, .control]).isEmpty:
            cancel() // Command-drag reorders the icon; Control-click is a context menu
        case .leftMouseDown:
            // A press on another window of this app, such as the Cleaning
            // Mode overlay above the menu bar, never reaches the button. A
            // windowless event is still a menu bar click.
            if let number = event.window?.windowNumber, number != mainButtonWindowNumber {
                cancel()
                return
            }
            guard let point = point(event, inset: 0) else { cancel(); return }
            leftPressStart = event.timestamp
            emit(gesture.leftDown(at: point, time: event.timestamp))
            schedule()
        case .leftMouseDragged:
            // The gesture itself drops a press that moves past its tolerance.
            gesture.moved(to: screenPoint(event), tolerance: dragMargin)
            schedule()
        case .leftMouseUp:
            guard let point = point(event, inset: dragMargin) else {
                cancel()
                return
            }
            // A watcher may have already finished this press. Preserve its
            // release marker; an unobserved newer click can still fall back
            // through the button action.
            guard gesture.watchesForRelease else { return }
            handledLeftRelease = event.timestamp
            emit(gesture.leftUp(at: point, time: event.timestamp, settings: settings,
                                tolerance: dragMargin))
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
            emit(gesture.expired(at: ProcessInfo.processInfo.systemUptime, settings: settings))
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        handledLeftRelease = now
        emit(gesture.leftUp(at: NSEvent.mouseLocation, time: releaseTime(now: now), settings: settings,
                            tolerance: dragMargin))
        schedule()
    }

    /// When the button came up, as the event source recorded it, kept between
    /// the press and this tick. A tick runs up to 40 ms after the release, and
    /// later still when the main thread is busy; judging the press by the
    /// tick would turn a short click into a hold.
    private func releaseTime(now: TimeInterval) -> TimeInterval {
        let sinceRelease = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseUp)
        let released = sinceRelease.isFinite && sinceRelease >= 0 ? now - sinceRelease : -.infinity
        return min(now, max(leftPressStart ?? now, released))
    }
}
