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
    var parentId: String? = nil
    let name: String
    let vendor: String?
    let vendorId: Int
    let productId: Int
    let serialNumber: String?
    let speedMbps: Int?
    let portMaxSpeedMbps: Int?
    let usbVersionBCD: Int?
    let isExternalStorage: Bool
    var isHub: Bool = false
    let bsdName: String?
    var category: USBItemCategory = .usbDevice
    var customSubtitle: String? = nil
    var volumeCapacity: String? = nil

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

    var cleanVendor: String? {
        guard let v = vendor?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty, v != name else { return nil }
        var cleaned = v
        cleaned = cleaned.replacingOccurrences(of: ", Inc.", with: "")
        cleaned = cleaned.replacingOccurrences(of: " Inc.", with: "")
        cleaned = cleaned.replacingOccurrences(of: " Inc", with: "")
        cleaned = cleaned.replacingOccurrences(of: " Corp.", with: "")
        cleaned = cleaned.replacingOccurrences(of: " Corporation", with: "")
        cleaned = cleaned.replacingOccurrences(of: " Ltd.", with: "")
        cleaned = cleaned.replacingOccurrences(of: " Co., Ltd.", with: "")
        cleaned = cleaned.replacingOccurrences(of: " Technology", with: "")
        return cleaned.isEmpty ? nil : cleaned
    }

    var iconName: String {
        switch category {
        case .charger: return "bolt.fill"
        case .ethernet: return "network"
        case .usbDevice:
            let combined = "\(name) \(vendor ?? "")".lowercased()
            if combined.contains("ax88") || combined.contains("rtl81") || combined.contains("ethernet") || combined.contains("lan adapter") || combined.contains("asix") {
                return "network"
            }
            if combined.contains("wlan") || combined.contains("wifi") || combined.contains("802.11") || combined.contains("wireless") {
                return "wifi"
            }
            if combined.contains("logitech") || combined.contains("insta360") || combined.contains("opal") || combined.contains("razer") || combined.contains("facecam") || combined.contains("c920") || combined.contains("brio") || combined.contains("camera") || combined.contains("webcam") || combined.contains("isight") || combined.contains("uvc") {
                return "web.camera"
            }
            if combined.contains("display") || combined.contains("monitor") || combined.contains("hdmi") || combined.contains("billboard") || combined.contains("displaylink") || combined.contains("dp ") || combined.contains("video") {
                return "display"
            }
            if combined.contains("card reader") || combined.contains("sd reader") || combined.contains("sdcard") || combined.contains("sd/mmc") || combined.contains("rts5") || combined.contains("gl32") {
                return "sdcard"
            }
            if combined.contains("wacom") || combined.contains("tablet") || combined.contains("cintiq") || combined.contains("intuos") {
                return "applepencil"
            }
            if combined.contains("capture") || combined.contains("elgato") || combined.contains("avermedia") || combined.contains("cam link") {
                return "video.fill"
            }
            if combined.contains("keyboard") || combined.contains("keypad") { return "keyboard" }
            if combined.contains("mouse") || combined.contains("trackpad") || combined.contains("pointing") { return "mouse" }
            if combined.contains("audio") || combined.contains("sound") || combined.contains("mic") || combined.contains("headset") || combined.contains("dac") || combined.contains("focusrite") || combined.contains("scarlett") {
                return "headphones"
            }
            if combined.contains("hub") || combined.contains("dock") || combined.contains("genesys") || combined.contains("vli") || combined.contains("rts54") || isHub {
                return "rectangle.grid.2x2"
            }
            if isExternalStorage { return "externaldrive" }
            return "cable.connector"
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
        case 40000: return "⚡ TB4 40 Gbps"
        case 80000: return "⚡ TB5 80 Gbps"
        default:
            if mbps >= 1000 {
                return String(format: "%.1f Gbps", Double(mbps) / 1000.0)
            }
            return "\(mbps) Mbps"
        }
    }

    var versionLabel: String {
        if let cap = volumeCapacity { return cap }
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

        // Observe Volume Mount/Unmount for SD Cards and External Media
        NotificationCenter.default.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
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

        // Scan Mounted Removable External Volumes (SD Cards, Flash Drives, External Media)
        let externalVolumes = scanMountedExternalVolumes()
        for vol in externalVolumes {
            if !seenIds.contains(vol.id) {
                let isAlreadyListed = items.contains(where: { dev in
                    if let bsd = dev.bsdName, !bsd.isEmpty, vol.id.contains(bsd) { return true }
                    if dev.isExternalStorage && dev.name.lowercased() == vol.name.lowercased() { return true }
                    return false
                })
                if !isAlreadyListed {
                    seenIds.insert(vol.id)
                    items.append(vol)
                }
            }
        }

        return items.sorted {
            if $0.category != $1.category {
                return $0.category.rawValue < $1.category.rawValue
            }
            return ($0.vendor ?? "") < ($1.vendor ?? "") ||
            ($0.vendor == $1.vendor && $0.name < $1.name)
        }
    }

    private func scanMountedExternalVolumes() -> [USBDeviceItem] {
        var items: [USBDeviceItem] = []
        guard let volumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeLocalizedNameKey, .volumeNameKey, .volumeTotalCapacityKey],
            options: [.skipHiddenVolumes]
        ) else {
            return items
        }

        for url in volumeURLs {
            guard let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeLocalizedNameKey, .volumeNameKey, .volumeTotalCapacityKey]) else { continue }
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false

            if url.path == "/" || url.path == "/System/Volumes/Data" || url.path.hasPrefix("/System/") { continue }

            if isRemovable || isEjectable {
                let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
                let capacityBytes = values.volumeTotalCapacity ?? 0
                let capacityString = capacityBytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(capacityBytes), countStyle: .file) : ""

                let volId = "vol-\(url.path)"
                let lowerName = name.lowercased()
                let isSDCard = lowerName.contains("sd") || lowerName.contains("card") || lowerName.contains("untitld") || lowerName.contains("dcim")

                items.append(USBDeviceItem(
                    id: volId,
                    parentId: nil,
                    name: name,
                    vendor: nil,
                    vendorId: 0,
                    productId: 0,
                    serialNumber: nil,
                    speedMbps: 5000,
                    portMaxSpeedMbps: nil,
                    usbVersionBCD: nil,
                    isExternalStorage: true,
                    isHub: false,
                    bsdName: url.lastPathComponent,
                    category: .usbDevice,
                    customSubtitle: nil,
                    volumeCapacity: capacityString.isEmpty ? nil : capacityString
                ))
            }
        }
        return items
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

        let deviceName = productString ?? registryName
        let isHubDevice = deviceName.lowercased().contains("hub") || registryName.lowercased().contains("hub") || intValue("bDeviceClass") == 9

        var parentId: String? = nil
        var parentEntry: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parentEntry) == KERN_SUCCESS, parentEntry != 0 {
            defer { IOObjectRelease(parentEntry) }
            var pProps: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(parentEntry, &pProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let pDict = pProps?.takeRetainedValue() as? [String: Any] {
                let pVid = (pDict["idVendor"] as? NSNumber)?.intValue ?? 0
                let pPid = (pDict["idProduct"] as? NSNumber)?.intValue ?? 0
                let pSerial = (pDict["USB Serial Number"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let pName = pDict["USB Product Name"] as? String ?? (pDict["kUSBProductString"] as? String ?? "")
                let pRegName = tryGetIORegistryName(parentEntry) ?? ""
                if pVid > 0 || pPid > 0 {
                    let pCleanSerial = pSerial
                    let pIdentifier = !pCleanSerial.isEmpty ? "\(pVid)-\(pPid)-\(pCleanSerial)" : "\(pVid)-\(pPid)-\(pName.isEmpty ? pRegName : pName)"
                    if pIdentifier != idString {
                        parentId = pIdentifier
                    }
                }
            }
        }

        return USBDeviceItem(
            id: idString,
            parentId: parentId,
            name: deviceName,
            vendor: vendorString,
            vendorId: vendorId,
            productId: productId,
            serialNumber: serial,
            speedMbps: speedMbps,
            portMaxSpeedMbps: nil,
            usbVersionBCD: usbVersionBCD,
            isExternalStorage: isStorage,
            isHub: isHubDevice,
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
        let url: URL
        if device.id.hasPrefix("vol-") {
            let path = device.id.replacingOccurrences(of: "vol-", with: "")
            url = URL(fileURLWithPath: path)
        } else if let bsdName = device.bsdName {
            url = URL(fileURLWithPath: "/dev/\(bsdName)")
        } else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
            self?.refresh()
        }
    }
}
