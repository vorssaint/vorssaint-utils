// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

final class PeripheralBatterySampler {
    private var cachedDevices: [PeripheralBatteryDevice] = []
    private var cachedAt: TimeInterval = 0
    private let cacheInterval: TimeInterval = 3

    func sample(now: TimeInterval) -> [PeripheralBatteryDevice] {
        if now - cachedAt < cacheInterval {
            return cachedDevices
        }
        let devices = Self.readDevices()
        cachedDevices = devices
        cachedAt = now
        return devices
    }

    private static func readDevices() -> [PeripheralBatteryDevice] {
        let devices = readMatchingServices(named: "AppleDeviceManagementHIDEventService")
            + readMatchingServices(named: "IOHIDDevice")
            + readBluetoothSystemProfilerDevices()
        return uniqueDevices(from: devices)
    }

    private static func readBluetoothSystemProfilerDevices(timeout: TimeInterval = 2) -> [PeripheralBatteryDevice] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return PeripheralBatterySupport.bluetoothDevices(fromSystemProfilerJSON: data)
    }

    private static func readMatchingServices(named className: String) -> [PeripheralBatteryDevice] {
        guard let matching = IOServiceMatching(className) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [PeripheralBatteryDevice] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let properties = properties(for: service),
               let device = device(from: properties, service: service) {
                devices.append(device)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return devices
    }

    private static func properties(for service: io_object_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let unmanaged else {
            return nil
        }
        let properties = unmanaged.takeRetainedValue() as NSDictionary
        return properties as? [String: Any]
    }

    private static func device(from properties: [String: Any],
                               service: io_object_t) -> PeripheralBatteryDevice? {
        let name = PeripheralBatterySupport.name(in: properties)
        let percent = PeripheralBatterySupport.percent(in: properties)
        let builtIn = PeripheralBatterySupport.isBuiltIn(properties)
        guard PeripheralBatterySupport.shouldInclude(name: name, isBuiltIn: builtIn, percent: percent),
              let name,
              let percent else {
            return nil
        }
        let primaryUsagePage = PeripheralBatterySupport.int(from: properties["PrimaryUsagePage"])
            ?? PeripheralBatterySupport.int(from: properties["DeviceUsagePage"])
        let primaryUsage = PeripheralBatterySupport.int(from: properties["PrimaryUsage"])
            ?? PeripheralBatterySupport.int(from: properties["DeviceUsage"])
        let pairs = PeripheralBatterySupport.usagePairs(from: properties["DeviceUsagePairs"])
        let kind = PeripheralBatterySupport.kind(product: name,
                                                 primaryUsagePage: primaryUsagePage,
                                                 primaryUsage: primaryUsage,
                                                 usagePairs: pairs)
        return PeripheralBatteryDevice(id: deviceID(from: properties, service: service, fallbackName: name),
                                       name: name,
                                       percent: percent,
                                       kind: kind)
    }

    private static func deviceID(from properties: [String: Any],
                                 service: io_object_t,
                                 fallbackName: String) -> String {
        for key in ["SerialNumber", "DeviceAddress", "LocationID", "ProductID", "VendorID"] {
            if let value = PeripheralBatterySupport.string(from: properties[key]) {
                return "\(key):\(value)"
            }
            if let value = PeripheralBatterySupport.int(from: properties[key]) {
                return "\(key):\(value)"
            }
        }
        var entryID: UInt64 = 0
        if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS, entryID != 0 {
            return "registry:\(entryID)"
        }
        return "name:\(fallbackName.lowercased())"
    }

    private static func uniqueDevices(from devices: [PeripheralBatteryDevice]) -> [PeripheralBatteryDevice] {
        var byID: [String: PeripheralBatteryDevice] = [:]
        for device in devices {
            byID[device.id] = device
        }

        var seenNames = Set<String>()
        var result: [PeripheralBatteryDevice] = []
        for device in PeripheralBatterySupport.sorted(Array(byID.values)) {
            let key = "\(device.name.lowercased())|\(device.kind.rawValue)"
            guard seenNames.insert(key).inserted else { continue }
            result.append(device)
        }
        return result
    }
}
