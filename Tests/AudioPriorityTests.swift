// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AudioPriorityTests {
    static func run(_ suite: TestSuite) {
        let available: Set<String> = ["speakers", "display"]
        suite.expect(MixerRoutingSupport.firstAvailablePriorityDeviceUID(
            orderedUIDs: ["offline", "display", "speakers"],
            availableUIDs: available) == "display",
            "priority falls through unavailable devices in the saved order")
        suite.expect(MixerRoutingSupport.firstAvailablePriorityDeviceUID(
            orderedUIDs: ["offline"], availableUIDs: available) == nil,
            "priority leaves the current system choice alone when no listed device is present")
        suite.expect(MixerRoutingSupport.priorityListIncludingAvailableDevices(
            storedUIDs: [], availableUIDs: ["speakers", "display"],
            currentUID: "display") == ["display", "speakers"],
            "a new list starts with the current device")
        suite.expect(MixerRoutingSupport.priorityListIncludingAvailableDevices(
            storedUIDs: ["offline", "display"], availableUIDs: ["speakers", "display"],
            currentUID: "speakers") == ["offline", "display", "speakers"],
            "disconnected entries keep their position and newly seen devices append")
        suite.expect(!MixerRoutingSupport.deviceAvailabilityChanged(
            previousUIDs: nil, currentUIDs: available),
            "the initial device snapshot establishes a baseline")
        suite.expect(!MixerRoutingSupport.deviceAvailabilityChanged(
            previousUIDs: available, currentUIDs: ["display", "speakers"]),
            "changing only the default device does not count as a connection event")
        suite.expect(MixerRoutingSupport.deviceAvailabilityChanged(
            previousUIDs: available, currentUIDs: ["speakers"]),
            "disconnecting a device re-evaluates priority")
        suite.expect(MixerRoutingSupport.deviceAvailabilityChanged(
            previousUIDs: available, currentUIDs: ["speakers", "display", "headphones"]),
            "connecting a device re-evaluates priority")
        suite.expect(MixerRoutingSupport.shouldSwitchToDevice(
            targetUID: "display", currentUID: "speakers")
            && !MixerRoutingSupport.shouldSwitchToDevice(
                targetUID: "display", currentUID: "display"),
            "priority writes only when its target differs from the current device")

        let input = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "preferred",
            availableUIDs: ["preferred", "priority"],
            currentUID: "priority",
            priorityIsActive: true)
        suite.expect(input == MixerInputRouteResolution(
            effectiveUID: "priority", selectedUnavailable: false,
            shouldApplyPreferred: false),
            "microphone priority leaves the dormant preferred microphone unapplied")
        let prioritySelection = MixerRoutingSupport.selectedInputDeviceUID(
            preferredUID: "preferred", currentUID: "priority", priorityIsActive: true)
        suite.expect(prioritySelection == "priority"
            && MixerRoutingSupport.selectedInputDeviceUID(
                preferredUID: "preferred", currentUID: "priority", priorityIsActive: false) == "preferred",
            "every microphone menu follows the current input while priority owns selection")

        let priorityOnlyInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "preferred",
            availableUIDs: ["preferred", "current"],
            currentUID: "current",
            preferredInputIsActive: false)
        suite.expect(priorityOnlyInput == MixerInputRouteResolution(
            effectiveUID: "current", selectedUnavailable: false,
            shouldApplyPreferred: false),
            "an uninstalled volume mixer cannot apply its saved preferred microphone")

        suite.expect(AppFeature.audioPriority.group == .sound
            && AppFeature.audioPriority.permissions.isEmpty
            && AppFeature.audioPriority.enabledKeys == [
                DefaultsKey.audioPriorityOutputEnabled, DefaultsKey.audioPriorityInputEnabled],
            "audio priority is an independent Sound feature with no additional permissions")
        suite.expect((AppFeature.availabilityDefaults[AppFeature.audioPriority.availabilityKey] as? Bool) == false
            && (Defaults.registeredDefaults[DefaultsKey.audioPriorityOutputEnabled] as? Bool) == true
            && (Defaults.registeredDefaults[DefaultsKey.audioPriorityInputEnabled] as? Bool) == true,
            "the feature ships uninstalled but both directions are ready on first install")
        let storedKeys: Set<String> = [
            DefaultsKey.audioPriorityOutputUIDs,
            DefaultsKey.audioPriorityInputUIDs,
            DefaultsKey.audioPriorityDeviceNames,
        ]
        suite.expect(storedKeys.isDisjoint(with: SettingsBackupSupport.unregisteredPreferenceKeys)
            && SettingsBackupSupport.exportKeys().isSuperset(of: storedKeys),
            "registered priority preferences travel in settings backups once")
        suite.expect(Defaults.sanitizedAudioPriorityUIDs(["a", "b", "a", "\n"]) == ["a", "b"],
            "saved lists keep valid devices once and preserve their order")
    }
}
