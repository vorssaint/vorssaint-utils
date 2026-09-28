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
/// Geometry is derived from the button's on-screen frame rather than from
/// window identity, so a changed status-bar window on a future macOS cannot
/// silently swallow clicks. Every entry point reports whether it consumed the
/// event; a caller that gets `false` must run the original single-click path,
/// because a click the gesture layer cannot reason about must never be lost.
final class StatusItemGestureHandler {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                   category: "statusgesture")

    /// How often the held button's release is looked for. The status button
    /// never reports it, and a person cannot tell 40 ms from instant, so this
    /// is short enough to feel immediate and long enough to cost nothing.
    private static let releaseWatchInterval: TimeInterval = 0.04
    weak var owner: StatusItemController?
    private var gesture = StatusItemGesture()
    private var settings: StatusItemGesture.Settings
    private var monitor: Any?
    private var timer: Timer?
    private var generation = 0
    private var observedLeftDown: TimeInterval?
    private var observedLeftUp: TimeInterval?
    private var resignObserver: Any?
    /// The status button is an `NSStatusItem`, and macOS never delivers a
    /// middle-click on one to the owning app — no local monitor can see it.
    /// A passive session tap is therefore the only way to serve this gesture.
    private var middleTap: CFMachPort?
    private var middleRunLoopSource: CFRunLoopSource?
    private var requestedAccessibilityForMiddle = false
    private var accessibilityObserver: AnyCancellable?

    init(owner: StatusItemController, settings: StatusItemGesture.Settings) {
        self.owner = owner
        self.settings = settings
        // A local monitor runs before the event reaches the button, so it
        // records the real down timestamp a held button needs. It never
        // consumes anything: the event continues to AppKit untouched.
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                       .rightMouseDown, .keyDown]) { [weak self] event in
            self?.observe(event)
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
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
                self?.syncMiddleTap(accessibilityGranted: granted, requestPermission: false)
            }
    }

    /// Installed only while a middle-click action is assigned, so a Mac that
    /// never uses this gesture pays neither the permission nor the tap.
    private func syncMiddleTap(accessibilityGranted: Bool = AXIsProcessTrusted(),
                               requestPermission: Bool = true) {
        guard settings.middle != .none else {
            tearDownMiddleTap()
            return
        }
        guard accessibilityGranted else {
            cancel()
            tearDownMiddleTap()
            // The one thing the user cannot guess: this gesture is the only
            // one that needs Accessibility. Ask once, in context.
            if requestPermission && !requestedAccessibilityForMiddle {
                requestedAccessibilityForMiddle = true
                Permissions.shared.requestAccessibility()
                log("middle tap needs Accessibility; asked once")
            }
            return
        }
        guard middleTap == nil else { return }
        installMiddleTap()
    }

    private func installMiddleTap() {
        // A listen-only tap observes without ever holding an event back, so it
        // cannot make another app's click late and needs no timeout recovery.
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
        guard type == .otherMouseDown || type == .otherMouseUp,
              event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return }
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height ?? 0
        let appKitPoint = StatusItemGesture.appKitPoint(displayPoint: event.location,
                                                        primaryHeight: primaryHeight)
        let frame = mainButtonFrame()
        guard StatusItemGesture.claims(appKitPoint, frame: frame) else {
            cancel()
            return
        }
        if type == .otherMouseDown {
            gesture.middleDown(at: appKitPoint, settings: settings)
        } else {
            emit(gesture.middleUp(at: appKitPoint, settings: settings, tolerance: dragMargin))
        }
        schedule()
    }

    private func log(_ message: String) {
        Self.log.notice("\(message, privacy: .public)")
    }

    deinit {
        tearDownMiddleTap()
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func sync(settings new: StatusItemGesture.Settings) {
        let changed = new != settings
        if changed {
            cancel()
            settings = new
        }
        syncMiddleTap(requestPermission: changed)
    }

    func cancel() {
        gesture.cancel()
        timer?.invalidate()
        timer = nil
        generation &+= 1
        observedLeftDown = nil
        observedLeftUp = nil
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
        guard observedLeftUp != event.timestamp else { return true }
        guard let point = point(event, inset: dragMargin) else {
            return false
        }
        if !gesture.isActive {
            observedLeftDown = event.timestamp
            emit(gesture.leftDown(at: point, time: event.timestamp))
        }
        // A missed monitor down must still start the release watcher. Do not
        // finish a press while the physical button is held.
        if NSEvent.pressedMouseButtons & 0x1 != 0 {
            schedule()
            return true
        }
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
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { cancel() } // Esc
        case .rightMouseDown:
            cancel()
        case .leftMouseDown where !event.modifierFlags.intersection([.command, .control]).isEmpty:
            cancel() // Command-drag reorders the icon; Control-click is a context menu
        case .leftMouseDown:
            guard let point = point(event, inset: 0) else { cancel(); return }
            observedLeftDown = event.timestamp
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
            guard gesture.isActive else {
                // The monitor never saw this press start — a status button runs
                // its own tracking loop, and a down can be consumed there. Do
                // NOT claim this up: leaving it unclaimed lets the button
                // action synthesize the press, so the click still lands.
                observedLeftUp = nil
                return
            }
            observedLeftUp = event.timestamp
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

    /// The status button reports its press, never its release, so a left press
    /// is followed by a repeating watcher on the physical button instead of a
    /// single deadline. Everything else still uses one one-shot deadline.
    /// Watches the physical button while a press is in flight.
    ///
    /// There is no deadline to schedule: the status button reports its press
    /// and never its release, so the long press and the release are both
    /// observed here. Nothing runs when no press is in flight.
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

    /// One turn of the press watcher. The long press is committed here once the
    /// threshold passes, and the release is delivered here the moment the
    /// physical button comes up — no event ever reports it.
    private func observeRelease() {
        let stillHeld = NSEvent.pressedMouseButtons & 0x1 != 0
        if stillHeld {
            emit(gesture.expired(at: ProcessInfo.processInfo.systemUptime, settings: settings))
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        emit(gesture.leftUp(at: NSEvent.mouseLocation, time: now, settings: settings,
                            tolerance: dragMargin))
        schedule()
    }
}
