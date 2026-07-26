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
    let isHeadphones: Bool
    let canBeDefaultOutput: Bool
    let canBeDefaultSystemOutput: Bool
    fileprivate let audioObjectID: AudioObjectID
}

/// One app in the mixer: every audio-producing process it is responsible for,
/// rolled into a single row.
struct MixerApp: Identifiable, Equatable {
    /// Identifies the row and its engine while the app runs.
    let id: String
    /// The key this row's volume and route are saved under: bundle id, or
    /// display name for a process without one. Nil when neither exists; such
    /// a row is still listed and adjustable, but writes nothing to disk.
    let persistenceID: String?
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

    var identity: MixerRowIdentity {
        MixerRowIdentity(rowID: id, persistenceID: persistenceID)
    }
}

/// An app the user took out of the mixer list, remembered by name so it can
/// be brought back even while it is not running (issue #300).
struct MixerHiddenApp: Identifiable, Equatable {
    let id: String
    let name: String
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
    /// Apps kept out of the list (issue #300), including the Finder when its
    /// own toggle hides it, so the panel can offer to bring any of them back.
    @Published private(set) var hiddenApps: [MixerHiddenApp] = []

    private var engines: [String: any GainEngine] = [:]
    /// Arbitrates the engine builds running off-main: it suppresses duplicate
    /// builds while a slider keeps dragging, and discards a build that lands
    /// after the mixer moved on (which would leave two live taps on one app).
    private var builds = MixerEngineBuilds()
    /// When each row's engine last changed, so a row whose audio objects
    /// flicker is rebuilt once instead of once per notification.
    private var engineChangeAt: [String: Double] = [:]
    /// When each row's audio last went away. Kept apart from the change stamp
    /// above: the wait before letting a tap go has to be measured from the
    /// moment the audio disappeared, not from whenever the tap was built.
    private var objectsLostAt: [String: Double] = [:]
    /// The last render count seen for each row's engine, so reconciliation
    /// can tell an engine that is rendering from one the HAL quietly stopped
    /// driving after sleep or a device reconfiguration (issue #341).
    private var engineRenderProgress: [String: MixerRoutingSupport.EngineRenderObservation] = [:]
    private var engineReconcilePending = false
    /// Volumes and routes of rows without a bundle id: adjustable while the
    /// process runs, never written to disk.
    private var sessionVolumes: [String: Double] = [:]
    private var sessionRoutes: [String: String] = [:]
    private var lastAudibleVolume: [String: Double] = [:]
    private var listenerInstalled = false
    /// The global HAL listeners (devices, default output, process list), kept
    /// so stop() can remove each one again when the mixer leaves the hub.
    private var globalListeners: [AudioObjectPropertySelector] = []
    /// One IsRunningOutput listener per live process object, kept so the
    /// registration can be removed when the process disappears. Without
    /// removal, a week of app churn leaves thousands of dead listeners
    /// registered with the HAL.
    private var runningListeners = Set<AudioObjectID>()
    private var stopped = false
    /// Waking is the one moment the render path of a live tap can die with no
    /// audio notification left to reveal it, so the wake itself asks for a
    /// refresh and reconciliation verifies every engine is still rendering.
    private var wakeObserver: NSObjectProtocol?
    private var lastAutomaticLoweredOutputUID: String?
    /// The output volume as it was before the headphone disconnect protection
    /// lowered it, so the speakers can be handed back the way they were found.
    private var loweredOutput: LoweredOutput?
    private var refreshPending = false
    private var lastListenerRefreshAt: CFAbsoluteTime = 0
    /// Decides which HAL pass gets to publish: one reader at a time, and a
    /// pass the mixer no longer wants is dropped rather than publishing state
    /// that is already out of date.
    private var refresh = MixerRefreshCoordinator()
    private let buildQueue = DispatchQueue(label: "com.vorssaint.utils.mixer", qos: .userInitiated)
    /// Every CoreAudio property read runs here, and every HAL notification is
    /// delivered here. Reads serialize behind the audio daemon's device state,
    /// so while a device is being reconfigured (headphones pairing, an
    /// interface renegotiating, a display with audio waking) a single read can
    /// wait for as long as the daemon holds that device — and a reconfiguration
    /// is exactly what fires the listeners in the first place.
    ///
    /// Deliberately not `buildQueue`: creating a tap and its aggregate device
    /// takes far longer than reading a property, and the panel must never wait
    /// behind one to learn which devices exist.
    private let halQueue = DispatchQueue(label: "com.vorssaint.utils.mixer.hal", qos: .userInitiated)

    private init() {}

    // MARK: - Lifecycle

    /// The whole mixer follows its hub availability: switched off means no
    /// HAL listeners, no taps and no published state at all.
    func syncWithPreferences() {
        if AppFeature.mixer.isAvailable {
            start()
        } else {
            stop()
        }
    }

