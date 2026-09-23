// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Automatically selects the highest-priority connected audio device.
///
/// Maintains independent ordered lists for system outputs and microphones.
/// When a higher-priority device connects, it becomes active. When the active
/// device disconnects, the next available prioritized device takes over. When
/// no prioritized device is available, the current macOS selection is left
/// alone.
///
/// The feature has its own enable flags for output and input, so one can be
/// automated while the other stays under manual control. It reuses the
/// device enumeration and default-device writes owned by `AppVolumeMixer` and
/// `AudioInputDeviceManager` without starting per-app process taps or audio
/// capture.
final class AudioPriorityService: ObservableObject {
    static let shared = AudioPriorityService()

    @Published private(set) var outputPriorityEnabled = false
    @Published private(set) var inputPriorityEnabled = false
    @Published private(set) var outputPriorityUIDs: [String] = []
    @Published private(set) var inputPriorityUIDs: [String] = []
    @Published private(set) var deviceNames: [String: String] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var enforceDebounce: DispatchWorkItem?
    private var settledOutputUIDs: Set<String>?
    private var settledInputUIDs: Set<String>?
    private var pendingOutputUIDs: Set<String>?
    private var pendingInputUIDs: Set<String>?
    private var pendingOutputPreferenceChange = false
    private var pendingInputPreferenceChange = false
    private var started = false

    private init() {}

    // MARK: - Lifecycle

    func syncWithPreferences() {
        if AppFeature.audioPriority.isAvailable {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !started else {
            loadPreferences()
            AudioInputDeviceManager.shared.setInputPriorityActive(inputPriorityEnabled)
            mergeAvailableDevicesIntoPriorityLists()
            updateDeviceNames()
            return
        }
        started = true
        loadPreferences()
        AudioInputDeviceManager.shared.setInputPriorityActive(inputPriorityEnabled)

        // The published device models also change when only the default flag
        // changes. Compare eligible UID sets so a manual selection anywhere
        // remains in effect until hardware changes or the user edits priority.
        AppVolumeMixer.shared.$outputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.observeOutputDevices($0) }
            .store(in: &cancellables)

        AudioInputDeviceManager.shared.$inputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.observeInputDevices($0) }
            .store(in: &cancellables)

