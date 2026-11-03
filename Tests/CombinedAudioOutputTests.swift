// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

enum CombinedAudioOutputContract {
    struct Device {
        let uid: String
        let canBeDefaultOutput: Bool
    }

    final class SimulatedMixer {
        var outputDevices: [Device] = []
        var combinedSelectedDeviceUIDs: Set<String> = []
        var combinedSubDeviceVolumes: [String: Double] = [:]
        var combinedSubDeviceMutes: [String: Bool] = [:]

        func eligibleCombinedOutputDevices() -> [Device] {
            outputDevices.filter { MixerRoutingSupport.isEligibleForCombinedOutput(uid: $0.uid, canBeDefault: $0.canBeDefaultOutput) }
        }

        func activeCombinedSubDeviceUIDs() -> [String] {
            let eligible = eligibleCombinedOutputDevices().map(\.uid)
            if combinedSelectedDeviceUIDs.isEmpty {
                return eligible
            }
            let selected = eligible.filter { combinedSelectedDeviceUIDs.contains($0) }
            return selected.count >= 2 ? selected : eligible
        }

        func toggleCombinedDeviceSelection(uid: String) {
            let eligible = eligibleCombinedOutputDevices().map(\.uid)
            var updated = combinedSelectedDeviceUIDs
            if updated.isEmpty {
                updated = Set(eligible)
            }

            if updated.contains(uid) {
                let remaining = updated.subtracting([uid]).intersection(Set(eligible))
                guard remaining.count >= 2 else { return }
                updated.remove(uid)
            } else {
                updated.insert(uid)
            }

            combinedSelectedDeviceUIDs = updated
        }

        func setCombinedSubDeviceVolume(_ volume: Double, for uid: String) {
            let clamped = min(max(volume, 0), 1)
            combinedSubDeviceVolumes[uid] = clamped
            let isMuted = (clamped <= 0.001)
            combinedSubDeviceMutes[uid] = isMuted
        }

        func toggleCombinedSubDeviceMute(for uid: String) {
            let currentMute = combinedSubDeviceMutes[uid] ?? false
            let newMute = !currentMute
            combinedSubDeviceMutes[uid] = newMute
        }
    }

