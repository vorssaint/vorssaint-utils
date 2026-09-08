// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BatteryMetricTests {
    static func run(expect: (Bool, String) -> Void) {
        let maxCapacityStringJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"93%"}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityStringJSON) == 93,
               "battery maximum capacity parses percentage strings")
        let maxCapacityNumberJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":93}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityNumberJSON) == 93,
               "battery maximum capacity parses numeric JSON")
        let maxCapacityNestedJSON = Data(#"{"SPPowerDataType":[{"_items":[{"_items":[{"Maximum Capacity":"93%"}]}]}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityNestedJSON) == 93,
               "battery maximum capacity parses nested System Report keys")
        let maxCapacityUnavailableJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"EM_DASH"}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityUnavailableJSON) == nil,
               "battery maximum capacity ignores placeholder values")

        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: false,
                                                   isCharging: false) == 13_320,
               "battery time converts the public time-to-empty minutes")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: -1,
                                                   externalConnected: false,
                                                   isCharging: false) == nil,
               "battery time preserves the system calculating state")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: true,
                                                   isCharging: false) == nil,
               "battery time stays hidden on external power")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: false,
                                                   isCharging: true) == nil,
               "battery time stays hidden while charging")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 65_535,
                                                   externalConnected: false,
                                                   isCharging: false) == nil,
               "battery time ignores the public unavailable sentinel")
        expect(BatteryTimeSupport.formatted(seconds: 13_320) == "3h 42m",
               "battery time formats hours and minutes")
        expect(BatteryTimeSupport.formatted(seconds: 30) == "0h 1m",
               "battery time keeps a positive final minute visible")

        expect(MetricFormat.systemPowerWatts(measured: 3,
                                             batteryWatts: 10,
                                             externalConnected: true) == 3,
               "system power keeps its independent sensor while connected to power")
        expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: 10,
                                             externalConnected: true) == nil,
               "system power does not mirror adapter input while connected to power")
        expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: -4,
                                             externalConnected: false) == 4,
               "battery discharge remains a valid system-power fallback")
        expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: -4,
                                             externalConnected: true) == nil,
               "battery flow alone does not claim total system power while plugged in")

        // MARK: Peripheral battery helpers

        expect(PeripheralBatterySupport.percent(from: "87%") == 87,
               "peripheral battery parses percentage strings")
        expect(PeripheralBatterySupport.percent(from: NSNumber(value: 62.4)) == 62,
               "peripheral battery rounds numeric values")
        expect(PeripheralBatterySupport.percent(from: 140) == nil,
               "peripheral battery ignores invalid percentages")
        let usageMouse = [["DeviceUsagePage": 1, "DeviceUsage": 2]]
        expect(PeripheralBatterySupport.kind(product: "Wireless Device",
                                             primaryUsagePage: nil,
                                             primaryUsage: nil,
                                             usagePairs: usageMouse) == .mouse,
               "peripheral battery infers mouse from HID usage")
        expect(PeripheralBatterySupport.kind(product: "soundcore Space Q45",
                                             minorType: "Headset",
                                             primaryUsagePage: nil,
                                             primaryUsage: nil,
                                             usagePairs: []) == .audio,
               "peripheral battery infers Bluetooth headsets as audio devices")
        let bluetoothJSON = Data("""
        {"SPBluetoothDataType":[{"device_connected":[
          {"soundcore Space Q45":{"device_address":"F4:9D:8A:A2:4C:12","device_batteryLevelMain":"100%","device_minorType":"Headset"}},
          {"AirPods Pro":{"device_address":"E5:04:BE:68:C2:93","device_batteryLevelCase":"88%","device_batteryLevelLeft":"92%","device_batteryLevelRight":"90%"}},
          {"Travel Pointer":{"device_address":"F0:00:00:00:00:01","device_minorType":"Mouse"}}
        ],"device_not_connected":[
          {"Old Mouse":{"device_address":"00:00:00:00:00:00","device_batteryLevelMain":"12%","device_minorType":"Mouse"}}
        ]}]}
        """.utf8)
        let bluetoothDevices = PeripheralBatterySupport.bluetoothDevices(fromSystemProfilerJSON: bluetoothJSON)
        expect(bluetoothDevices.contains(PeripheralBatteryDevice(id: "Bluetooth:F4:9D:8A:A2:4C:12",
                                                                 name: "soundcore Space Q45",
                                                                 percent: 100,
                                                                 kind: .audio)),
               "peripheral battery parses connected Bluetooth headset battery")
        expect(bluetoothDevices.contains(PeripheralBatteryDevice(id: "Bluetooth:E5:04:BE:68:C2:93",
                                                                 name: "AirPods Pro",
                                                                 percent: 88,
                                                                 kind: .audio)),
               "peripheral battery uses the lowest connected AirPods component")
        expect(!bluetoothDevices.contains { $0.name == "Old Mouse" },
               "peripheral battery ignores disconnected Bluetooth devices")
        let bluetoothKinds = PeripheralBatterySupport.bluetoothKindsByName(
            fromSystemProfilerJSON: bluetoothJSON
        )
        expect(bluetoothKinds["travel pointer"] == .mouse,
               "peripheral battery keeps the kind of connected devices without profiler charge data")
        let gattDevices = PeripheralBatterySupport.mergingBluetoothReadings(
            [
                BluetoothBatteryReading(id: "pointer", name: "Travel Pointer", percent: 73),
                BluetoothBatteryReading(id: "pointer", name: "Renamed Pointer", percent: 64),
                BluetoothBatteryReading(id: "duplicate", name: "soundcore space q45", percent: 17),
                BluetoothBatteryReading(id: "invalid", name: "Invalid Accessory", percent: 101),
            ],
            into: bluetoothDevices,
            knownKinds: bluetoothKinds
        )
        expect(gattDevices.contains(PeripheralBatteryDevice(id: "BluetoothGATT:pointer",
                                                            name: "Travel Pointer",
                                                            percent: 73,
                                                            kind: .mouse)),
               "peripheral battery adds a standard Bluetooth battery reading with its known kind")
        expect(gattDevices.first { $0.name.caseInsensitiveCompare("soundcore Space Q45") == .orderedSame }?.percent == 100,
               "peripheral battery keeps richer profiler data instead of a duplicate standard reading")
        expect(!gattDevices.contains { $0.name == "Renamed Pointer" },
               "peripheral battery keeps one row per Bluetooth identity")
        expect(!gattDevices.contains { $0.name == "Invalid Accessory" },
               "peripheral battery rejects invalid standard Bluetooth percentages")
        let keyboard = PeripheralBatteryDevice(id: "keyboard",
                                               name: "Magic Keyboard",
                                               percent: 78,
                                               kind: .keyboard)
        let mouse = PeripheralBatteryDevice(id: "mouse",
                                            name: "Magic Mouse",
                                            percent: 24,
                                            kind: .mouse)
        expect(PeripheralBatterySupport.sorted([keyboard, mouse]).map(\.id) == ["mouse", "keyboard"],
               "peripheral battery devices sort by lowest charge first")
        let menuMetric = PeripheralBatterySupport.menuBarMetric(for: [keyboard, mouse])
        expect(menuMetric?.label == "MOU" && menuMetric?.value == "24%+1",
               "peripheral battery menu metric shows the lowest device and extra count")
        expect(PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 300,
            lastStartedAt: -.greatestFiniteMagnitude,
            lastFinishedAt: -.greatestFiniteMagnitude,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh starts when no cache exists")
        expect(!PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 400,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: true,
            interval: 300
        ), "peripheral Bluetooth refresh is single-flight")
        expect(!PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 500,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh respects its cache interval")
        expect(PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 606,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh runs again only after the interval")
    }
}
