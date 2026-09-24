// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Small adapter for DisplayLink Manager's native brightness integration.
///
/// DisplayLink exposes this channel through DistributedNotificationCenter rather
/// than a public macOS display API. The payload is intentionally kept here
/// behind BrightnessSupport so the rest of the brightness service never has to
/// know about the notification protocol.
final class DisplayLinkControl {
    static let shared = DisplayLinkControl()
    static let displayListDidChangeNotification = Notification.Name(
        "Vorssaint.DisplayLinkDisplayListDidChange")
    static let brightnessDidChangeNotification = Notification.Name(
        "Vorssaint.DisplayLinkBrightnessDidChange")
    static let displayIDUserInfoKey = "displayID"
    static let brightnessUserInfoKey = "brightness"

    private let notificationCenter = DistributedNotificationCenter.default()
    private let stateLock = NSLock()
    private var displaysByID: [CGDirectDisplayID: BrightnessSupport.DisplayLinkDisplay] = [:]
    /// Persistent IDs whose native write failed. They stay out of discovery
    /// until an explicit refresh clears the failure, so a dead route cannot
    /// consume the work queue on every slider update.
    private var unavailablePersistentDisplayIDs = Set<String>()
    private var suppressNextDisplayListNotification = false
    private var displayListObserver: NSObjectProtocol?
    private var brightnessObserver: NSObjectProtocol?
    private var active = false
    private var lifecycleGeneration: UInt64 = 0

    private init() {}

    deinit {
        stop()
    }

    /// Starts the distributed observers only while the brightness feature is
    /// running. This keeps a stopped feature from retaining a live DisplayLink
    /// notification channel or stale display cache.
    func start() {
        stateLock.lock()
        guard !active else {
            stateLock.unlock()
            return
        }
        active = true
        lifecycleGeneration &+= 1
        stateLock.unlock()

        let listObserver = notificationCenter.addObserver(
            forName: Notification.Name("com.displaylink.DisplayListUpdated"),
            object: nil,
            queue: nil) { [weak self] notification in
                self?.handleDisplayListUpdate(notification)
            }
        let brightnessObserver = notificationCenter.addObserver(
            forName: Notification.Name("com.displaylink.BrightnessUpdated"),
            object: nil,
            queue: nil) { [weak self] notification in
                self?.handleBrightnessUpdate(notification)
            }

        stateLock.lock()
        if active {
            displayListObserver = listObserver
            self.brightnessObserver = brightnessObserver
            stateLock.unlock()
        } else {
            stateLock.unlock()
            notificationCenter.removeObserver(listObserver)
            notificationCenter.removeObserver(brightnessObserver)
        }
    }

    func stop() {
        stateLock.lock()
        guard active else {
            stateLock.unlock()
            return
        }
        active = false
        lifecycleGeneration &+= 1
        displaysByID = [:]
        unavailablePersistentDisplayIDs = []
        suppressNextDisplayListNotification = false
        let observers = [displayListObserver, brightnessObserver].compactMap { $0 }
        displayListObserver = nil
        brightnessObserver = nil
        stateLock.unlock()
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    /// Allows the next explicit discovery pass to retry persistent IDs whose
    /// native write previously failed. Failure handling itself does not call
    /// this, so an automatic rebuild cannot immediately resurrect a dead route.
    @discardableResult
    func allowRetry() -> Bool {
        stateLock.lock()
        let hadFailures = !unavailablePersistentDisplayIDs.isEmpty
        unavailablePersistentDisplayIDs = []
        stateLock.unlock()
        return hadFailures
    }

    /// Removes one failed native route from the cache. A later panel, wake, or
    /// topology refresh can explicitly clear the failure and discover it again.
    func markUnavailable(persistentDisplayID: String) {
        stateLock.lock()
        unavailablePersistentDisplayIDs.insert(persistentDisplayID)
        displaysByID = displaysByID.filter {
            $0.value.persistentDisplayID != persistentDisplayID
        }
        stateLock.unlock()
    }

    /// Refreshes the current DisplayLink display list. This is synchronous and
    /// must be called off the main thread: DisplayLink answers through a
    /// distributed notification and the request has a bounded wait.
    func refreshDisplays(timeout: TimeInterval = 1.5) -> [BrightnessSupport.DisplayLinkDisplay] {
        let generation = stateLock.withLock { () -> UInt64? in
            guard active else { return nil }
            suppressNextDisplayListNotification = true
            return lifecycleGeneration
        }
        guard let generation else { return [] }

        let raw = waitForNotification(
            name: "com.displaylink.DisplayListUpdated",
            timeout: timeout,
            filter: { _ in true },
            trigger: {
                self.notificationCenter.postNotificationName(
                    Notification.Name("com.displaylink.GetDisplays"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true)
            })
        let stillActive = stateLock.withLock { () -> Bool in
            guard active, lifecycleGeneration == generation else { return false }
            suppressNextDisplayListNotification = false
            return true
        }
        guard stillActive else { return [] }
        guard let raw,
              let displays = BrightnessSupport.decodeDisplayLinkDisplaysResult(raw) else {
            return cachedDisplays()
        }
        return replaceDisplays(displays)
    }

    private func cachedDisplays() -> [BrightnessSupport.DisplayLinkDisplay] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return displaysByID.values.filter {
            !unavailablePersistentDisplayIDs.contains($0.persistentDisplayID)
        }
    }

    func display(for id: CGDirectDisplayID) -> BrightnessSupport.DisplayLinkDisplay? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard active else { return nil }
        return displaysByID[id]
    }

