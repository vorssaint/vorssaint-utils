// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import HIDEventSystem

/// Applies macOS's per-device linear pointer mode and a pointer speed to
/// ordinary mouse devices. Trackpads are deliberately excluded.
final class MouseAccelerationService {
    static let shared = MouseAccelerationService()

    private let defaults = UserDefaults.standard
    private var client: IOHIDEventSystemClient?
    private var hidManager: IOHIDManager?
    private var reapplySchedule = MouseAccelerationReapplySchedule()
    private var reapplyWork: DispatchWorkItem?
    private var recoveryGuard: MouseAccelerationGuard.Handle?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var sessionIsActive = false
    private var systemIsAwake = true

    private init() {}

    static func recoverPendingAtLaunch() {
        guard MouseAccelerationRecovery.hasPendingEntries() else { return }
        _ = shared.pauseAndRestore()
    }

    func syncWithPreferences() {
        guard featureWanted else {
            stop()
            return
        }
        installLifecycleObservers()
        startIfAllowed()
    }

    /// Restores every value owned by this feature before its process goes away.
    @discardableResult
    func stop() -> Bool {
        removeLifecycleObservers()
        return pauseAndRestore()
    }

    private var featureWanted: Bool {
        AppFeature.mouseAcceleration.isAvailable && (accelerationWanted || speedWanted)
    }

    private var accelerationWanted: Bool {
        defaults.bool(forKey: DefaultsKey.mouseAccelerationDisabled)
    }

    private var speed: Int {
        MouseAccelerationSupport.sanitizedSpeed(defaults.integer(forKey: DefaultsKey.mousePointerSpeed))
    }

    private var speedWanted: Bool { speed != MouseAccelerationSupport.defaultSpeed }

    private func startIfAllowed() {
        guard featureWanted, sessionIsActive, systemIsAwake else {
            pauseAndRestore()
            return
        }
        start()
    }

    private func start() {
        if client != nil {
            applyMouseSettings()
            return
        }
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        _ = MouseAccelerationRecovery.restorePending(using: client)
        self.client = client
        startDeviceObservation()
        applyMouseSettings()
        scheduleDeviceReapplication()
    }

    @discardableResult
    private func pauseAndRestore() -> Bool {
        stopDeviceObservation()
        if let client {
            _ = MouseAccelerationRecovery.restorePending(using: client)
        } else if MouseAccelerationRecovery.hasPendingEntries() {
            _ = MouseAccelerationRecovery.restorePending()
        }
        client = nil
        if let recoveryGuard {
            _ = recoveryGuard.stop()
            self.recoveryGuard = nil
        }
        let hasPendingRecovery = MouseAccelerationRecovery.hasPendingEntries()
        if hasPendingRecovery {
            recoveryGuard = MouseAccelerationGuard.start()
        }
        return !hasPendingRecovery
    }

    private func applyMouseSettings() {
        guard let client,
              let services = MouseAccelerationRecovery.services(using: client),
              var journal = MouseAccelerationRecovery.journalForMutation() else {
            return
        }
        for service in services where MouseAccelerationRecovery.isMouse(service) {
            guard let id = MouseAccelerationRecovery.registryID(of: service),
                  let identity = MouseAccelerationRecovery.identity(of: service) else { continue }
            // Without linear mode, turning acceleration off takes over the
            // value speed would scale, so acceleration wins on those mice.
            let speedApplies = speedWanted
                && (!accelerationWanted || MouseAccelerationRecovery.supportsLinearMode(service))
            let wanted: [(MouseAccelerationSlot, Bool)] = [(.acceleration, accelerationWanted),
                                                           (.speed, speedApplies)]
            // Put back what is no longer wanted first, so a setting captured
            // next always saves the mouse's own value, never the other's.
            for (slot, isWanted) in wanted where !isWanted {
                if let saved = journal.entry(registryID: id, identity: identity, slot: slot),
                   MouseAccelerationRecovery.restore(saved, on: service) {
                    _ = MouseAccelerationRecovery.remove(registryID: id, slot: slot, from: &journal)
                }
            }
            for (slot, isWanted) in wanted where isWanted {
                guard apply(slot, to: service, id: id, identity: identity, journal: &journal) else {
                    pauseAndRestore()
                    return
                }
            }
        }

        if journal.entries.isEmpty, let recoveryGuard {
            _ = recoveryGuard.stop()
            self.recoveryGuard = nil
        }
    }

