// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Middle-click emulation for trackpads: a three-finger PHYSICAL click
/// becomes a middle click (mouse wheel click), and an opt-in tap mode fires
/// it from a light three or four finger tap (issue #161). By default taps,
/// swipes and resting fingers never click. Contact data comes from the
/// MultitouchSupport private framework (the only source; every middle-click
/// utility uses it), loaded via dlopen/dlsym so a macOS that changes it
/// degrades to the feature simply staying off. Requires Accessibility for
/// the event tap.
final class MiddleClickService: ObservableObject {
    static let shared = MiddleClickService()

    @Published private(set) var isRunning = false
    /// The system's own three-finger drag gesture (Accessibility) is enabled:
    /// it owns three-finger touches and synthesizes clicks from unpressed
    /// contact, so the middle click stands down and Settings shows why.
    @Published private(set) var systemDragGestureConflict = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Retains the MTDeviceRefs while listening; the framework hands out
    /// CF objects owned by this array.
    private var deviceList: CFArray?
    private var observers: [Any] = []
    private var hotplugPort: IONotificationPortRef?
    private var hotplugIterator: io_iterator_t = 0
    /// The physical left button is currently being relayed as a middle
    /// button, so its drag and release must transform too.
    private var middleButtonHeld = false
    /// When the hold began; a hold without its release for far too long means
    /// the up was lost (tap briefly disabled), and the flag must not keep
    /// swallowing clicks forever.
    private var middleButtonHeldSince: TimeInterval = 0
    /// When the last transformed click finished, for the bounce guard.
    private var lastTransformEnd: TimeInterval?
    /// Cached three-finger drag system setting; re-read at most every 2 s.
    private var dragGestureCache: (enabled: Bool, readAt: TimeInterval) = (false, -10)

    /// Contact state shared between the multitouch callback thread and the
    /// main thread; every access goes through `stateLock`.
    private let stateLock = NSLock()
    private var fingerCount = 0
    private var lastFrameUptime: TimeInterval = 0
    /// When the contact count last became exactly three.
    private var threeFingersSince: TimeInterval?

    // Tap-to-middle-click (issue #161), all under `stateLock`. A candidate
    // starts when the chosen finger count lands, collects movement, and is
    // judged when every finger lifts.
    private var tapFingers = 0
    private var tapDragConflict = false
    private var tapStartUptime: TimeInterval?
    private var tapStartPosition: (x: Float, y: Float)?
    private var tapStartSpread: Float?
    private var tapMaxMovement: Float = 0
    private var tapMaxSpreadChange: Float = 0
    private var tapExceededCount = false
    private var tapSawButton = false
    private var tapPositionUnavailable = false

    private init() {}

    func syncWithPreferences() {
        let enabled = AppFeature.middleClick.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.middleClickEnabled)
        let tap = Defaults.sanitizedMiddleClickTapFingers(
            UserDefaults.standard.integer(forKey: DefaultsKey.middleClickTapFingers))
        stateLock.lock()
        tapFingers = tap
        resetTapCandidateLocked()
        stateLock.unlock()
        refreshDragGestureConflict()
        if enabled, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    /// Re-reads the conflicting system gesture; Settings calls this when the
    /// Mouse tab appears so the warning reflects reality.
    func refreshDragGestureConflict() {
        dragGestureCache = (Self.systemThreeFingerDragEnabled(), ProcessInfo.processInfo.systemUptime)
        if systemDragGestureConflict != dragGestureCache.enabled {
            systemDragGestureConflict = dragGestureCache.enabled
        }
        stateLock.lock()
        tapDragConflict = dragGestureCache.enabled
        stateLock.unlock()
    }

