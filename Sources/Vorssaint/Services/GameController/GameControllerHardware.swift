// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit
import IOKit.hid

/// What the IORegistry knows about an attached game controller that the
/// GameController framework does not say: who made it and over which link.
struct ControllerHardwareEntry: Equatable {
    let registryID: UInt64
    let name: String
    let vendorID: Int?
    let productID: Int?
    let transport: String?
}

enum GameControllerHardware {
    /// HID usages that mark a game controller: Joystick and Game Pad.
    private static let gamePadUsages: Set<Int> = [4, 5]
    private static let genericDesktopPage = 1

    static func attached() -> [ControllerHardwareEntry] {
        guard let matching = IOServiceMatching("IOHIDDevice") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var entries: [ControllerHardwareEntry] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let entry = entry(for: service) { entries.append(entry) }
        }
        return entries
    }

    private static func entry(for service: io_object_t) -> ControllerHardwareEntry? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any],
              PeripheralBatterySupport.int(from: properties["PrimaryUsagePage"]) == genericDesktopPage,
              let usage = PeripheralBatterySupport.int(from: properties["PrimaryUsage"]),
              gamePadUsages.contains(usage),
              let name = PeripheralBatterySupport.string(from: properties["Product"]) else { return nil }
        var registryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { return nil }
        return ControllerHardwareEntry(
            registryID: registryID,
            name: name,
            vendorID: PeripheralBatterySupport.int(from: properties["VendorID"]),
            productID: PeripheralBatterySupport.int(from: properties["ProductID"]),
            transport: PeripheralBatterySupport.string(from: properties["Transport"]))
    }

    /// Asks a DualSense for its firmware information report. Opening the device
    /// does not take it away from the GameController framework.
    static func readDualSenseFirmware(registryID: UInt64) -> DualSenseFirmware? {
        guard let matching = IORegistryEntryIDMatching(registryID) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service),
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        var report = [UInt8](repeating: 0, count: GameControllerSupport.dualSenseFirmwareReportSize)
        var length = report.count
        let status = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature,
                                          CFIndex(GameControllerSupport.dualSenseFirmwareReportID),
                                          &report, &length)
        guard status == kIOReturnSuccess else { return nil }
        return GameControllerSupport.parseDualSenseFirmware(Array(report.prefix(length)))
    }
}
