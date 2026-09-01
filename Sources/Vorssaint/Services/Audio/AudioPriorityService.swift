// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreAudio
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
    @Published private(set) var lastError: String?

    private var cancellables = Set<AnyCancellable>()
    private var enforceDebouce: DispatchWorkItem?
    private var isEnforcing = false
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
            AudioInputDeviceManager.shared.inputPriorityIsActive = inputPriorityEnabled
            scheduleEnforcement()
            return
        }
        started = true
        loadPreferences()

        // Observe device list and default changes from the shared audio
        // services. These are already @Published on the main thread, so
        // enforcement runs there too — no competing HAL listeners.
        AppVolumeMixer.shared.$outputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleEnforcement() }
            .store(in: &cancellables)

        AppVolumeMixer.shared.$currentOutputDeviceUID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleEnforcement() }
            .store(in: &cancellables)

        AudioInputDeviceManager.shared.$inputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleEnforcement() }
            .store(in: &cancellables)

        AudioInputDeviceManager.shared.$currentInputDeviceUID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleEnforcement() }
            .store(in: &cancellables)

        // Update the input manager's suppression flag so singular preferred
        // input enforcement steps aside while priority is active.
        AudioInputDeviceManager.shared.inputPriorityIsActive = inputPriorityEnabled

        scheduleEnforcement()
    }

    func stop() {
        guard started else { return }
        started = false
        cancellables.removeAll()
        enforceDebouce?.cancel()
        enforceDebouce = nil
        isEnforcing = false
        AudioInputDeviceManager.shared.inputPriorityIsActive = false
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
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: DefaultsKey.audioPriorityOutputEnabled)
        outputPriorityEnabled = enabled
        mergeAvailableDevicesIntoPriorityLists()
        scheduleEnforcement()
    }

    func setInputPriorityEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: DefaultsKey.audioPriorityInputEnabled)
        inputPriorityEnabled = enabled
        AudioInputDeviceManager.shared.inputPriorityIsActive = enabled
        mergeAvailableDevicesIntoPriorityLists()
        scheduleEnforcement()
    }

    func setOutputPriorityUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedAudioPriorityUIDs(uids)
        let defaults = UserDefaults.standard
        if sanitized.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.audioPriorityOutputUIDs)
        } else {
            defaults.set(sanitized, forKey: DefaultsKey.audioPriorityOutputUIDs)
        }
        outputPriorityUIDs = sanitized
        updateDeviceNames()
        // Dragging can cross several rows in quick succession. Keep those
        // list edits immediate, but wait for the gesture to settle before a
        // synchronous CoreAudio default-device change reaches the main thread.
        scheduleEnforcement(after: Self.reorderEnforcementDelay)
    }

    func setInputPriorityUIDs(_ uids: [String]) {
        let sanitized = Defaults.sanitizedAudioPriorityUIDs(uids)
        let defaults = UserDefaults.standard
        if sanitized.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.audioPriorityInputUIDs)
        } else {
            defaults.set(sanitized, forKey: DefaultsKey.audioPriorityInputUIDs)
        }
        inputPriorityUIDs = sanitized
        updateDeviceNames()
        scheduleEnforcement(after: Self.reorderEnforcementDelay)
    }

    /// Promotes a UID to the front of the output priority list. Called when
    /// the user manually selects an output while output priority is active,
    /// so the automatic enforcement does not immediately undo the choice.
    func promoteOutputDevice(_ uid: String) {
        guard started, outputPriorityEnabled else { return }
        guard let sanitized = MixerRoutingSupport.sanitizedDeviceUID(uid) else { return }
        var uids = outputPriorityUIDs.filter { $0 != sanitized }
        uids.insert(sanitized, at: 0)
        let defaults = UserDefaults.standard
        defaults.set(uids, forKey: DefaultsKey.audioPriorityOutputUIDs)
        outputPriorityUIDs = uids
        updateDeviceNames()
        scheduleEnforcement()
    }

    /// Promotes a UID to the front of the input priority list. Called when
    /// the user manually selects a microphone while input priority is active.
    func promoteInputDevice(_ uid: String) {
        guard started, inputPriorityEnabled else { return }
        guard let sanitized = MixerRoutingSupport.sanitizedDeviceUID(uid) else { return }
        var uids = inputPriorityUIDs.filter { $0 != sanitized }
        uids.insert(sanitized, at: 0)
        let defaults = UserDefaults.standard
        defaults.set(uids, forKey: DefaultsKey.audioPriorityInputUIDs)
        inputPriorityUIDs = uids
        updateDeviceNames()
        scheduleEnforcement()
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

    /// Coalesces hardware event bursts into one enforcement pass. The HAL can
    /// fire several device/default notifications back-to-back, and each one
    /// only needs to ask "is the top available device already active?"
    private static let eventEnforcementDelay: TimeInterval = 0.15
    private static let reorderEnforcementDelay: TimeInterval = 0.65

    private func scheduleEnforcement(after delay: TimeInterval = eventEnforcementDelay) {
        guard started else { return }
        enforceDebouce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.enforce()
        }
        enforceDebouce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Evaluates the priority lists and performs a CoreAudio write only when
    /// the resolved UID exists and differs from the current default.
    private func enforce() {
        guard started, !isEnforcing else { return }
        isEnforcing = true
        defer { isEnforcing = false }

        mergeAvailableDevicesIntoPriorityLists()
        updateDeviceNames()

        if outputPriorityEnabled {
            enforceOutputPriority()
        }
        if inputPriorityEnabled {
            enforceInputPriority()
        }
    }

    private func enforceOutputPriority() {
        let availableUIDs = Set(AppVolumeMixer.shared.outputDevices
            .filter(\.canBeDefaultOutput)
            .map(\.uid))
        guard let target = MixerRoutingSupport.firstAvailablePriorityDeviceUID(
            orderedUIDs: outputPriorityUIDs,
            availableUIDs: availableUIDs) else { return }
        guard MixerRoutingSupport.shouldSwitchToDevice(
            targetUID: target,
            currentUID: AppVolumeMixer.shared.currentOutputDeviceUID) else { return }
        // Automatic selection preserves the configured priority order and
        // explicit per-app routes; only the normal system default changes.
        AppVolumeMixer.shared.setPriorityOutputDeviceUID(target)
    }

    private func enforceInputPriority() {
        let availableUIDs = Set(AudioInputDeviceManager.shared.inputDevices.map(\.uid))
        guard let target = MixerRoutingSupport.firstAvailablePriorityDeviceUID(
            orderedUIDs: inputPriorityUIDs,
            availableUIDs: availableUIDs) else { return }
        guard MixerRoutingSupport.shouldSwitchToDevice(
            targetUID: target,
            currentUID: AudioInputDeviceManager.shared.currentInputDeviceUID) else { return }
        AudioInputDeviceManager.shared.setCurrentInputDeviceUID(target)
    }
}
