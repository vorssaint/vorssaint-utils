// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit
import SystemConfiguration

/// What This Mac's rail says about the hardware beside its readings: core
/// counts, and the kind of connection, never its name.
enum NotchLockScreenSystemInfo {
    enum Connection: Equatable {
        case wifi, ethernet
    }

    static let cpuCores = ProcessInfo.processInfo.processorCount

    /// The GPU's cores as the Apple silicon driver lists them; nil elsewhere.
    static let gpuCores: Int? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? NSNumber)?.intValue
    }()

    /// The kind of interface the Mac's traffic leaves by, or nil when it is
    /// neither or there is none.
    static func connection() -> Connection? {
        guard let store = SCDynamicStoreCreate(nil, "Vorssaint" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primary = global["PrimaryInterface"] as? String else { return nil }
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard SCNetworkInterfaceGetBSDName(interface) as String? == primary,
                  let type = SCNetworkInterfaceGetInterfaceType(interface) else { continue }
            if type == kSCNetworkInterfaceTypeIEEE80211 { return .wifi }
            if type == kSCNetworkInterfaceTypeEthernet { return .ethernet }
            return nil
        }
        return nil
    }
}