    private func dragGestureEnabled(now: TimeInterval) -> Bool {
        if now - dragGestureCache.readAt > 2 {
            refreshDragGestureConflict()
        }
        return dragGestureCache.enabled
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
        guard tap == nil else { return }
        guard Multitouch.available else { return }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MiddleClickService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        startMultitouch()
        installObservers()
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
        if middleButtonHeld {
            middleButtonHeld = false
            // The press went out as a middle-button down; with the tap gone the
            // physical release stays a LEFT up, so apps would keep the middle
            // button held forever. Close it out explicitly.
            let position = CGEvent(source: nil)?.location ?? .zero
            CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                    mouseType: .otherMouseUp,
                    mouseCursorPosition: position,
                    mouseButton: .center)?.post(tap: .cghidEventTap)
        }
        stopMultitouch()
        removeObservers()
        lastTransformEnd = nil
        stateLock.lock()
        fingerCount = 0
        lastFrameUptime = 0
        threeFingersSince = nil
        resetTapCandidateLocked()
        stateLock.unlock()
        isRunning = false
    }

    /// Trackpads come and go across sleep and Bluetooth: drop every contact
    /// registration and rebuild from the current device list.
    private func restartMultitouch() {
        guard tap != nil else { return }
        stopMultitouch()
        startMultitouch()
    }

    private func startMultitouch() {
        guard deviceList == nil, let list = Multitouch.deviceList() else { return }
        deviceList = list
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            Multitouch.register(UnsafeMutableRawPointer(mutating: device), middleClickContactCallback)
            Multitouch.start(UnsafeMutableRawPointer(mutating: device))
        }
    }

    private func stopMultitouch() {
        guard let list = deviceList else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            Multitouch.stop(UnsafeMutableRawPointer(mutating: device))
            Multitouch.register(UnsafeMutableRawPointer(mutating: device), nil)
        }
        deviceList = nil
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.restartMultitouch()
        })
        installHotplugObserver()
    }

    /// A Magic Trackpad appearing mid-session (Bluetooth or USB) must start
    /// streaming without a relaunch. Event-driven via IOKit matching; if the
    /// registration fails the internal trackpad still works.
    private func installHotplugObserver() {
        guard hotplugPort == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var iterator: io_iterator_t = 0
        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching("AppleMultitouchDevice"),
            { context, iterator in
                guard let context else { return }
                while case let entry = IOIteratorNext(iterator), entry != 0 {
                    IOObjectRelease(entry)
                }
                let service = Unmanaged<MiddleClickService>.fromOpaque(context).takeUnretainedValue()
                service.restartMultitouch()
            },
            context,
            &iterator
        )
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }
        // Drain the existing devices or the notification never arms.
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            IOObjectRelease(entry)
        }
        hotplugPort = port
        hotplugIterator = iterator
    }

    private func removeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        if hotplugIterator != 0 {
            IOObjectRelease(hotplugIterator)
            hotplugIterator = 0
        }
        if let hotplugPort {
            IONotificationPortDestroy(hotplugPort)
            self.hotplugPort = nil
        }
    }

    // MARK: - Contact frames (multitouch callback thread)

    fileprivate func contactFrame(fingerCount count: Int,
                                  touches: UnsafeMutableRawPointer?) {
        let now = ProcessInfo.processInfo.systemUptime
        var fireTap = false
        stateLock.lock()
        if count == 3 {
            if fingerCount != 3 { threeFingersSince = now }
        } else {
            threeFingersSince = nil
        }
        fingerCount = count
        lastFrameUptime = now
        if tapFingers > 0 {
            // Touch geometry is read only while the tap option is on: with it
            // off (the default) the per-frame cost stays what it always was.
            let geometry = Multitouch.touchGeometry(touches: touches, count: count)
            fireTap = trackTapLocked(count: count, geometry: geometry, now: now)
        }
        stateLock.unlock()
        if fireTap {
            postMiddleTap()
        }
    }

    /// The tap candidate's life, under `stateLock`: born when the chosen
    /// finger count lands, cancelled by extra fingers, movement (a swipe), a
    /// physical click or unreadable positions, judged when the pad empties.
    /// Returns true when the finished touch should fire a middle click.
    private func trackTapLocked(count: Int,
                                geometry: (center: (x: Float, y: Float), spread: Float)?,
                                now: TimeInterval) -> Bool {
        if count == 0 {
            defer { resetTapCandidateLocked() }
            guard let startedAt = tapStartUptime else { return false }
            return MiddleClickSupport.tapShouldFire(duration: now - startedAt,
                                                    maxMovement: tapMaxMovement,
                                                    maxSpreadChange: tapMaxSpreadChange,
                                                    exceededFingerCount: tapExceededCount,
                                                    buttonPressedDuring: tapSawButton,
                                                    positionUnavailable: tapPositionUnavailable,
                                                    systemDragGestureEnabled: tapDragConflict,
                                                    tapFingers: tapFingers)
        }
        if count > tapFingers {
            tapExceededCount = true
            return false
        }
        if count == tapFingers {
            if tapStartUptime == nil {
                guard !tapExceededCount else { return false }
                tapStartUptime = now
                tapStartPosition = geometry?.center
                tapStartSpread = geometry?.spread
                tapMaxMovement = 0
                tapMaxSpreadChange = 0
                tapSawButton = false
                tapPositionUnavailable = geometry == nil
            } else if let start = tapStartPosition, let geometry {
                tapMaxMovement = max(tapMaxMovement,
                                     max(abs(geometry.center.x - start.x),
                                         abs(geometry.center.y - start.y)))
                if let startSpread = tapStartSpread {
                    tapMaxSpreadChange = max(tapMaxSpreadChange,
                                             abs(geometry.spread - startSpread))
                }
            } else if geometry == nil {
                tapPositionUnavailable = true
            }
        }
        // Counts between 1 and tapFingers - 1 are fingers landing or lifting
        // mid-touch; the candidate stays as it is until the pad empties.
        return false
    }

    private func resetTapCandidateLocked() {
        tapStartUptime = nil
        tapStartPosition = nil
        tapStartSpread = nil
        tapMaxMovement = 0
        tapMaxSpreadChange = 0
        tapExceededCount = false
        tapSawButton = false
        tapPositionUnavailable = false
    }

    /// A judged tap becomes a full middle click at the current pointer. Runs
    /// on the main thread; also arms the bounce guard so a system-synthesized
    /// click right behind the tap is not transformed into a second one.
    private func postMiddleTap() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tap != nil else { return }
            let position = CGEvent(source: nil)?.location ?? .zero
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
            self.lastTransformEnd = ProcessInfo.processInfo.systemUptime
        }
    }

    // MARK: - Event tap (main thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .leftMouseDown:
            stateLock.lock()
            if tapStartUptime != nil { tapSawButton = true }
            stateLock.unlock()
            if middleButtonHeld {
                // A lost release must not swallow the user's clicks forever.
                if now - middleButtonHeldSince > 10 {
                    middleButtonHeld = false
                } else {
                    // Duplicate synthesized press while the middle button is
                    // already being relayed: a bounce, drop it.
                    return nil
                }
            }
            stateLock.lock()
            let count = fingerCount
            let age = now - lastFrameUptime
            let settledFor = threeFingersSince.map { now - $0 } ?? 0
            stateLock.unlock()
            let action = MiddleClickSupport.actionForClick(
                fingerCount: count,
                frameAge: age,
                settledFor: settledFor,
                sinceLastTransformEnd: lastTransformEnd.map { now - $0 },
                systemDragGestureEnabled: dragGestureEnabled(now: now)
            )
            switch action {
            case .passThrough:
                return Unmanaged.passUnretained(event)
            case .swallow:
                return nil
            case .transform:
                middleButtonHeld = true
                middleButtonHeldSince = now
                return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseDown))
            }
        case .leftMouseDragged:
            guard middleButtonHeld else { return Unmanaged.passUnretained(event) }
            return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseDragged))
        case .leftMouseUp:
            guard middleButtonHeld else { return Unmanaged.passUnretained(event) }
            middleButtonHeld = false
            lastTransformEnd = now
            return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseUp))
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Rewrites the event in place: same position, timestamp and modifiers,
    /// but a middle-button event instead of a left one.
    private func asMiddle(_ event: CGEvent, type: CGEventType) -> CGEvent {
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        return event
    }
}

