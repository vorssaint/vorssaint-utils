// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit
import IOKit.usb

/// An external USB device plugged into the Mac.
struct ConnectedUSBDevice: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let vendorName: String?
    let vendorId: Int
    let productId: Int
    let locationId: UInt32
}

/// Samples connected external USB peripherals via IOKit on demand.
/// Only external, removable devices are reported (built-in peripherals,
/// internal sensors and root controllers are excluded).
final class USBDeviceSampler {
    func sample() -> [ConnectedUSBDevice] {
        var devices: [ConnectedUSBDevice] = []

        func scan(className: String) {
            guard let matching = IOServiceMatching(className) else { return }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(iterator) }

            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                guard let device = parseDevice(entry) else { continue }
                devices.append(device)
            }
        }

        scan(className: "IOUSBHostDevice")
        if devices.isEmpty {
            scan(className: kIOUSBDeviceClassName)
        }

        return Self.deduplicated(devices).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func deduplicated(_ devices: [ConnectedUSBDevice]) -> [ConnectedUSBDevice] {
        var seenIDs = Set<String>()
        return devices.filter { seenIDs.insert($0.id).inserted }
    }

    private func parseDevice(_ entry: io_registry_entry_t) -> ConnectedUSBDevice? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        var entryID: UInt64 = 0
        if IORegistryEntryGetRegistryEntryID(entry, &entryID) != KERN_SUCCESS {
            entryID = 0
        }

        return Self.parseDevice(properties: dict, registryEntryID: entryID)
    }

    /// Pure parser for testability.
    static func parseDevice(properties dict: [String: Any],
                            registryEntryID: UInt64 = 0) -> ConnectedUSBDevice? {
        func isTruthy(_ val: Any?) -> Bool {
            if let b = val as? Bool { return b }
            if let n = val as? NSNumber { return n.boolValue }
            if let s = val as? String {
                let lower = s.lowercased()
                return lower == "yes" || lower == "1" || lower == "true"
            }
            return false
        }

        // Exclude built-in / non-removable internal hardware
        if isTruthy(dict["Built-In"]) || isTruthy(dict["non-removable"]) {
            return nil
        }

        // Exclude root controllers and root hubs (vendor 0, product 0)
        let vendorId = (dict[kUSBVendorID as String] as? NSNumber)?.intValue
            ?? (dict["idVendor"] as? NSNumber)?.intValue ?? 0
        let productId = (dict[kUSBProductID as String] as? NSNumber)?.intValue
            ?? (dict["idProduct"] as? NSNumber)?.intValue ?? 0
        if vendorId == 0 && productId == 0 {
            return nil
        }

        // A physical USB hub can enumerate once per supported bus generation.
        // It is infrastructure rather than a connected peripheral, so omit it.
        // So is a billboard device (class 17): USB-C adapters and docks with a
        // display output add one that only reports whether the display mode worked.
        let deviceClass = (dict["bDeviceClass"] as? NSNumber)?.intValue
        if deviceClass == 9 || deviceClass == 17 {
            return nil
        }

        let productString = (dict[kUSBProductString as String] as? String)
            ?? (dict["USB Product Name"] as? String)
            ?? (dict["Product Name"] as? String) ?? ""
        // Without a product string the registry name is only the class name, so
        // the name stays empty and the list shows its translated fallback.
        let displayName = productString.trimmingCharacters(in: .whitespacesAndNewlines)

        let vendorString = (dict[kUSBVendorString as String] as? String)
            ?? (dict["USB Vendor Name"] as? String)
            ?? (dict["Vendor Name"] as? String)
        let displayVendor = vendorString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalVendor = (displayVendor?.isEmpty == false) ? displayVendor : nil

        let serial = (dict[kUSBSerialNumberString as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let locationIdNumber = (dict["locationID"] as? NSNumber)?.uint32Value ?? 0

        let uniqueId: String
        if registryEntryID != 0 {
            uniqueId = "\(vendorId)-\(productId)-\(registryEntryID)"
        } else if !serial.isEmpty {
            uniqueId = "\(vendorId)-\(productId)-\(serial)"
        } else if locationIdNumber != 0 {
            uniqueId = "\(vendorId)-\(productId)-loc\(locationIdNumber)"
        } else {
            uniqueId = "\(vendorId)-\(productId)-\(displayName)"
        }

        return ConnectedUSBDevice(
            id: uniqueId,
            name: displayName,
            vendorName: finalVendor,
            vendorId: vendorId,
            productId: productId,
            locationId: locationIdNumber
        )
    }
}
