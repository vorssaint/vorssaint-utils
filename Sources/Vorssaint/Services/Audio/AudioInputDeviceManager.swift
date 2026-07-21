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
    private var globalListeners: [AudioObjectPropertySelector] = []
    private var applyingPreferred = false
    private var refreshPending = false
    private var lastListenerRefreshAt: CFAbsoluteTime = 0
    /// Same arbitration as the mixer: the device sweep reads the audio HAL off
    /// the main thread, one reader at a time, and a sweep the manager no longer
    /// wants is dropped instead of publishing what it saw.
    private var refresh = MixerRefreshCoordinator()
    /// Every CoreAudio call of a refresh runs here, and every HAL notification
    /// is delivered here. A device being reconfigured can hold a property read
    /// for as long as the audio daemon holds the device, and that is exactly
    /// the moment the listeners fire.
    private let halQueue = DispatchQueue(label: "com.vorssaint.utils.audioinput.hal", qos: .userInitiated)
    /// The system input as it was before this app first pointed it somewhere
    /// else, and the device it was pointed at. Choosing a microphone here
    /// changes a system setting, so switching the feature off or quitting puts
    /// the original back.
    private var inputDeviceBeforeOverride: String?
    private var appliedInputDeviceUID: String?

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
        restoreOriginalInputDevice()
        guard listenerInstalled else { return }
        listenerInstalled = false
        // A sweep already reading the HAL must not publish into a manager that
        // has stopped watching.
        refresh.discardInFlight()
        for selector in globalListeners {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                              &address,
                                              Self.listenerCallback,
                                              listenerClient)
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
        // The choice supersedes a sweep still reading the HAL: that one saw the
        // previous preference and would publish it back for an instant.
        refresh.discardInFlight()
        refreshAndApply()
    }

    /// The smallest possible answer to a change: the system decides which
    /// thread this arrives on, so it only asks the main thread for a refresh
    /// and returns. The reading that follows happens away from the main
    /// thread. Handing a closure back to be removed never matches the one that
    /// was registered, so the plain callback is what makes stopping work.
    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let manager = Unmanaged<AudioInputDeviceManager>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { manager.scheduleListenerRefresh() }
        return noErr
    }

    /// Unretained is safe here and only here: this is a single instance that
    /// lives as long as the app.
    private var listenerClient: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private func installListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                             &address,
                                             Self.listenerCallback,
                                             listenerClient) == noErr else { return }
        globalListeners.append(selector)
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

    /// The main-thread state one sweep needs, copied in.
    private struct RefreshRequest {
        let savedUID: String?
        let inputDeviceBeforeOverride: String?
        let mayApplyPreferred: Bool
    }

    /// Everything one sweep read from the HAL, handed back to the main thread.
    private struct RefreshSnapshot {
        let savedUID: String?
        let currentUID: String?
        let devices: [MixerInputDevice]
        let resolution: MixerInputRouteResolution
        /// Non-nil when this sweep actually pointed the system input at the
        /// preferred device; the write has already happened on the HAL.
        let applied: AppliedInput?
    }

    private struct AppliedInput {
        let device: MixerInputDevice
        let status: OSStatus
        let deviceBeforeOverride: String?
    }

    /// Kicks off one sweep. Reading the devices and pointing the system input
    /// at the preferred one are HAL calls and run on `halQueue`; every
    /// published property is written back on the main thread.
    private func refreshAndApply() {
        // A throttled refresh can land after stop(); watching is over.
        guard listenerInstalled else { return }
        // One reader at a time; a request that arrives meanwhile is remembered
        // and runs with the values the current sweep is about to publish.
        guard let generation = refresh.begin() else { return }
        let request = RefreshRequest(
            savedUID: Defaults.sanitizedPreferredInputDeviceUID(
                UserDefaults.standard.string(forKey: DefaultsKey.preferredInputDevice)),
            inputDeviceBeforeOverride: inputDeviceBeforeOverride,
            mayApplyPreferred: !applyingPreferred)

        halQueue.async { [weak self] in
            let snapshot = Self.readSnapshot(request)
            DispatchQueue.main.async {
                self?.apply(snapshot, generation: generation)
            }
        }
    }

    /// Runs on `halQueue`. Every CoreAudio call of a sweep happens here.
    private static func readSnapshot(_ request: RefreshRequest) -> RefreshSnapshot {
        let savedUID = request.savedUID
        let currentUID = defaultInputDeviceUID()
        let devices = inputDevices(defaultUID: currentUID)
        let availableUIDs = Set(devices.map(\.uid))
        let resolution = MixerRoutingSupport.resolveInputDevice(preferredUID: savedUID,
                                                                availableUIDs: availableUIDs,
                                                                currentUID: currentUID)

        guard resolution.shouldApplyPreferred,
              request.mayApplyPreferred,
              let savedUID,
              let device = devices.first(where: { $0.uid == savedUID }) else {
            return RefreshSnapshot(savedUID: savedUID,
                                   currentUID: currentUID,
                                   devices: devices,
                                   resolution: resolution,
                                   applied: nil)
        }

        // Remembered once, at the first override: what the system had before
        // the app started steering it.
        let before = request.inputDeviceBeforeOverride ?? currentUID
        let status = setDefaultInputDevice(device.audioObjectID)
        return RefreshSnapshot(savedUID: savedUID,
                               currentUID: currentUID,
                               devices: devices,
                               resolution: resolution,
                               applied: AppliedInput(device: device,
                                                     status: status,
                                                     deviceBeforeOverride: before))
    }

    /// Main thread. Publishes one sweep in the same order the synchronous
    /// version used.
    private func apply(_ snapshot: RefreshSnapshot, generation: Int) {
        guard refresh.finish(generation) else {
            // The sweep is stale (the manager stopped, or the preference
            // changed, while it was reading), but a system input change it
            // already made on the HAL still has to be restorable on quit.
            if let applied = snapshot.applied, applied.status == noErr {
                if inputDeviceBeforeOverride == nil {
                    inputDeviceBeforeOverride = applied.deviceBeforeOverride
                }
                appliedInputDeviceUID = applied.device.uid
            }
            return
        }
        let refreshAgain = refresh.takeRepeatRequest()
        guard listenerInstalled else { return }
        defer { if refreshAgain { refreshAndApply() } }

        // Publish only real changes: refreshes run on every CoreAudio
        // notification, and assigning a @Published property signals SwiftUI
        // even when the value is identical — a chatty HAL would otherwise
        // re-render the mixer panel continuously.
        if preferredInputDeviceUID != snapshot.savedUID {
            preferredInputDeviceUID = snapshot.savedUID
        }
        if currentInputDeviceUID != snapshot.currentUID {
            currentInputDeviceUID = snapshot.currentUID
        }
        if effectiveInputDeviceUID != snapshot.resolution.effectiveUID {
            effectiveInputDeviceUID = snapshot.resolution.effectiveUID
        }
        if preferredUnavailable != snapshot.resolution.selectedUnavailable {
            preferredUnavailable = snapshot.resolution.selectedUnavailable
        }
        if inputDevices != snapshot.devices {
            inputDevices = snapshot.devices
        }

        guard let applied = snapshot.applied else { return }
        applyPreferredInputDevice(applied)
    }

    /// Main thread. Records the outcome of a system input change the sweep
    /// already made on the HAL.
    private func applyPreferredInputDevice(_ applied: AppliedInput) {
        applyingPreferred = true
        defer { applyingPreferred = false }

        if inputDeviceBeforeOverride == nil {
            inputDeviceBeforeOverride = applied.deviceBeforeOverride
        }
        let device = applied.device
        guard applied.status == noErr else {
            let message = "OSStatus \(applied.status)"
            if lastError != message {
                lastError = message
            }
            return
        }

        if lastError != nil {
            lastError = nil
        }
        appliedInputDeviceUID = device.uid
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

    /// Hands the system input back the way it was found. Only when the app is
    /// still the last one to have set it: if something else picked a
    /// microphone since, that choice stays.
    ///
    /// Deliberately synchronous on the main thread even though it reads and
    /// writes the HAL: `stop()` runs while the app is quitting, so the system
    /// setting has to go back before the process does.
    private func restoreOriginalInputDevice() {
        guard let originalUID = inputDeviceBeforeOverride,
              let appliedUID = appliedInputDeviceUID else { return }
        inputDeviceBeforeOverride = nil
        appliedInputDeviceUID = nil
        let devices = Self.inputDevices(defaultUID: nil)
        guard let restoredUID = MixerRoutingSupport.restorableInputDeviceUID(
            originalUID: originalUID,
            appliedUID: appliedUID,
            currentUID: Self.defaultInputDeviceUID(),
            availableUIDs: Set(devices.map(\.uid))),
            let device = devices.first(where: { $0.uid == restoredUID }) else { return }
        _ = Self.setDefaultInputDevice(device.audioObjectID)
    }

    private static func setDefaultInputDevice(_ deviceID: AudioObjectID) -> OSStatus {
        var nextDeviceID = deviceID
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                          &address,
                                          0,
                                          nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size),
                                          &nextDeviceID)
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
