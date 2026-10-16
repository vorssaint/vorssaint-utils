// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Whether another process is recording from any input. Per process, so a
/// headset that is only playing audio does not count.
enum AudioInputActivity {
    static func anyOtherProcessCapturing(excluding ownPID: pid_t = getpid()) -> Bool {
        processObjects().contains { process in
            readUInt32(process, kAudioProcessPropertyIsRunningInput) != 0 && pid(of: process) != ownPID
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func readUInt32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func pid(of id: AudioObjectID) -> pid_t {
        var addr = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : 0
    }
}
