// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOBluetooth
import IOKit

/// Either switches the radio off or closes only selected paired-device
/// connections on sleep. Selection mode never writes controller power.
///
/// Unlike the plain sleep-and-wake toggle, the restore is honest: the state
/// found before sleep is remembered, so Bluetooth the user had already turned
/// off is never switched back on for them. The memory is a preference rather
/// than a variable, so a Mac shut down while asleep still gets its Bluetooth
/// back on the next launch instead of staying dark.
///
/// Nothing runs while the feature is off: no observers, no polling, no cost.
final class BluetoothSleepService: ObservableObject {
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

    /// Inject the Bluetooth boundary and notification center for behavior
    /// tests. Production uses the same handler with the native environment.
    struct Environment {
        let isSupported: Bool
        let featureAvailable: () -> Bool
        let isPoweredOn: () -> Bool
        let setPowered: (Bool) -> Void
        let pairedDevices: () -> [BluetoothSleepSupport.Device]
        let disconnect: (String) -> Bool

        static var live: Environment {
            Environment(isSupported: BluetoothSleepService.isSupported,
                featureAvailable: { AppFeature.bluetoothSleep.isAvailable },
                isPoweredOn: { BluetoothSleepService.isPoweredOn },
                setPowered: { BluetoothSleepService.setPowered($0) },
                pairedDevices: { BluetoothSleepService.pairedDevices() },
                disconnect: { address in
                    guard let device = IOBluetoothDevice(addressString: address) else { return false }
                    guard device.isConnected() else { return true }
                    return device.closeConnection() == kIOReturnSuccess
                })
        }
    }

    private var observers: [NSObjectProtocol] = []
    private let defaults: UserDefaults
    private let environment: Environment
    private let notificationCenter: NotificationCenter
    @Published private(set) var failedDisconnectCount = 0
    private let disconnectQueue = DispatchQueue(label: "com.vorssaint.bluetooth-sleep.disconnect", qos: .userInitiated)
    private var disconnectOperation: BluetoothSleepDisconnectOperation?
    private var disconnectGeneration = UUID()

    init(defaults: UserDefaults = .standard, environment: Environment = .live,
         notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.defaults = defaults
        self.environment = environment
        self.notificationCenter = notificationCenter
    }

    func syncWithPreferences() {
        guard environment.isSupported else { return }
        cancelDeviceDisconnects()
        // A restore still owed here means an earlier run switched Bluetooth
        // off and never saw the wake, because the Mac was shut down (or the
        // app quit) while it slept. The debt is paid before anything else,
        // and paid even when the feature has since been switched off, so
        // nothing Vorssaint took away is ever kept.
        restoreIfOwed()
        if environment.featureAvailable(), defaults.bool(forKey: DefaultsKey.bluetoothSleepEnabled) {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard observers.isEmpty else { return }
        let center = notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.macWillSleep()
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.cancelDeviceDisconnects(invalidateReport: false)
                self?.restoreIfOwed()
            },
        ]
    }

    func stop() {
        cancelDeviceDisconnects()
        guard !observers.isEmpty else { return }
        let center = notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    private func macWillSleep() {
        // Recheck at the entry point: removing the feature or switching it off
        // must not let an already delivered notification disconnect anything.
        guard environment.featureAvailable(),
              defaults.bool(forKey: DefaultsKey.bluetoothSleepEnabled) else { return }
        if BluetoothSleepSupport.Mode(storageValue: defaults.string(forKey: DefaultsKey.bluetoothSleepMode))
            == .selectedDevices {
            disconnectSelectedDevices(defaults: defaults)
            return
        }
        let plan = BluetoothSleepSupport.sleepPlan(
            isPoweredOn: environment.isPoweredOn(),
            restoresOnWake: defaults.bool(forKey: DefaultsKey.bluetoothSleepRestoreOnWake))
        defaults.set(plan.owesRestore, forKey: DefaultsKey.bluetoothSleepRestorePending)
        if plan.powersOff { environment.setPowered(false) }
    }

    /// A fresh paired-device snapshot, read only when Settings asks or the Mac
    /// is going to sleep. Selecting a row never opens or closes a connection.
    static func pairedDevices() -> [BluetoothSleepSupport.Device] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap { device in
            guard let rawAddress = device.addressString,
                  let address = BluetoothSleepSupport.normalizedAddress(rawAddress) else { return nil }
            let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return BluetoothSleepSupport.Device(id: address, name: name.isEmpty ? address : name,
                                                isConnected: device.isConnected())
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    private func cancelDeviceDisconnects(invalidateReport: Bool = true) {
        disconnectOperation?.cancel()
        disconnectOperation = nil
        if invalidateReport { disconnectGeneration = UUID() }
    }

    private func disconnectSelectedDevices(defaults: UserDefaults) {
        cancelDeviceDisconnects()
        failedDisconnectCount = 0
        let targets = BluetoothSleepSupport.disconnectTargets(
            selected: defaults.stringArray(forKey: DefaultsKey.bluetoothSleepDevices) ?? [],
            devices: environment.pairedDevices())
        guard !targets.isEmpty else { return }
        // NSWorkspace's sleep observer permits a short delay before sleep.
        // Keep synchronous Bluetooth calls off the main queue and wait at most
        // two seconds; queued work expires even if sleep suspends the process.
        let operation = BluetoothSleepDisconnectOperation(deadline: Date().addingTimeInterval(2))
        disconnectOperation = operation
        let generation = disconnectGeneration
        let group = DispatchGroup()
        let disconnect = environment.disconnect
        group.enter()
        disconnectQueue.async { [weak self] in
            let failures = operation.run(targets: targets, disconnect: disconnect)
            group.leave()
            DispatchQueue.main.async {
                guard let self, self.disconnectGeneration == generation else { return }
                self.failedDisconnectCount = failures.count
            }
        }
        _ = group.wait(timeout: .now() + 2)
    }

    private func restoreIfOwed() {
        let restores = BluetoothSleepSupport.restores(
            owesRestore: defaults.bool(forKey: DefaultsKey.bluetoothSleepRestorePending),
            isPoweredOn: environment.isPoweredOn())
        // The debt is settled either way: Bluetooth the user switched on
        // themselves cancels it instead of waiting for the next sleep.
        defaults.set(false, forKey: DefaultsKey.bluetoothSleepRestorePending)
        if restores { environment.setPowered(true) }
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