    func brightness(for id: CGDirectDisplayID,
                    timeout: TimeInterval = 1.0) -> Double? {
        let displays = refreshDisplays(timeout: timeout)
        return displays.first(where: { CGDirectDisplayID($0.cgID) == id })?.brightness
    }

    /// Sends one native DisplayLink brightness write and waits for its
    /// acknowledgement. There is deliberately no alternate brightness route
    /// here: callers must treat a missing acknowledgement as unavailable.
    func setBrightness(for id: CGDirectDisplayID,
                       persistentDisplayID: String,
                       value: Double,
                       timeout: TimeInterval = 1.5) -> Bool {
        guard let knownDisplay = display(for: id),
              knownDisplay.persistentDisplayID == persistentDisplayID,
              knownDisplay.isEnabled,
              let payload = BrightnessSupport.displayLinkSetPayload(
                  persistentDisplayID: persistentDisplayID, brightness: value) else { return false }

        let update = waitForNotification(
            name: "com.displaylink.BrightnessUpdated",
            timeout: timeout,
            filter: {
                BrightnessSupport.acknowledgedDisplayLinkBrightness(
                    $0, persistentDisplayID: persistentDisplayID, requested: value) != nil
            },
            trigger: {
                self.notificationCenter.postNotificationName(
                    Notification.Name("com.displaylink.SetBrightness"),
                    object: payload,
                    userInfo: nil,
                    deliverImmediately: true)
            })
        guard let update,
              let acknowledged = BrightnessSupport.acknowledgedDisplayLinkBrightness(
                  update, persistentDisplayID: persistentDisplayID, requested: value) else {
            return false
        }
        guard cacheBrightness(persistentDisplayID: persistentDisplayID,
                              brightness: acknowledged) != nil else { return false }
        return true
    }

    private func handleDisplayListUpdate(_ notification: Notification) {
        guard controlIsActive(), let raw = Self.objectString(notification),
              let displays = BrightnessSupport.decodeDisplayLinkDisplaysResult(raw) else { return }
        let shouldNotify: Bool = stateLock.withLock {
            let suppress = suppressNextDisplayListNotification
            suppressNextDisplayListNotification = false
            return !suppress
        }
        replaceDisplays(displays)
        if shouldNotify {
            NotificationCenter.default.post(name: Self.displayListDidChangeNotification, object: nil)
        }
    }

    private func handleBrightnessUpdate(_ notification: Notification) {
        guard controlIsActive(), let raw = Self.objectString(notification),
              let update = BrightnessSupport.decodeDisplayLinkBrightnessUpdate(raw),
              update.statusCode == nil || update.statusCode == 0,
              let brightness = update.brightness,
              let displayID = cacheBrightness(persistentDisplayID: update.persistentDisplayID,
                                              brightness: brightness) else { return }
        NotificationCenter.default.post(
            name: Self.brightnessDidChangeNotification,
            object: nil,
            userInfo: [
                Self.displayIDUserInfoKey: NSNumber(value: displayID),
                Self.brightnessUserInfoKey: NSNumber(value: brightness)
            ])
    }

    @discardableResult
    private func cacheBrightness(persistentDisplayID: String,
                                 brightness: Double) -> CGDirectDisplayID? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let entry = displaysByID.first(where: {
            $0.value.persistentDisplayID == persistentDisplayID
        }) else { return nil }
        let updated = BrightnessSupport.DisplayLinkDisplay(
            cgID: entry.value.cgID,
            persistentDisplayID: entry.value.persistentDisplayID,
            name: entry.value.name,
            isEnabled: entry.value.isEnabled,
            brightness: brightness)
        displaysByID[entry.key] = updated
        return entry.key
    }

    @discardableResult
    private func replaceDisplays(_ displays: [BrightnessSupport.DisplayLinkDisplay]) -> [BrightnessSupport.DisplayLinkDisplay] {
        stateLock.lock()
        let available = displays.filter {
            !unavailablePersistentDisplayIDs.contains($0.persistentDisplayID)
        }
        displaysByID = Dictionary(available.map {
            (CGDirectDisplayID($0.cgID), $0)
        }, uniquingKeysWith: { first, _ in first })
        stateLock.unlock()
        return available
    }

    private func waitForNotification(
        name: String,
        timeout: TimeInterval,
        filter: @escaping (String) -> Bool,
        trigger: () -> Void
    ) -> String? {
        let state = NotificationWaitState()
        let observer = notificationCenter.addObserver(
            forName: Notification.Name(name), object: nil, queue: nil) { notification in
                guard let raw = Self.objectString(notification), filter(raw) else { return }
                state.store(raw)
            }
        defer { notificationCenter.removeObserver(observer) }

        trigger()
        let deadline = Date().addingTimeInterval(timeout)
        while state.value() == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return state.value()
    }

    private func controlIsActive() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return active
    }

    private static func objectString(_ notification: Notification) -> String? {
        if let string = notification.object as? String { return string }
        if let string = notification.object as? NSString { return string as String }
        return nil
    }

    private final class NotificationWaitState {
        private let lock = NSLock()
        private var notification: String?

        func store(_ notification: String) {
            lock.lock()
            defer { lock.unlock() }
            if self.notification == nil { self.notification = notification }
        }

        func value() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return notification
        }
    }
}
