// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import IOKit
import IOKit.usb

struct USBDeviceItem: Identifiable, Hashable, Codable {
    let id: String // Unique ID: vendorId-productId-serial
    let name: String
    let vendor: String?
    let vendorId: Int
    let productId: Int
    let serialNumber: String?
    let speedMbps: Int?
    let portMaxSpeedMbps: Int?
    let usbVersionBCD: Int?
    let isExternalStorage: Bool
    let bsdName: String?

    var speedLabel: String {
        guard let mbps = speedMbps else { return "Unknown Speed" }
        switch mbps {
        case 1, 2: return "USB 1.0 Low Speed (1.5 Mbps)"
        case 12: return "USB 1.1 Full Speed (12 Mbps)"
        case 480: return "USB 2.0 High Speed (480 Mbps)"
        case 5000: return "USB 3.0 / 3.1 / 3.2 Gen1 (5 Gbps)"
        case 10000: return "USB 3.1 / 3.2 Gen2 (10 Gbps)"
        case 20000: return "USB 3.2 Gen2x2 (20 Gbps)"
        case 40000: return "USB4 / Thunderbolt 3/4 (40 Gbps)"
        case 80000: return "USB4 v2 / Thunderbolt 5 (80 Gbps)"
        default:
            if mbps >= 1000 {
                return String(format: "%.1f Gbps", Double(mbps) / 1000.0)
            }
            return "\(mbps) Mbps"
        }
    }

    var versionLabel: String {
        guard let bcd = usbVersionBCD else { return "USB" }
        let major = (bcd >> 8) & 0xFF
        let minorHigh = (bcd >> 4) & 0x0F
        let minorLow = bcd & 0x0F
        let minor = minorHigh * 10 + minorLow

        switch major {
        case 1:
            if bcd == 0x0100 { return "USB 1.0" }
            if bcd == 0x0110 { return "USB 1.1" }
            return "USB 1.\(minor)"
        case 2:
            return "USB 2.0"
        case 3:
            if bcd >= 0x0320 { return "USB 3.2" }
            if bcd >= 0x0310 { return "USB 3.1" }
            return "USB 3.0"
        case 4:
            if bcd >= 0x0420 { return "USB4 2.0" }
            return "USB4"
        default:
            return minor == 0 ? "USB \(major)" : "USB \(major).\(minor)"
        }
    }
}

final class USBMonitorService: ObservableObject {
    static let shared = USBMonitorService()

    @Published private(set) var devices: [USBDeviceItem] = []
    @Published private(set) var isScanning = false

    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    private init() {
        startMonitoring()
        refresh()
    }

