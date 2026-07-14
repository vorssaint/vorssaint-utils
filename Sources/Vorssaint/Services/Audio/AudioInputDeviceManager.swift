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
    /// Stored so stop() can remove the HAL listeners when the mixer leaves
    /// the hub.
    private var globalListeners: [(selector: AudioObjectPropertySelector, block: AudioObjectPropertyListenerBlock)] = []
    private var applyingPreferred = false
    private var refreshPending = false
    private var lastListenerRefreshAt: CFAbsoluteTime = 0

    private init() {}

    /// The microphone selector lives in the mixer panel section, so it
    /// follows the mixer's hub availability.
    func syncWithPreferences() {
        if AppFeature.mixer.isAvailable {
            start()
        } else {
            stop()
        }
    }

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

    func stop() {
        guard listenerInstalled else { return }
        listenerInstalled = false
        for entry in globalListeners {
            var address = AudioObjectPropertyAddress(mSelector: entry.selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                   &address, .main, entry.block)
        }
        globalListeners.removeAll()
        if !inputDevices.isEmpty { inputDevices = [] }
        if preferredUnavailable { preferredUnavailable = false }
        if lastError != nil { lastError = nil }
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
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleListenerRefresh()
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        globalListeners.append((selector, block))
    }

    /// Same coalescing as AppVolumeMixer.scheduleListenerRefresh: one hardware
    /// event fires both listeners back-to-back, and a busy audio HAL keeps the
    /// stream going. Isolated notifications refresh immediately; bursts fold
    /// into a single trailing refresh.
    private func scheduleListenerRefresh() {
        guard !refreshPending else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastListenerRefreshAt
        if elapsed >= Self.listenerRefreshInterval {
            lastListenerRefreshAt = now
            refreshAndApply()
            return
        }
        refreshPending = true
        let delay = Self.listenerRefreshInterval - elapsed
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.lastListenerRefreshAt = CFAbsoluteTimeGetCurrent()
            self.refreshAndApply()
        }
    }

    private static let listenerRefreshInterval: CFAbsoluteTime = 0.2

    private func refreshAndApply() {
        // A throttled refresh can land after stop(); watching is over.
        guard listenerInstalled else { return }
        let savedUID = Defaults.sanitizedPreferredInputDeviceUID(
            UserDefaults.standard.string(forKey: DefaultsKey.preferredInputDevice))
        let currentUID = Self.defaultInputDeviceUID()
        let devices = Self.inputDevices(defaultUID: currentUID)
        let availableUIDs = Set(devices.map(\.uid))
        let resolution = MixerRoutingSupport.resolveInputDevice(preferredUID: savedUID,
                                                                availableUIDs: availableUIDs,
                                                                currentUID: currentUID)

        // Publish only real changes: refreshes run on every CoreAudio
        // notification, and assigning a @Published property signals SwiftUI
        // even when the value is identical — a chatty HAL would otherwise
        // re-render the mixer panel continuously.
        if preferredInputDeviceUID != savedUID {
            preferredInputDeviceUID = savedUID
        }
        if currentInputDeviceUID != currentUID {
            currentInputDeviceUID = currentUID
        }
        if effectiveInputDeviceUID != resolution.effectiveUID {
            effectiveInputDeviceUID = resolution.effectiveUID
        }
        if preferredUnavailable != resolution.selectedUnavailable {
            preferredUnavailable = resolution.selectedUnavailable
        }
        if inputDevices != devices {
            inputDevices = devices
        }

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
            let message = "OSStatus \(status)"
            if lastError != message {
                lastError = message
            }
            return
        }

        if lastError != nil {
            lastError = nil
        }
        if currentInputDeviceUID != device.uid {
            currentInputDeviceUID = device.uid
        }
        if effectiveInputDeviceUID != device.uid {
            effectiveInputDeviceUID = device.uid
        }
        let updated = inputDevices.map {
            MixerInputDevice(id: $0.id,
                             uid: $0.uid,
                             name: $0.name,
                             isDefault: $0.uid == device.uid,
                             audioObjectID: $0.audioObjectID)
        }
        if inputDevices != updated {
            inputDevices = updated
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
            MixerRoutingSupport.deviceDisplayOrderedBefore(
                isDefault: lhs.isDefault, name: lhs.name, uid: lhs.uid,
                otherIsDefault: rhs.isDefault, otherName: rhs.name, otherUID: rhs.uid)
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
