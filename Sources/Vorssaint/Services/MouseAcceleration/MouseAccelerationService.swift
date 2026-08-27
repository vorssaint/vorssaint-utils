// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import HIDEventSystem

/// Applies macOS's per-device linear pointer mode to ordinary mouse devices.
/// Trackpads are deliberately excluded.
///
/// `-1` is the documented HID value for disabled pointer acceleration and
/// sensitivity. The original value for each service is retained for the
/// lifetime of this setting and restored when it is switched back off.
final class MouseAccelerationService: ObservableObject {
    static let shared = MouseAccelerationService()

    private let defaults = UserDefaults.standard
    private var client: IOHIDEventSystemClient?
    private var refreshTimer: Timer?
    private struct OriginalSetting {
        let key: String
        let value: Any
    }

    private var originalValues: [UInt64: OriginalSetting] = [:]
    private static let trackpadAccelerationType = "HIDTrackpadAcceleration"

    private init() {}

    func syncWithPreferences() {
        let wanted = AppFeature.mouseAcceleration.isAvailable
            && defaults.bool(forKey: DefaultsKey.mouseAccelerationDisabled)
        if wanted {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        restoreOriginalValues()
        client = nil
    }

    private func start() {
        if client == nil {
            client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        }
        applyLinearMode()
        guard refreshTimer == nil else { return }
        // A simple client does not publish connection notifications. Refreshing
        // also covers a mouse connected after Vorssaint has launched.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.applyLinearMode()
        }
    }

    private func applyLinearMode() {
        guard let client,
              let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return }

        for service in services where isMouse(service) {
            let id = registryID(of: service)
            // Do not change a device unless its current setting can be kept
            // and restored. Some HID services accept a write but don't expose
            // the property for reading back.
            guard let original = originalValues[id] ?? currentSetting(for: service) else {
                continue
            }
            originalValues[id] = original
            if original.key == "HIDUseLinearScalingMouseAcceleration" {
                IOHIDServiceClientSetProperty(service,
                                              "HIDUseLinearScalingMouseAcceleration" as CFString,
                                              1 as CFNumber)
            } else {
                IOHIDServiceClientSetProperty(service,
                                              accelerationKey(for: service) as CFString,
                                              -1 as CFNumber)
            }
        }
    }

    private func restoreOriginalValues() {
        guard let client,
              let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            originalValues.removeAll()
            return
        }
        for service in services where isMouse(service) {
            let id = registryID(of: service)
            if let original = originalValues[id] {
                IOHIDServiceClientSetProperty(service, original.key as CFString, original.value as CFTypeRef)
            }
        }
        originalValues.removeAll()
    }

    private func isMouse(_ service: IOHIDServiceClient) -> Bool {
        // `Pointer` is deliberately not accepted here: macOS uses that
        // broader HID usage for devices other than mice, including trackpads.
        guard IOHIDServiceClientConformsTo(service,
                                           UInt32(kHIDPage_GenericDesktop),
                                           UInt32(kHIDUsage_GD_Mouse)) != 0 else {
            return false
        }
        let accelerationType = IOHIDServiceClientCopyProperty(
            service, "HIDPointerAccelerationType" as CFString
        ) as? String
        return accelerationType != Self.trackpadAccelerationType
    }

    private func registryID(of service: IOHIDServiceClient) -> UInt64 {
        (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
    }

    private func currentSetting(for service: IOHIDServiceClient) -> OriginalSetting? {
        if let value = IOHIDServiceClientCopyProperty(service,
                                                       "HIDUseLinearScalingMouseAcceleration" as CFString) {
            return OriginalSetting(key: "HIDUseLinearScalingMouseAcceleration", value: value)
        }
        let key = accelerationKey(for: service)
        guard let value = IOHIDServiceClientCopyProperty(service, key as CFString) else { return nil }
        return OriginalSetting(key: key, value: value)
    }

    private func accelerationKey(for service: IOHIDServiceClient) -> String {
        if let key = IOHIDServiceClientCopyProperty(service,
                                                    "HIDPointerAccelerationType" as CFString) as? String {
            return key
        }
        if IOHIDServiceClientCopyProperty(service, "HIDPointerAcceleration" as CFString) != nil {
            return "HIDPointerAcceleration"
        }
        return "HIDMouseAcceleration"
    }
}
