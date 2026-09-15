// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import HIDEventSystem

/// Base M1 machines can expose named thermal sensors through HID even when
/// AppleSMC has no mapped CPU cores or Tg keys. Match only temperature services.
final class HIDTemperatureSampler {
    private var client: IOHIDEventSystemClient?

    func readings(platform: CPUTemperaturePlatform) -> [(key: String, value: Double)] {
        guard platform == .appleM1Family else { return [] }
        if client == nil {
            client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
            if let client {
                IOHIDEventSystemClientSetMatching(client, [
                    "PrimaryUsagePage": 0xff00,
                    "PrimaryUsage": 5,
                ] as CFDictionary)
            }
        }
        guard let client,
              let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]
        else { return [] }
        return services.compactMap { service in
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let event = IOHIDServiceClientCopyEvent(service, 15, 0, 0)
            else { return nil }
            return (name, IOHIDEventGetFloatValue(event, 15 << 16))
        }
    }
}
