// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation
import IOKit

/// Tells its owner when macOS Secure Event Input turns on or off, without
/// polling. The flag has no notification of its own, but the window server
/// records its holder in the console users list on `IOResources`, and every
/// update of that list publishes a resource, which takes `IOResources` busy
/// and back. Measured on 27.2: one busy pair per change, plus a pair about
/// every ten seconds for unrelated updates. Each message rereads the flag,
/// about a microsecond, and only a change reaches the owner.
///
/// Main thread only. Where the interest cannot be registered, nothing is
/// watched and the owner still reads the flag whenever it applies its state.
final class SecureInputWatch {
    private let onChange: (Bool) -> Void
    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var lastSeen = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Safe to call repeatedly; only the first call after a stop registers.
    func start() {
        guard port == nil else { return }
        let resources = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources")
        guard resources != MACH_PORT_NULL else { return }
        defer { IOObjectRelease(resources) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        let result = IOServiceAddInterestNotification(
            port, resources, kIOBusyInterest, { context, _, _, _ in
                guard let context else { return }
                Unmanaged<SecureInputWatch>.fromOpaque(context).takeUnretainedValue().recheck()
            }, Unmanaged.passUnretained(self).toOpaque(), &notification)
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }
        self.port = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        // Read after registering, so a change in between still arrives as a
        // message instead of falling into the gap.
        lastSeen = IsSecureEventInputEnabled()
    }

    func stop() {
        if notification != 0 { IOObjectRelease(notification) }
        notification = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private func recheck() {
        let enabled = IsSecureEventInputEnabled()
        guard enabled != lastSeen else { return }
        lastSeen = enabled
        onChange(enabled)
    }
}
