// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Middle-click emulation for trackpads: a three-finger PHYSICAL click (four
/// while macOS three-finger drag owns three fingers) becomes a middle click
/// (mouse wheel click), and an opt-in tap mode fires
/// it from a light three or four finger tap (issue #161). By default taps,
/// swipes and resting fingers never click. Finger counts come from
/// `TrackpadTouchService`, the app's single reader of trackpad contacts.
/// The opt-in tap is recognized by `TrackpadGestureService`, which owns every
/// multi-finger tap and calls `postMiddleTap()` for the one reserved here.
/// Requires Accessibility for the event tap.
final class MiddleClickService: ObservableObject {
    static let shared = MiddleClickService()

    @Published private(set) var isRunning = false
    /// The system's own three-finger drag gesture (Accessibility) is enabled:
    /// it owns three-finger touches and synthesizes clicks from unpressed
    /// contact, so the press moves to four fingers and Settings shows why.
    @Published private(set) var systemDragGestureConflict = false
    /// Middle click started but MultitouchSupport gave it no touch device, so
    /// no contact can ever arrive. A pause or session switch clears it.
    @Published private(set) var touchDeviceMissing = false
    /// Mirrors the contact reader's warning while middle click runs.
    private var touchDeviceMissingObserver: AnyCancellable?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Guards the tap port above and the press state below: the callback runs
    /// on the pointer thread while the main thread arms and tears the feature
    /// down.
    private let tapStateLock = NSLock()
    /// Guards the cached system gesture setting, read on the tap callback and
    /// written on the main thread.
    private let dragLock = NSLock()
    private var dragGestureRefreshScheduled = false
    /// Whether presses are turned into middle clicks. Guarded by
    /// `tapStateLock`.
    private var middleClickOn = false
    /// A physical primary or secondary press is currently being relayed as a
    /// middle button, so its drag and release must transform too.
    private var middleButtonHeld = false
    /// A duplicate native down was dropped; its drag and up must be dropped as
    /// well instead of leaking an orphan event or ending the real held click.
    private var suppressedButtonSequence = false
    /// The process that received the transformed down. A recovery up targets
    /// the same process even while this app is terminating.
    private var middleButtonTargetPID: pid_t?
    /// When the hold began; a hold without its release for far too long means
    /// the up was lost (tap briefly disabled), and the flag must not keep
    /// swallowing clicks forever.
    private var middleButtonHeldSince: TimeInterval = 0
    /// When the last transformed click finished, for the bounce guard.
    private var lastTransformEnd: TimeInterval?
    /// Cached three-finger drag system setting; re-read at most every 2 s,
    /// always on the main thread, never from the event path.
    private var dragGestureCache: (enabled: Bool, readAt: TimeInterval) = (false, -10)

    /// Contact state shared between the multitouch callback thread and the
    /// main thread; every access goes through `stateLock`.
    private let stateLock = NSLock()
    private var fingerCount = 0
    private var lastFrameUptime: TimeInterval = 0
    /// When the contact count last changed, for the press settle guard.
    private var fingerCountSince: TimeInterval = 0