    deinit {
        stopMonitoring()
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let scanned = self.scanUSBDevices()
            DispatchQueue.main.async {
                self.devices = scanned
            }
        }
    }

    private func startMonitoring() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort = notifyPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let callback: IOServiceMatchingCallback = { context, iterator in
            let service = Unmanaged<USBMonitorService>.fromOpaque(context!).takeUnretainedValue()
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                IOObjectRelease(entry)
            }
            service.refresh()
        }

        let refCon = Unmanaged.passUnretained(self).toOpaque()

        let matchingAdded = IOServiceMatching("IOUSBHostDevice")
        IOServiceAddMatchingNotification(
            notifyPort,
            kIOFirstMatchNotification,
            matchingAdded,
            callback,
            refCon,
            &addedIterator
        )
        // Consume iterator to arm notification
        while case let entry = IOIteratorNext(addedIterator), entry != 0 {
            IOObjectRelease(entry)
        }

        let matchingRemoved = IOServiceMatching("IOUSBHostDevice")
        IOServiceAddMatchingNotification(
            notifyPort,
            kIOTerminatedNotification,
            matchingRemoved,
            callback,
            refCon,
            &removedIterator
        )
        // Consume iterator to arm notification
        while case let entry = IOIteratorNext(removedIterator), entry != 0 {
            IOObjectRelease(entry)
        }
    }

    private func stopMonitoring() {
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let notifyPort = notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
    }

    private func scanUSBDevices() -> [USBDeviceItem] {
        var items: [USBDeviceItem] = []
        var seenIds = Set<String>()

        func scanMatching(name: String) {
            guard let matching = IOServiceMatching(name) else { return }
            var iterator: io_iterator_t = 0
            let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard kr == KERN_SUCCESS else { return }
            defer { IOObjectRelease(iterator) }

            while case let entry = IOIteratorNext(iterator), entry != 0 {
                if let dev = parseDevice(from: entry) {
                    if !seenIds.contains(dev.id) {
                        seenIds.insert(dev.id)
                        items.append(dev)
                    }
                }
                IOObjectRelease(entry)
            }
        }

        scanMatching(name: "IOUSBHostDevice")
        scanMatching(name: kIOUSBDeviceClassName)

        return items.sorted {
            ($0.vendor ?? "") < ($1.vendor ?? "") ||
            ($0.vendor == $1.vendor && $0.name < $1.name)
        }
    }

    private func parseDevice(from entry: io_registry_entry_t) -> USBDeviceItem? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        func num(_ key: String) -> NSNumber? { dict[key] as? NSNumber }
        func intValue(_ key: String) -> Int? { num(key)?.intValue }
        func uint32Value(_ key: String) -> UInt32? { num(key)?.uint32Value }
        func doubleValue(_ key: String) -> Double? { num(key)?.doubleValue }
        func stringValue(_ key: String) -> String? { dict[key] as? String }

        let vendorId = intValue(kUSBVendorID as String) ?? 0
        let productId = intValue(kUSBProductID as String) ?? 0
        let productString = stringValue(kUSBProductString as String)
        let vendorString = stringValue(kUSBVendorString as String)
        let serial = stringValue(kUSBSerialNumberString as String)
        let registryName = tryGetIORegistryName(entry) ?? "USB Device"

        let bcdUSBCandidates = ["bcdUSB", "kUSBDevicePropertyUSBReleaseNumber", "USB-bcdUSB"]
        let usbVersionBCD = bcdUSBCandidates.compactMap { intValue($0) }.first

        let linkSpeedBpsCandidates = ["kUSBDevicePropertyLinkSpeed", "LinkSpeed", "DeviceLinkSpeed", "link-speed"]
        let linkSpeedBps: Double? = linkSpeedBpsCandidates.compactMap { doubleValue($0) ?? intValue($0).map(Double.init) }.first
        let speedMbpsFromDevice = linkSpeedBps.map { Int($0 / 1_000_000.0) }

        let speedCode = intValue(kUSBDevicePropertySpeed as String)
        let speedMbpsFromCode: Int? = speedCode.flatMap {
            switch $0 {
            case 0: return 2
            case 1: return 12
            case 2: return 480
            case 3: return 5000
            case 4: return 10000
            default: return nil
            }
        }
        let speedMbps = speedMbpsFromDevice ?? speedMbpsFromCode

        let bsdName = stringValue("BSD Name")
        let isStorage = (bsdName != nil)

        let serialClean = serial?.trimmingCharacters(in: .whitespaces) ?? ""
        let idString = !serialClean.isEmpty ? "\(vendorId)-\(productId)-\(serialClean)" : "\(vendorId)-\(productId)-\(registryName)"

        return USBDeviceItem(
            id: idString,
            name: productString ?? registryName,
            vendor: vendorString,
            vendorId: vendorId,
            productId: productId,
            serialNumber: serial,
            speedMbps: speedMbps,
            portMaxSpeedMbps: nil,
            usbVersionBCD: usbVersionBCD,
            isExternalStorage: isStorage,
            bsdName: bsdName
        )
    }

    private func tryGetIORegistryName(_ entry: io_registry_entry_t) -> String? {
        var cName = [CChar](repeating: 0, count: 128)
        if IORegistryEntryGetName(entry, &cName) == KERN_SUCCESS {
            let name = String(cString: cName)
            if !name.isEmpty && name != "IOUSBHostDevice" && name != kIOUSBDeviceClassName {
                return name
            }
        }
        return nil
    }

    func eject(_ device: USBDeviceItem) {
        guard let bsdName = device.bsdName else { return }
        let volumePath = "/dev/\(bsdName)"
        let url = URL(fileURLWithPath: volumePath)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
            self?.refresh()
        }
    }
}
