// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import IOBluetooth

fileprivate struct OutputVolumeEndpoint: Hashable {
    let selector: AudioObjectPropertySelector
    let element: AudioObjectPropertyElement
}

fileprivate struct OutputVolumeControl: Equatable {
    let endpoints: [OutputVolumeEndpoint]
    let isSettable: Bool
}

struct MixerOutputDevice: Identifiable, Equatable {
    let id: String
    let uid: String
    let name: String
    let isDefault: Bool
    let isHeadphones: Bool
    let canBeDefaultOutput: Bool
    let canBeDefaultSystemOutput: Bool
    let volume: Double?
    let volumeSettable: Bool
    fileprivate let audioObjectID: AudioObjectID
    fileprivate let volumeControl: OutputVolumeControl?

    fileprivate func replacingVolume(_ volume: Double) -> MixerOutputDevice {
        MixerOutputDevice(id: id,
                          uid: uid,
                          name: name,
                          isDefault: isDefault,
                          isHeadphones: isHeadphones,
                          canBeDefaultOutput: canBeDefaultOutput,
                          canBeDefaultSystemOutput: canBeDefaultSystemOutput,
                          volume: volume,
                          volumeSettable: volumeSettable,
                          audioObjectID: audioObjectID,
                          volumeControl: volumeControl)
    }
}

/// One app in the mixer: every audio-producing process it is responsible for,
/// rolled into a single row.
struct MixerApp: Identifiable, Equatable {
    /// Stable identity for persistence: the bundle id when there is one,
    /// otherwise the process name (pids recycle, names don't).
    let id: String
    let ownerPid: pid_t
    let name: String
    let audioObjects: [AudioObjectID]
    /// True while the app is actually emitting sound right now (shown as a
    /// live indicator). Apps appear in the mixer even when momentarily silent,
    /// as long as they hold an audio connection.
    let isPlaying: Bool
    /// The app manages its own audio (Zoom, DAWs): shown in the list so its
    /// absence doesn't read as a bug (issue #177), but never tapped — no
    /// slider, no routing, volume pinned at unity.
    var isBypassed: Bool = false
    var selectedOutputDeviceUID: String?
    var effectiveOutputDeviceUID: String?
    var outputDeviceUnavailable: Bool
    var volume: Double
}

/// Per-app volume control, something macOS does not offer natively.
///
/// For every app the user turns down or routes to a specific output, a muted
/// CoreAudio process tap removes the app's sound from the original output, and
/// an aggregate device re-renders the tapped stream with the chosen gain. Apps
/// on the system default output at 100% are left completely untouched.
final class AppVolumeMixer: ObservableObject {
    static let shared = AppVolumeMixer()

    static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    /// Volumes run 0...2: 1.0 is 100% (untouched passthrough), up to 2.0 is a
    /// 200% boost for sources that play too quietly.
    static let maxVolume: Double = 2.0

    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var outputDevices: [MixerOutputDevice] = []
    @Published private(set) var discoveredBluetoothOutputDevices: [MixerDiscoveredOutputDevice] = []
    @Published private(set) var currentOutputDeviceUID: String?
    @Published private(set) var outputSwitchError: String?
    @Published private(set) var outputSwitchInProgress = false
    @Published private(set) var connectingBluetoothSelectionID: String?
    @Published private(set) var outputMasterVolume: Double = 1
    /// Set when tap creation fails with a permission error, so the panel can
    /// point at the System Audio Recording consent.
    @Published private(set) var needsPermission = false

    private var engines: [String: any GainEngine] = [:]
    /// Apps whose engine is being built off-main; suppresses duplicate builds
    /// while the slider keeps dragging.
    private var buildingEngines = Set<String>()
    private var lastAudibleVolume: [String: Double] = [:]
    private var outputBaseVolumes: [String: Double] = [:]
    private var listenerInstalled = false
    /// One IsRunningOutput listener per live process object, kept so the block
    /// can be handed back to AudioObjectRemovePropertyListenerBlock when the
    /// process disappears. Without removal, a week of app churn leaves
    /// thousands of dead listener blocks registered with the HAL.
    private var runningListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var outputVolumeListeners: [OutputVolumeListenerKey: AudioObjectPropertyListenerBlock] = [:]
    private var stopped = false
    private var lastAutomaticLoweredOutputUID: String?
    private var refreshPending = false
    private var lastListenerRefreshAt: CFAbsoluteTime = 0
    private var masterVolumeApplyScheduled = false
    private var lastMasterVolumeApplyAt: CFAbsoluteTime = 0
    private var routeDiscoveryRunning = false
    private var lastRouteDiscoveryAt: CFAbsoluteTime = -.greatestFiniteMagnitude
    private var outputSwitchGeneration = 0
    private let buildQueue = DispatchQueue(label: "com.vorssaint.utils.mixer", qos: .userInitiated)
    private let outputSwitchQueue = DispatchQueue(label: "com.vorssaint.utils.output-switch", qos: .userInitiated)
    private let routeDiscoveryQueue = DispatchQueue(label: "com.vorssaint.utils.output-routes", qos: .utility)
    private let bluetoothConnectionQueue = DispatchQueue(label: "com.vorssaint.utils.bluetooth-connect",
                                                         qos: .userInitiated)

    private struct OutputVolumeListenerKey: Hashable {
        let deviceID: AudioObjectID
        let selector: AudioObjectPropertySelector
        let element: AudioObjectPropertyElement
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedMaster = (defaults.object(forKey: DefaultsKey.mixerOutputMasterVolume) as? NSNumber)?.doubleValue ?? 1
        outputMasterVolume = Defaults.sanitizedOutputMasterVolume(storedMaster)
        outputBaseVolumes = Defaults.sanitizedOutputBaseVolumes(
            defaults.dictionary(forKey: DefaultsKey.mixerOutputBaseVolumes) ?? [:])
    }

    // MARK: - Lifecycle

    /// Starts watching audio processes. Saved volumes re-apply as soon as the
    /// matching app produces sound — no panel interaction needed.
    func start() {
        stopped = false
        guard !listenerInstalled else {
            refreshApps()
            return
        }
        listenerInstalled = true
        installListener(selector: kAudioHardwarePropertyDevices)
        installListener(selector: kAudioHardwarePropertyDefaultOutputDevice)
        if Self.isSupported {
            installListener(selector: kAudioHardwarePropertyProcessObjectList)
        }
        refreshDiscoveredOutputRoutesIfNeeded(force: true)
        refreshApps()
    }

