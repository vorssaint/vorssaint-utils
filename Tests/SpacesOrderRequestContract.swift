// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// Production request and publication bodies are extracted by generate_sources.
/// This scheduler can pause after generation reservation but before enqueue.
/// Persistence is separate from the cache, without touching system preferences.
enum SpacesOrderRequestContract {
    static var errors = 0

    struct Log {
        func error(_ message: String) { errors += 1 }
        func info(_ message: String) {}
    }

    enum DispatchQueue {
        static let main = Queue()
    }

    final class Queue {
        var pending: [() -> Void] = []
        var beforeAsync: (() -> Void)?
        var beforeSync: (() -> Void)?

        func async(execute work: @escaping () -> Void) {
            let interrupt = beforeAsync
            beforeAsync = nil
            interrupt?()
            pending.append(work)
        }

        func sync<T>(execute work: () -> T) -> T {
            let interrupt = beforeSync
            beforeSync = nil
            interrupt?()
            return work()
        }

        func flushOne() {
            guard !pending.isEmpty else { return }
            pending.removeFirst()()
        }

        func flush() {
            while !pending.isEmpty { flushOne() }
        }
    }

    final class UserDefaults {
        var values: [String: Any]
        var durable: [String: Any]
        var synchronizeSucceeds = true
        var beforeSet: ((String) -> Void)?
        var onSet: ((String) -> Void)?

