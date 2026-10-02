// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

enum TouchBarHardware {
    static var isAvailable: Bool {
        guard let matching = IOServiceMatching("IOHIDUserDevice") else {
            return false
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator
        ) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let product = IORegistryEntryCreateCFProperty(
                service,
                "Product" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String

            IOObjectRelease(service)

            if product == "TouchBarUserDevice" {
                return true
            }

            service = IOIteratorNext(iterator)
        }

        return false
    }
}
