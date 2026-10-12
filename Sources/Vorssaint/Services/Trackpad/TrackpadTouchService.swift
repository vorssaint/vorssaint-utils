// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import IOKit

/// One contact frame from the trackpad, as every reader sees it.
struct TrackpadTouchFrame {
    /// Fingers touching the pad; 0 once the last one lifted.
    let count: Int
    /// Average position and spread of the fingers. Nil when no reader asked
    /// for positions, when nothing touches, or when the touch records could
    /// not be read safely.
    let geometry: TrackpadGestureSupport.Geometry?
}

/// The single reader of raw trackpad contacts. MultitouchSupport accepts one
/// contact callback per device, so the middle click's press detection and the
/// tap and gesture recognizer subscribe here instead of registering twice.
///
/// Contact data comes from the MultitouchSupport private framework (the only
/// source; every middle-click and gesture utility uses it), loaded via
/// dlopen/dlsym so a macOS that changes it degrades to the readers simply
/// receiving nothing. Devices are listened to only while someone subscribes.
final class TrackpadTouchService: ObservableObject {
    static let shared = TrackpadTouchService()

    /// A reader is subscribed but MultitouchSupport gave it no touch device,
    /// so no contact can ever arrive. The last unsubscribe clears it.
    @Published private(set) var touchDeviceMissing = false

    enum Reader: Hashable {
        case middleClick
        case gestures
    }

    private struct Subscription {
        let wantsGeometry: Bool
        let handler: (TrackpadTouchFrame) -> Void
    }

    /// Guards the subscriptions, read on the multitouch callback thread and
    /// written on the main thread.
    private let subscriptionLock = NSLock()
    private var subscriptions: [Reader: Subscription] = [:]
    /// The same subscriptions as a list, rebuilt only when one changes, so
    /// delivering a frame copies a reference instead of allocating.
    private var readers: [Subscription] = []
    /// Main thread only from here on.
    private var isListening = false
    /// Retains the MTDeviceRefs while listening; the framework hands out
    /// CF objects owned by this array.
    private var deviceList: CFArray?
    private var observers: [Any] = []
    private var hotplugPort: IONotificationPortRef?
    private var hotplugIterators: [io_iterator_t] = []

    private init() {}

    /// Whether this macOS still offers the contact API at all.
    static var isFrameworkAvailable: Bool { Multitouch.available }

    /// Starts delivering frames to `reader` on the multitouch thread. The
    /// handler must be quick and lock what it shares. Main thread.
    func subscribe(_ reader: Reader, wantsGeometry: Bool,
                   handler: @escaping (TrackpadTouchFrame) -> Void) {
        subscriptionLock.withLock {
            subscriptions[reader] = Subscription(wantsGeometry: wantsGeometry, handler: handler)
            readers = Array(subscriptions.values)
        }
        guard !isListening else { return }
        isListening = true
        guard Multitouch.available else {
            touchDeviceMissing = true
            return
        }
        startMultitouch()
        installObservers()
    }

    /// Stops delivering to `reader`; the devices are released with the last
    /// reader. Main thread.
    func unsubscribe(_ reader: Reader) {
        let empty = subscriptionLock.withLock { () -> Bool in
            subscriptions[reader] = nil
            readers = Array(subscriptions.values)
            return subscriptions.isEmpty
        }
        if empty, isListening { stop() }
    }

    private func stop() {
        isListening = false
        stopMultitouch()
        removeObservers()
        touchDeviceMissing = false
    }

    // MARK: - Devices

    /// Trackpads come and go across sleep and Bluetooth: drop every contact
    /// registration and rebuild from the current device list.
    private func restartMultitouch() {
        guard isListening else { return }
        stopMultitouch()
        startMultitouch()
    }

