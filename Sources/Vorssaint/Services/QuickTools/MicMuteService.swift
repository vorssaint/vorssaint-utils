// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import Foundation

/// Global microphone mute: one click or shortcut cuts every microphone the Mac
/// has, in any app. Muting only the system default is not enough, because an
/// app can be pointed at a device of its own (a headset picked inside a call
/// app keeps recording while the Mac's default sits muted), so the mute is
/// applied device by device. Each device uses its own mute switch when it has
/// one, else its input volume drops to zero and the saved level comes back on
/// unmute. A device that arrives while muted is muted as it appears, the mute
/// is re-asserted when the default input changes, and the state survives app
/// relaunches via the persisted flag. A device this app silenced stays its to
/// release even while unplugged: it gets its level back when it returns.
final class MicMuteService: ObservableObject {
    static let shared = MicMuteService()

    @Published private(set) var isMuted = false
    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 12)
    private var installedListeners: [AudioObjectPropertySelector] = []
    /// Reading or writing a device property can block for as long as the audio
    /// daemon holds the device (a headset connecting, an interface waking),
    /// and that is exactly the moment the listeners fire. Sweeping every
    /// device on the main thread would hand the app one hang per reconnection,
    /// so all of it happens here, one sweep at a time.
    private let halQueue = DispatchQueue(label: "com.vorssaint.utils.micmute.hal", qos: .userInitiated)
    /// A sweep that finished after a newer one started must not publish what
    /// it saw.
    private var applyGeneration = 0
    /// What the last request asked for, kept from the moment it is queued.
    /// `isMuted` and the persisted flag only follow once the sweep has
    /// published, so a device change or a preference sync that lands while a
    /// sweep is still running must re-assert the request in flight, never the
    /// state it is replacing: read from the flag, a mute still being applied
    /// looked like "unmuted, with claims to release" and was silently undone.
    private var wantsMute = UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive)
    private let inputVolumeLock = NSLock()
    private var inputVolumeBlocked = false
    private var inputVolumeLifetime = UUID()

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    /// The smallest possible answer to a change: the system decides which
    /// thread this arrives on, so it only asks the main thread to re-assert
    /// the mute and returns. Handing a closure back to be removed never
    /// matches the one that was registered, so the plain callback is what
    /// makes stopping work.
    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let service = Unmanaged<MicMuteService>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { service.reapplyIfNeeded() }
        return noErr
    }

    /// Unretained is safe here and only here: this is a single instance that
    /// lives as long as the app.
    private var listenerClient: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    func syncWithPreferences() {
        let available = AppFeature.micMute.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.micMuteShortcut,
                                            fallback: .micMuteDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.micMuteShortcut)

        if available {
            if wantsMute {
                apply(muted: true, announce: false)
            } else if hasOutstandingClaims {
                // A device this app silenced and never got to release: it
                // was away at the unmute, or the app went down. Its level
                // comes back now if it is here, else when it returns.
                apply(muted: false, announce: false)
            }
            isMuted = wantsMute
        } else {
            // Switching the feature off must not strand a muted microphone
            // with no control left to unmute it.
            if wantsMute || hasOutstandingClaims {
                apply(muted: false, announce: false)
                UserDefaults.standard.set(false, forKey: DefaultsKey.micMuteActive)
            }
            isMuted = false
        }
        syncListeners()
    }

    /// The listeners exist to keep an active mute true while devices come and
    /// go, and to catch a claimed device coming back so it can be released;
    /// they live only as long as one of those is pending.
    private func syncListeners() {
        if isMuted || (AppFeature.micMute.isAvailable && hasOutstandingClaims) {
            installListeners()
        } else {
            removeListeners()
        }
    }

    /// Devices this app silenced and has not yet put back, present or not.
    private var hasOutstandingClaims: Bool {
        !(UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []).isEmpty
    }

    func suspend() {
        hotkey.unregister()
    }

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        apply(muted: muted, announce: true)
    }

    var inputVolumeAdjustmentLifetime: UUID? {
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive) else { return nil }
        return inputVolumeLock.withLock { inputVolumeBlocked ? nil : inputVolumeLifetime }
    }

    /// Called from the input manager's audio queue, never the main thread.
    /// Sharing the mute queue prevents an older gain write from reopening a
    /// microphone after the mute sweep has already silenced it.
    func withUnmutedInput(lifetime: UUID, _ adjustment: () -> Void) {
        halQueue.sync {
            guard inputVolumeAdjustmentLifetime == lifetime else { return }
            adjustment()
        }
    }

    /// Unmute for a caller that is about to tear the app down. The queue that
    /// carries a normal sweep may never be drained once the app is going away,
    /// and a microphone left cut by an app that no longer exists is the one
    /// failure this feature cannot afford, so this one waits.
    func unmuteForTeardown() {
        let defaults = UserDefaults.standard
        // A mute still being applied has not reached the flag yet, and a claim
        // is a device this app owes its level back whatever the flag says.
        guard wantsMute || defaults.bool(forKey: DefaultsKey.micMuteActive) || hasOutstandingClaims else { return }
        // Any sweep still in flight loses its right to publish, and this one
        // runs behind it on the same serial queue.
        applyGeneration += 1
        wantsMute = false
        _ = halQueue.sync { Self.sweep(muted: false) }
        defaults.set(false, forKey: DefaultsKey.micMuteActive)
        isMuted = false
        inputVolumeLock.withLock {
            inputVolumeBlocked = false
            inputVolumeLifetime = UUID()
        }
        removeListeners()
    }

    /// Silently re-asserts the wanted state; used when the set of input
    /// devices, or the default one, changes underneath us. Unmuted, the same
    /// change is the moment a device this app still has to release may have
    /// come back.
    private func reapplyIfNeeded() {
        if wantsMute {
            apply(muted: true, announce: false)
        } else if hasOutstandingClaims {
            apply(muted: false, announce: false)
        }
    }

    // MARK: - Applying

    /// Hands the sweep to the audio queue and keeps the published state, the
    /// wanted state and the HUD on the main thread, where they belong.
    private func apply(muted: Bool, announce: Bool) {
        wantsMute = muted
        inputVolumeLock.withLock {
            inputVolumeBlocked = muted
            inputVolumeLifetime = UUID()
        }
        applyGeneration += 1
        let generation = applyGeneration
        halQueue.async { [weak self] in
            let outcome = Self.sweep(muted: muted)
            DispatchQueue.main.async {
                self?.finish(outcome, muted: muted, announce: announce, generation: generation)
            }
        }
    }

    /// Runs on `halQueue`. The record of what this app silenced is read here
    /// and written back here, so every sweep starts from what the one before
    /// it recorded. Two sweeps back to back are the normal case, not the
    /// exception: one headset connecting fires both listeners, and a quick
    /// double press queues two. Read on the main thread when each was asked
    /// for, both would start from the same record; the second would then find
    /// the devices the first had just silenced already quiet and unclaimed,
    /// leave them to "the user", and the unmute would never release them.
    private static func sweep(muted: Bool) -> MuteOutcome {
        let defaults = UserDefaults.standard
        let outcome = applyToDevices(
            muted: muted,
            savedVolumes: defaults.dictionary(forKey: DefaultsKey.micMuteSavedVolumes) as? [String: Double] ?? [:],
            savedChannelVolumes: defaults.dictionary(forKey: DefaultsKey.micMuteSavedChannelVolumes)
                as? [String: [String: Double]] ?? [:],
            // Missing means never tracked; an empty list means tracked and
            // owning nothing, and the sweep must keep those two apart.
            mutedDevices: defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices),
            legacyVolume: defaults.double(forKey: DefaultsKey.micMuteSavedVolume))
        // A sweep that reached nothing leaves the record alone: it is what a
        // later unmute needs to put every level back.
        if outcome.applied {
            defaults.set(outcome.savedVolumes, forKey: DefaultsKey.micMuteSavedVolumes)
            defaults.set(outcome.savedChannelVolumes, forKey: DefaultsKey.micMuteSavedChannelVolumes)
            defaults.set(outcome.mutedDevices, forKey: DefaultsKey.micMuteMutedDevices)
        }
        return outcome
    }

    /// Main thread. Publishes one sweep.
    private func finish(_ outcome: MuteOutcome, muted: Bool, announce: Bool, generation: Int) {
        guard generation == applyGeneration else { return }
        guard outcome.applied else {
            // Nothing was reached, so the request is dropped as it always was:
            // the published state stays what it is, and so does the wanted one.
            wantsMute = isMuted
            inputVolumeLock.withLock { inputVolumeBlocked = isMuted }
            return
        }
        if isMuted != muted { isMuted = muted }
        UserDefaults.standard.set(muted, forKey: DefaultsKey.micMuteActive)
        syncListeners()
        guard announce else { return }
        if outcome.failed {
            QuickToolHUD.show(icon: "exclamationmark.triangle",
                              message: muted ? L10n.shared.s.micMutePartialHUD : L10n.shared.s.micUnmutePartialHUD)
            return
        }
        QuickToolHUD.show(icon: muted ? "mic.slash.fill" : "mic.fill",
                          message: muted ? L10n.shared.s.micMutedHUD : L10n.shared.s.micUnmutedHUD)
    }

    // MARK: - CoreAudio

    private struct InputDevice {
        let id: AudioDeviceID
        let uid: String
    }

    private struct MuteOutcome {
        var applied: Bool
        var savedVolumes: [String: Double]
        /// Channel levels by device and element, so an unmute puts back the
        /// balance between channels instead of one level everywhere.
        var savedChannelVolumes: [String: [String: Double]]
        var mutedDevices: [String]
        /// A device this sweep had to reach and could not, next to ones it did.
        var failed = false
    }

    /// Runs on `halQueue`. Every CoreAudio call of a sweep happens here.
    private static func applyToDevices(muted: Bool,
                                       savedVolumes: [String: Double],
                                       savedChannelVolumes: [String: [String: Double]],
                                       mutedDevices: [String]?,
                                       legacyVolume: Double) -> MuteOutcome {
        let devices = inputDevices()
        guard !devices.isEmpty else {
            // Nothing to silence. An unmute has still done its job, and keeps
            // its claims for the devices that are away.
            return MuteOutcome(applied: !muted, savedVolumes: savedVolumes,
                               savedChannelVolumes: savedChannelVolumes, mutedDevices: mutedDevices ?? [])
        }
        return muted
            ? mute(devices, savedVolumes: savedVolumes, savedChannelVolumes: savedChannelVolumes,
                   mutedDevices: mutedDevices)
            : unmute(devices, savedVolumes: savedVolumes, savedChannelVolumes: savedChannelVolumes,
                     mutedDevices: mutedDevices, legacyVolume: legacyVolume)
    }

    private static func mute(_ devices: [InputDevice],
                             savedVolumes: [String: Double],
                             savedChannelVolumes: [String: [String: Double]],
                             mutedDevices: [String]?) -> MuteOutcome {
        var outcome = MuteOutcome(applied: false,
                                  savedVolumes: savedVolumes,
                                  savedChannelVolumes: savedChannelVolumes,
                                  mutedDevices: MicMuteSupport.absentClaims(recorded: mutedDevices,
                                                                            present: devices.map(\.uid)))
        let owned = Set(mutedDevices ?? [])
        for device in devices {
            // Already silent: a microphone the user muted themselves is left
            // alone, so unmuting later never opens something this app did not
            // close. One this app already muted keeps its owner.
            if isSilenced(device.id) {
                outcome.applied = true
                if owned.contains(device.uid) { outcome.mutedDevices.append(device.uid) }
                continue
            }
            if setMuteSwitch(true, of: device.id) {
                outcome.applied = true
                outcome.mutedDevices.append(device.uid)
                continue
            }
            // No mute switch, or a device that keeps its own: use the input
            // volume, remembering the level.
            let volume = inputVolume(of: device.id)
            if MicMuteSupport.shouldSaveVolume(volume), let volume {
                outcome.savedVolumes[device.uid] = Double(volume)
            }
            let channels = channelVolumes(of: device.id)
            if !channels.isEmpty { outcome.savedChannelVolumes[device.uid] = channels }
            // Claimed only when the device really went quiet: a driver that
            // takes the write and keeps its level must not be recorded as
            // muted, or the unmute would raise a microphone it never lowered.
            if setInputVolume(0, of: device.id), isSilenced(device.id) {
                outcome.applied = true
                outcome.mutedDevices.append(device.uid)
            } else {
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                // Only a microphone some app records from is left open. An aggregate
                // has no switch or level of its own; the microphones under it are
                // swept and reported on their own.
                var transport: UInt32 = 0
                var running: UInt32 = 0
                read(device.id, kAudioDevicePropertyTransportType, &transport)
                read(device.id, kAudioDevicePropertyDeviceIsRunningSomewhere, &running)
                if transport != kAudioDeviceTransportTypeAggregate, running != 0 { outcome.failed = true }
            }
        }
        return outcome
    }

    private static func unmute(_ devices: [InputDevice],
                               savedVolumes: [String: Double],
                               savedChannelVolumes: [String: [String: Double]],
                               mutedDevices: [String]?,
                               legacyVolume: Double) -> MuteOutcome {
        let present = devices.map(\.uid)
        var outcome = MuteOutcome(applied: false,
                                  savedVolumes: savedVolumes,
                                  savedChannelVolumes: savedChannelVolumes,
                                  mutedDevices: MicMuteSupport.absentClaims(recorded: mutedDevices,
                                                                            present: present))
        let targets = Set(MicMuteSupport.restoreTargets(recorded: mutedDevices, present: present))
        var attempted = false
        for device in devices where targets.contains(device.uid) {
            // A saved level only leaves once the device really opened: a
            // restore that failed keeps the claim and the level, so the next
            // attempt still knows the device is this app's to release.
            if muteSwitchValue(of: device.id) == 1 {
                attempted = true
                if setMuteSwitch(false, of: device.id) {
                    outcome.applied = true
                    outcome.savedVolumes.removeValue(forKey: device.uid)
                    outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                } else {
                    outcome.mutedDevices.append(device.uid)
                    outcome.failed = true
                }
                continue
            }
            guard let volume = inputVolume(of: device.id) else {
                // Unreadable right now (a headset mid reconnection): nothing
                // was restored, so the claim and the level survive.
                outcome.mutedDevices.append(device.uid)
                continue
            }
            guard volume <= 0.01 else {
                // Already audible: the level has nothing left to restore.
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                continue
            }
            attempted = true
            let restore = MicMuteSupport.volumeToRestore(uid: device.uid,
                                                         saved: savedVolumes,
                                                         legacy: legacyVolume)
            // A channel with no level of its own, as after a mute from before
            // channels were saved, takes the main level back.
            if setInputVolume(restore, of: device.id, channels: savedChannelVolumes[device.uid] ?? [:]) {
                outcome.applied = true
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
            } else {
                outcome.mutedDevices.append(device.uid)
                outcome.failed = true
            }
        }
        // Nothing left silenced is a finished unmute; the user must never be
        // left holding a mute the app refuses to release.
        if !attempted { outcome.applied = true }
        return outcome
    }

    /// True when no audio can come out of the device right now.
    private static func isSilenced(_ device: AudioDeviceID) -> Bool {
        if muteSwitchValue(of: device) == 1 { return true }
        guard let volume = inputVolume(of: device) else { return false }
        return volume <= 0.01
    }

    /// Every device that can capture audio, skipping the app's own mixing
    /// device and the ones the system is not really offering.
    private static func inputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        var devices: [InputDevice] = []
        for deviceID in deviceIDs {
            guard hasInputStreams(deviceID) else { continue }

            var isAlive: UInt32 = 1
            if read(deviceID, kAudioDevicePropertyDeviceIsAlive, &isAlive), isAlive == 0 { continue }

            var uidRef: CFString = "" as CFString
            guard read(deviceID, kAudioDevicePropertyDeviceUID, &uidRef) else { continue }
            let uid = uidRef as String
            guard !uid.isEmpty else { continue }

            var nameRef: CFString = "" as CFString
            let name = read(deviceID, kAudioObjectPropertyName, &nameRef) ? nameRef as String : uid
            guard !MicMuteSupport.isOwnDevice(name: name) else { continue }

            devices.append(InputDevice(id: deviceID, uid: uid))
        }
        return devices
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= MemoryLayout<AudioObjectID>.size
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func muteSwitchValue(of device: AudioDeviceID) -> UInt32? {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// The device's own mute switch, when it has one that can be written. Some
    /// drivers answer a write with success and keep their own value, so the
    /// switch only counts when the device reads back the way it was asked to;
    /// otherwise the caller still has the volume to fall back on.
    private static func setMuteSwitch(_ muted: Bool, of device: AudioDeviceID) -> Bool {
        var address = muteAddress()
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        guard AudioObjectSetPropertyData(device, &address, 0, nil,
                                         UInt32(MemoryLayout<UInt32>.size), &value) == noErr else { return false }
        guard let readBack = muteSwitchValue(of: device) else { return true }
        return readBack == value
    }

    private static func volumeAddresses() -> [AudioObjectPropertyAddress] {
        // Main element first; devices without a master volume expose the
        // channels individually.
        [kAudioObjectPropertyElementMain, 1, 2].map { element in
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: element)
        }
    }

    private static func inputVolume(of device: AudioDeviceID) -> Float? {
        for var address in volumeAddresses() where AudioObjectHasProperty(device, &address) {
            var volume = Float(0)
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }
        return nil
    }

    /// Channels 1 and 2 as levels of their own, keyed by element. A mute
    /// lowers them with the main level, and an unmute that wrote the main
    /// level into every channel would flatten the balance between them.
    private static func channelVolumes(of device: AudioDeviceID) -> [String: Double] {
        var levels: [String: Double] = [:]
        for var address in volumeAddresses() where address.mElement != kAudioObjectPropertyElementMain
            && AudioObjectHasProperty(device, &address) {
            var volume = Float(0)
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr,
               MicMuteSupport.shouldSaveVolume(volume) {
                levels[String(address.mElement)] = Double(volume)
            }
        }
        return levels
    }

    /// Writes the main level and channels 1 and 2, each channel taking its
    /// own entry in `channels` when there is one.
    private static func setInputVolume(_ volume: Float, of device: AudioDeviceID,
                                       channels: [String: Double] = [:]) -> Bool {
        var applied = false
        for var address in volumeAddresses() where AudioObjectHasProperty(device, &address) {
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value = channels[String(address.mElement)].map(Float.init) ?? volume
            if AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<Float>.size), &value) == noErr {
                applied = true
            }
        }
        return applied
    }

    @discardableResult
    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    // MARK: - Listeners

    /// Two changes can defeat an active mute: a device arriving (a headset
    /// connecting mid call) and the default input moving. Both re-assert it,
    /// and both are how a device still owed its level back announces itself.
    private static let watchedSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultInputDevice,
    ]

    private func installListeners() {
        for selector in Self.watchedSelectors where !installedListeners.contains(selector) {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let status = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                                        &address, Self.listenerCallback,
                                                        listenerClient)
            if status == noErr {
                installedListeners.append(selector)
            }
        }
    }

    private func removeListeners() {
        for selector in installedListeners {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                              &address, Self.listenerCallback,
                                              listenerClient)
        }
        installedListeners.removeAll()
    }
}
