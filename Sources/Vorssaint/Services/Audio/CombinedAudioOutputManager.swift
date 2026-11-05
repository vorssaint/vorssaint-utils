// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AudioToolbox
import CoreAudio
import Foundation

final class CombinedAudioOutputManager {
    static let shared = CombinedAudioOutputManager()
    static let combinedOutputUID = "com.vorssaint.combined-output"
    static let combinedOutputName = "Combine All Outputs"

    private(set) var activeAggregateID: AudioObjectID = 0

    private init() {}

    static func isCombinedOutputUID(_ uid: String?) -> Bool {
        guard let uid else { return false }
        return uid == combinedOutputUID || uid == MixerRoutingSupport.combineAllOutputsSelectionID
    }

    func createOrUpdateMultiOutputDevice(subDeviceUIDs: [String], masterUID: String? = nil) -> AudioObjectID? {
        var seen = Set<String>()
        var uniqueUIDs: [String] = []
        for uid in subDeviceUIDs where !uid.isEmpty {
            if seen.insert(uid).inserted {
                uniqueUIDs.append(uid)
            }
        }
        guard uniqueUIDs.count >= 2 else { return nil }
        let master = (masterUID != nil && uniqueUIDs.contains(masterUID!)) ? masterUID! : uniqueUIDs[0]

        destroyDevice()

        let subDevices: [[String: Any]] = uniqueUIDs.map { uid in
            [
                kAudioSubDeviceUIDKey: uid,
                kAudioSubDeviceDriftCompensationKey: (uid == master ? 0 : 1)
            ]
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.combinedOutputName,
            kAudioAggregateDeviceUIDKey: Self.combinedOutputUID,
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: master,
            kAudioAggregateDeviceSubDeviceListKey: subDevices
        ]

        var aggregateID: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != 0 else {
            return nil
        }

        self.activeAggregateID = aggregateID
        return aggregateID
    }

    func destroyDevice() {
        if activeAggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(activeAggregateID)
            activeAggregateID = 0
        }
    }
}
