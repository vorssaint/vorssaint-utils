// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import HIDEventSystem

/// Named thermal sensors used when an M1 has no suitable SMC reading.
final class HIDTemperatureSampler {
    // Resolve the complete private API before creating a client. Missing symbols
    // disable this fallback without preventing the app or helper from launching.
    private struct API {
        typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<IOHIDEventSystemClient>?
        typealias SetMatching = @convention(c) (IOHIDEventSystemClient, CFDictionary) -> Void
        typealias CopyEvent = @convention(c) (IOHIDServiceClient, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
        typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double

        let create: Create
        let setMatching: SetMatching
        let copyEvent: CopyEvent
        let floatValue: FloatValue

        init?(resolve: (String) -> UnsafeMutableRawPointer?) {
            guard let create = resolve("IOHIDEventSystemClientCreate"),
                  let matching = resolve("IOHIDEventSystemClientSetMatching"),
                  let event = resolve("IOHIDServiceClientCopyEvent"),
                  let value = resolve("IOHIDEventGetFloatValue") else { return nil }
            self.create = unsafeBitCast(create, to: Create.self)
            self.setMatching = unsafeBitCast(matching, to: SetMatching.self)
            self.copyEvent = unsafeBitCast(event, to: CopyEvent.self)
            self.floatValue = unsafeBitCast(value, to: FloatValue.self)
        }
    }

    private let api: API?
    private var client: IOHIDEventSystemClient?

    init(resolve: (String) -> UnsafeMutableRawPointer? = {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), $0)
    }) {
        api = API(resolve: resolve)
    }

    func readings(platform: CPUTemperaturePlatform) -> [(key: String, value: Double)] {
        guard platform == .appleM1Family, let api else { return [] }
        if client == nil {
            client = api.create(kCFAllocatorDefault)?.takeRetainedValue()
            if let client {
                api.setMatching(client, [
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
                  let event = api.copyEvent(service, 15, 0, 0)?.takeRetainedValue()
            else { return nil }
            return (name, api.floatValue(event, 15 << 16))
        }
    }
}
