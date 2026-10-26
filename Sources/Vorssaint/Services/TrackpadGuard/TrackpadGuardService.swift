// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import HIDEventSystem

/// Follows foreground-app and device notifications. The only repeating work is
/// a heartbeat while input is actually being ignored; idle and disabled modes
/// never poll the input devices or inspect other processes' arguments.
final class TrackpadGuardService: ObservableObject {
    static let shared = TrackpadGuardService()
    enum Status: Equatable { case off, chooseApps, waiting, ignoring, unavailable }

    @Published private(set) var apps: [String]
    @Published private(set) var status: Status = .off
    private let defaults: UserDefaults
    private let session = TrackpadGuardSession { TrackpadGuardWatchdog() }
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var manager: IOHIDManager?
    private var deviceRefresh: DispatchWorkItem?
    private var heartbeatTimer: Timer?
    private var mousePresent = false
    private var consoleActive = true
    private var screenLocked = false
    private var awake = true
    private var configuration = ""

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        apps = Defaults.sanitizedBundleIdentifierList(defaults.stringArray(forKey: DefaultsKey.trackpadGuardApps) ?? [])
    }

    func syncWithPreferences() {
        let enabled = featureWanted
        apps = Defaults.sanitizedBundleIdentifierList(defaults.stringArray(forKey: DefaultsKey.trackpadGuardApps) ?? [])
        let next = "\(enabled):\(apps)"
        if next != configuration {
            configuration = next
            if !session.isIgnoring, TrackpadGuardRecovery.restorePending() { session.retry() }
        }
        guard enabled, !apps.isEmpty else {
            stop()
            status = session.failed ? .unavailable : enabled ? .chooseApps : .off
            return
        }
        guard !session.failed else { status = .unavailable; return }
        if workspaceObservers.isEmpty {
            guard TrackpadGuardRecovery.restorePending() else { status = .unavailable; return }
            installObservers()
            guard startDeviceObservation() else {
                stop()
                status = .unavailable
                return
            }
            refreshMousePresence()
        }
        evaluate()
    }

    func add(_ identity: String) {
        let updated = Defaults.sanitizedBundleIdentifierList(apps + [identity])
        guard updated != apps else { return }
        defaults.set(updated, forKey: DefaultsKey.trackpadGuardApps)
        syncWithPreferences()
    }

    func remove(_ identity: String) {
        defaults.set(apps.filter { $0 != identity }, forKey: DefaultsKey.trackpadGuardApps)
        syncWithPreferences()
    }

    @discardableResult
    func stop() -> Bool {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        deviceRefresh?.cancel()
        deviceRefresh = nil
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()
        let distributed = DistributedNotificationCenter.default()
        lockObservers.forEach(distributed.removeObserver)
        lockObservers.removeAll()
        mousePresent = false
        let restored = session.stop()
        let recovered = restored || TrackpadGuardRecovery.restorePending()
        TrackpadGuardInputGate.setActive(false)
        status = session.failed ? .unavailable : .off
        return recovered
    }

    private var featureWanted: Bool {
        AppFeature.trackpadGuard.isAvailable && defaults.bool(forKey: DefaultsKey.trackpadGuardEnabled)
    }

    private func evaluate() {
        guard featureWanted, !apps.isEmpty else {
            stop()
            status = session.failed ? .unavailable : featureWanted ? .chooseApps : .off
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        let identities = MouseAppExceptionSupport.identities(
            bundleID: app?.bundleIdentifier, executablePath: app?.executableURL?.path,
            readsPath: apps.contains(where: MouseAppExceptionSupport.isExecutablePathIdentity))
        let selected = TrackpadGuardSupport.matches(apps: apps, identities: identities,
                                                    executablePath: app?.executableURL?.path)
        let wanted = TrackpadGuardSupport.shouldIgnore(
            enabled: featureWanted, selectedAppInFront: selected, mousePresent: mousePresent,
            sessionActive: consoleActive && !screenLocked, awake: awake)
        session.update(shouldIgnore: wanted)
        TrackpadGuardInputGate.setActive(session.isIgnoring)
        if session.isIgnoring {
            if heartbeatTimer == nil {
                let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.session.heartbeat()
                    self.evaluate()
                }
                heartbeatTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
        }
        status = session.failed ? .unavailable : session.isIgnoring ? .ignoring : .waiting
    }

    private func installObservers() {
        awake = true
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        consoleActive = SessionActivitySupport.isOnConsole(dictionary)
        screenLocked = dictionary?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in self?.evaluate() })
        for (name, active) in [(NSWorkspace.sessionDidResignActiveNotification, false),
                               (NSWorkspace.sessionDidBecomeActiveNotification, true)] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.consoleActive = active
                self?.evaluate()
            })
        }
        for (name, awake) in [(NSWorkspace.willSleepNotification, false), (NSWorkspace.didWakeNotification, true)] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.awake = awake
                if awake { self?.refreshMousePresence() } else { self?.evaluate() }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil,
                queue: .main) { [weak self] _ in
                    self?.screenLocked = locked
                    self?.evaluate()
                })
        }
    }

    private static let deviceChanged: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let service = Unmanaged<TrackpadGuardService>.fromOpaque(context).takeUnretainedValue()
        // A physical-device callback can precede its event-system service.
        service.refreshMousePresence()
        service.deviceRefresh?.cancel()
        let work = DispatchWorkItem { [weak service] in service?.refreshMousePresence() }
        service.deviceRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func startDeviceObservation() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceChanged, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceChanged, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }
        self.manager = manager
        return true
    }

    private func refreshMousePresence() {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        mousePresent = services.contains { service in
            let trackpad = IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Digitizer),
                                                       UInt32(kHIDUsage_Dig_TouchPad)) != 0
            return !trackpad && TrackpadGuardSupport.isExternalMouse(
                conformsToMouse: IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop),
                                                              UInt32(kHIDUsage_GD_Mouse)) != 0,
                builtIn: (IOHIDServiceClientCopyProperty(service, "Built-In" as CFString) as? NSNumber)?.boolValue == true,
                accelerationType: IOHIDServiceClientCopyProperty(service, "HIDPointerAccelerationType" as CFString) as? String,
                transport: IOHIDServiceClientCopyProperty(service, "Transport" as CFString) as? String)
        }
        evaluate()
    }
}