        mergeAvailableDevicesIntoPriorityLists()
        updateDeviceNames()
    }

    func stop() {
        started = false
        cancellables.removeAll()
        enforceDebounce?.cancel()
        enforceDebounce = nil
        settledOutputUIDs = nil
        settledInputUIDs = nil
        pendingOutputUIDs = nil
        pendingInputUIDs = nil
        pendingOutputPreferenceChange = false
        pendingInputPreferenceChange = false
        if outputPriorityEnabled { outputPriorityEnabled = false }
        if inputPriorityEnabled { inputPriorityEnabled = false }
        AudioInputDeviceManager.shared.setInputPriorityActive(false)
    }

    // MARK: - Preference loading

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        outputPriorityEnabled = defaults.bool(forKey: DefaultsKey.audioPriorityOutputEnabled)
        inputPriorityEnabled = defaults.bool(forKey: DefaultsKey.audioPriorityInputEnabled)
        outputPriorityUIDs = Defaults.sanitizedAudioPriorityUIDs(
            defaults.array(forKey: DefaultsKey.audioPriorityOutputUIDs) ?? [])
        inputPriorityUIDs = Defaults.sanitizedAudioPriorityUIDs(
            defaults.array(forKey: DefaultsKey.audioPriorityInputUIDs) ?? [])
        deviceNames = Defaults.sanitizedAudioPriorityDeviceNames(
            defaults.dictionary(forKey: DefaultsKey.audioPriorityDeviceNames) ?? [:])
    }

    // MARK: - Public API (UI)

    func setOutputPriorityEnabled(_ enabled: Bool) {
        let becameEnabled = enabled && !outputPriorityEnabled
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: DefaultsKey.audioPriorityOutputEnabled)
        outputPriorityEnabled = enabled
        mergeAvailableDevicesIntoPriorityLists()
        updateDeviceNames()
        if becameEnabled {
            pendingOutputPreferenceChange = true
            scheduleEnforcement()
        }
    }

    func setInputPriorityEnabled(_ enabled: Bool) {
        let becameEnabled = enabled && !inputPriorityEnabled
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: DefaultsKey.audioPriorityInputEnabled)
        inputPriorityEnabled = enabled
        AudioInputDeviceManager.shared.setInputPriorityActive(enabled)
        mergeAvailableDevicesIntoPriorityLists()
        updateDeviceNames()
        if becameEnabled {
            pendingInputPreferenceChange = true
            scheduleEnforcement()
        }
    }

    func setOutputPriorityUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedAudioPriorityUIDs(uids)
        guard sanitized != outputPriorityUIDs else { return }
        let defaults = UserDefaults.standard
        if sanitized.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.audioPriorityOutputUIDs)
        } else {
            defaults.set(sanitized, forKey: DefaultsKey.audioPriorityOutputUIDs)
        }
        outputPriorityUIDs = sanitized
        updateDeviceNames()
        if outputPriorityEnabled {
            pendingOutputPreferenceChange = true
            scheduleEnforcement()
        }
    }

    func setInputPriorityUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedAudioPriorityUIDs(uids)
        guard sanitized != inputPriorityUIDs else { return }
        let defaults = UserDefaults.standard
        if sanitized.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.audioPriorityInputUIDs)
        } else {
            defaults.set(sanitized, forKey: DefaultsKey.audioPriorityInputUIDs)
        }
        inputPriorityUIDs = sanitized
        updateDeviceNames()
        if inputPriorityEnabled {
            pendingInputPreferenceChange = true
            scheduleEnforcement()
        }
    }

    // MARK: - Device name tracking

    /// Updates the stored last-known-name map for UIDs that are currently in a
    /// priority list, using the names observed by the shared device services.
    private func updateDeviceNames() {
        let allPriorityUIDs = Set(outputPriorityUIDs + inputPriorityUIDs)
        guard !allPriorityUIDs.isEmpty else {
            if !deviceNames.isEmpty {
                deviceNames = [:]
                UserDefaults.standard.removeObject(forKey: DefaultsKey.audioPriorityDeviceNames)
            }
            return
        }
        var names = deviceNames
        for device in AppVolumeMixer.shared.outputDevices where allPriorityUIDs.contains(device.uid) {
            names[device.uid] = device.name
        }
        for device in AudioInputDeviceManager.shared.inputDevices where allPriorityUIDs.contains(device.uid) {
            names[device.uid] = device.name
        }
        // Prune entries no longer in any list.
        names = names.filter { allPriorityUIDs.contains($0.key) }
        if names != deviceNames {
            deviceNames = names
            UserDefaults.standard.set(names, forKey: DefaultsKey.audioPriorityDeviceNames)
        }
    }

    /// Keeps the editor as a complete ordered device list. Existing and
    /// disconnected entries retain their positions; a device first seen now
    /// is appended, except that the current device seeds an empty list first.
    /// This makes setup useful immediately without letting newly discovered
    /// hardware jump ahead of an established preference.
    private func mergeAvailableDevicesIntoPriorityLists() {
        let mixer = AppVolumeMixer.shared
        let mergedOutputs = Defaults.sanitizedAudioPriorityUIDs(
            MixerRoutingSupport.priorityListIncludingAvailableDevices(
                storedUIDs: outputPriorityUIDs,
                availableUIDs: mixer.outputDevices.filter(\.canBeDefaultOutput).map(\.uid),
                currentUID: mixer.currentOutputDeviceUID))
        if mergedOutputs != outputPriorityUIDs {
            outputPriorityUIDs = mergedOutputs
            UserDefaults.standard.set(mergedOutputs, forKey: DefaultsKey.audioPriorityOutputUIDs)
        }

        let inputManager = AudioInputDeviceManager.shared
        let mergedInputs = Defaults.sanitizedAudioPriorityUIDs(
            MixerRoutingSupport.priorityListIncludingAvailableDevices(
                storedUIDs: inputPriorityUIDs,
                availableUIDs: inputManager.inputDevices.map(\.uid),
                currentUID: inputManager.currentInputDeviceUID))
        if mergedInputs != inputPriorityUIDs {
            inputPriorityUIDs = mergedInputs
            UserDefaults.standard.set(mergedInputs, forKey: DefaultsKey.audioPriorityInputUIDs)
        }
    }

    /// Returns the display name for a UID, preferring a currently connected
    /// device and falling back to the stored last-known name.
    func displayName(for uid: String) -> String? {
        if let device = AppVolumeMixer.shared.outputDevices.first(where: { $0.uid == uid }) {
            return device.name
        }
        if let device = AudioInputDeviceManager.shared.inputDevices.first(where: { $0.uid == uid }) {
            return device.name
        }
        return deviceNames[uid]
    }

    /// Whether a UID is currently connected and eligible as an output.
    func isOutputAvailable(_ uid: String) -> Bool {
        AppVolumeMixer.shared.outputDevices.contains { $0.uid == uid && $0.canBeDefaultOutput }
    }

    /// Whether a UID is currently connected and eligible as an input.
    func isInputAvailable(_ uid: String) -> Bool {
        AudioInputDeviceManager.shared.inputDevices.contains { $0.uid == uid }
    }

    // MARK: - Enforcement

    /// Coalesces connect/disconnect bursts and list edits into one pass. Core Audio can
    /// briefly publish an incomplete inventory while changing only the
    /// default device, so compare the final settled set with the last settled
    /// set instead of treating every intermediate publication as hardware.
    private static let eventEnforcementDelay: TimeInterval = 0.25

    private func observeOutputDevices(_ devices: [MixerOutputDevice]) {
        let availableUIDs = Set(devices.filter(\.canBeDefaultOutput).map(\.uid))
        // An empty initial publication precedes the first HAL snapshot. It is
        // initialization, not every built-in device connecting at app launch.
        guard settledOutputUIDs != nil || !availableUIDs.isEmpty else { return }
        guard settledOutputUIDs != nil else {
            settledOutputUIDs = availableUIDs
            mergeAvailableDevicesIntoPriorityLists()
            updateDeviceNames()
            return
        }
        pendingOutputUIDs = availableUIDs
        mergeAvailableDevicesIntoPriorityLists()
        updateDeviceNames()
        scheduleEnforcement()
    }

    private func observeInputDevices(_ devices: [MixerInputDevice]) {
        let availableUIDs = Set(devices.map(\.uid))
        guard settledInputUIDs != nil || !availableUIDs.isEmpty else { return }
        guard settledInputUIDs != nil else {
            settledInputUIDs = availableUIDs
            mergeAvailableDevicesIntoPriorityLists()
            updateDeviceNames()
            return
        }
        pendingInputUIDs = availableUIDs
        mergeAvailableDevicesIntoPriorityLists()
        updateDeviceNames()
        scheduleEnforcement()
    }

    private func scheduleEnforcement() {
        guard started else { return }
        enforceDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.enforceAvailabilityChanges()
        }
        enforceDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.eventEnforcementDelay, execute: work)
    }

    private func enforceAvailabilityChanges() {
        guard started else { return }
        enforceDebounce = nil
        let enforceOutput = pendingOutputPreferenceChange || (pendingOutputUIDs.map {
            MixerRoutingSupport.deviceAvailabilityChanged(
                previousUIDs: settledOutputUIDs,
                currentUIDs: $0)
        } ?? false)
        let enforceInput = pendingInputPreferenceChange || (pendingInputUIDs.map {
            MixerRoutingSupport.deviceAvailabilityChanged(
                previousUIDs: settledInputUIDs,
                currentUIDs: $0)
        } ?? false)
        if let pendingOutputUIDs { settledOutputUIDs = pendingOutputUIDs }
        if let pendingInputUIDs { settledInputUIDs = pendingInputUIDs }
        pendingOutputUIDs = nil
        pendingInputUIDs = nil
        pendingOutputPreferenceChange = false
        pendingInputPreferenceChange = false
        mergeAvailableDevicesIntoPriorityLists()
        updateDeviceNames()

        if enforceOutput, outputPriorityEnabled {
            enforceOutputPriority()
        }
        if enforceInput, inputPriorityEnabled {
            enforceInputPriority()
        }
    }

    private func enforceOutputPriority() {
        let availableUIDs = Set(AppVolumeMixer.shared.outputDevices
            .filter(\.canBeDefaultOutput)
            .map(\.uid))
        let currentUID = AppVolumeMixer.shared.currentOutputDeviceUID
        guard let target = MixerRoutingSupport.firstAvailablePriorityDeviceUID(
            orderedUIDs: outputPriorityUIDs,
            availableUIDs: availableUIDs) else { return }
        guard MixerRoutingSupport.shouldSwitchToDevice(
            targetUID: target,
            currentUID: currentUID) else { return }
        // Automatic selection preserves the configured priority order and
        // explicit per-app routes; only the normal system default changes.
        AppVolumeMixer.shared.setPriorityOutputDeviceUID(target)
    }

    private func enforceInputPriority() {
        let availableUIDs = Set(AudioInputDeviceManager.shared.inputDevices.map(\.uid))
        let currentUID = AudioInputDeviceManager.shared.currentInputDeviceUID
        guard let target = MixerRoutingSupport.firstAvailablePriorityDeviceUID(
            orderedUIDs: inputPriorityUIDs,
            availableUIDs: availableUIDs) else { return }
        guard MixerRoutingSupport.shouldSwitchToDevice(
            targetUID: target,
            currentUID: currentUID) else { return }
        AudioInputDeviceManager.shared.setCurrentInputDeviceUID(target)
    }
}
