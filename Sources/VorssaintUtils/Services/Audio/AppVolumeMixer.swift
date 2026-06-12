import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio

/// One app in the mixer: every audio-producing process it is responsible for,
/// rolled into a single row.
struct MixerApp: Identifiable, Equatable {
    /// Stable identity for persistence: the bundle id when there is one,
    /// otherwise the process name (pids recycle, names don't).
    let id: String
    let ownerPid: pid_t
    let name: String
    let audioObjects: [AudioObjectID]
    var volume: Double
}

/// Per-app volume control, something macOS does not offer natively.
///
/// For every app the user turns down, a muted CoreAudio process tap removes
/// the app's sound from the output device, and an aggregate device re-renders
/// the tapped stream with the chosen gain (the AudioCap architecture, public
/// API since macOS 14.4). Apps at 100% are left completely untouched —
/// bit-perfect passthrough, zero overhead. Volumes persist per app and
/// re-apply when the app plays again.
final class AppVolumeMixer: ObservableObject {
    static let shared = AppVolumeMixer()

    static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    @Published private(set) var apps: [MixerApp] = []
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
    private let buildQueue = DispatchQueue(label: "com.vorssaint.utils.mixer", qos: .userInitiated)

    private init() {}

    // MARK: - Lifecycle

    /// Starts watching audio processes. Saved volumes re-apply as soon as the
    /// matching app produces sound — no panel interaction needed.
    func start() {
        guard Self.isSupported, !listenerInstalled else { return }
        listenerInstalled = true
        installListener(selector: kAudioHardwarePropertyProcessObjectList)
        installListener(selector: kAudioHardwarePropertyDefaultOutputDevice)
        refreshApps()
    }

    /// Tears every tap down so all apps return to untouched system output.
    func stopAll() {
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

    func setVolume(_ volume: Double, for app: MixerApp) {
        let clamped = min(max(volume, 0), 1)
        persistVolume(clamped, for: app.id)
        if clamped > 0.001 { lastAudibleVolume[app.id] = clamped }
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].volume = clamped
        }
        applyVolume(clamped, for: app)
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
    private func applyVolume(_ volume: Double, for app: MixerApp) {
        if volume >= 0.999 {
            // Full volume: remove the tap entirely — true passthrough.
            engines.removeValue(forKey: app.id)?.stop()
            return
        }
        if let engine = engines[app.id] {
            engine.gain = Float(volume)
            return
        }
        guard #available(macOS 14.4, *), !buildingEngines.contains(app.id) else { return }

        buildingEngines.insert(app.id)
        buildQueue.async { [weak self] in
            let engine = TapGainEngine(objects: app.audioObjects, gain: Float(volume))
            DispatchQueue.main.async {
                guard let self else {
                    engine?.stop()
                    return
                }
                self.buildingEngines.remove(app.id)
                guard let engine else {
                    self.needsPermission = true
                    return
                }
                self.needsPermission = false
                // The slider may have moved (or returned to 100%) while the
                // engine was being built — honor the latest state.
                let latest = self.apps.first { $0.id == app.id }?.volume ?? volume
                if latest >= 0.999 {
                    engine.stop()
                } else {
                    engine.gain = Float(latest)
                    self.engines[app.id] = engine
                }
            }
        }
    }

    // MARK: - Process discovery

