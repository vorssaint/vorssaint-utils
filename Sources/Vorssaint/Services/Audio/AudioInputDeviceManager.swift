// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreAudio
import Foundation

struct MixerInputDevice: Identifiable, Equatable {
    let id: String
    let uid: String
    let name: String
    let isDefault: Bool
    fileprivate let audioObjectID: AudioObjectID
}

/// Keeps Vorssaint's preferred microphone in sync with macOS' global input.
/// This is intentionally separate from the per-app output mixer: selecting a
/// microphone changes the system default input, without taps or audio capture.
final class AudioInputDeviceManager: ObservableObject {
    static let shared = AudioInputDeviceManager()

    @Published private(set) var inputDevices: [MixerInputDevice] = []
    @Published private(set) var preferredInputDeviceUID: String?
    @Published private(set) var currentInputDeviceUID: String?
    @Published private(set) var effectiveInputDeviceUID: String?
    @Published private(set) var preferredUnavailable = false
    @Published private(set) var lastError: String?

    private var listenerInstalled = false
    private var applyingPreferred = false

    private init() {}

    func start() {
        guard !listenerInstalled else {
            refreshAndApply()
            return
        }
        listenerInstalled = true
        installListener(selector: kAudioHardwarePropertyDevices)
        installListener(selector: kAudioHardwarePropertyDefaultInputDevice)
        refreshAndApply()
    }

    func setPreferredInputDeviceUID(_ uid: String?) {
        let sanitized = Defaults.sanitizedPreferredInputDeviceUID(uid)
        if let sanitized {
            UserDefaults.standard.set(sanitized, forKey: DefaultsKey.preferredInputDevice)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.preferredInputDevice)
        }
        preferredInputDeviceUID = sanitized
        lastError = nil
        refreshAndApply()
    }

    private func installListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            self?.refreshAndApply()
        }
    }

    private func refreshAndApply() {
        let savedUID = Defaults.sanitizedPreferredInputDeviceUID(
            UserDefaults.standard.string(forKey: DefaultsKey.preferredInputDevice))
        let currentUID = Self.defaultInputDeviceUID()
        let devices = Self.inputDevices(defaultUID: currentUID)
        let availableUIDs = Set(devices.map(\.uid))
        let resolution = MixerRoutingSupport.resolveInputDevice(preferredUID: savedUID,
                                                                availableUIDs: availableUIDs,
                                                                currentUID: currentUID)

        preferredInputDeviceUID = savedUID
        currentInputDeviceUID = currentUID
        effectiveInputDeviceUID = resolution.effectiveUID
        preferredUnavailable = resolution.selectedUnavailable
        inputDevices = devices

        guard resolution.shouldApplyPreferred,
              !applyingPreferred,
              let savedUID,
              let device = devices.first(where: { $0.uid == savedUID }) else { return }
        applyPreferredInputDevice(device)
    }

    private func applyPreferredInputDevice(_ device: MixerInputDevice) {
        applyingPreferred = true
        defer { applyingPreferred = false }

        var nextDeviceID = device.audioObjectID
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address,
                                                0,
                                                nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size),
                                                &nextDeviceID)
        guard status == noErr else {
            lastError = "OSStatus \(status)"
            return
        }

        lastError = nil
        currentInputDeviceUID = device.uid
        effectiveInputDeviceUID = device.uid
        inputDevices = inputDevices.map {
            MixerInputDevice(id: $0.id,
                             uid: $0.uid,
                             name: $0.name,
                             isDefault: $0.uid == device.uid,
                             audioObjectID: $0.audioObjectID)
        }
    }

    private static func inputDevices(defaultUID: String?) -> [MixerInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var deviceIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        var devices: [MixerInputDevice] = []
        for deviceID in deviceIDs {
            guard hasInputStreams(deviceID) else { continue }

            var isAlive: UInt32 = 1
            if read(deviceID, kAudioDevicePropertyDeviceIsAlive, &isAlive), isAlive == 0 {
                continue
            }
            var isHidden: UInt32 = 0
            if read(deviceID, kAudioDevicePropertyIsHidden, &isHidden), isHidden != 0 {
                continue
            }
            var canBeDefault: UInt32 = 1
            if read(deviceID,
                    kAudioDevicePropertyDeviceCanBeDefaultDevice,
                    &canBeDefault,
                    scope: kAudioObjectPropertyScopeInput),
               canBeDefault == 0 {
                continue
            }

            var uidRef: CFString = "" as CFString
            guard read(deviceID, kAudioDevicePropertyDeviceUID, &uidRef) else { continue }
            let uid = uidRef as String
            guard !uid.isEmpty else { continue }

            var nameRef: CFString = "" as CFString
            let name = read(deviceID, kAudioObjectPropertyName, &nameRef)
                ? nameRef as String
                : uid
            guard name != "Vorssaint Mixer" else { continue }

            devices.append(MixerInputDevice(id: uid,
                                            uid: uid,
                                            name: name,
                                            isDefault: uid == defaultUID,
                                            audioObjectID: deviceID))
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func hasInputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= MemoryLayout<AudioObjectID>.size
    }

    private static func defaultInputDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultInputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uidRef: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uidRef) else { return nil }
        return uidRef as String
    }

    @discardableResult
    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }
}
