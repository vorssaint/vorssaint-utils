// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio

struct MixerOutputDevice: Identifiable, Equatable {
    let id: String
    let uid: String
    let name: String
    let isDefault: Bool
    let canBeDefaultOutput: Bool
    let canBeDefaultSystemOutput: Bool
    fileprivate let audioObjectID: AudioObjectID
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
    @Published private(set) var currentOutputDeviceUID: String?
    @Published private(set) var outputSwitchError: String?
    /// Set when tap creation fails with a permission error, so the panel can
    /// point at the System Audio Recording consent.
    @Published private(set) var needsPermission = false

    private var engines: [String: any GainEngine] = [:]
    /// Apps whose engine is being built off-main; suppresses duplicate builds
    /// while the slider keeps dragging.
    private var buildingEngines = Set<String>()
    private var lastAudibleVolume: [String: Double] = [:]
    private var listenerInstalled = false
    private var runningListeners = Set<AudioObjectID>()
    private var stopped = false
    private let buildQueue = DispatchQueue(label: "com.vorssaint.utils.mixer", qos: .userInitiated)

    private init() {}

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
        refreshApps()
    }

    /// Tears every tap down so all apps return to untouched system output.
    func stopAll() {
        stopped = true
        buildingEngines.removeAll()
        for engine in engines.values { engine.stop() }
        engines.removeAll()
    }

    private func installListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            self?.refreshApps()
        }
    }

    private func subscribeToRunningChanges(of object: AudioObjectID) {
        guard !runningListeners.contains(object) else { return }
        runningListeners.insert(object)
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(object, &address, .main) { [weak self] _, _ in
            self?.refreshApps()
        }
    }

    // MARK: - Volume API (panel)

    /// 100% means bit-perfect passthrough (no tap). A value the UI would round to
    /// 100% counts as unity, so dragging near 100% or tapping reset both restore
    /// true passthrough; anything else (quieter or boosted) runs the gain engine.
    private func isUnity(_ volume: Double) -> Bool { MixerRoutingSupport.isUnity(volume) }

    func setVolume(_ volume: Double, for app: MixerApp) {
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

    func setUniversalOutputDeviceUID(_ uid: String) {
        guard let sanitized = Defaults.sanitizedAppOutputDeviceUID(uid),
              let device = outputDevices.first(where: { $0.uid == sanitized && $0.canBeDefaultOutput }) else {
            outputSwitchError = L10n.shared.s.mixerOutputUnavailable
            refreshApps()
            return
        }

        let status = Self.setDefaultDevice(device.audioObjectID,
                                           selector: kAudioHardwarePropertyDefaultOutputDevice)
        guard status == noErr else {
            outputSwitchError = "OSStatus \(status)"
            refreshApps()
            return
        }

        if device.canBeDefaultSystemOutput {
            _ = Self.setDefaultDevice(device.audioObjectID,
                                      selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        }

        outputSwitchError = nil
        let preferences = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedOutputDeviceUIDs(),
            volumes: savedVolumes(),
            switchSucceeded: true)
        persistOutputDeviceUIDs(preferences.outputDeviceUIDs)

        currentOutputDeviceUID = device.uid
        outputDevices = outputDevices.map { outputDevice in
            MixerOutputDevice(id: outputDevice.id,
                              uid: outputDevice.uid,
                              name: outputDevice.name,
                              isDefault: outputDevice.uid == device.uid,
                              canBeDefaultOutput: outputDevice.canBeDefaultOutput,
                              canBeDefaultSystemOutput: outputDevice.canBeDefaultSystemOutput,
                              audioObjectID: outputDevice.audioObjectID)
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

    func toggleMute(_ app: MixerApp) {
        if app.volume > 0.001 {
            lastAudibleVolume[app.id] = app.volume
            setVolume(0, for: app)
        } else {
            setVolume(lastAudibleVolume[app.id] ?? 1, for: app)
        }
    }

    /// Main-thread only. Engine creation happens off-main (CoreAudio object
    /// setup takes tens of milliseconds) and lands back here exactly once.
    private func applyRouting(for app: MixerApp) {
        guard !stopped else { return }
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
                    self.needsPermission = true
                    return
                }
                self.needsPermission = false
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
        let defaultUID = Self.defaultOutputDeviceUID()
        let nextOutputDevices = Self.outputDevices(defaultUID: defaultUID)
        let availableUIDs = Set(nextOutputDevices.map(\.uid))
        if defaultUID != currentOutputDeviceUID {
            outputSwitchError = nil
        }
        let audioEnvironmentChanged = currentOutputDeviceUID != nil
            && (defaultUID != currentOutputDeviceUID || nextOutputDevices != outputDevices)
        if audioEnvironmentChanged {
            buildingEngines.removeAll()
            for engine in engines.values { engine.stop() }
            engines.removeAll()
        }
        currentOutputDeviceUID = defaultUID
        if nextOutputDevices != outputDevices {
            outputDevices = nextOutputDevices
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
        var bundleHints: [pid_t: String] = [:]
        for object in Self.audioProcessObjects() {
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
            next.append(MixerApp(id: id,
                                 ownerPid: owner,
                                 name: name,
                                 audioObjects: objects.sorted(),
                                 isPlaying: playing.contains(owner),
                                 selectedOutputDeviceUID: savedOutputs[id],
                                 effectiveOutputDeviceUID: MixerRoutingSupport.effectiveDeviceUID(
                                    selectedUID: savedOutputs[id],
                                    availableUIDs: availableUIDs,
                                    defaultUID: defaultUID),
                                 outputDeviceUnavailable: MixerRoutingSupport.selectedDeviceUnavailable(
                                    selectedUID: savedOutputs[id],
                                    availableUIDs: availableUIDs),
                                 volume: saved[id] ?? 1))
        }
        next.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard audioEnvironmentChanged || next != apps else { return }
        apps = next
        reconcileEngines(with: next)
        clearPermissionIfNoActiveAdjustments()
    }

    /// Brings the running engines in line with the current app list: drops
    /// taps for apps that stopped playing, retargets taps whose process set
    /// changed (new helper spawned), and applies saved volumes to newcomers.
    private func reconcileEngines(with apps: [MixerApp]) {
        let byId = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

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

            devices.append(MixerOutputDevice(id: uid,
                                             uid: uid,
                                             name: name,
                                             isDefault: uid == defaultUID,
                                             canBeDefaultOutput: canBeDefaultOutput,
                                             canBeDefaultSystemOutput: canBeDefaultSystemOutput,
                                             audioObjectID: deviceID))
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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