        init(enabled: Bool, marker: String?) {
            values = [DefaultsKey.spacesOrderEnabled: enabled]
            values[DefaultsKey.spacesOrderRestore] = marker
            durable = values
        }

        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func string(forKey key: String) -> String? { values[key] as? String }
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) {
            beforeSet?(key)
            values[key] = value
            onSet?(key)
        }
        func removeObject(forKey key: String) {
            values.removeValue(forKey: key)
        }
        @discardableResult
        func synchronize() -> Bool {
            guard synchronizeSucceeds else { return false }
            durable = values
            return true
        }
    }

    final class Dock {
        var value: SpacesRearrangeSetting
        var reads = 0
        var writes: [SpacesRearrangeSetting] = []
        var restarts = 0
        init(_ value: SpacesRearrangeSetting) { self.value = value }
    }

    class Fixture {
        static let log = Log()
        let defaults: UserDefaults
        let dock: Dock
        let system: SpacesOrderSystem
        let queue = Queue()
        let requestLock = NSRecursiveLock()
        var requestGeneration: UInt64 = 0
        var pendingLetGoOwner: UInt64?
        var markerGeneration: UInt64 = 0
        var watches: [Bool] = []

        init(enabled: Bool = true, marker: String? = nil, value: SpacesRearrangeSetting = .on) {
            defaults = UserDefaults(enabled: enabled, marker: marker)
            let dock = Dock(value)
            self.dock = dock
            system = SpacesOrderSystem(
                read: {
                    dock.reads += 1
                    return dock.value
                },
                write: { value in
                    dock.value = value.map { $0 ? .on : .off } ?? .absent
                    dock.writes.append(dock.value)
                    return true
                },
                restartDock: {
                    dock.restarts += 1
                    return true
                },
                dockPID: { 500 + Int32(dock.restarts) }
            )
        }

        var isWanted: Bool { defaults.bool(forKey: DefaultsKey.spacesOrderEnabled) }
        func onQueue<T>(_ work: () -> T) -> T { queue.sync(execute: work) }
        func watch(_ enabled: Bool) { watches.append(enabled) }
    }

    static func run(_ suite: TestSuite) {
        let enabled = DefaultsKey.spacesOrderEnabled
        let marker = DefaultsKey.spacesOrderRestore
        let on = SpacesOrderSupport.restoreOn
        DispatchQueue.main.pending = []
        errors = 0

        // sync has its old generation, but has not joined the worker queue.
        let lateSync = Host(marker: on, value: .off)
        var removed = false
        lateSync.queue.beforeAsync = { removed = lateSync.restoreForRemoval() }
        lateSync.syncWithPreferences()
        let writesAfterRemoval = lateSync.dock.writes
        let readsAfterRemoval = lateSync.dock.reads
        lateSync.queue.flush()
        suite.expect(removed && lateSync.dock.value == .on
                     && lateSync.defaults.string(forKey: marker) == nil
                     && lateSync.dock.writes == writesAfterRemoval
                     && lateSync.dock.reads == readsAfterRemoval
                     && lateSync.watches.isEmpty && errors == 0,
                     "a sync enqueued after a newer removal stays silent and cannot recreate its hold")
        lateSync.syncWithPreferences()
        lateSync.queue.flush()
        suite.expect(lateSync.dock.value == .off && lateSync.defaults.string(forKey: marker) == on,
                     "a new current sync still establishes a legitimate hold")

        let oldRestore = Host()
        oldRestore.queue.beforeSync = { _ = oldRestore.reconcile(wanted: true) }
        suite.expect(!oldRestore.restoreForRemoval() && oldRestore.dock.value == .off
                     && oldRestore.defaults.string(forKey: marker) == on,
                     "a removal superseded before admission returns false and leaves the new hold alone")
        let oldReconcile = Host()
        oldReconcile.queue.beforeSync = { _ = oldReconcile.restoreForRemoval() }
        suite.expect(!oldReconcile.reconcile(wanted: true) && oldReconcile.dock.writes.isEmpty
                     && oldReconcile.dock.reads == 0 && oldReconcile.defaults.string(forKey: marker) == nil,
                     "a reconcile superseded before admission returns false without system work")

        let publication = Host(marker: on)
        var markerKeptBeforeOff = false
        publication.defaults.beforeSet = { key in
            guard key == enabled else { return }
            publication.defaults.beforeSet = nil
            publication.queue.flush()
            markerKeptBeforeOff = publication.defaults.durable[marker] as? String == on
                && publication.defaults.durable[enabled] as? Bool == true
        }
        var requestedDuringPublication = false
        publication.defaults.onSet = { key in
            if key == enabled, !requestedDuringPublication {
                requestedDuringPublication = true
                publication.syncWithPreferences()
            }
        }
        publication.defaults.synchronizeSucceeds = false
        suite.expect(publication.letGoIfRearrangingReturned(),
                     "an external choice queues toggle publication")
        DispatchQueue.main.flushOne()
        publication.queue.flush()
        suite.expect(markerKeptBeforeOff && requestedDuringPublication
                     && publication.defaults.string(forKey: marker) == on
                     && publication.defaults.durable[marker] as? String == on
                     && publication.defaults.durable[enabled] as? Bool == true
                     && publication.dock.writes.isEmpty,
                     "failed off persistence and a reentrant sync cannot discard recovery")

        // The cached toggle is already false. The retry must still confirm its
        // durable off before it grants cleanup, including after a crash here.
        publication.defaults.synchronizeSucceeds = true
        DispatchQueue.main.flushOne()
        suite.expect(publication.defaults.durable[enabled] as? Bool == false
                     && publication.defaults.durable[marker] as? String == on,
                     "off is durable before cleanup can remove its marker")
        let relaunched = Host(enabled: publication.defaults.durable[enabled] as? Bool ?? true,
                              marker: publication.defaults.durable[marker] as? String)
        suite.expect(relaunched.reconcile(wanted: relaunched.isWanted)
                     && relaunched.dock.value == .on && relaunched.dock.writes.isEmpty,
                     "a crash after off persistence never reapplies fixed order at the next launch")
        publication.queue.flush()
        suite.expect(!publication.defaults.bool(forKey: enabled)
                     && publication.defaults.string(forKey: marker) == nil
                     && publication.dock.writes.isEmpty,
                     "a successful retry finishes cleanup without changing the external choice")

        let reenabled = Host(marker: on)
        reenabled.defaults.synchronizeSucceeds = false
        _ = reenabled.letGoIfRearrangingReturned()
        DispatchQueue.main.flushOne()
        reenabled.defaults.set(true, forKey: enabled)
        reenabled.defaults.synchronizeSucceeds = true
        reenabled.syncWithPreferences()
        reenabled.queue.flush()
        DispatchQueue.main.flush()
        suite.expect(reenabled.defaults.bool(forKey: enabled)
                     && reenabled.defaults.durable[enabled] as? Bool == true
                     && reenabled.defaults.string(forKey: marker) == on
                     && reenabled.dock.value == .off,
                     "reenabling after failed off persistence starts a new hold without reversing the new choice")
        suite.expect(reenabled.restoreForRemoval() && reenabled.dock.value == .on
                     && reenabled.defaults.string(forKey: marker) == nil,
                     "the new hold still restores the setting it found")

        DispatchQueue.main.pending = []
    }
}
