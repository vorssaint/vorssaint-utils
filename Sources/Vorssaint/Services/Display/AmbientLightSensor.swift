// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

/// BezelServices selects the Mac's ambient light sensor. Its HID event's
/// level is illuminance in lux (event type 12, field 12 << 16). Symbols are
/// optional because these private interfaces may not exist on every Mac.
/// All reads and resource lifetime changes belong to the service's worker queue.
final class AmbientLightSensor {
    private typealias CopySensor = @convention(c) () -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    private static let api: (sensor: CopySensor, event: CopyEvent, value: FloatValue)? = {
        guard let bezel = dlopen("/System/Library/PrivateFrameworks/BezelServices.framework/BezelServices", RTLD_LAZY),
              let hid = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let sensor = dlsym(bezel, "ALCALSCopyALSServiceClient"),
              let event = dlsym(hid, "IOHIDServiceClientCopyEvent"),
              let value = dlsym(hid, "IOHIDEventGetFloatValue") else { return nil }
        return (unsafeBitCast(sensor, to: CopySensor.self),
                unsafeBitCast(event, to: CopyEvent.self),
                unsafeBitCast(value, to: FloatValue.self))
    }()

    private var client: CFTypeRef?

    func readLux() -> Double? {
        guard let api = Self.api else { return nil }
        if client == nil { client = api.sensor()?.takeRetainedValue() }
        guard let client, let event = api.event(client, 12, 0, 0)?.takeRetainedValue() else {
            self.client = nil // Reconnect after sleep or a temporary service loss.
            return nil
        }
        return AmbientLightSupport.validLux(api.value(event, 12 << 16))
    }

    func close() { client = nil }
}