    private init() {
        // Multitouch callbacks and the filter tap belong only to the login
        // session on screen. A switched-away process must own neither.
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        // The tap recognizer reads the middle click's tap setting and its
        // running state, so it follows every change made here.
        defer { TrackpadGestureService.shared.syncWithPreferences() }
        let defaults = UserDefaults.standard
        let enabled = AppFeature.middleClick.isAvailable
            && defaults.bool(forKey: DefaultsKey.middleClickEnabled)
        tapStateLock.withLock { middleClickOn = enabled }
        refreshDragGestureConflict()
        if SessionActivitySupport.tapShouldRun(
            featureWanted: enabled,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    /// Re-reads the conflicting system gesture; Settings calls this when the
    /// Mouse tab appears so the warning reflects reality.
    func refreshDragGestureConflict() {
        let enabled = Self.systemThreeFingerDragEnabled()
        dragLock.lock()
        dragGestureCache = (enabled, ProcessInfo.processInfo.systemUptime)
        dragGestureRefreshScheduled = false
        dragLock.unlock()
        if systemDragGestureConflict != enabled {
            systemDragGestureConflict = enabled
        }
    }

    /// Answers from the cache: reading a system preference and publishing the
    /// conflict belong on the main thread, never in the path of a click. A
    /// stale answer refreshes behind the press and applies to the next one.
    private func dragGestureEnabled(now: TimeInterval) -> Bool {
        dragLock.lock()
        let cache = dragGestureCache
        let needsRefresh = now - cache.readAt > 2 && !dragGestureRefreshScheduled
        if needsRefresh { dragGestureRefreshScheduled = true }
        dragLock.unlock()
        if needsRefresh {
            DispatchQueue.main.async { [weak self] in self?.refreshDragGestureConflict() }
        }
        return cache.enabled
    }

    private static func systemThreeFingerDragEnabled() -> Bool {
        boolPreference("TrackpadThreeFingerDrag", domain: "com.apple.AppleMultitouchTrackpad")
            || boolPreference("TrackpadThreeFingerDrag",
                              domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad")
    }

    private static func boolPreference(_ key: String, domain: String) -> Bool {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else {
            return false
        }
        return (value as? NSNumber)?.boolValue ?? false
    }

    /// Force-stops everything regardless of the preference. Used by Cleaning
    /// Mode (wiping the trackpad is nothing but stray contacts) and before
    /// the app resets its own permissions.
    func suspend() { stop() }

    // MARK: - Lifecycle

    private func start() {
        guard tapStateLock.withLock({ tap }) == nil else { return }
        guard TrackpadTouchService.isFrameworkAvailable else {
            touchDeviceMissing = true
            return
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MiddleClickService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapStateLock.withLock {
            self.tap = tap
            runLoopSource = source
        }
        if let source {
            PointerTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        let touch = TrackpadTouchService.shared
        touch.subscribe(.middleClick, wantsGeometry: false) { [weak self] frame in
            self?.contactFrame(fingerCount: frame.count)
        }
        touchDeviceMissingObserver = touch.$touchDeviceMissing.sink { [weak self] missing in
            self?.touchDeviceMissing = missing
        }
        isRunning = true
    }

    private func stop() {
        // Close a transformed press while this process and its event tap are
        // still alive, before tearing down either source.
        releaseHeldMiddleButton()
        let (port, source) = tapStateLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source {
            PointerTapRunLoop.remove(source, invalidating: port)
        }
        touchDeviceMissingObserver = nil
        TrackpadTouchService.shared.unsubscribe(.middleClick)
        tapStateLock.withLock {
            lastTransformEnd = nil
            suppressedButtonSequence = false
        }
        stateLock.lock()
        fingerCount = 0
        lastFrameUptime = 0
        fingerCountSince = 0
        stateLock.unlock()
        isRunning = false
        touchDeviceMissing = false
    }

    // MARK: - Contact frames (multitouch callback thread)

    private func contactFrame(fingerCount count: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        if count != fingerCount { fingerCountSince = now }
        fingerCount = count
        lastFrameUptime = now
        stateLock.unlock()
    }

    /// A judged tap becomes a full middle click at the current pointer. Runs
    /// on the main thread, away from the tap callback; also arms the bounce
    /// guard so a system-synthesized click right behind the tap is not
    /// transformed into a second one. Called by the tap recognizer for the
    /// tap this feature reserves; does nothing while middle click is off.
    func postMiddleTap() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tapStateLock.withLock({ self.tap }) != nil else { return }
            let position = CGEvent(source: nil)?.location ?? .zero
            // Nothing is synthesized over an app on the exception list.
            guard !MouseAppExceptions.shared.excludesPointerTarget(.middleClick, at: position) else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            guard let down = CGEvent(mouseEventSource: source,
                                     mouseType: .otherMouseDown,
                                     mouseCursorPosition: position,
                                     mouseButton: .center),
                  let up = CGEvent(mouseEventSource: source,
                                   mouseType: .otherMouseUp,
                                   mouseCursorPosition: position,
                                   mouseButton: .center) else { return }
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            self.tapStateLock.withLock {
                self.lastTransformEnd = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    // MARK: - Event tap (pointer thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseHeldMiddleButton()
            let enabled = AppFeature.middleClick.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.middleClickEnabled)
            let shouldRearm = SessionActivitySupport.tapShouldRun(
                featureWanted: enabled,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            // stop() lets go of the port before it switches the tap off, and
            // that switch-off arrives here as well. A suspension has to
            // outlast it, so only a tap still held is recovered.
            let port = tapStateLock.withLock { tap }
            switch SessionActivitySupport.disabledTapRecovery(tapHeld: port != nil,
                                                              tapShouldRun: shouldRearm) {
            case .rearm:
                if let port { CGEvent.tapEnable(tap: port, enable: true) }
            case .tearDown:
                // The matching middle-up was sent above. Tear the disabled tap
                // down after its callback returns instead of resurrecting it.
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.syncWithPreferences()
                }
            case .leaveStopped:
                break
            }
            return Unmanaged.passUnretained(event)
        }

        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .leftMouseDown, .rightMouseDown:
            tapStateLock.lock()
            guard middleClickOn else {
                tapStateLock.unlock()
                return Unmanaged.passUnretained(event)
            }
            if suppressedButtonSequence {
                tapStateLock.unlock()
                return nil
            }
            var releaseLostHold = false
            if middleButtonHeld {
                // A lost release must not swallow the user's clicks forever.
                if now - middleButtonHeldSince > 10 {
                    releaseLostHold = true
                } else {
                    // Duplicate synthesized press while the middle button is
                    // already being relayed: drop its whole sequence without
                    // ending the real held click.
                    suppressedButtonSequence = true
                    tapStateLock.unlock()
                    return nil
                }
            }
            tapStateLock.unlock()
            // The release posts an event and waits for it, so it happens with
            // no lock held. It also ends a transform, which the bounce guard
            // below reads back afterwards, exactly as it did inline.
            if releaseLostHold { releaseHeldMiddleButton() }
            // An app on the exception list keeps the plain native click, so a
            // three-finger click means to it what it always meant (issue #358).
            if MouseAppExceptions.shared.excludesPointerTarget(.middleClick, at: event.location) {
                return Unmanaged.passUnretained(event)
            }
            stateLock.lock()
            let count = fingerCount
            let age = now - lastFrameUptime
            let settledFor = now - fingerCountSince
            stateLock.unlock()
            let sinceLastTransformEnd = tapStateLock.withLock { lastTransformEnd }
            let action = MiddleClickSupport.actionForClick(
                fingerCount: count,
                frameAge: age,
                settledFor: settledFor,
                sinceLastTransformEnd: sinceLastTransformEnd.map { now - $0 },
                systemDragGestureEnabled: dragGestureEnabled(now: now)
            )
            switch action {
            case .passThrough:
                return Unmanaged.passUnretained(event)
            case .swallow:
                tapStateLock.withLock { suppressedButtonSequence = true }
                return nil
            case .transform:
                let targetPID = event.getIntegerValueField(.eventTargetUnixProcessID)
                tapStateLock.withLock {
                    middleButtonHeld = true
                    middleButtonHeldSince = now
                    middleButtonTargetPID = targetPID > 0 ? pid_t(targetPID) : nil
                }
                return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseDown))
            }
        case .leftMouseDragged, .rightMouseDragged:
            let (held, suppressed) = tapStateLock.withLock {
                (middleButtonHeld, suppressedButtonSequence)
            }
            if held {
                return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseDragged))
            }
            return suppressed ? nil : Unmanaged.passUnretained(event)
        case .leftMouseUp, .rightMouseUp:
            tapStateLock.lock()
            if suppressedButtonSequence {
                suppressedButtonSequence = false
                tapStateLock.unlock()
                return nil
            }
            guard middleButtonHeld else {
                tapStateLock.unlock()
                return Unmanaged.passUnretained(event)
            }
            middleButtonHeld = false
            middleButtonTargetPID = nil
            lastTransformEnd = now
            tapStateLock.unlock()
            return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseUp))
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// A transformed down must always get its matching middle-button up, even
    /// when the native release was lost or the event tap is being torn down.
    private func releaseHeldMiddleButton() {
        tapStateLock.lock()
        suppressedButtonSequence = false
        guard middleButtonHeld else {
            tapStateLock.unlock()
            return
        }
        middleButtonHeld = false
        let targetPID = middleButtonTargetPID
        middleButtonTargetPID = nil
        tapStateLock.unlock()
        let position = CGEvent(source: nil)?.location ?? .zero
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                            mouseType: .otherMouseUp,
                            mouseCursorPosition: position,
                            mouseButton: .center)
        if let targetPID {
            event?.postToPid(targetPID)
        } else {
            event?.post(tap: .cghidEventTap)
        }
        // CGEvent posting is asynchronous. During app termination, keep this
        // process alive just long enough for WindowServer to deliver the up.
        Thread.sleep(forTimeInterval: 0.02)
        tapStateLock.withLock { lastTransformEnd = ProcessInfo.processInfo.systemUptime }
    }

    /// Rewrites the event in place: same position, timestamp and modifiers,
    /// but a middle-button event instead of its native button.
    private func asMiddle(_ event: CGEvent, type: CGEventType) -> CGEvent {
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        return event
    }
}