    private func refreshApps() {
        guard Self.isSupported else { return }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let saved = savedVolumes()

        var groups: [pid_t: [AudioObjectID]] = [:]
        var bundleHints: [pid_t: String] = [:]
        for object in Self.audioProcessObjects() {
            // Audio starting/stopping in a process flips IsRunningOutput
            // without changing the object list — subscribe per object.
            subscribeToRunningChanges(of: object)

            var pid: pid_t = -1
            guard Self.read(object, kAudioProcessPropertyPID, &pid), pid > 0, pid != ownPid else { continue }
            var running: UInt32 = 0
            _ = Self.read(object, kAudioProcessPropertyIsRunningOutput, &running)
            guard running != 0 else { continue }

            let owner = ResponsibleProcess.owner(of: pid)
            groups[owner, default: []].append(object)
            if bundleHints[owner] == nil,
               let bundle = NSRunningApplication(processIdentifier: owner)?.bundleIdentifier {
                bundleHints[owner] = bundle
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
                                 volume: saved[id] ?? 1))
        }
        next.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard next != apps else { return }
        apps = next
        reconcileEngines(with: next)
    }

    /// Brings the running engines in line with the current app list: drops
    /// taps for apps that stopped playing, retargets taps whose process set
    /// changed (new helper spawned), and applies saved volumes to newcomers.
    private func reconcileEngines(with apps: [MixerApp]) {
        let byId = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        for (id, engine) in engines {
            guard let app = byId[id] else {
                engine.stop()
                engines.removeValue(forKey: id)
                continue
            }
            if engine.tappedObjects != app.audioObjects {
                let gain = engine.gain
                engine.stop()
                engines.removeValue(forKey: id)
                applyVolume(Double(gain), for: app)
            }
        }

        for app in apps where app.volume < 0.999 && engines[app.id] == nil {
            applyVolume(app.volume, for: app)
        }
    }

    // MARK: - Persistence

    private func savedVolumes() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: DefaultsKey.appVolumes) as? [String: Double] ?? [:]
    }

    private func persistVolume(_ volume: Double, for id: String) {
        var volumes = savedVolumes()
        if volume >= 0.999 {
            volumes.removeValue(forKey: id)
        } else {
            volumes[id] = volume
        }
        UserDefaults.standard.set(volumes, forKey: DefaultsKey.appVolumes)
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

    @discardableResult
    fileprivate static func read<T>(_ object: AudioObjectID,
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
}

// MARK: - Tap engine

/// Availability-erased face of the engine, so the mixer can store engines on
/// any macOS while the implementation requires 14.4.
private protocol GainEngine: AnyObject {
    var gain: Float { get set }
    var tappedObjects: [AudioObjectID] { get }
    func stop()
}

/// The audio path for one app while its volume is below 100%: a muted process
/// tap (the app's sound no longer reaches the speakers) feeding an aggregate
/// device whose IO proc re-renders the samples scaled by `gain` onto the real
/// output device.
@available(macOS 14.4, *)
private final class TapGainEngine: GainEngine {
    let tappedObjects: [AudioObjectID]
    var gain: Float {
        get { gainBox.value }
        set { gainBox.value = min(max(newValue, 0), 1) }
    }

    /// Read on the realtime audio thread, written from the main thread; a
    /// torn float write is harmless here (one transient sample scale).
    private final class GainBox { var value: Float = 1 }

    private let gainBox = GainBox()
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?

    init?(objects: [AudioObjectID], gain: Float) {
        tappedObjects = objects
        gainBox.value = min(max(gain, 0), 1)

        var defaultDevice = AudioObjectID(0)
        guard AppVolumeMixer.read(AudioObjectID(kAudioObjectSystemObject),
                                  kAudioHardwarePropertyDefaultOutputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uidRef: CFString = "" as CFString
        guard AppVolumeMixer.read(defaultDevice, kAudioDevicePropertyDeviceUID, &uidRef) else { return nil }
        let outputUID = uidRef as String

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            return nil
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vorssaint Utils Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
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
            for (index, inputBuffer) in inputBuffers.enumerated() where index < outputBuffers.count {
                guard let source = inputBuffer.mData?.assumingMemoryBound(to: Float.self),
                      let destination = outputBuffers[index].mData?.assumingMemoryBound(to: Float.self)
                else { continue }
                let frames = min(Int(inputBuffer.mDataByteSize),
                                 Int(outputBuffers[index].mDataByteSize)) / MemoryLayout<Float>.size
                vDSP_vsmul(source, 1, &gain, destination, 1, vDSP_Length(frames))
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