    static func run(_ suite: TestSuite) {
        // 1. Sentinel & UID recognition
        suite.expect(MixerRoutingSupport.combineAllOutputsSelectionID == "__vorssaint_combine_all_outputs__",
                     "sentinel selection ID matches expected constant")
        suite.expect(CombinedAudioOutputManager.isCombinedOutputUID(MixerRoutingSupport.combineAllOutputsSelectionID),
                     "sentinel ID is recognized as combined output")
        suite.expect(CombinedAudioOutputManager.isCombinedOutputUID("com.vorssaint.combined-output"),
                     "driver UID is recognized as combined output")
        suite.expect(!CombinedAudioOutputManager.isCombinedOutputUID("BuiltInSpeakerDevice"),
                     "standard speaker UID is not recognized as combined output")
        suite.expect(!CombinedAudioOutputManager.isCombinedOutputUID(nil),
                     "nil UID is not recognized as combined output")

        // 2. Eligibility checks
        suite.expect(MixerRoutingSupport.isEligibleForCombinedOutput(uid: "BuiltInSpeakerDevice", canBeDefault: true),
                     "built-in speaker is eligible for combined output")
        suite.expect(MixerRoutingSupport.isEligibleForCombinedOutput(uid: "ExternalDisplay", canBeDefault: true),
                     "external display is eligible for combined output")
        suite.expect(!MixerRoutingSupport.isEligibleForCombinedOutput(uid: AirPlayRouteManager.airPlaySentinelUID, canBeDefault: false),
                     "AirPlay route is not eligible for combined output")
        suite.expect(!MixerRoutingSupport.isEligibleForCombinedOutput(uid: MixerRoutingSupport.combineAllOutputsSelectionID, canBeDefault: true),
                     "sentinel ID itself is not eligible for combined output")
        suite.expect(!MixerRoutingSupport.isEligibleForCombinedOutput(uid: "VirtualNonDefault", canBeDefault: false),
                     "devices that cannot be default output are not eligible")
        suite.expect(!MixerRoutingSupport.isEligibleForCombinedOutput(uid: "", canBeDefault: true),
                     "empty UID is not eligible")

        // 3. Minimum devices requirement, deduplication and sanitization in CombinedAudioOutputManager
        let manager = CombinedAudioOutputManager.shared
        suite.expect(manager.createOrUpdateMultiOutputDevice(subDeviceUIDs: []) == nil,
                     "creating combined device with empty list returns nil")
        suite.expect(manager.createOrUpdateMultiOutputDevice(subDeviceUIDs: ["OnlyOneDevice"]) == nil,
                     "creating combined device with fewer than 2 devices returns nil")
        suite.expect(manager.createOrUpdateMultiOutputDevice(subDeviceUIDs: ["devA", "devA"]) == nil,
                     "creating combined device with duplicate identical UIDs returns nil")
        suite.expect(manager.createOrUpdateMultiOutputDevice(subDeviceUIDs: ["devA", ""]) == nil,
                     "creating combined device with empty string UID returns nil")
        suite.expect(manager.createOrUpdateMultiOutputDevice(subDeviceUIDs: ["", ""]) == nil,
                     "creating combined device with all empty UIDs returns nil")

        // Deduplication with 2 unique devices out of duplicate list is handled cleanly
        _ = manager.createOrUpdateMultiOutputDevice(subDeviceUIDs: ["devA", "devB", "devA"])
        suite.expect(true, "passing duplicate UIDs (devA, devB, devA) is handled cleanly without error")

        // Subsets of devices are handled cleanly
        _ = manager.createOrUpdateMultiOutputDevice(subDeviceUIDs: ["devA", "devB"])
        suite.expect(true, "creating combined device with subset of 2 devices out of 3 is handled cleanly")

        manager.destroyDevice()
        suite.expect(manager.activeAggregateID == 0,
                     "activeAggregateID is reset to 0 after destroyDevice")

        // 4. Persistent selection key
        suite.expect(DefaultsKey.mixerCombinedOutputSelectedDeviceUIDs == "mixerCombinedOutputSelectedDeviceUIDs",
                     "mixerCombinedOutputSelectedDeviceUIDs key matches expected string constant")

        UserDefaults.standard.set(["devA", "devB"], forKey: DefaultsKey.mixerCombinedOutputSelectedDeviceUIDs)
        let savedUIDs = UserDefaults.standard.stringArray(forKey: DefaultsKey.mixerCombinedOutputSelectedDeviceUIDs)
        suite.expect(savedUIDs == ["devA", "devB"],
                     "selected device UIDs can be saved and read from UserDefaults")
        UserDefaults.standard.removeObject(forKey: DefaultsKey.mixerCombinedOutputSelectedDeviceUIDs)

        // 5. Selective combining: device selection resolution and toggling
        let mixer = SimulatedMixer()
        mixer.outputDevices = [
            Device(uid: "speaker", canBeDefaultOutput: true),
            Device(uid: "headphones", canBeDefaultOutput: true),
            Device(uid: "display", canBeDefaultOutput: true)
        ]

        // When selection is empty, active devices defaults to all eligible devices
        suite.expect(mixer.activeCombinedSubDeviceUIDs() == ["speaker", "headphones", "display"],
                     "empty selection resolves to all eligible devices")

        // Selecting a subset of 2 devices out of 3
        mixer.combinedSelectedDeviceUIDs = ["speaker", "headphones"]
        suite.expect(mixer.activeCombinedSubDeviceUIDs() == ["speaker", "headphones"],
                     "active devices resolves to selected subset of 2 devices")

        // Deselecting down to 2 devices works when 3 are selected
        mixer.combinedSelectedDeviceUIDs = ["speaker", "headphones", "display"]
        mixer.toggleCombinedDeviceSelection(uid: "display")
        suite.expect(mixer.combinedSelectedDeviceUIDs == ["speaker", "headphones"],
                     "toggling selected device removes it when more than 2 remain")

        // Refusing deselection when fewer than 2 devices would remain
        mixer.toggleCombinedDeviceSelection(uid: "headphones")
        suite.expect(mixer.combinedSelectedDeviceUIDs == ["speaker", "headphones"],
                     "deselection is refused when only 2 devices remain")

        // Toggling an unselected device adds it
        mixer.toggleCombinedDeviceSelection(uid: "display")
        suite.expect(mixer.combinedSelectedDeviceUIDs == ["speaker", "headphones", "display"],
                     "toggling unselected device adds it to selection")

        // When selection has fewer than 2 devices, active sub-devices safely falls back to all eligible
        mixer.combinedSelectedDeviceUIDs = ["speaker"]
        suite.expect(mixer.activeCombinedSubDeviceUIDs() == ["speaker", "headphones", "display"],
                     "active sub-devices falls back to all eligible devices when selection count is under 2")

        // 6. Per-device volume clamping
        mixer.setCombinedSubDeviceVolume(1.5, for: "speaker")
        suite.expect(mixer.combinedSubDeviceVolumes["speaker"] == 1.0,
                     "volume above 1.0 is clamped to 1.0")

        mixer.setCombinedSubDeviceVolume(-0.5, for: "speaker")
        suite.expect(mixer.combinedSubDeviceVolumes["speaker"] == 0.0,
                     "volume below 0.0 is clamped to 0.0")

        mixer.setCombinedSubDeviceVolume(0.75, for: "speaker")
        suite.expect(mixer.combinedSubDeviceVolumes["speaker"] == 0.75,
                     "volume within 0...1 retains its exact value")

        // 7. Threshold muting at 0.001
        mixer.setCombinedSubDeviceVolume(0.001, for: "speaker")
        suite.expect(mixer.combinedSubDeviceMutes["speaker"] == true,
                     "volume at exactly threshold 0.001 is muted")

        mixer.setCombinedSubDeviceVolume(0.0005, for: "speaker")
        suite.expect(mixer.combinedSubDeviceMutes["speaker"] == true,
                     "volume below threshold 0.001 is muted")

        mixer.setCombinedSubDeviceVolume(0.0, for: "speaker")
        suite.expect(mixer.combinedSubDeviceMutes["speaker"] == true,
                     "volume at 0.0 is muted")

        mixer.setCombinedSubDeviceVolume(0.0011, for: "speaker")
        suite.expect(mixer.combinedSubDeviceMutes["speaker"] == false,
                     "volume above threshold 0.001 (0.0011) is unmuted")

        mixer.setCombinedSubDeviceVolume(0.5, for: "speaker")
        suite.expect(mixer.combinedSubDeviceMutes["speaker"] == false,
                     "normal volume (0.5) is unmuted")

        // Mute toggling
        mixer.toggleCombinedSubDeviceMute(for: "speaker")
        suite.expect(mixer.combinedSubDeviceMutes["speaker"] == true,
                     "toggling mute flips unmuted device to muted")

        mixer.toggleCombinedSubDeviceMute(for: "speaker")
        suite.expect(mixer.combinedSubDeviceMutes["speaker"] == false,
                     "toggling mute again flips muted device to unmuted")

        // Independent per-device state
        mixer.setCombinedSubDeviceVolume(0.8, for: "speaker")
        mixer.setCombinedSubDeviceVolume(0.2, for: "headphones")
        suite.expect(mixer.combinedSubDeviceVolumes["speaker"] == 0.8 &&
                     mixer.combinedSubDeviceVolumes["headphones"] == 0.2,
                     "sub-device volumes are tracked independently")

        mixer.toggleCombinedSubDeviceMute(for: "headphones")
        suite.expect(mixer.combinedSubDeviceMutes["headphones"] == true &&
                     mixer.combinedSubDeviceMutes["speaker"] == false,
                     "sub-device mute states are tracked independently")
    }
}
