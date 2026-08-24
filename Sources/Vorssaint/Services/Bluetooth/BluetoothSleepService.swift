// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit

/// Switches Bluetooth off while the Mac sleeps, so a closed laptop in a bag
/// stops grabbing the headphones the user is listening to elsewhere.
///
/// Unlike the plain sleep-and-wake toggle, the restore is honest: the state
/// found before sleep is remembered, so Bluetooth the user had already turned
/// off is never switched back on for them. The memory is a preference rather
/// than a variable, so a Mac shut down while asleep still gets its Bluetooth
/// back on the next launch instead of staying dark.
///
/// Nothing runs while the feature is off: no observers, no polling, no cost.
final class BluetoothSleepService {
    static let shared = BluetoothSleepService()

    /// A Bluetooth controller is soldered in or it is not; the answer cannot
    /// change while the Mac is running, so resolve it once.
    static let isSupported: Bool = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOBluetoothHCIController"))
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }()

    private var observers: [NSObjectProtocol] = []

    private init() {}

    func syncWithPreferences() {
        guard Self.isSupported else { return }
        // A restore still owed here means an earlier run switched Bluetooth
        // off and never saw the wake, because the Mac was shut down (or the
        // app quit) while it slept. The debt is paid before anything else,
        // and paid even when the feature has since been switched off, so
        // nothing Vorssaint took away is ever kept.
        restoreIfOwed()
        if AppFeature.bluetoothSleep.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.bluetoothSleepEnabled) {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.macWillSleep()
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.restoreIfOwed()
            },
        ]
    }

    func stop() {
        guard !observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    private func macWillSleep() {
        let defaults = UserDefaults.standard
        let plan = BluetoothSleepSupport.sleepPlan(
            isPoweredOn: Self.isPoweredOn,
            restoresOnWake: defaults.bool(forKey: DefaultsKey.bluetoothSleepRestoreOnWake))
        defaults.set(plan.owesRestore, forKey: DefaultsKey.bluetoothSleepRestorePending)
        if plan.powersOff { Self.setPowered(false) }
    }

    private func restoreIfOwed() {
        let defaults = UserDefaults.standard
        let restores = BluetoothSleepSupport.restores(
            owesRestore: defaults.bool(forKey: DefaultsKey.bluetoothSleepRestorePending),
            isPoweredOn: Self.isPoweredOn)
        // The debt is settled either way: Bluetooth the user switched on
        // themselves cancels it instead of waiting for the next sleep.
        defaults.set(false, forKey: DefaultsKey.bluetoothSleepRestorePending)
        if restores { Self.setPowered(true) }
    }

    // MARK: Controller power

    private typealias PowerGet = @convention(c) () -> Int32
    private typealias PowerSet = @convention(c) (Int32) -> Void

    /// The Bluetooth controller's power switch, the same pair the menu bar
    /// item uses. Resolved once and guarded: without it the feature simply
    /// does nothing rather than pretending to work.
    private static let controllerPower: (get: PowerGet, set: PowerSet)? = {
        let path = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
        guard let handle = dlopen(path, RTLD_LAZY),
              let getSymbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState"),
              let setSymbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { return nil }
        return (unsafeBitCast(getSymbol, to: PowerGet.self),
                unsafeBitCast(setSymbol, to: PowerSet.self))
    }()

    private static var isPoweredOn: Bool {
        guard let controllerPower else { return false }
        return controllerPower.get() != 0
    }

    private static func setPowered(_ on: Bool) {
        controllerPower?.set(on ? 1 : 0)
    }
}
