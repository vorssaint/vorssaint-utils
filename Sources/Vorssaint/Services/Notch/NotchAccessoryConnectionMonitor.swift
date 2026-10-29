// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOBluetooth

/// Only values cross into presentation; reading an IOBluetoothDevice there
/// would put a synchronous Bluetooth request back on the main thread.
enum NotchAccessoryConnectionEvent: Equatable {
    case connected(name: String, majorClass: UInt32, minorClass: UInt32)
    case disconnected(name: String?)
}

protocol NotchAccessoryConnectionSource: AnyObject {
    func start(isCancelled: @escaping () -> Bool,
               onEvent: @escaping (NotchAccessoryConnectionEvent) -> Void)
    func stop()
}

/// Lifecycle belongs to the main thread. Native work and cleanup share one
/// run loop, even across disable/enable, so a stuck request cannot create a
/// growing set of Bluetooth workers. Neither start nor stop waits for it.
final class NotchAccessoryConnectionMonitor {
    typealias Perform = (@escaping () -> Void) -> Void

    private final class Session {
        private let lock = NSLock()
        private var cancelled = false
        // Accessed only by the Bluetooth worker.
        var source: NotchAccessoryConnectionSource?

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private let perform: Perform
    private let deliver: Perform
    private let makeSource: (@escaping Perform) -> NotchAccessoryConnectionSource
    private var session: Session?

    init(perform: @escaping Perform = { NotchAccessoryBluetoothRunLoop.shared.perform($0) },
         deliver: @escaping Perform = { DispatchQueue.main.async(execute: $0) },
         makeSource: @escaping (@escaping Perform) -> NotchAccessoryConnectionSource = {
             NotchAccessoryBluetoothSource(perform: $0)
         }) {
        self.perform = perform
        self.deliver = deliver
        self.makeSource = makeSource
    }

    deinit { stop() }

    /// Publishes on the main queue only while this activation is still alive.
    func start(onEvent: @escaping (NotchAccessoryConnectionEvent) -> Void) {
        stop()
        let session = Session()
        self.session = session
        let makeSource = makeSource
        let perform = perform
        let deliver = deliver
        perform { [session] in
            guard !session.isCancelled else { return }
            let source = makeSource(perform)
            session.source = source
            source.start(isCancelled: { [weak session] in session?.isCancelled ?? true }) { [weak session] event in
                guard let session, !session.isCancelled else { return }
                deliver { [weak session] in
                    guard let session, !session.isCancelled else { return }
                    onEvent(event)
                }
            }
        }
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        // Invalidate immediately, including while start is inside the system
        // framework. Unregistration can wait for that call to return.
        session.cancel()
        perform {
            session.source?.stop()
            session.source = nil
        }
    }
}

/// IOBluetooth does not promise a callback queue. Its selectors only enqueue
/// work, without querying devices or synchronously calling into the UI.
private final class NotchAccessoryBluetoothSource: NSObject, NotchAccessoryConnectionSource {
    private let perform: NotchAccessoryConnectionMonitor.Perform
    private var isCancelled: () -> Bool = { true }
    private var onEvent: ((NotchAccessoryConnectionEvent) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var connectionState = NotchAccessoryConnectionState()

    init(perform: @escaping NotchAccessoryConnectionMonitor.Perform) {
        self.perform = perform
        super.init()
    }

    func start(isCancelled: @escaping () -> Bool,
               onEvent: @escaping (NotchAccessoryConnectionEvent) -> Void) {
        self.isCancelled = isCancelled
        self.onEvent = onEvent
        guard !isCancelled() else { return }
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var baseline = Set<String>()
        for device in devices {
            guard !isCancelled() else { return }
            let connected = device.isConnected()
            guard !isCancelled() else { return }
            if connected, let id = device.addressString {
                baseline.insert(id)
                observeDisconnect(device, id: id)
            }
        }
        connectionState.establishBaseline(baseline)
        guard !isCancelled() else { return }
        let notification = IOBluetoothDevice.register(forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:)))
        // A framework call can run a nested run loop and finish after stop.
        if isCancelled() { notification?.unregister() }
        else { connectNotification = notification }
    }

    func stop() {
        isCancelled = { true }
        onEvent = nil
        connectNotification?.unregister(); connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        connectionState = NotchAccessoryConnectionState()
    }

    private func observeDisconnect(_ device: IOBluetoothDevice, id: String) {
        guard !isCancelled(), disconnectNotifications[id] == nil else { return }
        let notification = device.register(forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:)))
        if isCancelled() { notification?.unregister() }
        else { disconnectNotifications[id] = notification }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        perform { [weak self] in
            guard let self, !self.isCancelled(), self.connectNotification === notification,
                  device.isConnected() else { return }
            guard !self.isCancelled() else { return }
            let major = UInt32(device.deviceClassMajor)
            guard !self.isCancelled(), NotchAccessorySupport.announcesConnection(majorClass: major),
                  let id = device.addressString, self.connectionState.connected(id) else { return }
            self.observeDisconnect(device, id: id)
            guard !self.isCancelled(),
                  let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            guard !self.isCancelled() else { return }
            let minor = UInt32(device.deviceClassMinor)
            guard !self.isCancelled() else { return }
            self.onEvent?(.connected(name: name, majorClass: major, minorClass: minor))
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        perform { [weak self] in
            guard let self, !self.isCancelled(), !device.isConnected() else { return }
            guard !self.isCancelled(), let id = device.addressString,
                  self.disconnectNotifications[id] === notification else { return }
            self.connectionState.disconnected(id)
            let name = device.name
            self.disconnectNotifications.removeValue(forKey: id)?.unregister()
            guard !self.isCancelled() else { return }
            self.onEvent?(.disconnected(name: name))
        }
    }
}

/// Starts lazily and asynchronously. A serial dispatch queue alone is not a
/// stable thread/run loop for IOBluetooth's notification registrations.
private final class NotchAccessoryBluetoothRunLoop {
    static let shared = NotchAccessoryBluetoothRunLoop()
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var pending: [() -> Void] = []
    private var started = false
    private var draining = false

    func perform(_ work: @escaping () -> Void) {
        let action = lock.withLock { () -> (launch: Bool, runLoop: CFRunLoop?) in
            pending.append(work)
            if let runLoop, !draining {
                draining = true
                return (false, runLoop)
            }
            guard !started else { return (false, nil) }
            started = true
            return (true, nil)
        }
        if let runLoop = action.runLoop { scheduleDrain(on: runLoop) }
        if action.launch {
            let thread = Thread { self.run() }
            thread.name = "Vorssaint Bluetooth Accessories"
            thread.qualityOfService = .utility
            thread.start()
        }
    }

    // Keep the drain reserved until the active native call returns: a nested
    // framework run loop must not start another source or unregister the
    // source whose start is still on the stack.
    private func scheduleDrain(on runLoop: CFRunLoop) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { self.drain() }
        CFRunLoopWakeUp(runLoop)
    }

    private func drain() {
        while let work = lock.withLock({ () -> (() -> Void)? in
            guard !pending.isEmpty else { draining = false; return nil }
            return pending.removeFirst()
        }) {
            autoreleasepool(invoking: work)
        }
    }

    private func run() {
        let runLoop = CFRunLoopGetCurrent()!
        // No polling: the port only keeps the run loop alive between events.
        RunLoop.current.add(NSMachPort(), forMode: .common)
        lock.withLock {
            self.runLoop = runLoop
            draining = true
        }
        scheduleDrain(on: runLoop)
        while true {
            autoreleasepool {
                _ = CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, true)
            }
        }
    }
}
