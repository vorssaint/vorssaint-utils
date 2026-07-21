// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import IOKit
import IOKit.ps
import IOKit.usb
import SystemConfiguration

enum USBItemCategory: String, Codable {
    case usbDevice
    case ethernet
    case charger
}

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
    var category: USBItemCategory = .usbDevice
    var customSubtitle: String? = nil

    var hexVIDPID: String {
        guard vendorId > 0 || productId > 0 else { return "" }
        return String(format: "%04X:%04X", vendorId, productId)
    }

    var bcdHexLabel: String {
        guard let bcd = usbVersionBCD else { return "" }
        return String(format: "USB Version: %@ (0x%04X)", versionLabel, bcd)
    }

    var serialFormatted: String? {
        guard let sn = serialNumber, !sn.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return "SN: \(sn)"
    }

    var iconName: String {
        switch category {
        case .usbDevice:
            if isExternalStorage { return "externaldrive" }
            let combined = "\(name) \(vendor ?? "")".lowercased()
            if combined.contains("hub") { return "rectangle.grid.2x2" }
            if combined.contains("keyboard") { return "keyboard" }
            if combined.contains("mouse") || combined.contains("trackpad") { return "mouse" }
            if combined.contains("camera") || combined.contains("webcam") { return "web.camera" }
            if combined.contains("audio") || combined.contains("sound") || combined.contains("mic") || combined.contains("headset") { return "headphones" }
            return "cable.connector"
        case .ethernet: return "network"
        case .charger: return "bolt.fill"
        }
    }

    var speedLabel: String {
        if let subtitle = customSubtitle { return subtitle }
        guard let mbps = speedMbps else { return "Unknown Speed" }
        switch mbps {
        case 1, 2: return "1.5 Mbps"
        case 12: return "12 Mbps"
        case 480: return "480 Mbps"
        case 5000: return "5 Gbps"
        case 10000: return "10 Gbps"
        case 20000: return "20 Gbps"
        case 40000: return "40 Gbps"
        case 80000: return "80 Gbps"
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
            guard let context = context else { return }
            let service = Unmanaged<USBMonitorService>.fromOpaque(context).takeUnretainedValue()
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

        let showEthernet = UserDefaults.standard.bool(forKey: DefaultsKey.usbShowEthernet)
        let showPower = UserDefaults.standard.bool(forKey: DefaultsKey.usbShowPowerCable)

        if showPower, let charger = scanPowerSource() {
            items.append(charger)
        }

        if showEthernet {
            items.append(contentsOf: scanEthernetAdapters())
        }

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
            if $0.category != $1.category {
                return $0.category.rawValue < $1.category.rawValue
            }
            return ($0.vendor ?? "") < ($1.vendor ?? "") ||
            ($0.vendor == $1.vendor && $0.name < $1.name)
        }
    }

    private func scanPowerSource() -> USBDeviceItem? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        var pct = 0
        var isACConnected = false

        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String,
               state == (kIOPSACPowerValue as String) {
                isACConnected = true
                pct = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
                break
            }
        }

        guard isACConnected else { return nil }

        let displayName = "Power supply"
        var tag: String = "MagSafe"

        if let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            let watts = adapterDetails["Watts"] as? Int ?? (adapterDetails["Watts"] as? Double).map(Int.init)
            let name = (adapterDetails["Name"] as? String ?? "").lowercased()
            let desc = (adapterDetails["Description"] as? String ?? "").lowercased()
            let combined = "\(name) \(desc)"

            if combined.contains("usb-c") && !combined.contains("magsafe") {
                tag = watts != nil && watts! > 0 ? "USB-C \(watts!)W" : "USB-C"
            } else if let w = watts, w > 0 {
                tag = "MagSafe \(w)W"
            } else {
                tag = "MagSafe"
            }
        } else {
            tag = "MagSafe"
        }

        let rightStatus = "⚡ \(pct)%"

        return USBDeviceItem(
            id: "power-charger-adapter",
            name: displayName,
            vendor: tag,
            vendorId: 0,
            productId: 0,
            serialNumber: nil,
            speedMbps: nil,
            portMaxSpeedMbps: nil,
            usbVersionBCD: nil,
            isExternalStorage: false,
            bsdName: nil,
            category: .charger,
            customSubtitle: rightStatus
        )
    }

    private func scanEthernetAdapters() -> [USBDeviceItem] {
        var items: [USBDeviceItem] = []
        guard let store = SCDynamicStoreCreate(nil, "VorssaintEthernet" as CFString, nil, nil),
              let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return items
        }
        for iface in interfaces {
            let type = SCNetworkInterfaceGetInterfaceType(iface) as String?
            if type == (kSCNetworkInterfaceTypeEthernet as String) {
                guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
                let key = "State:/Network/Interface/\(bsd)/Link" as CFString
                let isLinkActive = (SCDynamicStoreCopyValue(store, key) as? [String: Any])?["Active"] as? Bool ?? false
                if isLinkActive {
                    let displayName = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? ?? "Ethernet Adapter (\(bsd))"
                    items.append(USBDeviceItem(
                        id: "ethernet-\(bsd)",
                        name: displayName,
                        vendor: "LAN Cable",
                        vendorId: 0,
                        productId: 0,
                        serialNumber: nil,
                        speedMbps: 1000,
                        portMaxSpeedMbps: nil,
                        usbVersionBCD: nil,
                        isExternalStorage: false,
                        bsdName: bsd,
                        category: .ethernet,
                        customSubtitle: "Active Link (\(bsd))"
                    ))
                }
            }
        }
        return items
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