    /// Saves the mouse's own value for `slot` once, then writes the target.
    /// Returns false only when recovery can no longer be guaranteed.
    private func apply(_ slot: MouseAccelerationSlot,
                       to service: IOHIDServiceClient,
                       id: UInt64,
                       identity: MouseAccelerationDeviceIdentity,
                       journal: inout MouseAccelerationRecoveryJournal) -> Bool {
        let entry: MouseAccelerationRecoveryEntry
        if let existing = journal.entry(registryID: id, identity: identity, slot: slot) {
            entry = existing
        } else {
            let unresolvedIdentity = identity.canMatchAcrossRegistryIDs
                && journal.entries.contains { $0.slot == slot && $0.identity.matches(identity) }
            guard !journal.entries.contains(where: { $0.registryID == id && $0.slot == slot }),
                  !unresolvedIdentity,
                  ensureRecoveryGuard() else { return true }
            let captured: MouseAccelerationRecoveryEntry
            switch slot {
            case .acceleration:
                guard let value = MouseAccelerationRecovery.captureEntry(for: service,
                                                                         registryID: id,
                                                                         identity: identity) else { return true }
                captured = value
            case .speed:
                guard let value = MouseAccelerationRecovery.captureSpeedEntry(for: service,
                                                                              registryID: id,
                                                                              identity: identity) else { return true }
                captured = value
            }
            guard MouseAccelerationRecovery.record(captured, in: &journal) else { return true }
            entry = captured
        }

        guard ensureRecoveryGuard() else { return false }
        let applied: Bool
        switch slot {
        case .acceleration:
            applied = MouseAccelerationRecovery.applyTarget(for: entry, to: service)
        case .speed:
            applied = MouseAccelerationRecovery.apply(
                MouseAccelerationSupport.speedTarget(original: entry.original, speed: speed),
                for: entry, to: service)
        }
        if !applied, MouseAccelerationRecovery.restore(entry, on: service) {
            _ = MouseAccelerationRecovery.remove(registryID: id, slot: slot, from: &journal)
        }
        return true
    }

    private func ensureRecoveryGuard() -> Bool {
        if recoveryGuard != nil { return true }
        recoveryGuard = MouseAccelerationGuard.start()
        return recoveryGuard != nil
    }

    // MARK: - Device lifecycle

    private static let deviceChanged: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let service = Unmanaged<MouseAccelerationService>.fromOpaque(context).takeUnretainedValue()
        service.scheduleDeviceReapplication()
    }

    private func scheduleDeviceReapplication() {
        guard client != nil, featureWanted, sessionIsActive, systemIsAwake else { return }
        reapplyWork?.cancel()
        scheduleDeviceReapplication(for: reapplySchedule.restart())
    }

    private func scheduleDeviceReapplication(for token: UUID) {
        guard let delay = reapplySchedule.nextDelay(for: token) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.reapplySchedule.isCurrent(token) else { return }
            self.reapplyWork = nil
            guard self.client != nil, self.featureWanted,
                  self.sessionIsActive, self.systemIsAwake else { return }
            // Physical-device callbacks can precede the event-system service, and
            // its initial settings can arrive later still. Read a fresh service list.
            let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
            self.client = client
            _ = MouseAccelerationRecovery.restorePending(using: client,
                                                          preservingConnectedEntries: true)
            self.applyMouseSettings()
            self.scheduleDeviceReapplication(for: token)
        }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startDeviceObservation() {
        guard hidManager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceChanged, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceChanged, context)
        IOHIDManagerScheduleWithRunLoop(manager,
                                        CFRunLoopGetMain(),
                                        CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager,
                                              CFRunLoopGetMain(),
                                              CFRunLoopMode.commonModes.rawValue)
            return
        }
        hidManager = manager
    }

    private func stopDeviceObservation() {
        reapplyWork?.cancel()
        reapplyWork = nil
        reapplySchedule.cancel()
        guard let manager = hidManager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager,
                                          CFRunLoopGetMain(),
                                          CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
    }

    // MARK: - Session and sleep lifecycle

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        lifecycleObservers = [
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.sessionIsActive = false
                self?.pauseAndRestore()
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.sessionIsActive = true
                self?.startIfAllowed()
            },
            center.addObserver(forName: NSWorkspace.willSleepNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.systemIsAwake = false
                self?.pauseAndRestore()
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.systemIsAwake = true
                self?.startIfAllowed()
            },
        ]
        sessionIsActive = Self.currentSessionIsActive()
    }

    private func removeLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in lifecycleObservers { center.removeObserver(observer) }
        lifecycleObservers = []
    }

    private static func currentSessionIsActive() -> Bool {
        SessionActivitySupport.isOnConsole(
            CGSessionCopyCurrentDictionary() as? [String: Any])
    }
}
