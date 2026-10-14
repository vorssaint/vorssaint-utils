// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum BluetoothSleepTests {
    private static let headphones = "10-20-30-40-50-60"
    private static let keyboard = "11-21-31-41-51-61"
    private static let mouse = "12-22-32-42-52-62"

    private final class Fixture {
        var available = true
        var powered = true
        var devices = [
            BluetoothSleepSupport.Device(id: headphones, name: "Headphones", isConnected: true),
            BluetoothSleepSupport.Device(id: keyboard, name: "Keyboard", isConnected: true),
            BluetoothSleepSupport.Device(id: mouse, name: "Mouse", isConnected: true),
        ]
        var fail: Set<String> = []
        var powerWrites: [Bool] = []
        var powerReads = 0
        var snapshots = 0
        let lock = NSLock()
        private var closed: [String] = []
        var disconnections: [String] { lock.withLock { closed } }
        let center = NotificationCenter()

        func environment() -> BluetoothSleepService.Environment {
            .init(isSupported: true, featureAvailable: { self.available },
                isPoweredOn: { self.powerReads += 1; return self.powered },
                setPowered: { self.powered = $0; self.powerWrites.append($0) },
                pairedDevices: { self.snapshots += 1; return self.devices },
                disconnect: { address in
                    self.lock.withLock { self.closed.append(address) }
                    return !self.fail.contains(address)
                })
        }

        func sleep() { center.post(name: NSWorkspace.willSleepNotification, object: nil) }
        func wake() { center.post(name: NSWorkspace.didWakeNotification, object: nil) }
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.bluetooth-sleep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        func configure(mode: String? = nil, enabled: Bool = true, selected: [String] = [], restore: Bool = true) {
            defaults.removePersistentDomain(forName: name)
            defaults.set(enabled, forKey: DefaultsKey.bluetoothSleepEnabled)
            defaults.set(mode, forKey: DefaultsKey.bluetoothSleepMode)
            defaults.set(selected, forKey: DefaultsKey.bluetoothSleepDevices)
            defaults.set(restore, forKey: DefaultsKey.bluetoothSleepRestoreOnWake)
        }
        func service(_ fixture: Fixture) -> BluetoothSleepService {
            let service = BluetoothSleepService(defaults: defaults, environment: fixture.environment(),
                                                 notificationCenter: fixture.center)
            service.syncWithPreferences()
            return service
        }

        // The actual service and actual notification handlers run here. Only
        // the native Bluetooth boundary is replaced, so no physical connection
        // is changed and no system sleep is requested by this suite.
        configure()
        let legacy = Fixture()
        let legacyService = service(legacy)
        legacy.sleep()
        suite.expect(legacy.powerWrites == [false] && legacy.disconnections.isEmpty,
                     "existing users retain whole-controller power-off without device calls")
        suite.expect(defaults.bool(forKey: DefaultsKey.bluetoothSleepRestorePending),
                     "the legacy mode remembers that it owes controller power back")
        legacy.wake()
        suite.expect(legacy.powerWrites == [false, true]
            && !defaults.bool(forKey: DefaultsKey.bluetoothSleepRestorePending),
            "the legacy wake restores only power taken by the app")
        legacyService.stop()

        configure(restore: false)
        let noRestore = Fixture()
        let noRestoreService = service(noRestore)
        noRestore.sleep(); noRestore.wake()
        suite.expect(noRestore.powerWrites == [false], "legacy restore-off remains honored")
        noRestoreService.stop()

        configure()
        let alreadyOff = Fixture()
        alreadyOff.powered = false
        let offService = service(alreadyOff)
        alreadyOff.sleep(); alreadyOff.wake()
        suite.expect(alreadyOff.powerWrites.isEmpty, "Bluetooth already off is never turned on by a sleep cycle")
        offService.stop()

        configure(mode: "selectedDevices", selected: [headphones])
        let selective = Fixture()
        let selectiveService = service(selective)
        selective.sleep(); selective.wake()
        suite.expect(selective.disconnections == [headphones],
                     "selecting headphones leaves the connected keyboard and mouse untouched")
        suite.expect(selective.powerWrites.isEmpty && selective.powerReads == 0,
                     "selected-device sleep and wake never read or write controller power")
        suite.expect(!defaults.bool(forKey: DefaultsKey.bluetoothSleepRestorePending),
                     "selected-device mode creates no controller restore debt")
        suite.expect(selective.snapshots == 1,
                     "paired devices are read at sleep, without launch/wake polling")
        // Repeat to verify fresh connection state and a new per-sleep operation.
        selective.devices[0] = .init(id: headphones, name: "Renamed headphones", isConnected: true)
        selective.sleep(); selective.wake()
        suite.expect(selective.disconnections == [headphones, headphones],
                     "device renaming and repeated sleep/wake do not lose address-based selection")
        selectiveService.stop()

        configure(mode: "selectedDevices")
        let empty = Fixture()
        let emptyService = service(empty)
        empty.sleep(); empty.wake()
        suite.expect(empty.disconnections.isEmpty && empty.powerWrites.isEmpty,
                     "an empty selected-device list never falls back to disconnecting all or powering off")
        emptyService.stop()

        configure(mode: "selectedDevices", selected: [headphones, "FF-FF-FF-FF-FF-FF", "invalid"])
        let stale = Fixture()
        stale.devices[0] = .init(id: headphones, name: "Headphones", isConnected: false)
        let staleService = service(stale)
        stale.sleep()
        suite.expect(stale.disconnections.isEmpty && stale.powerWrites.isEmpty,
                     "disconnected, unpaired and malformed selections never target other connected devices")
        staleService.stop()

        configure(mode: "selectedDevices", selected: ["10:20:30:40:50:60", headphones, " 10-20-30-40-50-60 "])
        let duplicate = Fixture()
        duplicate.devices[1] = .init(id: keyboard, name: "Headphones", isConnected: true)
        let duplicateService = service(duplicate)
        duplicate.sleep()
        suite.expect(duplicate.disconnections == [headphones],
                     "duplicate spellings collapse and another device with the same name is never disconnected")
        duplicateService.stop()

        configure(mode: "selectedDevices", enabled: false, selected: [headphones])
        let disabled = Fixture()
        let disabledService = service(disabled)
        disabled.sleep(); disabled.wake()
        suite.expect(disabled.disconnections.isEmpty && disabled.snapshots == 0 && disabled.powerWrites.isEmpty,
                     "a disabled feature registers no device work")
        disabledService.stop()

        configure(mode: "selectedDevices", selected: [headphones])
        let removed = Fixture()
        let removedService = service(removed)
        removed.available = false
        removed.sleep()
        suite.expect(removed.disconnections.isEmpty && removed.snapshots == 0,
                     "the sleep entry point rechecks feature removal even before observers resync")
        removedService.syncWithPreferences()
        removed.sleep()
        suite.expect(removed.powerWrites.isEmpty, "removing the feature stops its sleep observers")
        removedService.stop()

        configure(mode: "selectedDevices", selected: [headphones])
        let failure = Fixture()
        failure.fail = [headphones]
        let failureService = service(failure)
        failure.sleep(); failure.wake()
        let reportDeadline = Date().addingTimeInterval(0.5)
        while failureService.failedDisconnectCount == 0, Date() < reportDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        suite.expect(failureService.failedDisconnectCount == 1 && failure.powerWrites.isEmpty,
                     "a native disconnect failure is reported after wake without switching the radio off")
        failureService.stop()

        configure(mode: "selectedDevices", selected: [headphones])
        let switched = Fixture()
        let switchedService = service(switched)
        defaults.set("powerOff", forKey: DefaultsKey.bluetoothSleepMode)
        switchedService.syncWithPreferences()
        switched.sleep()
        suite.expect(switched.powerWrites == [false] && switched.disconnections.isEmpty,
                     "switching modes uses the newly chosen action")
        switched.wake(); switchedService.stop()

        operationChecks(suite)
        suite.expect(BluetoothSleepSupport.Mode(storageValue: nil) == .powerOff
            && BluetoothSleepSupport.Mode(storageValue: "unknown") == .powerOff,
            "absent and invalid mode storage preserves the legacy upgrade behavior")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.bluetoothSleepDevices] as? [String] == [],
                     "no peripheral is selected automatically")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.bluetoothSleepMode)
            && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.bluetoothSleepDevices),
            "backups carry the mode but keep device pairing addresses on their own Mac")
        suite.expect(!SettingsBackupSupport.keysToClear(whenImporting: [:]).contains(DefaultsKey.bluetoothSleepDevices),
                     "importing a backup preserves the receiving Mac's chosen devices")
    }

    private static func operationChecks(_ suite: TestSuite) {
        let time = Date(timeIntervalSince1970: 100)
        var called: [String] = []
        let cancelled = BluetoothSleepDisconnectOperation(deadline: time.addingTimeInterval(2), now: { time })
        cancelled.cancel()
        let cancelledFailures = cancelled.run(targets: [headphones, keyboard]) { called.append($0); return true }
        suite.expect(called.isEmpty && cancelledFailures.count == 2,
                     "work cancelled by wake, disable or a mode change starts no disconnect calls")
        let interrupted = BluetoothSleepDisconnectOperation(deadline: time.addingTimeInterval(2), now: { time })
        let remaining = interrupted.run(targets: [headphones, keyboard]) { address in
            called.append(address)
            interrupted.cancel()
            return true
        }
        suite.expect(called == [headphones] && remaining == [keyboard],
                     "cancelling during a native call prevents the next queued device from disconnecting")
        var clock = time
        let expires = BluetoothSleepDisconnectOperation(deadline: time.addingTimeInterval(2), now: { clock })
        called = []
        let expired = expires.run(targets: [headphones, keyboard]) { address in
            called.append(address)
            clock = time.addingTimeInterval(3)
            return true
        }
        suite.expect(called == [headphones] && expired == [keyboard],
                     "expired sleep work reports unattempted devices and never begins a later disconnect")
        called = []
        let beforeWake = BluetoothSleepDisconnectOperation(deadline: time.addingTimeInterval(2), now: { time })
        suite.expect(beforeWake.run(targets: [headphones, keyboard]) { address in
            called.append(address); return address != headphones
        } == [headphones] && called == [headphones, keyboard],
            "one native failure does not prevent another explicitly selected device from disconnecting")
        for invalid in ["", "AA-BB-CC", "AA-BB-CC-DD-EE-GG", "A-BB-CC-DD-EE-FF", "AA--BB-CC-DD-EE-FF"] {
            suite.expect(BluetoothSleepSupport.normalizedAddress(invalid) == nil,
                         "malformed addresses are rejected")
        }
        suite.expect(BluetoothSleepSupport.normalizedAddress(" aa:bb:cc:dd:ee:ff ") == "AA-BB-CC-DD-EE-FF",
                     "address spelling is normalized without using the device name")
    }
}
