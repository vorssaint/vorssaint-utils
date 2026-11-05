// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ObjectiveC

/// Read-only observation of the system's effective Night Shift state. macOS
/// owns the schedule (including sunset, sunrise and temporary overrides).
/// CoreBrightness has no public API; reject an unfamiliar status ABI rather
/// than guessing at its memory layout. Used only while following Night Shift.
final class NightShiftObserver {
    private typealias GetStatus = @convention(c)
        (NSObject, Selector, UnsafeMutableRawPointer) -> ObjCBool
    private typealias SetNotification = @convention(c)
        (NSObject, Selector, AnyObject?) -> Void

    private let client: NSObject
    private let getStatus: GetStatus
    private let setNotification: SetNotification
    private let statusSelector = NSSelectorFromString("getBlueLightStatus:")
    private let notificationSelector = NSSelectorFromString("setStatusNotificationBlock:")
    private var wakeObserver: NSObjectProtocol?
    private var timer: Timer?

    init?(onChange: @escaping () -> Void) {
        guard let framework = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              framework.load(),
              let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type,
              let statusMethod = class_getInstanceMethod(type, statusSelector),
              let notificationMethod = class_getInstanceMethod(type, notificationSelector),
              let argumentType = method_copyArgumentType(statusMethod, 2)
        else { return nil }
        defer { free(argumentType) }
        let layout = String(cString: argumentType).replacingOccurrences(
            of: "\\{[^=]*=", with: "{=", options: .regularExpression)
        // Three BOOLs, mode, two hour/minute pairs, disable flags, availability.
        guard layout == "^{=BBBi{={=ii}{=ii}}QB}" else { return nil }
        client = type.init()
        getStatus = unsafeBitCast(method_getImplementation(statusMethod), to: GetStatus.self)
        setNotification = unsafeBitCast(method_getImplementation(notificationMethod), to: SetNotification.self)
        let notify: @convention(block) () -> Void = {
            DispatchQueue.main.async(execute: onChange)
        }
        setNotification(client, notificationSelector, notify as AnyObject)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in onChange() }
        // Recover from a lost notification or a transient read failure. The
        // callback handles ordinary schedule transitions without this delay.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in onChange() }
        timer?.tolerance = 10
    }

    var enabled: Bool? {
        let status = UnsafeMutableRawPointer.allocate(byteCount: 40, alignment: 8)
        defer { status.deallocate() }
        status.initializeMemory(as: UInt8.self, repeating: 0, count: 40)
        guard getStatus(client, statusSelector, status).boolValue else { return nil }
        // `active` is the service state, `enabled` is the effective filter state.
        return status.load(fromByteOffset: 1, as: UInt8.self) != 0
    }

    deinit {
        setNotification(client, notificationSelector, nil)
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