// MARK: - MultitouchSupport bridge

/// The raw contact callback: (device, touches, count, timestamp, frame).
/// The finger count always feeds the press path; the touch records are read
/// (two floats per touch, range-checked) only while the opt-in tap mode is
/// on — see Multitouch.touchGeometry for the layout contract.
private func middleClickContactCallback(_ device: UnsafeMutableRawPointer?,
                                        _ touches: UnsafeMutableRawPointer?,
                                        _ count: Int32,
                                        _ timestamp: Double,
                                        _ frame: Int32) -> Int32 {
    MiddleClickService.shared.contactFrame(fingerCount: Int(count), touches: touches)
    return 0
}

/// dlopen/dlsym bridge to MultitouchSupport. Everything is optional: a macOS
/// build without the framework or its symbols makes `available` false and the
/// feature stays off instead of crashing.
private enum Multitouch {
    typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback?) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_NOW
    )

    private static let createListFn: CreateListFn? = symbol("MTDeviceCreateList")
    private static let registerFn: RegisterFn? = symbol("MTRegisterContactFrameCallback")
    private static let startFn: StartFn? = symbol("MTDeviceStart")
    private static let stopFn: StopFn? = symbol("MTDeviceStop")

    static var available: Bool {
        createListFn != nil && registerFn != nil && startFn != nil && stopFn != nil
    }

    static func deviceList() -> CFArray? {
        guard let createListFn else { return nil }
        let list = createListFn()?.takeRetainedValue()
        guard let list, CFArrayGetCount(list) > 0 else { return nil }
        return list
    }

    static func register(_ device: UnsafeMutableRawPointer, _ callback: ContactCallback?) {
        registerFn?(device, callback)
    }

    static func start(_ device: UnsafeMutableRawPointer) {
        startFn?(device, 0)
    }

    static func stop(_ device: UnsafeMutableRawPointer) {
        stopFn?(device)
    }

    /// The canonical touch record layout every multitouch utility relies on
    /// (96-byte stride; normalized position floats at offsets 32/36),
    /// unchanged for over a decade. Only those two floats are read, and any
    /// value outside the pad's normalized range means the layout moved: the
    /// frame reports no position and tap detection stands down for the touch
    /// instead of misfiring.
    private static let touchStride = 96
    private static let touchPositionXOffset = 32
    private static let touchPositionYOffset = 36

    /// Centroid plus spread (mean distance of the touches from the centroid):
    /// the spread is what separates a still tap from a pinch, whose centroid
    /// barely moves.
    static func touchGeometry(touches: UnsafeMutableRawPointer?,
                              count: Int) -> (center: (x: Float, y: Float), spread: Float)? {
        guard let touches, count > 0 else { return nil }
        var xs = [Float]()
        var ys = [Float]()
        xs.reserveCapacity(count)
        ys.reserveCapacity(count)
        for index in 0..<count {
            let base = touches.advanced(by: index * touchStride)
            let x = base.loadUnaligned(fromByteOffset: touchPositionXOffset, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: touchPositionYOffset, as: Float.self)
            guard x.isFinite, y.isFinite,
                  x >= -0.2, x <= 1.2, y >= -0.2, y <= 1.2 else { return nil }
            xs.append(x)
            ys.append(y)
        }
        let centerX = xs.reduce(0, +) / Float(count)
        let centerY = ys.reduce(0, +) / Float(count)
        var spread: Float = 0
        for index in 0..<count {
            let dx = xs[index] - centerX
            let dy = ys[index] - centerY
            spread += (dx * dx + dy * dy).squareRoot()
        }
        spread /= Float(count)
        return ((centerX, centerY), spread)
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
