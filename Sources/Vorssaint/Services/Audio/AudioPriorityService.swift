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
/// alone, and so is a device the lists have not ranked yet: it joins first
/// when macOS switches to it, and below the other hardware when it does not.
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
    /// Devices the lists have never ranked wait here until macOS settles on
    /// them. Until then priority does not override them.
    private var unplacedOutputUIDs = Set<String>()
    private var unplacedInputUIDs = Set<String>()
    private var placementWork: DispatchWorkItem?
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
        placementWork?.cancel()
        placementWork = nil
        unplacedOutputUIDs.removeAll()
        unplacedInputUIDs.removeAll()
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
    /// disconnected entries retain their positions. An empty list starts with
    /// the current device, built-in devices, other hardware and then virtual
    /// or aggregate devices. A device the list has never seen waits a moment
    /// for macOS to settle before it gets a place (see `placeNewDevices`), so
    /// headphones macOS just switched to are not taken back while unranked.
    private func mergeAvailableDevicesIntoPriorityLists() {
        let mixer = AppVolumeMixer.shared
        let outputs = mixer.outputDevices.filter(\.canBeDefaultOutput)
        if outputPriorityUIDs.isEmpty {
            storeOutputPriorityUIDs(MixerRoutingSupport.initialPriorityList(
                availableUIDs: outputs.map(\.uid),
                currentUID: mixer.currentOutputDeviceUID,
                tier: outputTier))
        } else {
            let unseen = outputs.map(\.uid).filter { !outputPriorityUIDs.contains($0) }
            unplacedOutputUIDs.formUnion(unseen)
            if !unseen.isEmpty { schedulePlacement() }
        }

        let inputManager = AudioInputDeviceManager.shared
        if inputPriorityUIDs.isEmpty {
            storeInputPriorityUIDs(MixerRoutingSupport.initialPriorityList(
                availableUIDs: inputManager.inputDevices.map(\.uid),
                currentUID: inputManager.currentInputDeviceUID,
                tier: inputTier))
        } else {
            let unseen = inputManager.inputDevices.map(\.uid).filter { !inputPriorityUIDs.contains($0) }
            unplacedInputUIDs.formUnion(unseen)
            if !unseen.isEmpty { schedulePlacement() }
        }
    }

    /// Long enough for macOS to switch to headphones or AirPods it just
    /// connected, which can land after the device itself appears.
    private static let newDevicePlacementDelay: TimeInterval = 2

    private func schedulePlacement() {
        placementWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.placeNewDevices() }
        placementWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.newDevicePlacementDelay, execute: work)
    }

    /// Gives each newly seen device that is still connected its place: first
    /// when it is the device in use, otherwise below the other hardware.
    private func placeNewDevices() {
        placementWork = nil
        guard started else { return }
        let mixer = AppVolumeMixer.shared
        let outputs = Set(mixer.outputDevices.filter(\.canBeDefaultOutput).map(\.uid))
        var outputList = outputPriorityUIDs
        for uid in unplacedOutputUIDs.sorted() where outputs.contains(uid) {
            outputList = MixerRoutingSupport.placingNewPriorityDevice(
                uid, in: outputList, isCurrent: uid == mixer.currentOutputDeviceUID, tier: outputTier)
        }
        unplacedOutputUIDs.removeAll()
        storeOutputPriorityUIDs(outputList)

        let inputManager = AudioInputDeviceManager.shared
        let inputs = Set(inputManager.inputDevices.map(\.uid))
        var inputList = inputPriorityUIDs
        for uid in unplacedInputUIDs.sorted() where inputs.contains(uid) {
            inputList = MixerRoutingSupport.placingNewPriorityDevice(
                uid, in: inputList, isCurrent: uid == inputManager.currentInputDeviceUID, tier: inputTier)
        }
        unplacedInputUIDs.removeAll()
        storeInputPriorityUIDs(inputList)
        updateDeviceNames()
    }

    private func storeOutputPriorityUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedAudioPriorityUIDs(uids)
        guard sanitized != outputPriorityUIDs else { return }
        outputPriorityUIDs = sanitized
        UserDefaults.standard.set(sanitized, forKey: DefaultsKey.audioPriorityOutputUIDs)
    }

    private func storeInputPriorityUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedAudioPriorityUIDs(uids)
        guard sanitized != inputPriorityUIDs else { return }
        inputPriorityUIDs = sanitized
        UserDefaults.standard.set(sanitized, forKey: DefaultsKey.audioPriorityInputUIDs)
    }

    /// Devices that are not connected now keep the plain hardware tier.
    private func outputTier(_ uid: String) -> MixerRoutingSupport.PriorityTier {
        AppVolumeMixer.shared.outputDevices.first { $0.uid == uid }?.priorityTier ?? .hardware
    }

    private func inputTier(_ uid: String) -> MixerRoutingSupport.PriorityTier {
        AudioInputDeviceManager.shared.inputDevices.first { $0.uid == uid }?.priorityTier ?? .hardware
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
        // macOS just moved to a device the list has not ranked yet; leave that
        // choice alone until the device has its place.
        if let currentUID, unplacedOutputUIDs.contains(currentUID) { return }
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
        if let currentUID, unplacedInputUIDs.contains(currentUID) { return }
        guard let target = MixerRoutingSupport.firstAvailablePriorityDeviceUID(
            orderedUIDs: inputPriorityUIDs,
            availableUIDs: availableUIDs) else { return }
        guard MixerRoutingSupport.shouldSwitchToDevice(
            targetUID: target,
            currentUID: currentUID) else { return }
        AudioInputDeviceManager.shared.setCurrentInputDeviceUID(target)
    }
}
