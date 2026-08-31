// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Hardware-independent microphone data used by routing rules and tests.
struct DictationInputDeviceDescriptor: Equatable {
    let uid: String
    let name: String
    let isDefault: Bool
}

struct DictationInputDevice: Identifiable, Equatable {
    let uid: String
    let name: String
    let isDefault: Bool
    let audioDeviceID: AudioDeviceID

    var id: String { uid }

    var descriptor: DictationInputDeviceDescriptor {
        DictationInputDeviceDescriptor(uid: uid, name: name, isDefault: isDefault)
    }
}

struct DictationInputDeviceSelection: Equatable {
    let preferredUID: String?
    let effectiveUID: String?
    let usedFallback: Bool
}

enum DictationInputDeviceRouting {
    static func resolve(preferredUID: String?,
                        devices: [DictationInputDeviceDescriptor]) -> DictationInputDeviceSelection {
        if let preferredUID,
           devices.contains(where: { $0.uid == preferredUID }) {
            return DictationInputDeviceSelection(preferredUID: preferredUID,
                                                 effectiveUID: preferredUID,
                                                 usedFallback: false)
        }
        guard let fallback = devices.first(where: \.isDefault) else {
            return DictationInputDeviceSelection(preferredUID: preferredUID,
                                                 effectiveUID: nil,
                                                 usedFallback: preferredUID != nil)
        }
        return DictationInputDeviceSelection(preferredUID: preferredUID,
                                             effectiveUID: fallback.uid,
                                             usedFallback: preferredUID != nil)
    }
}

enum DictationInputDeviceCatalog {
    static func availableDevices() -> [DictationInputDevice] {
        let defaultID = defaultInputDeviceID()
        let devices = allDeviceIDs().compactMap { deviceID -> DictationInputDevice? in
            guard hasInputStreams(deviceID), isAlive(deviceID), !isHidden(deviceID),
                  let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
                  !uid.isEmpty else { return nil }
            let name = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceNameCFString) ?? uid
            return DictationInputDevice(uid: uid,
                                        name: name,
                                        isDefault: deviceID == defaultID,
                                        audioDeviceID: deviceID)
        }
        return devices.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func selection(preferredUID: String?) -> (selection: DictationInputDeviceSelection,
                                                      device: DictationInputDevice?) {
        let devices = availableDevices()
        let resolution = DictationInputDeviceRouting.resolve(
            preferredUID: preferredUID,
            devices: devices.map(\.descriptor))
        let device = resolution.effectiveUID.flatMap { uid in devices.first { $0.uid == uid } }
        return (resolution, device)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0,
                                  count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var id: AudioDeviceID = 0
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultInputDevice, &id), id != 0 else { return nil }
        return id
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return false }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, list) == noErr else {
            return false
        }
        return UnsafeMutableAudioBufferListPointer(list).contains { $0.mNumberChannels > 0 }
    }

    private static func isAlive(_ deviceID: AudioDeviceID) -> Bool {
        var alive: UInt32 = 1
        return read(deviceID, kAudioDevicePropertyDeviceIsAlive, &alive) && alive != 0
    }

    private static func isHidden(_ deviceID: AudioDeviceID) -> Bool {
        var hidden: UInt32 = 0
        return read(deviceID, kAudioDevicePropertyIsHidden, &hidden) && hidden != 0
    }

    private static func stringProperty(_ deviceID: AudioDeviceID,
                                       selector: AudioObjectPropertySelector) -> String? {
        var value: CFString = "" as CFString
        guard read(deviceID, selector, &value) else { return nil }
        return value as String
    }

    @discardableResult
    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }
}
