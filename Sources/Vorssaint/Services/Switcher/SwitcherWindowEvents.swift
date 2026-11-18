// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// WindowServer can deliver on a worker queue while the feature stops on main.
final class SwitcherNotificationLifetime {
    private let lock = NSLock()
    private var active: UUID?
    var current: UUID? { lock.withLock { active } }
    func start() { lock.withLock { active = UUID() } }
    func stop() { lock.withLock { active = nil } }
}

struct SwitcherWindowWatch {
    private var accepted: Set<CGWindowID>?

    mutating func update(to ids: Set<CGWindowID>, request: (Set<CGWindowID>) -> Bool) -> Bool {
        if accepted == ids { return true }
        guard request(ids) else {
            accepted = nil
            return false
        }
        accepted = ids
        return true
    }
}

/// Bridges private WindowServer notifications to switcher events on main.
final class SwitcherWindowEvents {
    static let shared = SwitcherWindowEvents()

    enum Event {
        case changed(CGWindowID)
        case destroyed(CGWindowID)
        case focused(CGWindowID)
        case membershipChanged
        case spacesChanged
    }

    // Private API signatures and subscription semantics:
    // https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/SkyLight.framework.swift#L197-L229
    private typealias NotificationCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, UInt32) -> Void
    private typealias RegisterNotification = @convention(c) (UInt32, NotificationCallback, UInt32, UnsafeMutableRawPointer?) -> CGError
    private typealias RequestWindowNotifications = @convention(c) (UInt32, UnsafeMutablePointer<CGWindowID>?, Int32) -> CGError

    // Event IDs: https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/windowserver/WsEventRouting.swift#L8-L21
    private enum Notification: UInt32, CaseIterable {
        case windowCreated = 811
        case windowDestroyed = 804
        case windowMoved = 806
        case windowResized = 807
        case windowOrderedIn = 815
        case windowOrderedOut = 816
        case windowFocused = 808
        case windowAddedToSpace = 1325
        case windowRemovedFromSpace = 1326
        case spaceCurrentChanged = 1329
        case activeSpaceChanged = 1401
    }
    private var handler: ((Event) -> Void)?
    private var registered = Set<Notification>()
    private let lifetime = SwitcherNotificationLifetime()
    private var watchState = SwitcherWindowWatch()

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    private let connection: UInt32 = {
        typealias Function = @convention(c) () -> UInt32
        guard let address = SwitcherWindowEvents.symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(address, to: Function.self)()
    }()

    private let registerNotification: RegisterNotification? = {
        guard let address = SwitcherWindowEvents.symbol("SLSRegisterConnectionNotifyProc") else { return nil }
        return unsafeBitCast(address, to: RegisterNotification.self)
    }()

    private let requestWindowNotifications: RequestWindowNotifications? = {
        guard let address = SwitcherWindowEvents.symbol("SLSRequestNotificationsForWindows") else { return nil }
        return unsafeBitCast(address, to: RequestWindowNotifications.self)
    }()

    // WindowServer calls off-main; copy the window ID before its payload expires.
    private static let notificationCallback: NotificationCallback = { event, data, length, _, _ in
        let owner = SwitcherWindowEvents.shared
        guard let generation = owner.lifetime.current, let notification = Notification(rawValue: event) else { return }
        var windowID: CGWindowID = 0
        if let data, length >= MemoryLayout<CGWindowID>.size {
            memcpy(&windowID, data, MemoryLayout<CGWindowID>.size)
        }
        let decoded: Event
        switch notification {
        case .windowDestroyed: decoded = .destroyed(windowID)
        case .windowFocused: decoded = .focused(windowID)
        case .windowAddedToSpace, .windowRemovedFromSpace: decoded = .membershipChanged
        case .spaceCurrentChanged, .activeSpaceChanged: decoded = .spacesChanged
        case .windowCreated, .windowMoved, .windowResized, .windowOrderedIn, .windowOrderedOut:
            decoded = .changed(windowID)
        }
        DispatchQueue.main.async {
            guard owner.lifetime.current == generation else { return }
            owner.handler?(decoded)
        }
    }

    static func matchesWindowNumber(_ number: Int, windowID: CGWindowID) -> Bool {
        number > 0 && CGWindowID(exactly: number) == windowID
    }

    func start(handler: @escaping (Event) -> Void) -> Bool {
        self.handler = handler
        lifetime.start()
        guard connection != 0, let registerNotification, requestWindowNotifications != nil else { return false }
        for notification in Notification.allCases where !registered.contains(notification) {
            if registerNotification(connection, Self.notificationCallback, notification.rawValue, nil) == .success {
                registered.insert(notification)
            }
        }
        return registered.count == Notification.allCases.count
    }

    @discardableResult
    func watch(_ windowIDs: Set<CGWindowID>) -> Bool {
        guard let requestWindowNotifications else { return false }
        let connection = self.connection
        return watchState.update(to: windowIDs) { ids in
            var windows = Array(ids)
            return windows.withUnsafeMutableBufferPointer { buffer in
                requestWindowNotifications(connection, buffer.baseAddress, Int32(buffer.count)) == .success
            }
        }
    }

    func stop() {
        lifetime.stop()
        watch([])
        handler = nil
    }
}
