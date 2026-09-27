// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum NotchCapsLockTests {
    enum ReviewDefaults { static var current: UserDefaults! }
    enum NotchContentTransition { case replace }
    enum Permissions {
        static var shared = Access()
        struct Access { var accessibility = false }
    }
    enum SuperKeyService {
        static let capsLockDidChange = Notification.Name("SuperKeyCapsLockDidChange")
        static var locked = false
        static func capsLockIsOn() -> Bool { locked }
    }
    final class NSEvent {
        typealias EventTypeMask = AppKit.NSEvent.EventTypeMask
        let modifierFlags: AppKit.NSEvent.ModifierFlags
        init(_ flags: AppKit.NSEvent.ModifierFlags) { modifierFlags = flags }

        static var global: [Int: (NSEvent) -> Void] = [:]
        static var local: [Int: (NSEvent) -> NSEvent?] = [:]
        static var nextID = 0
        static func addGlobalMonitorForEvents(matching: EventTypeMask,
                                              handler: @escaping (NSEvent) -> Void) -> Any? {
            nextID += 1
            global[nextID] = handler
            return nextID
        }
        static func addLocalMonitorForEvents(matching: EventTypeMask,
                                             handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
            nextID += 1
            local[nextID] = handler
            return nextID
        }
        static func removeMonitor(_ token: Any) {
            global[token as! Int] = nil
            local[token as! Int] = nil
        }
    }
    class State {
        var running = true
        var suspended = false
        var capsLockOn = false
        var capsLockMonitors: [Any] = []
        var capsLockObserver: NSObjectProtocol?
        var refreshes = 0
        func refreshPresentation(animated: Bool, transitionContent: NotchContentTransition) {
            refreshes += 1
        }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-caps-lock-monitor"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        ReviewDefaults.current = defaults
        defer {
            ReviewDefaults.current = nil
            defaults.removePersistentDomain(forName: domain)
            NSEvent.global.removeAll()
            NSEvent.local.removeAll()
        }

        let service = Service()
        SuperKeyService.locked = true
        service.syncCapsLockMonitoring()
        suite.expect(!service.capsLockOn && NSEvent.global.isEmpty,
                     "the disabled option starts no keyboard monitor")

        defaults.set(true, forKey: DefaultsKey.notchCapsLock)
        service.syncCapsLockMonitoring()
        suite.expect(!service.capsLockOn && NSEvent.global.isEmpty,
                     "monitoring waits for Accessibility permission")

        Permissions.shared.accessibility = true
        service.syncCapsLockMonitoring()
        suite.expect(service.capsLockOn && NSEvent.global.count == 1 && NSEvent.local.count == 1,
                     "enabling reads the current lock and observes other apps and this app")
        let initialRefreshes = service.refreshes
        NSEvent.global.values.first?(NSEvent([]))
        NSEvent.global.values.first?(NSEvent(.capsLock))
        _ = NSEvent.local.values.first?(NSEvent([]))
        suite.expect(!service.capsLockOn && service.refreshes == initialRefreshes + 3,
                     "global and local transitions update the presentation in both directions")

        SuperKeyService.locked = true
        NotificationCenter.default.post(name: SuperKeyService.capsLockDidChange, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        suite.expect(service.capsLockOn,
                     "a Super Key solo action refreshes the actual system lock state")

        defaults.set(false, forKey: DefaultsKey.notchCapsLock)
        service.syncCapsLockMonitoring()
        suite.expect(!service.capsLockOn && NSEvent.global.isEmpty && NSEvent.local.isEmpty,
                     "disabling clears the state and removes both monitors")
        SuperKeyService.locked = true
        NotificationCenter.default.post(name: SuperKeyService.capsLockDidChange, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        suite.expect(!service.capsLockOn, "the removed Super Key observer cannot revive the status")

        defaults.set(true, forKey: DefaultsKey.notchCapsLock)
        service.syncCapsLockMonitoring()
        service.suspended = true
        service.syncCapsLockMonitoring()
        suite.expect(!service.capsLockOn && NSEvent.global.isEmpty,
                     "sleep and session suspension stop background keyboard work")
        service.suspended = false
        service.syncCapsLockMonitoring()
        suite.expect(service.capsLockOn && NSEvent.global.count == 1,
                     "reactivation samples a lock that was already on")
        SuperKeyService.locked = false
        service.sampleCapsLock()
        suite.expect(!service.capsLockOn, "app activation repairs a missed change")
        service.stopCapsLockMonitoring()
    }
}
