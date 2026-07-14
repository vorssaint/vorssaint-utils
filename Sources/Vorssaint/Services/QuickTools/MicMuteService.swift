// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import Foundation

/// Global microphone mute: one click or shortcut cuts the default input, in
/// any app. Uses the device's own mute switch when it has one, else drops the
/// input volume to zero and restores the saved level on unmute. The muted
/// state is reapplied when the default input device changes (a hot-plugged
/// headset must not silently unmute a call), and it survives app relaunches
/// via the persisted flag.
final class MicMuteService: ObservableObject {
    static let shared = MicMuteService()

    @Published private(set) var isMuted = false
    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 12)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let available = AppFeature.micMute.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.micMuteShortcut,
                                            fallback: .micMuteDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)

        let wantsMute = UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive)
        if available {
            if wantsMute {
                applyMute(true)
            }
            isMuted = wantsMute
        } else {
            // Switching the feature off must not strand a muted microphone
            // with no control left to unmute it.
            if wantsMute {
                applyMute(false)
                UserDefaults.standard.set(false, forKey: DefaultsKey.micMuteActive)
            }
            isMuted = false
        }
        syncDefaultDeviceListener()
    }

    /// The listener only exists to re-assert an active mute when the default
    /// input device changes, so it lives exactly as long as the mute does.
    private func syncDefaultDeviceListener() {
        if isMuted {
            installDefaultDeviceListenerIfNeeded()
        } else {
            removeDefaultDeviceListener()
        }
    }

    func suspend() {
        hotkey.unregister()
    }

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard applyMute(muted) else { return }
        isMuted = muted
        UserDefaults.standard.set(muted, forKey: DefaultsKey.micMuteActive)
        syncDefaultDeviceListener()
        QuickToolHUD.show(icon: muted ? "mic.slash.fill" : "mic.fill",
                          message: muted ? L10n.shared.s.micMutedHUD : L10n.shared.s.micUnmutedHUD)
    }

    /// Silently re-asserts the persisted state; used when the default input
    /// device changes underneath us.
    private func reapplyIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive) else { return }
        _ = applyMute(true)
    }

    // MARK: - CoreAudio

    @discardableResult
    private func applyMute(_ muted: Bool) -> Bool {
        guard let device = Self.defaultInputDevice() else { return false }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable = DarwinBoolean(false)
        if AudioObjectHasProperty(device, &muteAddress),
           AudioObjectIsPropertySettable(device, &muteAddress, &settable) == noErr,
           settable.boolValue {
            var value: UInt32 = muted ? 1 : 0
            let status = AudioObjectSetPropertyData(device, &muteAddress, 0, nil,
                                                    UInt32(MemoryLayout<UInt32>.size), &value)
            if status == noErr { return true }
        }

        // No mute switch: use the input volume, remembering the level.
        if muted {
            if let volume = Self.inputVolume(of: device), volume > 0.01 {
                UserDefaults.standard.set(Double(volume), forKey: DefaultsKey.micMuteSavedVolume)
            }
            return Self.setInputVolume(0, of: device)
        }
        let saved = UserDefaults.standard.double(forKey: DefaultsKey.micMuteSavedVolume)
        let restore = Float(saved > 0.01 ? saved : 0.75)
        return Self.setInputVolume(restore, of: device)
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
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

    private static func setInputVolume(_ volume: Float, of device: AudioDeviceID) -> Bool {
        var applied = false
        for var address in volumeAddresses() where AudioObjectHasProperty(device, &address) {
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value = volume
            if AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<Float>.size), &value) == noErr {
                applied = true
            }
        }
        return applied
    }

    private func installDefaultDeviceListenerIfNeeded() {
        guard defaultDeviceListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.reapplyIfNeeded() }
        }
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                         &address, DispatchQueue.main, listener)
        if status == noErr {
            defaultDeviceListener = listener
        }
    }

    private func removeDefaultDeviceListener() {
        guard let listener = defaultDeviceListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, DispatchQueue.main, listener)
        defaultDeviceListener = nil
    }
}
