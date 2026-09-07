// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Mutes the current system output only for the lifetime of a dictation
/// recording. It restores the value only when it still owns the mutation, so
/// a volume or mute change made by the user during dictation is never undone.
@MainActor
final class DictationOutputMuteController {
    static let shared = DictationOutputMuteController()

    private enum Restoration {
        case mute(device: AudioDeviceID, original: UInt32)
        case volume(device: AudioDeviceID, original: Float32)
    }

    private var restoration: Restoration?

    private init() {}

    func begin() {
        end()
        guard UserDefaults.standard.bool(forKey: DefaultsKey.dictationMuteOutput),
              let device = Self.defaultOutputDevice() else { return }

        if let currentMute = Self.readUInt32(device,
                                              selector: kAudioDevicePropertyMute) {
            // An already-muted output is not ours to restore and should not
            // be touched through the volume fallback below.
            guard currentMute == 0 else { return }
            if Self.writeUInt32(1, to: device, selector: kAudioDevicePropertyMute) {
                restoration = .mute(device: device, original: currentMute)
                return
            }
        }

        // Some aggregate/Bluetooth devices do not expose a master mute
        // property. A zero-volume fallback still provides the requested
        // privacy and remembers the exact level for restoration.
        if let currentVolume = Self.readFloat32(device,
                                                 selector: kAudioDevicePropertyVolumeScalar),
           currentVolume > 0,
           Self.writeFloat32(0, to: device, selector: kAudioDevicePropertyVolumeScalar) {
            restoration = .volume(device: device, original: currentVolume)
        }
    }

    func end() {
        guard let restoration else { return }
        self.restoration = nil
        switch restoration {
        case let .mute(device, original):
            guard Self.readUInt32(device, selector: kAudioDevicePropertyMute) == 1 else { return }
            _ = Self.writeUInt32(original, to: device, selector: kAudioDevicePropertyMute)
        case let .volume(device, original):
            guard let current = Self.readFloat32(device,
                                                 selector: kAudioDevicePropertyVolumeScalar),
                  current <= 0.0001 else { return }
            _ = Self.writeFloat32(original, to: device,
                                  selector: kAudioDevicePropertyVolumeScalar)
        }
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device: AudioDeviceID = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func address(selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func readUInt32(_ device: AudioDeviceID,
                                   selector: AudioObjectPropertySelector) -> UInt32? {
        var property = address(selector: selector)
        guard AudioObjectHasProperty(device, &property) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func readFloat32(_ device: AudioDeviceID,
                                    selector: AudioObjectPropertySelector) -> Float32? {
        var property = address(selector: selector)
        guard AudioObjectHasProperty(device, &property) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    @discardableResult
    private static func writeUInt32(_ value: UInt32,
                                    to device: AudioDeviceID,
                                    selector: AudioObjectPropertySelector) -> Bool {
        var property = address(selector: selector)
        guard AudioObjectHasProperty(device, &property) else { return false }
        var value = value
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &property, 0, nil, size, &value) == noErr
    }

    @discardableResult
    private static func writeFloat32(_ value: Float32,
                                     to device: AudioDeviceID,
                                     selector: AudioObjectPropertySelector) -> Bool {
        var property = address(selector: selector)
        guard AudioObjectHasProperty(device, &property) else { return false }
        var value = value
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &property, 0, nil, size, &value) == noErr
    }
}