    /// Tears every tap down so all apps return to untouched system output.
    func stopAll() {
        stopped = true
        outputSwitchGeneration += 1
        outputSwitchInProgress = false
        connectingBluetoothSelectionID = nil
        buildingEngines.removeAll()
        removeOutputVolumeListeners()
        for engine in engines.values { engine.stop() }
        engines.removeAll()
    }

    private func installListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            self?.scheduleListenerRefresh()
        }
    }

    private func subscribeToRunningChanges(of object: AudioObjectID) {
        guard runningListeners[object] == nil else { return }
        var address = Self.isRunningOutputAddress()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleListenerRefresh()
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            runningListeners[object] = block
        }
    }

    /// Drops the listeners of process objects that no longer exist. Removal on
    /// a dead object can fail; the entry is forgotten either way, since the
    /// object id will never come back.
    private func pruneRunningListeners(keeping current: Set<AudioObjectID>) {
        for (object, block) in runningListeners where !current.contains(object) {
            var address = Self.isRunningOutputAddress()
            if AudioObjectHasProperty(object, &address) {
                AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
            }
            runningListeners.removeValue(forKey: object)
        }
    }

    private static func isRunningOutputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func syncOutputVolumeListeners(with devices: [MixerOutputDevice]) {
        var expected = Set<OutputVolumeListenerKey>()
        let liveDeviceIDs = Set(devices.map(\.audioObjectID))
        for device in devices {
            for endpoint in device.volumeControl?.endpoints ?? [] {
                var address = Self.outputVolumeAddress(endpoint)
                guard AudioObjectHasProperty(device.audioObjectID, &address) else { continue }
                let key = OutputVolumeListenerKey(deviceID: device.audioObjectID,
                                                  selector: endpoint.selector,
                                                  element: endpoint.element)
                expected.insert(key)
                guard outputVolumeListeners[key] == nil else { continue }
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    self?.scheduleListenerRefresh()
                }
                if AudioObjectAddPropertyListenerBlock(device.audioObjectID, &address, .main, block) == noErr {
                    outputVolumeListeners[key] = block
                }
            }
        }

        for (key, block) in outputVolumeListeners where !expected.contains(key) {
            if liveDeviceIDs.contains(key.deviceID) {
                var address = Self.outputVolumeAddress(OutputVolumeEndpoint(selector: key.selector,
                                                                            element: key.element))
                if AudioObjectHasProperty(key.deviceID, &address) {
                    AudioObjectRemovePropertyListenerBlock(key.deviceID, &address, .main, block)
                }
            }
            outputVolumeListeners.removeValue(forKey: key)
        }
    }

    private func removeOutputVolumeListeners() {
        for (key, block) in outputVolumeListeners {
            var address = Self.outputVolumeAddress(OutputVolumeEndpoint(selector: key.selector,
                                                                        element: key.element))
            if AudioObjectHasProperty(key.deviceID, &address) {
                AudioObjectRemovePropertyListenerBlock(key.deviceID, &address, .main, block)
            }
        }
        outputVolumeListeners.removeAll()
    }

    /// One hardware event fires several of the listeners above back-to-back
    /// (device list, default device, process list, plus one IsRunningOutput per
    /// process), and a busy audio HAL can keep that stream going for as long as
    /// the panel is open. An isolated notification still refreshes immediately
    /// (headphone unplug must react now); a burst is coalesced into one trailing
    /// refresh so the panel does not redraw once per listener.
    private func scheduleListenerRefresh() {
        guard !refreshPending else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastListenerRefreshAt
        if elapsed >= Self.listenerRefreshInterval {
            lastListenerRefreshAt = now
            refreshApps()
            return
        }
        refreshPending = true
        let delay = Self.listenerRefreshInterval - elapsed
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.lastListenerRefreshAt = CFAbsoluteTimeGetCurrent()
            self.refreshApps()
        }
    }

    private static let listenerRefreshInterval: CFAbsoluteTime = 0.2
    private static let routeDiscoveryInterval: CFAbsoluteTime = 300
    private static let masterVolumeApplyInterval: CFAbsoluteTime = 1.0 / 30.0

    private func refreshDiscoveredOutputRoutesIfNeeded(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - lastRouteDiscoveryAt >= Self.routeDiscoveryInterval else { return }
        guard !routeDiscoveryRunning else { return }
        routeDiscoveryRunning = true
        lastRouteDiscoveryAt = now

        routeDiscoveryQueue.async { [weak self] in
            let devices = Self.readBluetoothOutputRoutes()
            DispatchQueue.main.async {
                guard let self else { return }
                self.routeDiscoveryRunning = false
                if self.discoveredBluetoothOutputDevices != devices {
                    self.discoveredBluetoothOutputDevices = devices
                }
            }
        }
    }

    // MARK: - Volume API (panel)

    /// 100% means bit-perfect passthrough (no tap). A value the UI would round to
    /// 100% counts as unity, so dragging near 100% or tapping reset both restore
    /// true passthrough; anything else (quieter or boosted) runs the gain engine.
    private func isUnity(_ volume: Double) -> Bool { MixerRoutingSupport.isUnity(volume) }

    private func beginOutputSwitchRequest(connectingBluetoothSelectionID: String? = nil) -> Int {
        outputSwitchGeneration += 1
        let generation = outputSwitchGeneration
        outputSwitchInProgress = true
        self.connectingBluetoothSelectionID = connectingBluetoothSelectionID
        if outputSwitchError != nil {
            outputSwitchError = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.outputSwitchTimeout) { [weak self] in
            guard let self,
                  self.outputSwitchGeneration == generation,
                  self.outputSwitchInProgress else { return }
            self.outputSwitchGeneration += 1
            self.outputSwitchInProgress = false
            self.connectingBluetoothSelectionID = nil
            self.outputSwitchError = L10n.shared.s.mixerOutputUnavailable
        }
        return generation
    }

    private func finishOutputSwitchRequest() {
        outputSwitchInProgress = false
        connectingBluetoothSelectionID = nil
    }

    private static let outputSwitchTimeout: TimeInterval = 8

    func setVolume(_ volume: Double, for app: MixerApp) {
        guard !app.isBypassed else { return }
        let clamped = Defaults.sanitizedAppVolume(volume)
        persistVolume(clamped, for: app.id)
        if clamped > 0.001 { lastAudibleVolume[app.id] = clamped }
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].volume = clamped
            let updated = apps[index]
            applyRouting(for: updated)
        } else {
            applyRouting(for: app)
        }
    }

    func setOutputDeviceUID(_ uid: String?, for app: MixerApp) {
        guard !app.isBypassed else { return }
        let sanitized = Defaults.sanitizedAppOutputDeviceUID(uid)
        persistOutputDeviceUID(sanitized, for: app.id)
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].selectedOutputDeviceUID = sanitized
            applyOutputRoute(to: &apps[index],
                             savedOutputs: [app.id: sanitized].compactMapValues { $0 },
                             availableUIDs: Set(outputDevices.map(\.uid)),
                             defaultUID: currentOutputDeviceUID)
            let updated = apps[index]
            engines.removeValue(forKey: updated.id)?.stop()
            applyRouting(for: updated)
        }
    }

    @discardableResult
    func setUniversalOutputDeviceUID(_ uid: String) -> Bool {
        guard let sanitized = Defaults.sanitizedAppOutputDeviceUID(uid),
              let device = outputDevices.first(where: { $0.uid == sanitized && $0.canBeDefaultOutput }) else {
            outputSwitchError = L10n.shared.s.mixerOutputUnavailable
            refreshApps()
            return false
        }

        return setUniversalOutputDevice(device)
    }

    @discardableResult
    private func setUniversalOutputDevice(_ device: MixerOutputDevice,
                                          connectingBluetoothSelectionID: String? = nil) -> Bool {
        guard device.canBeDefaultOutput,
              Defaults.sanitizedAppOutputDeviceUID(device.uid) != nil else {
            outputSwitchError = L10n.shared.s.mixerOutputUnavailable
            return false
        }

        let generation = beginOutputSwitchRequest(
            connectingBluetoothSelectionID: connectingBluetoothSelectionID)
        outputSwitchQueue.async { [weak self] in
            let status = Self.setDefaultDevice(device.audioObjectID,
                                               selector: kAudioHardwarePropertyDefaultOutputDevice)
            if status == noErr, device.canBeDefaultSystemOutput {
                _ = Self.setDefaultDevice(device.audioObjectID,
                                          selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
            }
            DispatchQueue.main.async {
                guard let self, self.outputSwitchGeneration == generation else { return }
                guard status == noErr else {
                    self.finishOutputSwitchRequest()
                    self.outputSwitchError = "OSStatus \(status)"
                    self.refreshApps()
                    return
                }
                self.finishUniversalOutputSwitch(device)
            }
        }
        return true
    }

    private func finishUniversalOutputSwitch(_ device: MixerOutputDevice) {
        var knownDevices = outputDevices
        if let index = knownDevices.firstIndex(where: { $0.uid == device.uid }) {
            knownDevices[index] = device
        } else {
            knownDevices.append(device)
        }

        finishOutputSwitchRequest()
        outputSwitchError = nil
        let preferences = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedOutputDeviceUIDs(),
            volumes: savedVolumes(),
            switchSucceeded: true)
        persistOutputDeviceUIDs(preferences.outputDeviceUIDs)

        currentOutputDeviceUID = device.uid
        outputDevices = knownDevices.map { outputDevice in
            MixerOutputDevice(id: outputDevice.id,
                              uid: outputDevice.uid,
                              name: outputDevice.name,
                              isDefault: outputDevice.uid == device.uid,
                              isHeadphones: outputDevice.isHeadphones,
                              canBeDefaultOutput: outputDevice.canBeDefaultOutput,
                              canBeDefaultSystemOutput: outputDevice.canBeDefaultSystemOutput,
                              volume: outputDevice.volume,
                              volumeSettable: outputDevice.volumeSettable,
                              audioObjectID: outputDevice.audioObjectID,
                              volumeControl: outputDevice.volumeControl)
        }

        buildingEngines.removeAll()
        for engine in engines.values { engine.stop() }
        engines.removeAll()

        let availableUIDs = Set(outputDevices.map(\.uid))
        apps = apps.map { current in
            var app = current
            app.volume = preferences.volumes[app.id] ?? app.volume
            applyOutputRoute(to: &app,
                             savedOutputs: preferences.outputDeviceUIDs,
                             availableUIDs: availableUIDs,
                             defaultUID: device.uid)
            return app
        }
        reconcileEngines(with: apps)
        clearPermissionIfNoActiveAdjustments()
        refreshApps()
    }

    func connectBluetoothOutputDevice(selectionID: String) {
        guard let route = discoveredBluetoothOutputDevices.first(where: { $0.id == selectionID }),
              let address = route.bluetoothAddress else {
            outputSwitchError = L10n.shared.s.mixerOutputUnavailable
            return
        }

        let generation = beginOutputSwitchRequest(connectingBluetoothSelectionID: selectionID)
        bluetoothConnectionQueue.async { [weak self] in
            let status = Self.openPairedBluetoothConnection(address: address)
            let device = Self.waitForOutputDevice(matching: route, timeout: 6)
            DispatchQueue.main.async {
                guard let self, self.outputSwitchGeneration == generation else { return }
                self.refreshDiscoveredOutputRoutesIfNeeded(force: true)
                guard let device else {
                    self.finishOutputSwitchRequest()
                    self.outputSwitchError = status == noErr ? L10n.shared.s.mixerOutputUnavailable : "Bluetooth \(status)"
                    self.refreshApps()
                    return
                }
                _ = self.setUniversalOutputDevice(device,
                                                  connectingBluetoothSelectionID: selectionID)
            }
        }
    }

    @discardableResult
    func switchToNextSoundOutput(in selectedUIDs: [String]) -> Bool {
        let availableUIDs = Set(outputDevices.filter(\.canBeDefaultOutput).map(\.uid))
        guard let nextUID = MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: currentOutputDeviceUID,
            selectedUIDs: selectedUIDs,
            availableUIDs: availableUIDs) else { return false }
        return setUniversalOutputDeviceUID(nextUID)
    }

    func toggleMute(_ app: MixerApp) {
        if app.volume > 0.001 {
            lastAudibleVolume[app.id] = app.volume
            setVolume(0, for: app)
        } else {
            setVolume(lastAudibleVolume[app.id] ?? 1, for: app)
        }
    }

    func setOutputVolume(_ volume: Double, forOutputDeviceUID uid: String) {
        let clamped = min(max(volume, 0), 1)
        guard let device = outputDevices.first(where: { $0.uid == uid }),
              let volumeControl = device.volumeControl,
              volumeControl.isSettable else { return }
        let previousBase = outputBaseVolumes[uid] ?? device.volume ?? clamped
        let base = MixerRoutingSupport.baseOutputVolume(effective: clamped,
                                                        master: outputMasterVolume,
                                                        previousBase: previousBase)
        let effective = MixerRoutingSupport.effectiveOutputVolume(base: base,
                                                                  master: outputMasterVolume)
        guard Self.setOutputVolume(Float32(effective),
                                   for: device.audioObjectID,
                                   control: volumeControl) else { return }

        outputBaseVolumes[uid] = base
        persistOutputMasterState()
        let actual = Self.outputVolume(for: device.audioObjectID, control: volumeControl) ?? effective
        outputDevices = outputDevices.map { outputDevice in
            guard outputDevice.uid == uid else { return outputDevice }
            return outputDevice.replacingVolume(actual)
        }
    }

    func setOutputMasterVolume(_ volume: Double) {
        let clamped = min(max(volume, 0), 1)
        guard abs(clamped - outputMasterVolume) > 0.0001 else { return }
        for device in outputDevices where device.volumeSettable {
            if outputBaseVolumes[device.uid] == nil, let current = device.volume {
                outputBaseVolumes[device.uid] = current
            }
        }
        outputMasterVolume = clamped
        persistOutputMasterState()
        scheduleOutputMasterVolumeApply()
    }

    private func scheduleOutputMasterVolumeApply() {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastMasterVolumeApplyAt
        if elapsed >= Self.masterVolumeApplyInterval {
            lastMasterVolumeApplyAt = now
            applyOutputMasterVolume()
            return
        }
        guard !masterVolumeApplyScheduled else { return }
        masterVolumeApplyScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.masterVolumeApplyInterval - elapsed) { [weak self] in
            guard let self else { return }
            self.masterVolumeApplyScheduled = false
            self.lastMasterVolumeApplyAt = CFAbsoluteTimeGetCurrent()
            self.applyOutputMasterVolume()
        }
    }

    private func applyOutputMasterVolume() {
        var updated = outputDevices
        for index in updated.indices {
            let device = updated[index]
            guard let base = outputBaseVolumes[device.uid],
                  let control = device.volumeControl,
                  control.isSettable else { continue }
            let target = MixerRoutingSupport.effectiveOutputVolume(base: base,
                                                                   master: outputMasterVolume)
            guard Self.setOutputVolume(Float32(target),
                                       for: device.audioObjectID,
                                       control: control) else { continue }
            let actual = Self.outputVolume(for: device.audioObjectID, control: control) ?? target
            updated[index] = device.replacingVolume(actual)
        }
        if updated != outputDevices {
            outputDevices = updated
        }
    }

    private func persistOutputMasterState() {
        UserDefaults.standard.set(outputMasterVolume, forKey: DefaultsKey.mixerOutputMasterVolume)
        UserDefaults.standard.set(outputBaseVolumes, forKey: DefaultsKey.mixerOutputBaseVolumes)
    }

    /// Main-thread only. Engine creation happens off-main (CoreAudio object
    /// setup takes tens of milliseconds) and lands back here exactly once.
    private func applyRouting(for app: MixerApp) {
        guard !stopped else { return }
        guard !app.isBypassed else {
            engines.removeValue(forKey: app.id)?.stop()
            return
        }
        guard let targetOutputDeviceUID = app.effectiveOutputDeviceUID,
              appNeedsEngine(app) else {
            // System default at 100% stays true passthrough.
            engines.removeValue(forKey: app.id)?.stop()
            clearPermissionIfNoActiveAdjustments()
            return
        }
        if let engine = engines[app.id] {
            if engine.tappedObjects == app.audioObjects,
               engine.outputDeviceUID == targetOutputDeviceUID {
                engine.gain = Float(app.volume)
                return
            }
            engine.stop()
            engines.removeValue(forKey: app.id)
        }
        guard #available(macOS 14.4, *), !buildingEngines.contains(app.id) else { return }

        buildingEngines.insert(app.id)
        buildQueue.async { [weak self] in
            let engine = TapGainEngine(objects: app.audioObjects,
                                       gain: Float(app.volume),
                                       outputDeviceUID: targetOutputDeviceUID)
            DispatchQueue.main.async {
                guard let self else {
                    engine?.stop()
                    return
                }
                self.buildingEngines.remove(app.id)
                guard !self.stopped else {
                    engine?.stop()
                    return
                }
                guard let engine else {
                    if !self.needsPermission {
                        self.needsPermission = true
                    }
                    return
                }
                if self.needsPermission {
                    self.needsPermission = false
                }
                // The slider may have moved (or returned to 100%) while the
                // engine was being built, or the app's audio objects may have
                // changed. Honor the latest state, never an old tap target.
                guard let latestApp = self.apps.first(where: { $0.id == app.id }) else {
                    engine.stop()
                    return
                }
                if latestApp.audioObjects != engine.tappedObjects {
                    engine.stop()
                    self.applyRouting(for: latestApp)
                    return
                }
                if engine.outputDeviceUID != latestApp.effectiveOutputDeviceUID {
                    engine.stop()
                    self.applyRouting(for: latestApp)
                    return
                }
                if !self.appNeedsEngine(latestApp) {
                    engine.stop()
                    self.clearPermissionIfNoActiveAdjustments()
                } else {
                    engine.gain = Float(latestApp.volume)
                    self.engines[app.id] = engine
                }
            }
        }
    }

    private func appNeedsEngine(_ app: MixerApp) -> Bool {
        MixerRoutingSupport.requiresEngine(volume: app.volume,
                                           selectedOutputDeviceUID: app.selectedOutputDeviceUID,
                                           targetOutputDeviceUID: app.effectiveOutputDeviceUID,
                                           defaultOutputDeviceUID: currentOutputDeviceUID)
    }

    private func applyOutputRoute(to app: inout MixerApp,
                                  savedOutputs: [String: String],
                                  availableUIDs: Set<String>,
                                  defaultUID: String?) {
        let selectedUID = savedOutputs[app.id]
        app.selectedOutputDeviceUID = selectedUID
        app.effectiveOutputDeviceUID = MixerRoutingSupport.effectiveDeviceUID(
            selectedUID: selectedUID,
            availableUIDs: availableUIDs,
            defaultUID: defaultUID)
        app.outputDeviceUnavailable = MixerRoutingSupport.selectedDeviceUnavailable(
            selectedUID: selectedUID,
            availableUIDs: availableUIDs)
    }

    // MARK: - Process discovery

    private func refreshApps() {
        refreshDiscoveredOutputRoutesIfNeeded()
        let defaultUID = Self.defaultOutputDeviceUID()
        var nextOutputDevices = Self.outputDevices(defaultUID: defaultUID)
        if defaultUID != currentOutputDeviceUID, outputSwitchError != nil {
            outputSwitchError = nil
        }
        if lowerVolumeIfHeadphonesDisconnected(previousDefaultUID: currentOutputDeviceUID,
                                               previousOutputDevices: outputDevices,
                                               nextDefaultUID: defaultUID,
                                               nextOutputDevices: nextOutputDevices) {
            nextOutputDevices = Self.outputDevices(defaultUID: defaultUID)
        }
        let shouldApplyMasterVolume = syncOutputBaseVolumes(previous: outputDevices,
                                                           next: nextOutputDevices)
        let availableUIDs = Set(nextOutputDevices.map(\.uid))
        syncOutputVolumeListeners(with: nextOutputDevices)
        let audioEnvironmentChanged = currentOutputDeviceUID != nil
            && (defaultUID != currentOutputDeviceUID || !Self.sameOutputTopology(nextOutputDevices, outputDevices))
        if audioEnvironmentChanged {
            buildingEngines.removeAll()
            for engine in engines.values { engine.stop() }
            engines.removeAll()
        }
        // Assigning a @Published property signals SwiftUI even when the value is
        // identical, and refreshes run on every CoreAudio notification — publish
        // only real changes or a chatty HAL re-renders the panel continuously.
        if currentOutputDeviceUID != defaultUID {
            currentOutputDeviceUID = defaultUID
        }
        if nextOutputDevices != outputDevices {
            outputDevices = nextOutputDevices
        }
        if shouldApplyMasterVolume {
            applyOutputMasterVolume()
        }

        guard Self.isSupported else {
            if !apps.isEmpty {
                apps = []
            }
            return
        }

        let ownPid = ProcessInfo.processInfo.processIdentifier
        let saved = savedVolumes()
        let savedOutputs = savedOutputDeviceUIDs()
        var groups: [pid_t: [AudioObjectID]] = [:]
        var playing: Set<pid_t> = []
        var bypassed: Set<pid_t> = []
        var bundleHints: [pid_t: String] = [:]
        let processObjects = Self.audioProcessObjects()
        pruneRunningListeners(keeping: Set(processObjects))
        for object in processObjects {
            // Audio starting/stopping in a process flips IsRunningOutput
            // without changing the object list — subscribe per object.
            subscribeToRunningChanges(of: object)

            var pid: pid_t = -1
            guard Self.read(object, kAudioProcessPropertyPID, &pid), pid > 0, pid != ownPid else { continue }

            // Show every regular app that holds an audio connection, not only
            // the ones making sound this instant, so apps are adjustable before
            // they play and stay put between sounds.
            let owner = ResponsibleProcess.owner(of: pid)
            guard let app = NSRunningApplication(processIdentifier: owner),
                  app.activationPolicy == .regular else { continue }
            let name = ResponsibleProcess.displayName(pid: owner, fallback: app.localizedName ?? "pid \(owner)")
            // Bypassed apps (Zoom, DAWs) still get a row — hiding them read
            // as a bug (issue #177) — but they are never tapped: volume
            // pinned at unity, no saved routing, so appNeedsEngine is always
            // false for them.
            if MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: app.bundleIdentifier,
                                                      name: name) {
                bypassed.insert(owner)
            }

            var running: UInt32 = 0
            _ = Self.read(object, kAudioProcessPropertyIsRunningOutput, &running)
            if running != 0 { playing.insert(owner) }

            groups[owner, default: []].append(object)
            if bundleHints[owner] == nil {
                bundleHints[owner] = app.bundleIdentifier
            }
        }

        var next: [MixerApp] = []
        for (owner, objects) in groups {
            let name = ResponsibleProcess.displayName(pid: owner, fallback: "pid \(owner)")
            let id = bundleHints[owner] ?? name
            let isBypassed = bypassed.contains(owner)
            next.append(MixerApp(id: id,
                                 ownerPid: owner,
                                 name: name,
                                 audioObjects: objects.sorted(),
                                 isPlaying: playing.contains(owner),
                                 isBypassed: isBypassed,
                                 selectedOutputDeviceUID: isBypassed ? nil : savedOutputs[id],
                                 effectiveOutputDeviceUID: isBypassed ? nil : MixerRoutingSupport.effectiveDeviceUID(
                                    selectedUID: savedOutputs[id],
                                    availableUIDs: availableUIDs,
                                    defaultUID: defaultUID),
                                 outputDeviceUnavailable: isBypassed ? false : MixerRoutingSupport.selectedDeviceUnavailable(
                                    selectedUID: savedOutputs[id],
                                    availableUIDs: availableUIDs),
                                 volume: isBypassed ? 1 : (saved[id] ?? 1)))
        }
        next.sort {
            MixerRoutingSupport.displayOrderedBefore(name: $0.name, id: $0.id,
                                                     otherName: $1.name, otherID: $1.id)
        }
        next = Self.coalescingAppsWithDuplicateIDs(next)

        guard audioEnvironmentChanged || next != apps else { return }
        if apps != next {
            apps = next
        }
        reconcileEngines(with: next)
        clearPermissionIfNoActiveAdjustments()
    }

    private static func coalescingAppsWithDuplicateIDs(_ apps: [MixerApp]) -> [MixerApp] {
        var merged: [MixerApp] = []
        var indexesByID: [String: Int] = [:]

        for app in apps {
            guard let index = indexesByID[app.id] else {
                indexesByID[app.id] = merged.count
                merged.append(app)
                continue
            }

            let existing = merged[index]
            let audioObjects = Array(Set(existing.audioObjects).union(app.audioObjects)).sorted()
            merged[index] = MixerApp(id: existing.id,
                                     ownerPid: existing.ownerPid,
                                     name: existing.name,
                                     audioObjects: audioObjects,
                                     isPlaying: existing.isPlaying || app.isPlaying,
                                     selectedOutputDeviceUID: existing.selectedOutputDeviceUID,
                                     effectiveOutputDeviceUID: existing.effectiveOutputDeviceUID,
                                     outputDeviceUnavailable: existing.outputDeviceUnavailable,
                                     volume: existing.volume)
        }

        return merged
    }

    private static func sameOutputTopology(_ lhs: [MixerOutputDevice], _ rhs: [MixerOutputDevice]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.uid == right.uid
                && left.audioObjectID == right.audioObjectID
                && left.name == right.name
                && left.isDefault == right.isDefault
                && left.isHeadphones == right.isHeadphones
                && left.canBeDefaultOutput == right.canBeDefaultOutput
                && left.canBeDefaultSystemOutput == right.canBeDefaultSystemOutput
        }
    }

    private func syncOutputBaseVolumes(previous: [MixerOutputDevice],
                                       next: [MixerOutputDevice]) -> Bool {
        let previousByUID = Dictionary(uniqueKeysWithValues: previous.map { ($0.uid, $0) })
        var shouldApplyMaster = false
        var baseVolumesChanged = false
        for device in next where device.volumeSettable {
            guard let volume = device.volume else { continue }
            guard let base = outputBaseVolumes[device.uid] else {
                outputBaseVolumes[device.uid] = volume
                baseVolumesChanged = true
                shouldApplyMaster = outputMasterVolume < 0.999 || shouldApplyMaster
                continue
            }
            guard let oldDevice = previousByUID[device.uid] else {
                shouldApplyMaster = outputMasterVolume < 0.999 || shouldApplyMaster
                continue
            }
            if oldDevice.audioObjectID != device.audioObjectID {
                shouldApplyMaster = outputMasterVolume < 0.999 || shouldApplyMaster
            } else if let oldVolume = oldDevice.volume,
                      abs(oldVolume - volume) > 0.005 {
                if outputMasterVolume > 0.001 {
                    outputBaseVolumes[device.uid] = MixerRoutingSupport.baseOutputVolume(
                        effective: volume,
                        master: outputMasterVolume,
                        previousBase: base)
                    baseVolumesChanged = true
                }
                shouldApplyMaster = outputMasterVolume < 0.999 || shouldApplyMaster
            }
        }
        if baseVolumesChanged {
            persistOutputMasterState()
        }
        return shouldApplyMaster
    }

    private func lowerVolumeIfHeadphonesDisconnected(previousDefaultUID: String?,
                                                     previousOutputDevices: [MixerOutputDevice],
                                                     nextDefaultUID: String?,
                                                     nextOutputDevices: [MixerOutputDevice]) -> Bool {
        if let nextDefaultUID,
           nextOutputDevices.first(where: { $0.uid == nextDefaultUID })?.isHeadphones == true {
            lastAutomaticLoweredOutputUID = nil
            return false
        }

        guard UserDefaults.standard.bool(forKey: DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect),
              let previousDefaultUID,
              let previousDefault = previousOutputDevices.first(where: { $0.uid == previousDefaultUID }),
              previousDefault.isHeadphones,
              !nextOutputDevices.contains(where: { $0.uid == previousDefaultUID && $0.isHeadphones }),
              let nextDefaultUID,
              let nextDefault = nextOutputDevices.first(where: { $0.uid == nextDefaultUID }),
              !nextDefault.isHeadphones,
              lastAutomaticLoweredOutputUID != nextDefaultUID else {
            return false
        }

        let percent = Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(
            UserDefaults.standard.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
        )
        if Self.setOutputVolume(Float32(Double(percent) / 100), for: nextDefault.audioObjectID) {
            lastAutomaticLoweredOutputUID = nextDefaultUID
            return true
        }
        return false
    }

    /// Brings the running engines in line with the current app list: drops
    /// taps for apps that stopped playing, retargets taps whose process set
    /// changed (new helper spawned), and applies saved volumes to newcomers.
    private func reconcileEngines(with apps: [MixerApp]) {
        let apps = Self.coalescingAppsWithDuplicateIDs(apps)
        var byId: [String: MixerApp] = [:]
        for app in apps {
            byId[app.id] = app
        }

        for (id, engine) in Array(engines) {
            guard let app = byId[id] else {
                engine.stop()
                engines.removeValue(forKey: id)
                continue
            }
            if engine.tappedObjects != app.audioObjects
                || engine.outputDeviceUID != app.effectiveOutputDeviceUID
                || !appNeedsEngine(app) {
                engine.stop()
                engines.removeValue(forKey: id)
                applyRouting(for: app)
            }
        }

        for app in apps where appNeedsEngine(app) && engines[app.id] == nil {
            applyRouting(for: app)
        }
    }

    // MARK: - Persistence

    private func savedVolumes() -> [String: Double] {
        let raw = UserDefaults.standard.dictionary(forKey: DefaultsKey.appVolumes) ?? [:]
        var sanitized: [String: Double] = [:]
        for (id, value) in raw {
            let number: Double?
            if let value = value as? Double {
                number = value
            } else if let value = value as? NSNumber {
                number = value.doubleValue
            } else {
                number = nil
            }
            guard let number, number.isFinite else { continue }
            sanitized[id] = Defaults.sanitizedAppVolume(number)
        }
        return sanitized
    }

    private func savedOutputDeviceUIDs() -> [String: String] {
        let raw = UserDefaults.standard.dictionary(forKey: DefaultsKey.appOutputDevices) ?? [:]
        return Defaults.sanitizedAppOutputDevices(raw)
    }

    private func persistVolume(_ volume: Double, for id: String) {
        var volumes = savedVolumes()
        if isUnity(volume) {
            volumes.removeValue(forKey: id)
        } else {
            volumes[id] = volume
        }
        UserDefaults.standard.set(volumes, forKey: DefaultsKey.appVolumes)
    }

    private func persistOutputDeviceUID(_ uid: String?, for id: String) {
        var routes = savedOutputDeviceUIDs()
        if let uid {
            routes[id] = uid
        } else {
            routes.removeValue(forKey: id)
        }
        UserDefaults.standard.set(routes, forKey: DefaultsKey.appOutputDevices)
    }

    private func persistOutputDeviceUIDs(_ routes: [String: String]) {
        if routes.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.appOutputDevices)
        } else {
            UserDefaults.standard.set(routes, forKey: DefaultsKey.appOutputDevices)
        }
    }

    private func clearPermissionIfNoActiveAdjustments() {
        guard needsPermission,
              !apps.contains(where: appNeedsEngine),
              engines.isEmpty,
              buildingEngines.isEmpty else { return }
        needsPermission = false
    }

    // MARK: - CoreAudio plumbing

    private static func readBluetoothOutputRoutes(timeout: TimeInterval = 2) -> [MixerDiscoveredOutputDevice] {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-bluetooth-\(UUID().uuidString).json")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else { return [] }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        guard !process.isRunning else { return [] }
        process.waitUntilExit()
        try? output.synchronize()
        try? output.close()
        guard let data = try? Data(contentsOf: outputURL) else { return [] }
        return MixerRoutingSupport.bluetoothAudioOutputs(fromSystemProfilerJSON: data)
    }

    private static func openPairedBluetoothConnection(address: String) -> IOReturn {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        guard let device = devices.first(where: {
            MixerRoutingSupport.normalizedBluetoothAddress($0.addressString) == address
        }) else {
            return kIOReturnNotFound
        }
        return device.isConnected() ? kIOReturnSuccess : device.openConnection()
    }

    private static func waitForOutputDevice(matching route: MixerDiscoveredOutputDevice,
                                            timeout: TimeInterval) -> MixerOutputDevice? {
        let deadline = Date().addingTimeInterval(timeout)
        var previousCandidateUID: String?
        repeat {
            let devices = outputDevices(defaultUID: defaultOutputDeviceUID())
            let candidate = outputDevice(matching: route, in: devices)
            if MixerRoutingSupport.outputDeviceIsStable(previousUID: previousCandidateUID,
                                                        candidateUID: candidate?.uid) {
                return candidate
            }
            previousCandidateUID = candidate?.uid
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }

    private static func outputDevice(matching route: MixerDiscoveredOutputDevice,
                                     in devices: [MixerOutputDevice]) -> MixerOutputDevice? {
        return devices.first {
            $0.canBeDefaultOutput
                && MixerRoutingSupport.outputMatchesDiscoveredBluetooth(name: $0.name,
                                                                        uid: $0.uid,
                                                                        route: route)
        }
    }

    private static func audioProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func outputDevices(defaultUID: String?) -> [MixerOutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var deviceIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        var devices: [MixerOutputDevice] = []
        for deviceID in deviceIDs {
            guard hasOutputStreams(deviceID) else { continue }

            var isAlive: UInt32 = 1
            if read(deviceID, kAudioDevicePropertyDeviceIsAlive, &isAlive), isAlive == 0 {
                continue
            }
            var isHidden: UInt32 = 0
            if read(deviceID, kAudioDevicePropertyIsHidden, &isHidden), isHidden != 0 {
                continue
            }
            let canBeDefaultOutput = canBeDefault(deviceID,
                                                  selector: kAudioDevicePropertyDeviceCanBeDefaultDevice)
            let canBeDefaultSystemOutput = canBeDefault(
                deviceID,
                selector: kAudioDevicePropertyDeviceCanBeDefaultSystemDevice)

            var uidRef: CFString = "" as CFString
            guard read(deviceID, kAudioDevicePropertyDeviceUID, &uidRef) else { continue }
            let uid = uidRef as String
            guard !uid.isEmpty else { continue }

            var nameRef: CFString = "" as CFString
            let name = read(deviceID, kAudioObjectPropertyName, &nameRef)
                ? nameRef as String
                : uid
            guard name != "Vorssaint Mixer" else { continue }
            let dataSourceName = outputDataSourceName(for: deviceID)
            let volumeControl = outputVolumeControl(for: deviceID)

            devices.append(MixerOutputDevice(id: uid,
                                             uid: uid,
                                             name: name,
                                             isDefault: uid == defaultUID,
                                             isHeadphones: MixerRoutingSupport.outputLooksLikeHeadphones(
                                                name: name,
                                                uid: uid,
                                                dataSourceName: dataSourceName),
                                             canBeDefaultOutput: canBeDefaultOutput,
                                             canBeDefaultSystemOutput: canBeDefaultSystemOutput,
                                             volume: volumeControl.flatMap {
                                                outputVolume(for: deviceID, control: $0)
                                             },
                                             volumeSettable: volumeControl?.isSettable == true,
                                             audioObjectID: deviceID,
                                             volumeControl: volumeControl))
        }

        return devices.sorted { lhs, rhs in
            MixerRoutingSupport.deviceDisplayOrderedBefore(
                isDefault: lhs.isDefault, name: lhs.name, uid: lhs.uid,
                otherIsDefault: rhs.isDefault, otherName: rhs.name, otherUID: rhs.uid)
        }
    }

    private static func outputDataSourceName(for deviceID: AudioObjectID) -> String? {
        var dataSourceID: UInt32 = 0
        guard read(deviceID,
                   kAudioDevicePropertyDataSource,
                   &dataSourceID,
                   scope: kAudioObjectPropertyScopeOutput) else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var nameRef: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &dataSourceID) { dataSourcePointer in
            withUnsafeMutablePointer(to: &nameRef) { namePointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(dataSourcePointer),
                    mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                    mOutputData: UnsafeMutableRawPointer(namePointer),
                    mOutputDataSize: UInt32(MemoryLayout<CFString>.size))
                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(
                    deviceID,
                    &address,
                    0,
                    nil,
                    &size,
                    &translation)
            }
        }
        guard status == noErr else { return nil }
        return nameRef as String
    }

    private static func hasOutputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= MemoryLayout<AudioObjectID>.size
    }

    private static func canBeDefault(_ deviceID: AudioObjectID,
                                     selector: AudioObjectPropertySelector) -> Bool {
        var value: UInt32 = 0
        return read(deviceID, selector, &value, scope: kAudioObjectPropertyScopeOutput) && value != 0
    }

    private static func defaultOutputDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultOutputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uidRef: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uidRef) else { return nil }
        return uidRef as String
    }

    private static func setDefaultDevice(_ deviceID: AudioObjectID,
                                         selector: AudioObjectPropertySelector) -> OSStatus {
        var nextDeviceID = deviceID
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                          &address,
                                          0,
                                          nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size),
                                          &nextDeviceID)
    }

    private static let outputVolumeSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyVolumeScalar,
    ]

    private static let masterOutputVolumeEndpoints = outputVolumeSelectors.map {
        OutputVolumeEndpoint(selector: $0, element: kAudioObjectPropertyElementMain)
    }

    private static func outputVolumeAddress(_ endpoint: OutputVolumeEndpoint) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: endpoint.selector,
                                   mScope: kAudioObjectPropertyScopeOutput,
                                   mElement: endpoint.element)
    }

    private static func outputVolumeChannelElements(for deviceID: AudioObjectID) -> [AudioObjectPropertyElement] {
        var elements: [AudioObjectPropertyElement] = []
        var preferred = [UInt32](repeating: 0, count: 2)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size * preferred.count)
        let status = preferred.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(paramErr) }
            return AudioObjectGetPropertyData(deviceID,
                                              &address,
                                              0,
                                              nil,
                                              &size,
                                              baseAddress)
        }
        if status == noErr {
            elements.append(contentsOf: preferred.compactMap {
                $0 == 0 ? nil : AudioObjectPropertyElement($0)
            })
        }

        // ponytail: stereo fallback; enumerate stream layouts if multi-channel precision matters.
        elements.append(contentsOf: [1, 2])
        var seen = Set<AudioObjectPropertyElement>()
        return elements.filter { seen.insert($0).inserted }
    }

    private static func outputVolumeValue(for deviceID: AudioObjectID,
                                          endpoint: OutputVolumeEndpoint) -> Double? {
        var address = outputVolumeAddress(endpoint)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr,
              volume.isFinite else { return nil }
        return Double(min(max(volume, 0), 1))
    }

    private static func outputVolume(for deviceID: AudioObjectID,
                                     control: OutputVolumeControl) -> Double? {
        let values = control.endpoints.compactMap {
            outputVolumeValue(for: deviceID, endpoint: $0)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func outputVolumeSettable(for deviceID: AudioObjectID,
                                             endpoint: OutputVolumeEndpoint) -> Bool {
        var address = outputVolumeAddress(endpoint)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr
            && isSettable.boolValue
    }

    private static func outputVolumeControl(for deviceID: AudioObjectID) -> OutputVolumeControl? {
        let masterEndpoints = masterOutputVolumeEndpoints
        let channelEndpoints = outputVolumeChannelElements(for: deviceID).map {
            OutputVolumeEndpoint(selector: kAudioDevicePropertyVolumeScalar, element: $0)
        }
        let masterReadable = masterEndpoints.map { outputVolumeValue(for: deviceID, endpoint: $0) != nil }
        let masterSettable = masterEndpoints.map { outputVolumeSettable(for: deviceID, endpoint: $0) }
        let channelReadable = channelEndpoints.map { outputVolumeValue(for: deviceID, endpoint: $0) != nil }
        let channelSettable = channelEndpoints.map { outputVolumeSettable(for: deviceID, endpoint: $0) }

        guard let selection = MixerRoutingSupport.outputVolumeEndpointSelection(
            masterReadable: masterReadable,
            masterSettable: masterSettable,
            channelReadable: channelReadable,
            channelSettable: channelSettable
        ) else { return nil }
        let source = selection.group == .master ? masterEndpoints : channelEndpoints
        return OutputVolumeControl(endpoints: selection.indexes.map { source[$0] },
                                   isSettable: selection.isSettable)
    }

    private static func setOutputVolume(_ volume: Float32, for deviceID: AudioObjectID) -> Bool {
        guard let control = outputVolumeControl(for: deviceID) else { return false }
        return setOutputVolume(volume, for: deviceID, control: control)
    }

    private static func setOutputVolume(_ volume: Float32,
                                        for deviceID: AudioObjectID,
                                        control: OutputVolumeControl) -> Bool {
        guard control.isSettable, !control.endpoints.isEmpty else { return false }
        let clamped = min(max(volume, 0), 1)
        var succeeded = true
        for endpoint in control.endpoints {
            var address = outputVolumeAddress(endpoint)
            var nextVolume = clamped
            if AudioObjectSetPropertyData(deviceID,
                                          &address,
                                          0,
                                          nil,
                                          UInt32(MemoryLayout<Float32>.size),
                                          &nextVolume) != noErr {
                succeeded = false
            }
        }
        return succeeded
    }

    @discardableResult
    fileprivate static func read<T>(_ object: AudioObjectID,
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

// MARK: - Tap engine

/// Availability-erased face of the engine, so the mixer can store engines on
/// any macOS while the implementation requires 14.4.
private protocol GainEngine: AnyObject {
    var gain: Float { get set }
    var tappedObjects: [AudioObjectID] { get }
    var outputDeviceUID: String { get }
    func stop()
}

/// The audio path for one routed app: a muted process tap feeding an aggregate
/// device whose IO proc re-renders the samples scaled by `gain` onto the chosen
/// output device.
@available(macOS 14.4, *)
private final class TapGainEngine: GainEngine {
    let tappedObjects: [AudioObjectID]
    let outputDeviceUID: String
    var gain: Float {
        get { gainBox.value }
        set { gainBox.value = min(max(newValue, 0), Float(AppVolumeMixer.maxVolume)) }
    }

    /// Read on the realtime audio thread, written from the main thread; a
    /// torn float write is harmless here (one transient sample scale).
    private final class GainBox { var value: Float = 1 }

    private let gainBox = GainBox()
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?

    init?(objects: [AudioObjectID], gain: Float, outputDeviceUID: String) {
        tappedObjects = objects
        gainBox.value = min(max(gain, 0), Float(AppVolumeMixer.maxVolume))
        self.outputDeviceUID = outputDeviceUID

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            return nil
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vorssaint Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let box = gainBox
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil, { _, input, _, output, _ in
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
            var gain = box.value
            let boosting = gain > 1
            var low: Float = -1, high: Float = 1
            for (index, inputBuffer) in inputBuffers.enumerated() where index < outputBuffers.count {
                guard let source = inputBuffer.mData?.assumingMemoryBound(to: Float.self),
                      let destination = outputBuffers[index].mData?.assumingMemoryBound(to: Float.self)
                else { continue }
                let frames = min(Int(inputBuffer.mDataByteSize),
                                 Int(outputBuffers[index].mDataByteSize)) / MemoryLayout<Float>.size
                vDSP_vsmul(source, 1, &gain, destination, 1, vDSP_Length(frames))
                // A boost can push samples past [-1, 1]; hard-limit so nothing out
                // of range reaches the device (a clean clip, never garbage).
                if boosting {
                    vDSP_vclip(destination, 1, &low, &high, destination, 1, vDSP_Length(frames))
                }
            }
        }) == noErr else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            stop()
            return nil
        }
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            self.ioProc = nil
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
    }

    deinit { stop() }
}