    /// Starts watching audio processes. Saved volumes re-apply as soon as the
    /// matching app produces sound — no panel interaction needed.
    func start() {
        stopped = false
        publishHiddenApps()
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
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                // A wake can wedge an engine while leaving the HAL snapshot
                // byte-identical, and apply() skips reconciliation when
                // nothing changed. Dropping the stored render observations
                // and reconciling directly arms the note-then-recheck
                // sequence deterministically, so a frozen engine is caught
                // even on a quiet wake.
                self.engineRenderProgress.removeAll()
                self.refreshApps()
                self.reconcileEngines(with: self.apps)
                self.scheduleEngineReconcile(after: 2)
            }
        }
        refreshApps()
    }

    /// Tears every tap down so all apps return to untouched system output, and
    /// hands back the one system setting the mixer changes on its own.
    func stopAll() {
        stopped = true
        builds.invalidateAll()
        for engine in engines.values { engine.stop() }
        engines.removeAll()
        engineChangeAt.removeAll()
        objectsLostAt.removeAll()
        engineRenderProgress.removeAll()
        restoreLoweredOutputVolume()
    }

    /// Full teardown for the hub: taps, per-process listeners and the global
    /// HAL listeners all go away, and the published state empties out.
    func stop() {
        stopAll()
        sessionVolumes.removeAll()
        sessionRoutes.removeAll()
        // A refresh already reading the HAL must not publish into a mixer that
        // is no longer watching, nor re-register the listeners just removed.
        refresh.discardInFlight()
        pruneRunningListeners(keeping: [])
        removeGlobalListeners()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if !apps.isEmpty { apps = [] }
        if !hiddenApps.isEmpty { hiddenApps = [] }
        if !outputDevices.isEmpty { outputDevices = [] }
        if currentOutputDeviceUID != nil { currentOutputDeviceUID = nil }
        if outputSwitchError != nil { outputSwitchError = nil }
        if needsPermission { needsPermission = false }
    }

    /// What the audio system calls when something changes.
    ///
    /// Deliberately the smallest possible answer: the system decides which
    /// thread this arrives on and it is not always the same one, so all it
    /// does is ask the main thread for a refresh and return. Everything the
    /// refresh then reads from the audio system happens away from the main
    /// thread.
    ///
    /// This is the plain callback rather than the closure form on purpose.
    /// Handing a closure back to be removed never matches the one that was
    /// registered: the call answers that it worked and the listener stays,
    /// which measured as two live registrations after one removal and one
    /// re-registration. Matching on this function and the pointer below works.
    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let mixer = Unmanaged<AppVolumeMixer>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { mixer.scheduleListenerRefresh() }
        return noErr
    }

    /// Identifies these registrations as ours. Unretained is safe here and
    /// only here: the mixer is a single instance that lives as long as the app.
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

    private func removeGlobalListeners() {
        guard listenerInstalled else { return }
        listenerInstalled = false
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
    }

    private func subscribeToRunningChanges(of object: AudioObjectID) {
        guard !runningListeners.contains(object) else { return }
        var address = Self.isRunningOutputAddress()
        if AudioObjectAddPropertyListener(object, &address,
                                          Self.listenerCallback, listenerClient) == noErr {
            runningListeners.insert(object)
        }
    }

    /// Drops the listeners of process objects that no longer exist. Removal on
    /// a dead object can fail; the entry is forgotten either way. Object ids do
    /// come back (the HAL reuses them for later processes), and a returning id
    /// is simply subscribed again on the next refresh.
    private func pruneRunningListeners(keeping current: Set<AudioObjectID>) {
        for object in runningListeners where !current.contains(object) {
            var address = Self.isRunningOutputAddress()
            AudioObjectRemovePropertyListener(object, &address,
                                              Self.listenerCallback, listenerClient)
            runningListeners.remove(object)
        }
    }

    private static func isRunningOutputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
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

    // MARK: - Volume API (panel)

    /// 100% means bit-perfect passthrough (no tap). A value the UI would round to
    /// 100% counts as unity, so dragging near 100% or tapping reset both restore
    /// true passthrough; anything else (quieter or boosted) runs the gain engine.
    private func isUnity(_ volume: Double) -> Bool { MixerRoutingSupport.isUnity(volume) }

    func setVolume(_ volume: Double, for app: MixerApp) {
        guard !app.isBypassed else { return }
        let clamped = Defaults.sanitizedAppVolume(volume)
        persistVolume(clamped, for: app)
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
        persistOutputDeviceUID(sanitized, for: app)
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].selectedOutputDeviceUID = sanitized
            applyOutputRoute(to: &apps[index],
                             savedOutputs: [app.id: sanitized].compactMapValues { $0 },
                             availableUIDs: Set(outputDevices.map(\.uid)),
                             defaultUID: currentOutputDeviceUID)
            // The running tap is left alone here: applyRouting builds the one
            // for the new device first and only then stops this one, so the
            // sound never falls back to the old output in between.
            applyRouting(for: apps[index])
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

        let status = Self.setDefaultDevice(device.audioObjectID,
                                           selector: kAudioHardwarePropertyDefaultOutputDevice)
        guard status == noErr else {
            outputSwitchError = "OSStatus \(status)"
            refreshApps()
            return false
        }

        if device.canBeDefaultSystemOutput {
            _ = Self.setDefaultDevice(device.audioObjectID,
                                      selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        }

        outputSwitchError = nil
        // The system output just changed by this app's own hand, so a refresh
        // still reading the previous devices is thrown away; the one at the end
        // of this method replaces it.
        refresh.discardInFlight()
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
                              isHeadphones: outputDevice.isHeadphones,
                              canBeDefaultOutput: outputDevice.canBeDefaultOutput,
                              canBeDefaultSystemOutput: outputDevice.canBeDefaultSystemOutput,
                              audioObjectID: outputDevice.audioObjectID)
        }

        // Builds started for the previous device can no longer be installed;
        // the engines themselves stay live until reconciliation has their
        // replacement running on the new device.
        builds.invalidateAll()

        let availableUIDs = Set(outputDevices.map(\.uid))
        apps = apps.map { current in
            var app = current
            app.volume = storedVolume(for: app.identity, saved: preferences.volumes) ?? app.volume
            applyOutputRoute(to: &app,
                             savedOutputs: preferences.outputDeviceUIDs,
                             availableUIDs: availableUIDs,
                             defaultUID: device.uid)
            return app
        }
        reconcileEngines(with: apps)
        clearPermissionIfNoActiveAdjustments()
        refreshApps()
        return true
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

    /// Main-thread only. Engine creation happens off-main (CoreAudio object
    /// setup takes tens of milliseconds) and lands back here exactly once.
    ///
    /// A tap mutes the app on the real output and replays it through the
    /// aggregate, so an engine that goes away for even a moment hands the app
    /// straight back to the speakers at full volume. Replacements are built
    /// first and the old engine is stopped only once the new one is running.
    private func applyRouting(for app: MixerApp) {
        guard !stopped else { return }
        guard !app.isBypassed else {
            discardEngine(for: app.id)
            return
        }
        guard let targetOutputDeviceUID = app.effectiveOutputDeviceUID,
              appNeedsEngine(app) else {
            // System default at 100% stays true passthrough.
            discardEngine(for: app.id)
            clearPermissionIfNoActiveAdjustments()
            return
        }
        if let engine = engines[app.id],
           engine.tappedObjects == app.audioObjects,
           engine.outputDeviceUID == targetOutputDeviceUID {
            engine.gain = Float(app.volume)
            return
        }
        // Nothing is ever tapped on behalf of an app the user never adjusted.
        guard rowMayBeTapped(app) else {
            discardEngine(for: app.id)
            clearPermissionIfNoActiveAdjustments()
            return
        }
        guard #available(macOS 14.4, *), let token = builds.begin(app.id) else { return }

        buildQueue.async { [weak self] in
            let engine = TapGainEngine(objects: app.audioObjects,
                                       gain: Float(app.volume),
                                       outputDeviceUID: targetOutputDeviceUID)
            DispatchQueue.main.async {
                guard let self else {
                    engine?.stop()
                    return
                }
                self.install(engine, for: app.id, token: token)
            }
        }
    }

    /// Lands one finished build on the main thread.
    private func install(_ engine: (any GainEngine)?, for id: String, token: Int) {
        let isCurrentBuild = builds.isCurrent(id, token: token)
        builds.finish(id, token: token)
        // A build that started before the mixer moved on (feature switched
        // off, output device changed, a newer build for the same row) would
        // add a second live tap to the app and render its sound twice.
        guard isCurrentBuild, !stopped else {
            engine?.stop()
            return
        }
        guard let engine else {
            // The tap could not be created: keeping the engine that is already
            // running beats leaving the app with none, unless it renders to a
            // device that is gone, in which case it can only mute the app.
            if let running = engines[id],
               !outputDevices.contains(where: { $0.uid == running.outputDeviceUID }) {
                discardEngine(for: id)
            }
            // A row that still has a tap running is plainly not being refused
            // for lack of consent, so the permission hint stays out of it.
            if engines[id] == nil, !needsPermission {
                needsPermission = true
            }
            return
        }
        if needsPermission {
            needsPermission = false
        }
        // The slider may have moved (or returned to 100%) while the engine was
        // being built, or the app's audio objects may have changed. Honor the
        // latest state, never an old tap target.
        guard let latestApp = apps.first(where: { $0.id == id }) else {
            engine.stop()
            return
        }
        guard latestApp.audioObjects == engine.tappedObjects,
              latestApp.effectiveOutputDeviceUID == engine.outputDeviceUID,
              appNeedsEngine(latestApp) else {
            engine.stop()
            applyRouting(for: latestApp)
            return
        }
        engine.gain = Float(latestApp.volume)
        let previous = engines.updateValue(engine, forKey: id)
        engineChangeAt[id] = CFAbsoluteTimeGetCurrent()
        // The fresh engine starts its render count over.
        engineRenderProgress.removeValue(forKey: id)
        previous?.stop()
    }

    /// Stops and forgets a row's engine. Used where silence is the intent
    /// (back to 100% on the default output, row gone), never for a rebuild.
    private func discardEngine(for id: String) {
        engines.removeValue(forKey: id)?.stop()
        engineChangeAt.removeValue(forKey: id)
        objectsLostAt.removeValue(forKey: id)
        engineRenderProgress.removeValue(forKey: id)
    }

    private func rowMayBeTapped(_ app: MixerApp) -> Bool {
        MixerRoutingSupport.rowMayBeTapped(
            savedVolume: storedVolume(for: app.identity, saved: savedVolumes()),
            savedRouteUID: storedRoute(for: app.identity, saved: savedOutputDeviceUIDs()),
            defaultOutputDeviceUID: currentOutputDeviceUID)
    }

    private func appNeedsEngine(_ app: MixerApp) -> Bool {
        MixerRoutingSupport.requiresEngine(hasAudioObjects: !app.audioObjects.isEmpty,
                                           volume: app.volume,
                                           selectedOutputDeviceUID: app.selectedOutputDeviceUID,
                                           targetOutputDeviceUID: app.effectiveOutputDeviceUID,
                                           defaultOutputDeviceUID: currentOutputDeviceUID)
    }

    private func applyOutputRoute(to app: inout MixerApp,
                                  savedOutputs: [String: String],
                                  availableUIDs: Set<String>,
                                  defaultUID: String?) {
        let selectedUID = storedRoute(for: app.identity, saved: savedOutputs)
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

    /// The main-thread state one refresh pass needs, copied in so the HAL pass
    /// never reads a property that another thread can be writing.
    private struct RefreshRequest {
        let previousDefaultUID: String?
        let previousOutputDevices: [MixerOutputDevice]
        let lowered: LoweredOutputState
        let lowerOnHeadphonesDisconnect: Bool
        let lowerToPercent: Int
        let savedVolumes: [String: Double]
        let savedOutputs: [String: String]
        let sessionVolumes: [String: Double]
        let sessionRoutes: [String: String]
        let showFinder: Bool
        /// Persistence ids the list must leave out: the apps the user hid,
        /// plus the Finder while its toggle is off (issue #300).
        let hiddenRowIDs: Set<String>
        let ownPid: pid_t
    }

    /// Everything one refresh read from the HAL, handed back for the main
    /// thread to turn into published state.
    private struct RefreshSnapshot {
        let defaultUID: String?
        let outputDevices: [MixerOutputDevice]
        /// Nil where process taps do not exist (before macOS 14.4): the app
        /// list stays empty and no process object is looked at.
        let apps: [MixerApp]?
        let processObjects: [AudioObjectID]
        let lowered: LoweredOutputState
    }

    /// Kicks off one refresh. Reading the audio HAL happens on `halQueue`;
    /// everything published, every engine and every listener record is touched
    /// back on the main thread, where it lives.
    private func refreshApps() {
        // A throttled refresh can land after stop(); watching is over.
        guard listenerInstalled else { return }
        // A pass already reading the HAL holds the slot: running a second one
        // now would read against state the first has not published yet. The
        // request is remembered and runs as soon as that one lands.
        guard let generation = refresh.begin() else { return }
        let request = RefreshRequest(
            previousDefaultUID: currentOutputDeviceUID,
            previousOutputDevices: outputDevices,
            lowered: LoweredOutputState(lastAutomaticLoweredOutputUID: lastAutomaticLoweredOutputUID,
                                        loweredOutput: loweredOutput),
            lowerOnHeadphonesDisconnect: UserDefaults.standard.bool(
                forKey: DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect),
            lowerToPercent: Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(
                UserDefaults.standard.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)),
            savedVolumes: savedVolumes(),
            savedOutputs: savedOutputDeviceUIDs(),
            sessionVolumes: sessionVolumes,
            sessionRoutes: sessionRoutes,
            showFinder: UserDefaults.standard.bool(forKey: DefaultsKey.mixerShowFinder),
            hiddenRowIDs: MixerRoutingSupport.hiddenRowIDs(
                hiddenApps: savedHiddenApps(),
                showFinder: UserDefaults.standard.bool(forKey: DefaultsKey.mixerShowFinder)),
            ownPid: ProcessInfo.processInfo.processIdentifier)

        halQueue.async { [weak self] in
            let snapshot = Self.readSnapshot(request)
            DispatchQueue.main.async {
                self?.apply(snapshot, generation: generation)
            }
        }
    }

    /// Main thread. Turns one HAL snapshot into published state, engines and
    /// listener records, in the same order the synchronous version used.
    private func apply(_ snapshot: RefreshSnapshot, generation: Int) {
        // The mixer no longer wants this pass (it stopped, or changed the
        // output itself, while the pass was reading). The one thing still
        // worth keeping is a volume the pass lowered on the HAL, so the
        // speakers can be handed back later.
        guard refresh.finish(generation) else {
            if snapshot.lowered.loweredOutput != nil {
                lastAutomaticLoweredOutputUID = snapshot.lowered.lastAutomaticLoweredOutputUID
                loweredOutput = snapshot.lowered.loweredOutput
            }
            return
        }
        let refreshAgain = refresh.takeRepeatRequest()
        guard listenerInstalled else { return }
        defer { if refreshAgain { refreshApps() } }

        lastAutomaticLoweredOutputUID = snapshot.lowered.lastAutomaticLoweredOutputUID
        loweredOutput = snapshot.lowered.loweredOutput

        if snapshot.defaultUID != currentOutputDeviceUID, outputSwitchError != nil {
            outputSwitchError = nil
        }
        let audioEnvironmentChanged = currentOutputDeviceUID != nil
            && (snapshot.defaultUID != currentOutputDeviceUID || snapshot.outputDevices != outputDevices)
        if audioEnvironmentChanged {
            // Builds aimed at the previous audio environment can no longer be
            // installed; reconciliation below replaces the live engines one by
            // one, each new tap running before its predecessor stops.
            builds.invalidateAll()
        }
        // Assigning a @Published property signals SwiftUI even when the value is
        // identical, and refreshes run on every CoreAudio notification — publish
        // only real changes or a chatty HAL re-renders the panel continuously.
        if currentOutputDeviceUID != snapshot.defaultUID {
            currentOutputDeviceUID = snapshot.defaultUID
        }
        if snapshot.outputDevices != outputDevices {
            outputDevices = snapshot.outputDevices
        }

        guard let next = snapshot.apps else {
            if !apps.isEmpty {
                apps = []
            }
            return
        }

        pruneRunningListeners(keeping: Set(snapshot.processObjects))
        for object in snapshot.processObjects {
            // Audio starting/stopping in a process flips IsRunningOutput
            // without changing the object list — subscribe per object.
            subscribeToRunningChanges(of: object)
        }

        guard audioEnvironmentChanged || next != apps else { return }
        if apps != next {
            apps = next
        }
        reconcileEngines(with: next)
        clearPermissionIfNoActiveAdjustments()
    }

    /// Runs on `halQueue`. Every CoreAudio read of a refresh happens here and
    /// nothing outside the returned snapshot is touched.
    private static func readSnapshot(_ request: RefreshRequest) -> RefreshSnapshot {
        let defaultUID = defaultOutputDeviceUID()
        let nextOutputDevices = outputDevices(defaultUID: defaultUID)
        let availableUIDs = Set(nextOutputDevices.map(\.uid))
        let lowered = loweringOutputVolumeIfHeadphonesDisconnected(
            state: request.lowered,
            previousDefaultUID: request.previousDefaultUID,
            previousOutputDevices: request.previousOutputDevices,
            nextDefaultUID: defaultUID,
            nextOutputDevices: nextOutputDevices,
            lowerOnDisconnect: request.lowerOnHeadphonesDisconnect,
            lowerToPercent: request.lowerToPercent)

        guard isSupported else {
            return RefreshSnapshot(defaultUID: defaultUID,
                                   outputDevices: nextOutputDevices,
                                   apps: nil,
                                   processObjects: [],
                                   lowered: lowered)
        }

        let ownPid = request.ownPid
        let saved = request.savedVolumes
        let savedOutputs = request.savedOutputs
        let showFinder = request.showFinder
        var groups: [pid_t: [AudioObjectID]] = [:]
        var playing: Set<pid_t> = []
        var bypassed: Set<pid_t> = []
        var bundleHints: [pid_t: String] = [:]
        let processObjects = audioProcessObjects()
        for object in processObjects {
            var pid: pid_t = -1
            guard Self.read(object, kAudioProcessPropertyPID, &pid), pid > 0, pid != ownPid else { continue }

            // Show every regular app that holds an audio connection, not only
            // the ones making sound this instant, so apps are adjustable before
            // they play and stay put between sounds.
            guard let app = ResponsibleProcess.regularAppOwner(of: pid) else { continue }
            let owner = app.processIdentifier
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
                // The audio object knows the bundle id of its own process,
                // which is the app itself whenever it plays its own sound.
                // For a helper that plays on an app's behalf the owner found
                // above is the app, and its bundle id is the one that counts.
                bundleHints[owner] = app.bundleIdentifier
                    ?? (pid == owner ? Self.processBundleIdentifier(of: object) : nil)
            }
        }

        var next: [MixerApp] = []
        for (owner, objects) in groups {
            let fallbackName = "pid \(owner)"
            let name = ResponsibleProcess.displayName(pid: owner, fallback: fallbackName)
            // The pid fallback is not a name to save under: pids recycle.
            let identity = MixerRoutingSupport.rowIdentity(bundleIdentifier: bundleHints[owner],
                                                           ownerPid: owner,
                                                           displayName: name == fallbackName ? nil : name)
            // Hidden means no row, and with no row the engine reconciliation
            // below tears its tap down too: an app taken off the list always
            // plays untouched, never silently attenuated (issue #300).
            if MixerRoutingSupport.isHiddenFromMixer(persistenceID: identity.persistenceID,
                                                     hiddenIDs: request.hiddenRowIDs) { continue }
            let isBypassed = bypassed.contains(owner)
            let route = isBypassed ? nil : storedRoute(for: identity,
                                                       saved: savedOutputs,
                                                       session: request.sessionRoutes)
            next.append(MixerApp(id: identity.rowID,
                                 persistenceID: identity.persistenceID,
                                 ownerPid: owner,
                                 name: name,
                                 audioObjects: objects.sorted(),
                                 isPlaying: playing.contains(owner),
                                 isBypassed: isBypassed,
                                 selectedOutputDeviceUID: route,
                                 effectiveOutputDeviceUID: isBypassed ? nil : MixerRoutingSupport.effectiveDeviceUID(
                                    selectedUID: route,
                                    availableUIDs: availableUIDs,
                                    defaultUID: defaultUID),
                                 outputDeviceUnavailable: isBypassed ? false : MixerRoutingSupport.selectedDeviceUnavailable(
                                    selectedUID: route,
                                    availableUIDs: availableUIDs),
                                 volume: isBypassed ? 1 : (storedVolume(for: identity,
                                                                       saved: saved,
                                                                       session: request.sessionVolumes) ?? 1)))
        }
        if MixerRoutingSupport.needsPersistentFinderRow(
            showFinder: showFinder,
            hasFinderRow: next.contains { $0.id == MixerRoutingSupport.finderBundleIdentifier }
        ), let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: MixerRoutingSupport.finderBundleIdentifier
        ).first {
            let id = MixerRoutingSupport.finderBundleIdentifier
            next.append(MixerApp(id: id,
                                 persistenceID: id,
                                 ownerPid: finder.processIdentifier,
                                 name: finder.localizedName ?? "Finder",
                                 audioObjects: [],
                                 isPlaying: false,
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
        next.sort {
            MixerRoutingSupport.displayOrderedBefore(name: $0.name, id: $0.id,
                                                     otherName: $1.name, otherID: $1.id)
        }
        next = coalescingAppsWithDuplicateIDs(next)

        return RefreshSnapshot(defaultUID: defaultUID,
                               outputDevices: nextOutputDevices,
                               apps: next,
                               processObjects: processObjects,
                               lowered: lowered)
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
                                     persistenceID: existing.persistenceID,
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

    /// What the headphone disconnect protection has done to the system volume,
    /// so it can be undone. Main-thread state; a refresh pass gets a copy and
    /// hands the new value back.
    private struct LoweredOutput {
        let uid: String
        let previousVolume: Float32
        let appliedVolume: Float32
    }

    private struct LoweredOutputState {
        var lastAutomaticLoweredOutputUID: String?
        var loweredOutput: LoweredOutput?
    }

    /// Runs on `halQueue` as part of a refresh: reading and writing an output
    /// device's volume are HAL calls, and this fires exactly when the audio
    /// daemon is busiest (a device just went away).
    private static func loweringOutputVolumeIfHeadphonesDisconnected(
        state: LoweredOutputState,
        previousDefaultUID: String?,
        previousOutputDevices: [MixerOutputDevice],
        nextDefaultUID: String?,
        nextOutputDevices: [MixerOutputDevice],
        lowerOnDisconnect: Bool,
        lowerToPercent: Int) -> LoweredOutputState {
        var state = state
        if let nextDefaultUID,
           nextOutputDevices.first(where: { $0.uid == nextDefaultUID })?.isHeadphones == true {
            state.lastAutomaticLoweredOutputUID = nil
            // Headphones are back: the speakers get the volume they had before
            // the disconnect lowered them.
            state.loweredOutput = restoringLoweredOutputVolume(state.loweredOutput,
                                                               in: nextOutputDevices)
            return state
        }

        guard lowerOnDisconnect,
              let previousDefaultUID,
              let previousDefault = previousOutputDevices.first(where: { $0.uid == previousDefaultUID }),
              previousDefault.isHeadphones,
              !nextOutputDevices.contains(where: { $0.uid == previousDefaultUID && $0.isHeadphones }),
              let nextDefaultUID,
              let nextDefault = nextOutputDevices.first(where: { $0.uid == nextDefaultUID }),
              !nextDefault.isHeadphones,
              state.lastAutomaticLoweredOutputUID != nextDefaultUID else {
            return state
        }

        let volume = Float32(Double(lowerToPercent) / 100)
        let previousVolume = outputVolume(for: nextDefault.audioObjectID)
        if setOutputVolume(volume, for: nextDefault.audioObjectID) {
            state.lastAutomaticLoweredOutputUID = nextDefaultUID
            if let previousVolume, previousVolume > volume {
                state.loweredOutput = LoweredOutput(uid: nextDefaultUID,
                                                    previousVolume: previousVolume,
                                                    appliedVolume: volume)
            }
        }
        return state
    }

    /// Puts back the volume this feature lowered, as long as it is still the
    /// value the app set: anything else means it was changed since, and that
    /// choice wins. Returns what is left to restore later.
    private static func restoringLoweredOutputVolume(_ lowered: LoweredOutput?,
                                                     in devices: [MixerOutputDevice]) -> LoweredOutput? {
        guard let lowered else { return nil }
        guard let device = devices.first(where: { $0.uid == lowered.uid }) else {
            // The device is not around to restore right now; it may come back.
            return lowered
        }
        guard MixerRoutingSupport.shouldRestoreOutputVolume(
            appliedVolume: Double(lowered.appliedVolume),
            currentVolume: outputVolume(for: device.audioObjectID).map(Double.init)) else { return nil }
        _ = setOutputVolume(lowered.previousVolume, for: device.audioObjectID)
        return nil
    }

    /// Teardown path only, and deliberately synchronous: `stopAll()` runs while
    /// the app is quitting, so anything the mixer still owes the system has to
    /// be handed back before the process goes away.
    private func restoreLoweredOutputVolume() {
        loweredOutput = Self.restoringLoweredOutputVolume(loweredOutput, in: outputDevices)
    }

    /// Brings the running engines in line with the current app list: drops
    /// taps for apps that stopped playing, retargets taps whose process set
    /// changed (new helper spawned), and applies saved volumes to newcomers.
    ///
    /// A tap is never torn down to be rebuilt right after: the replacement is
    /// built first (applyRouting) and the old one stops once it is running.
    /// Rows that keep changing fold into a single trailing rebuild instead of
    /// one per notification.
    private func reconcileEngines(with apps: [MixerApp]) {
        let apps = Self.coalescingAppsWithDuplicateIDs(apps)
        var byId: [String: MixerApp] = [:]
        for app in apps {
            byId[app.id] = app
        }

        let now = CFAbsoluteTimeGetCurrent()
        var nextPassDelay: Double?

        for (id, engine) in Array(engines) {
            let app = byId[id]
            let hasAudioObjects = !(app?.audioObjects.isEmpty ?? true)

            // The row is gone or momentarily has no audio object: an app that
            // recreates its audio unit between clips does exactly this and is
            // back a few milliseconds later. Nothing is audible in between, so
            // the tap is kept for a short window instead of being destroyed
            // and rebuilt once per notification.
            guard hasAudioObjects, let app else {
                let lostAt = objectsLostAt[id]
                if let delay = MixerRoutingSupport.engineTeardownDelay(
                    hasAudioObjects: false,
                    lastChangeAt: lostAt,
                    now: now) {
                    if lostAt == nil { objectsLostAt[id] = now }
                    nextPassDelay = min(nextPassDelay ?? delay, delay)
                } else {
                    discardEngine(for: id)
                }
                continue
            }
            // The audio came back inside the window, so the next disappearance
            // starts its own wait rather than inheriting this one.
            objectsLostAt.removeValue(forKey: id)

            // Waking from sleep, or a device renegotiating right after, can
            // leave the aggregate wedged: its IO proc never runs again while
            // the tap keeps muting the app, and nothing else about the engine
            // looks wrong, so it used to be kept forever and the app stayed
            // silent until quit (issue #341). A render count that stops
            // moving while the app is playing is conclusive: the engine goes
            // away at once, which unmutes the app even if the rebuild below
            // cannot land yet, and a fresh tap takes its place.
            switch MixerRoutingSupport.engineRenderVerdict(previous: engineRenderProgress[id],
                                                           cycles: engine.renderCycles,
                                                           isPlaying: app.isPlaying,
                                                           now: now) {
            case .note(let observation, let recheckAfter):
                engineRenderProgress[id] = observation
                if let recheckAfter {
                    nextPassDelay = min(nextPassDelay ?? recheckAfter, recheckAfter)
                }
            case .stalled(let recheckAfter):
                nextPassDelay = min(nextPassDelay ?? recheckAfter, recheckAfter)
            case .wedged:
                engines.removeValue(forKey: id)?.stop()
                engineRenderProgress.removeValue(forKey: id)
                engineChangeAt[id] = now
                applyRouting(for: app)
                continue
            case nil:
                engineRenderProgress.removeValue(forKey: id)
            }

            guard engine.tappedObjects != app.audioObjects
                || engine.outputDeviceUID != app.effectiveOutputDeviceUID
                || !appNeedsEngine(app) else { continue }

            engineChangeAt[id] = now
            guard appNeedsEngine(app) else {
                // Back to 100% on the default output: passthrough is the point.
                discardEngine(for: id)
                continue
            }
            // An engine rendering to a device that is gone (headphones just
            // unplugged) can only mute the app, so it goes right away; every
            // other rebuild keeps its tap until the replacement is running.
            if !outputDevices.contains(where: { $0.uid == engine.outputDeviceUID }) {
                engines.removeValue(forKey: id)?.stop()
                engineRenderProgress.removeValue(forKey: id)
            }
            applyRouting(for: app)
        }

        for app in apps where appNeedsEngine(app) && engines[app.id] == nil {
            applyRouting(for: app)
        }
        forgetEngineStateOfMissingRows(byId)
        if let nextPassDelay {
            scheduleEngineReconcile(after: nextPassDelay)
        }
    }

    /// One trailing pass for rows whose rebuild was coalesced. A single
    /// scheduled block, never a repeating timer: with nothing left to
    /// reconcile the mixer goes back to being purely event driven.
    private func scheduleEngineReconcile(after delay: Double) {
        guard !engineReconcilePending else { return }
        engineReconcilePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.01)) { [weak self] in
            guard let self else { return }
            self.engineReconcilePending = false
            guard !self.stopped, self.listenerInstalled else { return }
            self.reconcileEngines(with: self.apps)
        }
    }

    /// Session state of rows that are gone. Volumes chosen for rows without a
    /// bundle id are deliberately kept: an app that recreates its audio unit
    /// drops off the list for a moment, and its slider must survive that.
    private func forgetEngineStateOfMissingRows(_ byId: [String: MixerApp]) {
        for id in engineChangeAt.keys where byId[id] == nil && engines[id] == nil {
            engineChangeAt.removeValue(forKey: id)
            objectsLostAt.removeValue(forKey: id)
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

    // MARK: - List visibility (issue #300)

    /// Takes a row out of the list. Its saved volume and route are kept for
    /// the day it comes back; while hidden the app is never tapped, so it
    /// always plays untouched. The Finder keeps its own preference key, from
    /// the days when it was the only row that could be hidden.
    func hideFromList(_ app: MixerApp) {
        guard let id = app.persistenceID else { return }
        if id == MixerRoutingSupport.finderBundleIdentifier {
            UserDefaults.standard.set(false, forKey: DefaultsKey.mixerShowFinder)
        } else {
            var hidden = savedHiddenApps()
            hidden[id] = app.name
            persistHiddenApps(hidden)
        }
        publishHiddenApps()
        refreshApps()
    }

    /// Puts a hidden app back on the list; its saved volume and route apply
    /// again on the next refresh.
    func showInList(id: String) {
        if id == MixerRoutingSupport.finderBundleIdentifier {
            UserDefaults.standard.set(true, forKey: DefaultsKey.mixerShowFinder)
        } else {
            var hidden = savedHiddenApps()
            hidden.removeValue(forKey: id)
            persistHiddenApps(hidden)
        }
        publishHiddenApps()
        refreshApps()
    }

    private func savedHiddenApps() -> [String: String] {
        MixerRoutingSupport.sanitizedHiddenApps(
            UserDefaults.standard.dictionary(forKey: DefaultsKey.mixerHiddenApps) ?? [:])
    }

    private func persistHiddenApps(_ hidden: [String: String]) {
        if hidden.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.mixerHiddenApps)
        } else {
            UserDefaults.standard.set(hidden, forKey: DefaultsKey.mixerHiddenApps)
        }
    }

    /// Rebuilds the published hidden list: the stored map, plus the Finder
    /// while its toggle keeps it out, sorted the same way as the visible rows.
    private func publishHiddenApps() {
        var entries = savedHiddenApps().map { MixerHiddenApp(id: $0.key, name: $0.value) }
        if !UserDefaults.standard.bool(forKey: DefaultsKey.mixerShowFinder) {
            let finderID = MixerRoutingSupport.finderBundleIdentifier
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: finderID)
                .first?.localizedName ?? "Finder"
            entries.append(MixerHiddenApp(id: finderID, name: name))
        }
        entries.sort {
            MixerRoutingSupport.displayOrderedBefore(name: $0.name, id: $0.id,
                                                     otherName: $1.name, otherID: $1.id)
        }
        if hiddenApps != entries { hiddenApps = entries }
    }

    /// The volume of a row: from disk when the row has a key to save under,
    /// otherwise from this session only. Static so a refresh pass can resolve
    /// rows off the main thread from copies of the session maps.
    private static func storedVolume(for identity: MixerRowIdentity,
                                     saved: [String: Double],
                                     session: [String: Double]) -> Double? {
        guard let key = identity.persistenceID else { return session[identity.rowID] }
        return saved[key]
    }

    private static func storedRoute(for identity: MixerRowIdentity,
                                    saved: [String: String],
                                    session: [String: String]) -> String? {
        guard let key = identity.persistenceID else { return session[identity.rowID] }
        return saved[key]
    }

    private func storedVolume(for identity: MixerRowIdentity, saved: [String: Double]) -> Double? {
        Self.storedVolume(for: identity, saved: saved, session: sessionVolumes)
    }

    private func storedRoute(for identity: MixerRowIdentity, saved: [String: String]) -> String? {
        Self.storedRoute(for: identity, saved: saved, session: sessionRoutes)
    }

    private func persistVolume(_ volume: Double, for app: MixerApp) {
        guard let id = app.persistenceID else {
            // Neither a bundle id nor a display name: nothing stable to write
            // down. The slider still works while the app runs.
            if isUnity(volume) {
                sessionVolumes.removeValue(forKey: app.id)
            } else {
                sessionVolumes[app.id] = volume
            }
            return
        }
        var volumes = savedVolumes()
        if isUnity(volume) {
            volumes.removeValue(forKey: id)
        } else {
            volumes[id] = volume
        }
        UserDefaults.standard.set(volumes, forKey: DefaultsKey.appVolumes)
    }

    private func persistOutputDeviceUID(_ uid: String?, for app: MixerApp) {
        guard let id = app.persistenceID else {
            if let uid {
                sessionRoutes[app.id] = uid
            } else {
                sessionRoutes.removeValue(forKey: app.id)
            }
            return
        }
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
              builds.isEmpty else { return }
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

    /// The bundle id the audio HAL itself reports for a process object. Used
    /// only to fill in an identity the running-application lookup could not
    /// provide, never to override it.
    private static func processBundleIdentifier(of object: AudioObjectID) -> String? {
        guard #available(macOS 14.4, *) else { return nil }
        var bundleRef: CFString = "" as CFString
        guard read(object, kAudioProcessPropertyBundleID, &bundleRef) else { return nil }
        let bundleID = bundleRef as String
        return bundleID.isEmpty ? nil : bundleID
    }

    private static func outputVolume(for deviceID: AudioObjectID) -> Float32? {
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyVolumeScalar,
        ]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var volume: Float32 = 0
            if read(deviceID, selector, &volume, scope: kAudioObjectPropertyScopeOutput) {
                return volume
            }
        }
        return nil
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
                                             audioObjectID: deviceID))
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

    private static func setOutputVolume(_ volume: Float32, for deviceID: AudioObjectID) -> Bool {
        let clamped = min(max(volume, 0), 1)
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyVolumeScalar,
        ]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }

            var isSettable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
                  isSettable.boolValue else { continue }

            var nextVolume = clamped
            let status = AudioObjectSetPropertyData(deviceID,
                                                    &address,
                                                    0,
                                                    nil,
                                                    UInt32(MemoryLayout<Float32>.size),
                                                    &nextVolume)
            if status == noErr {
                return true
            }
        }
        return false
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
    /// How many IO callbacks the engine has completed. A count that stops
    /// moving while the tapped app is playing means the aggregate is no
    /// longer rendering, so the tap can only mute (issue #341).
    var renderCycles: UInt64 { get }
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

    /// Written on the realtime audio thread, read from the main thread; the
    /// reader only asks whether the value moved at all, so being one
    /// callback behind is harmless.
    private final class CycleBox { var value: UInt64 = 0 }

    /// One limiter per output buffer, preallocated so the realtime thread
    /// never allocates. Touched only by the IO proc once rendering starts.
    private final class LimiterBox {
        var limiters: ContiguousArray<BoostLimiter>
        init(sampleRate: Double, bufferCount: Int) {
            limiters = ContiguousArray(repeating: BoostLimiter(sampleRate: sampleRate),
                                       count: bufferCount)
        }
    }

    private let gainBox = GainBox()
    private let cycleBox = CycleBox()
    var renderCycles: UInt64 { cycleBox.value }
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
        // A boost pushes loud samples past full scale, and clamping the
        // overshoot flattens every peak into audible crackle (issue #326).
        // The limiter turns the whole signal down for just the moment a peak
        // would not fit, so a boosted app gets louder without distorting.
        let limiterBox = LimiterBox(sampleRate: Self.nominalSampleRate(of: aggregateID),
                                    bufferCount: 8)
        let cycles = cycleBox
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil, { _, input, _, output, _ in
            cycles.value &+= 1
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
            var gain = box.value
            let boosting = gain > 1
            var low: Float = -1, high: Float = 1
            for (index, inputBuffer) in inputBuffers.enumerated() where index < outputBuffers.count {
                guard let source = inputBuffer.mData?.assumingMemoryBound(to: Float.self),
                      let destination = outputBuffers[index].mData?.assumingMemoryBound(to: Float.self)
                else { continue }
                let samples = min(Int(inputBuffer.mDataByteSize),
                                  Int(outputBuffers[index].mDataByteSize)) / MemoryLayout<Float>.size
                vDSP_vsmul(source, 1, &gain, destination, 1, vDSP_Length(samples))
                guard boosting else { continue }
                let channels = Int(outputBuffers[index].mNumberChannels)
                if index < limiterBox.limiters.count, channels > 0, samples % channels == 0 {
                    limiterBox.limiters[index].process(destination,
                                                       frames: samples / channels,
                                                       channels: channels)
                } else {
                    // A stream shaped like nothing a tap produces still must
                    // not hand the device samples out of range.
                    vDSP_vclip(destination, 1, &low, &high, destination, 1, vDSP_Length(samples))
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

    /// The rate the aggregate renders at, for the limiter's release timing.
    /// A failed read falls back to the common device rate; being off by a
    /// device's worth of rate only shifts the release by milliseconds.
    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var sampleRate: Float64 = 0
        guard AppVolumeMixer.read(deviceID, kAudioDevicePropertyNominalSampleRate, &sampleRate),
              sampleRate > 0 else { return 48000 }
        return sampleRate
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
