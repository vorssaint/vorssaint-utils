// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import IOKit
import IOKit.ps
import IOKit.usb

/// Counts the external USB/Thunderbolt devices, external disks, and connected power adapters.
///
/// The monitor is **lazy**: it allocates no IOKit ports, no run loop sources and
/// no workspace observers while the menu bar metric is off. Call `setActive(true)`
/// when the metric is enabled; call `setActive(false)` to tear everything down.
final class ConnectedDevicesMonitor: ObservableObject {
    static let shared = ConnectedDevicesMonitor()

    /// The current number of plugged-in external devices. Published on the main
    /// queue so the status item can observe it directly.
    @Published private(set) var count = 0

    // MARK: - IOKit state (nil while inactive)

    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var addedLegacyIterator: io_iterator_t = 0
    private var removedLegacyIterator: io_iterator_t = 0
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?
    private var isActive = false

    private init() {}

    // MARK: - Public lifecycle

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            startMonitoring()
            refresh(retryLateDescriptors: true)
        } else {
            stopMonitoring()
            count = 0
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort else { return }

        let source = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        let callback: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            let monitor = Unmanaged<ConnectedDevicesMonitor>.fromOpaque(context).takeUnretainedValue()
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                IOObjectRelease(entry)
            }
            monitor.refresh(retryLateDescriptors: true)
        }

        let refCon = Unmanaged.passUnretained(self).toOpaque()

        // IOUSBHostDevice (modern)
        if let matchAdded = IOServiceMatching("IOUSBHostDevice") {
            IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification,
                                             matchAdded, callback, refCon,
                                             &addedIterator)
            while case let e = IOIteratorNext(addedIterator), e != 0 { IOObjectRelease(e) }
        }
        if let matchRemoved = IOServiceMatching("IOUSBHostDevice") {
            IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification,
                                             matchRemoved, callback, refCon,
                                             &removedIterator)
            while case let e = IOIteratorNext(removedIterator), e != 0 { IOObjectRelease(e) }
        }

        // IOUSBDevice (legacy)
        if let matchLegacyAdded = IOServiceMatching(kIOUSBDeviceClassName) {
            IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification,
                                             matchLegacyAdded, callback, refCon,
                                             &addedLegacyIterator)
            while case let e = IOIteratorNext(addedLegacyIterator), e != 0 { IOObjectRelease(e) }
        }
        if let matchLegacyRemoved = IOServiceMatching(kIOUSBDeviceClassName) {
            IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification,
                                             matchLegacyRemoved, callback, refCon,
                                             &removedLegacyIterator)
            while case let e = IOIteratorNext(removedLegacyIterator), e != 0 { IOObjectRelease(e) }
        }

        // Power Source changes (charger / MagSafe connected / disconnected)
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<ConnectedDevicesMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.refresh(retryLateDescriptors: false)
        }, refCon)?.takeRetainedValue()
        if let powerSourceRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .commonModes)
        }

        // Volume mount/unmount for removable media (SD cards, flash drives, external SSDs)
        let center = NSWorkspace.shared.notificationCenter
        let m1 = center.addObserver(forName: NSWorkspace.didMountNotification,
                                    object: nil, queue: .main) { [weak self] _ in
            self?.refresh(retryLateDescriptors: true)
        }
        let m2 = center.addObserver(forName: NSWorkspace.didUnmountNotification,
                                    object: nil, queue: .main) { [weak self] _ in
            self?.refresh(retryLateDescriptors: true)
        }
        workspaceObservers = [m1, m2]

        // Recompute when exclusion toggles change in Settings
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(retryLateDescriptors: false)
        }
    }

    private func stopMonitoring() {
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if addedLegacyIterator != 0 { IOObjectRelease(addedLegacyIterator); addedLegacyIterator = 0 }
        if removedLegacyIterator != 0 { IOObjectRelease(removedLegacyIterator); removedLegacyIterator = 0 }
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .commonModes)
            self.powerSourceRunLoopSource = nil
        }
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
    }

    // MARK: - Scanning

    /// Refreshes the connected device count.
    ///
    /// USB descriptors often arrive hundreds of milliseconds after the initial IOKit
    /// connection notification (`kIOFirstMatchNotification`). When `retryLateDescriptors`
    /// is true, a follow-up scan is automatically scheduled to ensure newly plugged
    /// devices are captured once their metadata enumerates.
    func refresh(retryLateDescriptors: Bool = true) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.isActive else { return }
            let scanned = self.countExternalDevices()
            DispatchQueue.main.async {
                guard self.isActive else { return }
                self.count = scanned
            }
        }
        if retryLateDescriptors {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.isActive else { return }
                self.refresh(retryLateDescriptors: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.isActive else { return }
                self.refresh(retryLateDescriptors: false)
            }
        }
    }

    private struct ScannedUSBDevice {
        let id: String
        let bsdName: String?
        let isHub: Bool
        let isStorage: Bool
        let isEthernet: Bool
    }

    /// Counts distinct external USB/Thunderbolt devices and removable disks,
    /// respecting user category exclusion settings (chargers, hubs, ethernet, storage).
    /// Deduplicates devices matched across both legacy and modern tables, and
    /// prevents connected storage drives from being counted twice (once via
    /// IOKit USB device and once via mounted volume).
    private func countExternalDevices() -> Int {
        var usbDevices: [ScannedUSBDevice] = []
        var seenKeys = Set<String>()
        var knownDisks = Set<String>()

        func scan(className: String) {
            guard let matching = IOServiceMatching(className) else { return }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(iterator) }

            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                guard let dev = parseUSBDevice(entry) else { continue }
                if seenKeys.insert(dev.id).inserted {
                    usbDevices.append(dev)
                    if let bsd = dev.bsdName, !bsd.isEmpty {
                        knownDisks.insert(bsd)
                        knownDisks.insert(wholeDiskName(from: bsd))
                    }
                }
            }
        }

        scan(className: "IOUSBHostDevice")
        scan(className: kIOUSBDeviceClassName)

        let excludeChargers = UserDefaults.standard.bool(forKey: DefaultsKey.usbExcludeChargersFromCount)
        let excludeHubs = UserDefaults.standard.bool(forKey: DefaultsKey.usbExcludeHubsFromCount)
        let excludeEthernet = UserDefaults.standard.bool(forKey: DefaultsKey.usbExcludeEthernetFromCount)
        let excludeStorage = UserDefaults.standard.bool(forKey: DefaultsKey.usbExcludeStorageFromCount)

        // Scan Mounted Removable / External Volumes (SD cards, USB drives, external SSDs)
        var additionalExternalDisks = Set<String>()
        if !excludeStorage, let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey],
            options: [.skipHiddenVolumes]
        ) {
            for url in urls {
                guard let vals = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey]),
                      (vals.volumeIsRemovable == true || vals.volumeIsEjectable == true) else { continue }
                if url.path == "/" || url.path.hasPrefix("/System") { continue }

                var stat = statfs()
                guard statfs(url.path, &stat) == 0 else { continue }
                let mntFrom = withUnsafePointer(to: &stat.f_mntfromname) { ptr in
                    String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
                }
                let bsd = mntFrom.replacingOccurrences(of: "/dev/", with: "")
                let whole = wholeDiskName(from: bsd)

                // If this volume is already backed by a detected USB device, do not double-count it
                if !knownDisks.contains(bsd) && !knownDisks.contains(whole) {
                    additionalExternalDisks.insert(whole)
                }
            }
        }

        var total = 0
        for dev in usbDevices {
            if excludeHubs && dev.isHub { continue }
            if excludeStorage && dev.isStorage { continue }
            if excludeEthernet && dev.isEthernet { continue }
            total += 1
        }

        if !excludeStorage {
            total += additionalExternalDisks.count
        }

        if !excludeChargers && isExternalPowerConnected() {
            total += 1
        }

        return total
    }

    /// Returns true if an external power adapter (MagSafe / USB-C charger) is connected.
    private func isExternalPowerConnected() -> Bool {
        if let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           !details.isEmpty {
            return true
        }
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String,
               state == (kIOPSACPowerValue as String) {
                return true
            }
        }
        return false
    }

    private func wholeDiskName(from bsd: String) -> String {
        if let match = bsd.range(of: "^disk\\d+", options: .regularExpression) {
            return String(bsd[match])
        }
        return bsd
    }

    private func parseUSBDevice(_ entry: io_registry_entry_t) -> ScannedUSBDevice? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        func isTrue(_ val: Any?) -> Bool {
            if let b = val as? Bool { return b }
            if let n = val as? NSNumber { return n.boolValue }
            if let s = val as? String {
                let lower = s.lowercased()
                return lower == "yes" || lower == "1" || lower == "true"
            }
            return false
        }

        // Skip internal / built-in devices (e.g. internal keyboards, ALS sensors, internal webcams)
        if isTrue(dict["Built-In"]) || isTrue(dict["non-removable"]) { return nil }

        let vendorId = (dict[kUSBVendorID as String] as? NSNumber)?.intValue ?? 0
        let productId = (dict[kUSBProductID as String] as? NSNumber)?.intValue ?? 0

        // Skip root hubs and host controllers (vendor 0, product 0)
        if vendorId == 0, productId == 0 { return nil }

        let devClass = (dict["bDeviceClass"] as? NSNumber)?.intValue ?? 0
        let devProtocol = (dict["bDeviceProtocol"] as? NSNumber)?.intValue ?? 0

        var cName = [CChar](repeating: 0, count: 128)
        let regName = (IORegistryEntryGetName(entry, &cName) == KERN_SUCCESS) ? String(cString: cName) : ""
        let productString = (dict[kUSBProductString as String] as? String) ?? ""
        let displayName = !productString.isEmpty ? productString : regName

        let isHub = devClass == 9 || devProtocol == 9 ||
            displayName.lowercased().contains("hub") ||
            regName.lowercased().contains("hub")

        let serial = (dict[kUSBSerialNumberString as String] as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let locationId = (dict["locationID"] as? NSNumber)?.intValue ?? 0

        // Build stable identifier across both IOUSBHostDevice and legacy IOUSBDevice
        let uniqueId: String
        if !serial.isEmpty {
            uniqueId = "\(vendorId)-\(productId)-\(serial)"
        } else if locationId != 0 {
            uniqueId = "\(vendorId)-\(productId)-loc\(locationId)"
        } else {
            uniqueId = "\(vendorId)-\(productId)-\(displayName)"
        }

        // Recursively find BSD Name if this USB device provides storage
        let searchedBsd: String? = {
            if let directBsd = dict["BSD Name"] as? String { return directBsd }
            if let searched = IORegistryEntrySearchCFProperty(
                entry,
                kIOServicePlane,
                "BSD Name" as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively)
            ) as? String {
                let trimmed = searched.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }()

        let ifClass = (dict["bInterfaceClass"] as? NSNumber)?.intValue ?? 0
        let isStorage = (searchedBsd != nil) || devClass == 8 || ifClass == 8
        let isEthernet = devClass == 2 || ifClass == 2 ||
            displayName.lowercased().contains("ethernet") ||
            displayName.lowercased().contains("lan") ||
            regName.lowercased().contains("ethernet")

        return ScannedUSBDevice(
            id: uniqueId,
            bsdName: searchedBsd,
            isHub: isHub,
            isStorage: isStorage,
            isEthernet: isEthernet
        )
    }
}