    private func startMultitouch() {
        guard deviceList == nil else { return }
        guard let list = Multitouch.deviceList() else {
            touchDeviceMissing = true
            return
        }
        touchDeviceMissing = false
        deviceList = list
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            Multitouch.register(UnsafeMutableRawPointer(mutating: device), trackpadContactCallback)
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

    /// Rebuild on both arrivals and removals, so unplugging the last trackpad
    /// releases its contacts and shows the same warning as starting without one.
    /// If notification registration fails, the current trackpad still works.
    private func installHotplugObserver() {
        guard hotplugPort == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var iterators: [io_iterator_t] = []
        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port,
                notification,
                IOServiceMatching("AppleMultitouchDevice"),
                { context, iterator in
                    guard let context else { return }
                    while case let entry = IOIteratorNext(iterator), entry != 0 {
                        IOObjectRelease(entry)
                    }
                    let service = Unmanaged<TrackpadTouchService>.fromOpaque(context).takeUnretainedValue()
                    service.restartMultitouch()
                },
                context,
                &iterator
            )
            guard result == KERN_SUCCESS else {
                if iterator != 0 { IOObjectRelease(iterator) }
                for registered in iterators { IOObjectRelease(registered) }
                IONotificationPortDestroy(port)
                return
            }
            // Drain the existing devices or the notification never arms.
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                IOObjectRelease(entry)
            }
            iterators.append(iterator)
        }
        hotplugPort = port
        hotplugIterators = iterators
    }

    private func removeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        for iterator in hotplugIterators { IOObjectRelease(iterator) }
        hotplugIterators.removeAll()
        if let hotplugPort {
            IONotificationPortDestroy(hotplugPort)
            self.hotplugPort = nil
        }
    }

    // MARK: - Contact frames (multitouch callback thread)

    fileprivate func deliver(count: Int, touches: UnsafeMutableRawPointer?) {
        let readers = subscriptionLock.withLock { self.readers }
        guard !readers.isEmpty else { return }
        // Touch records are read only for a reader that needs positions, so a
        // middle click on its own costs what it always did per frame.
        let geometry = readers.contains(where: \.wantsGeometry)
            ? Multitouch.touchGeometry(touches: touches, count: count).map {
                TrackpadGestureSupport.Geometry(x: $0.center.x, y: $0.center.y, spread: $0.spread)
            }
            : nil
        let frame = TrackpadTouchFrame(count: count, geometry: geometry)
        for reader in readers { reader.handler(frame) }
    }
}

// MARK: - MultitouchSupport bridge

/// The raw contact callback: (device, touches, count, timestamp, frame).
/// The finger count always feeds the readers; the touch records are read
/// (two floats per touch, range-checked) only for a reader that wants
/// positions — see Multitouch.touchGeometry for the layout contract.
private func trackpadContactCallback(_ device: UnsafeMutableRawPointer?,
                                     _ touches: UnsafeMutableRawPointer?,
                                     _ count: Int32,
                                     _ timestamp: Double,
                                     _ frame: Int32) -> Int32 {
    TrackpadTouchService.shared.deliver(count: Int(count), touches: touches)
    return 0
}

/// dlopen/dlsym bridge to MultitouchSupport. Everything is optional: a macOS
/// build without the framework or its symbols makes `available` false and the
/// readers stay off instead of crashing.
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
    /// frame reports no position and gesture detection stands down for the
    /// touch instead of misfiring.
    private static let touchStride = 96
    private static let touchPositionXOffset = 32
    private static let touchPositionYOffset = 36

    /// Centroid plus spread (mean distance of the touches from the centroid):
    /// the spread is what separates a still tap from a pinch, whose centroid
    /// barely moves.
    static func touchGeometry(touches: UnsafeMutableRawPointer?,
                              count: Int) -> (center: (x: Float, y: Float), spread: Float)? {
        guard let touches, count > 0 else { return nil }
        var sumX: Float = 0
        var sumY: Float = 0
        for index in 0..<count {
            let base = touches.advanced(by: index * touchStride)
            let x = base.loadUnaligned(fromByteOffset: touchPositionXOffset, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: touchPositionYOffset, as: Float.self)
            guard x.isFinite, y.isFinite,
                  x >= -0.2, x <= 1.2, y >= -0.2, y <= 1.2 else { return nil }
            sumX += x
            sumY += y
        }
        let centerX = sumX / Float(count)
        let centerY = sumY / Float(count)
        var spread: Float = 0
        for index in 0..<count {
            let base = touches.advanced(by: index * touchStride)
            let x = base.loadUnaligned(fromByteOffset: touchPositionXOffset, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: touchPositionYOffset, as: Float.self)
            let dx = x - centerX
            let dy = y - centerY
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
