// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import Foundation

/// Real routing and selection bodies against in-memory HAL responses and
/// preferences. No audio device, process tap or user setting is touched.
enum MixerUniversalRoutingContract {
    struct Device {
        let uid: String
        let canBeDefaultOutput: Bool
        let audioObjectID: AudioObjectID
    }

    enum L10n {
        static let shared = Strings()
        struct Strings {
            var s: Strings { self }
            let mixerOutputUnavailable = "unavailable"
        }
    }

    final class AirPlay {
        static let shared = AirPlay()
        static let isSpeakerConnected = false
        let isConnected = false
        func presentPicker() {}
    }

    enum VolumeDefaults {
        static var current: Foundation.UserDefaults!
        static var standard: Foundation.UserDefaults { current }
    }
    final class VolumeHost {
        typealias MixerApp = MixerUniversalRoutingContract.MixerApp
        typealias UserDefaults = VolumeDefaults
        var sessionVolumes: [String: Double] = [:]
    }

    final class Preferences {
        static let standard = Preferences()
        var values: [String: String] = [:]
        var arrays: [String: [String]] = [:]
        func string(forKey key: String) -> String? { values[key] }
        func bool(forKey key: String) -> Bool { values[key] == "1" }
        func set(_ value: Bool, forKey key: String) { values[key] = value ? "1" : "0" }
        func set(_ value: String?, forKey key: String) { values[key] = value }
        func stringArray(forKey key: String) -> [String]? { arrays[key] }
        func array(forKey key: String) -> [Any]? { arrays[key] }
        func removeObject(forKey key: String) { arrays[key] = nil; values[key] = nil }
        func set(_ value: [String], forKey key: String) { arrays[key] = value }
    }

    final class VirtualOutputService {
        static let shared = VirtualOutputService()
        var isActive = false
        var isStarting = false
        var selectedUIDs: [String] = []
        var physicalOutputUID: String?
        var requestedOutputUID: String?
        var rejectedUIDs: Set<String> = []
        func selectOutput(_ uid: String) -> Bool {
            guard isActive || isStarting || requestedOutputUID != nil, !rejectedUIDs.contains(uid) else { return false }
            selectedUIDs.append(uid); requestedOutputUID = uid; return true
        }
    }
    final class Switcher {
        typealias UserDefaults = Preferences
        typealias VirtualOutputService = MixerUniversalRoutingContract.VirtualOutputService
        var lastSwitchFailed = false
    }
    final class DeferredQueue {
        var pending: [() -> Void] = []
        func async(execute: @escaping () -> Void) { pending.append(execute) }
        func flush() { while !pending.isEmpty { pending.removeFirst()() } }
        func sync(execute: () -> Void) { flush(); execute() }
    }
    enum SelectionQueues { static let main = DeferredQueue() }
    enum SelectionHAL {
        static var current = VirtualOutputSupport.deviceUID
        static var nativeSelections: [String] = []
        static var systemCurrent = "alerts"
        static func physicalDevices() -> [(uid: String, id: AudioObjectID)] { [("fixed",1),("nativeA",2),("nativeB",3)] }
        static func hasHardwareVolume(_ uid: String) -> Bool { uid.hasPrefix("native") }
        static func restorableOutputs(systemSounds: Bool) -> [String] { ["fixed", "nativeA", "nativeB", "externalVirtual"] }
        static func componentDevice() -> AudioObjectID? { 99 }
        static func uid(_ device: AudioObjectID) -> String? { VirtualOutputSupport.deviceUID }
        static func defaultUID(_ selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice) -> String? { selector == kAudioHardwarePropertyDefaultSystemOutputDevice ? systemCurrent : current }
        static func select(_ uid: String, selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice) -> Bool {
            if selector == kAudioHardwarePropertyDefaultOutputDevice { current = uid; nativeSelections.append(uid) }
            else if selector == kAudioHardwarePropertyDefaultSystemOutputDevice { systemCurrent = uid }
            return true
        }
    }
    final class UpdateAlert {
        static var shown: [UpdateAlert] = []
        let alert: NSAlert
        var completion: ((NSApplication.ModalResponse) -> Void)?
        init(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
            self.alert = alert; self.completion = completion
        }
        static func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) -> UpdateAlert {
            let presentation = UpdateAlert(alert, completion: completion)
            shown.append(presentation); return presentation
        }
        func dismiss(with response: NSApplication.ModalResponse) {
            let callback = completion; completion = nil; callback?(response)
        }
    }
    enum UpdateHAL {
        static var installedComponentBuild: Int? = 4
        static var requiredComponentBuild = 5
        static var ready = false
    }
    struct UpdateBundle {
        static let main = UpdateBundle()
        static var available = true
        func url(forResource: String, withExtension: String) -> URL? {
            Self.available ? URL(fileURLWithPath: "/bundled/VorssaintAudio.pkg") : nil
        }
    }
    final class UpdateLauncher {
        static let shared = UpdateLauncher()
        var opened: [URL] = []
        var succeeds = true
        func open(_ url: URL) -> Bool { opened.append(url); return succeeds }
    }
    final class UpdateMixer {
        static let shared = UpdateMixer()
        var syncs = 0
        func syncSoftwareOutputWithPreferences() { syncs += 1 }
    }
    struct UpdateL10n {
        static let shared = UpdateL10n()
        let language = AppLanguage.enUS
        var s: UpdateL10n { self }
        let uninstallerCancel = "Cancel"
    }
    final class UpdateHost {
        typealias VirtualOutputHAL = UpdateHAL
        typealias NonModalAlert = UpdateAlert
        typealias NSWorkspace = UpdateLauncher
        typealias Bundle = UpdateBundle
        typealias UserDefaults = Preferences
        typealias AppVolumeMixer = UpdateMixer
        typealias L10n = UpdateL10n
        var isRemoving = false, installerOpened = false, updateOffered = false
        var acceptsOutputSelections = true
        var updateAlert: UpdateAlert?
        var error: String?
        var isInstalled: Bool { UpdateHAL.ready }
    }
    final class SelectionSession {
        typealias VirtualOutputHAL = SelectionHAL
        typealias DispatchQueue = SelectionQueues
        struct Bridge { let physicalUID: String }
        var queue = DeferredQueue()
        var isActive = true, isStarting = false, isRemoving = false, suspended = false
        var acceptsOutputSelections = true
        var installerOpened = false
        var updateAlert: UpdateAlert?
        var physicalOutputUID: String? = "fixed"
        var requestedOutputUID: String?
        let outputRequests = VirtualOutputSupport.OutputRequests()
        var previousOutput: String?, previousSystemOutput: String?
        var virtual: AudioObjectID? = 99
        var virtualUID = VirtualOutputSupport.deviceUID
        var bridge: Bridge? = Bridge(physicalUID: "fixed")
        var errors: [VirtualOutputSupport.Issue] = []
        func deactivate() {
            if virtual != nil, SelectionHAL.current == virtualUID { SelectionHAL.current = previousOutput ?? "nativeA" }
            virtual = nil; bridge = nil; physicalOutputUID = nil; isActive = false
        }
        func replaceBridge(physicalUID: String) {
            guard virtual != nil else { return }
            self.physicalOutputUID = physicalUID; bridge = Bridge(physicalUID: physicalUID)
            SelectionHAL.current = virtualUID; isActive = true
        }
        func publish(error: VirtualOutputSupport.Issue) { errors.append(error) }
    }
    final class PriorityHost {
        typealias AppVolumeMixer = Mixer
        var unplacedOutputUIDs: Set<String> = []
        var outputPriorityUIDs: [String] = []
    }
    final class Mixer {
        static let shared = Mixer()
        var prioritySelections: [String] = []
        func setPriorityOutputDeviceUID(_ uid: String) { prioritySelections.append(uid) }
        typealias VirtualOutputService = MixerUniversalRoutingContract.VirtualOutputService
        typealias MixerApp = MixerUniversalRoutingContract.MixerApp
        typealias L10n = MixerUniversalRoutingContract.L10n
        typealias AirPlayRouteManager = AirPlay
        typealias UserDefaults = Preferences
        typealias PreciseVolumeRollerService = MixerUniversalRoutingContract.PreciseVolumeRollerService
        static var deviceLists: [AudioObjectID: [AudioObjectID]] = [:]
        static var reads: [(AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyScope)] = []
        static var writes: [(AudioObjectID, AudioObjectPropertySelector)] = []
        static var writeStatus: OSStatus = noErr
        static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope) -> [AudioObjectID] {
            reads.append((object, selector, scope))
            return deviceLists[object] ?? []
        }
        static func setDefaultDevice(_ device: AudioObjectID, selector: AudioObjectPropertySelector) -> OSStatus {
            writes.append((device, selector))
            return writeStatus
        }

        var outputDevices = [Device(uid: "speakers", canBeDefaultOutput: true, audioObjectID: 10),
                             Device(uid: "airpods", canBeDefaultOutput: true, audioObjectID: 20)]
        var currentOutputDeviceUID: String? = "speakers"
        var outputSwitchError: String?
        var apps: [MixerApp] = []
        var volumeEdits: Set<String> = []
        var engines: [String: Bool] = [:]
        var savedRoutes: [String: String] = [:]
        var volumes: [String: Double] = [:]
        var sessionRoutes: [String: String] = [:]
        var sessionVolumes: [String: Double] = [:]
        var refresh = MixerRefreshCoordinator()
        var builds = MixerEngineBuilds()
        var engineRecovery = MixerEngineRecovery()
        var refreshCount = 0
        var applied: [MixerApp] = []
        func refreshApps() { refreshCount += 1 }
        func savedOutputDeviceUIDs() -> [String: String] { savedRoutes }
        func savedVolumes() -> [String: Double] { volumes }
        func persistOutputDeviceUIDs(_ routes: [String: String]) { savedRoutes = routes }
        func persistOutputDeviceUID(_ uid: String?, for app: MixerApp) {
            if let key = app.persistenceID { savedRoutes[key] = uid }
            else { sessionRoutes[app.id] = uid }
        }
        func applyRouting(for app: MixerApp) { applied.append(app) }
        func chooseAirPlaySpeaker(for app: MixerApp) {}
        func clearPermissionIfNoActiveAdjustments() {}
    }

    final class PreciseVolumeRollerService {
        static let shared = PreciseVolumeRollerService()
        func syncWithPreferences() {}
    }

    static func row(_ id: String = "process:77", objects: [AudioObjectID] = [100],
                    persistenceID: String? = "Wine Game", selectedUID: String? = nil,
                    bypassed: Bool = false, playing: Bool = true) -> MixerApp {
        MixerApp(id: id, persistenceID: persistenceID, ownerPid: 77, name: "Game",
                 audioObjects: objects, isPlaying: playing, isBypassed: bypassed,
                 selectedOutputDeviceUID: selectedUID, effectiveOutputDeviceUID: "airpods",
                 outputDeviceUnavailable: false, volume: 1)
    }

    private static func callAudioCompatibility(_ suite: TestSuite) {
        for id in ["com.hnc.Discord", "com.microsoft.teams2"] {
            let mixer = Mixer()
            var app = row(id, persistenceID: id, selectedUID: "airpods")
            app.supportsVolumeOverride = MixerRoutingSupport.needsScreenSharingProtection(bundleIdentifier: id)
            app.isBypassed = MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: id, name: "Call")
            // Old installations may already have a boost and a route saved.
            app.volume = 1.2
            mixer.apps = [app]
            mixer.volumes[id] = 1.2
            mixer.savedRoutes[id] = "airpods"
            suite.expect(!mixer.appNeedsEngine(app) && !mixer.rowMayBeTapped(app),
                         "\(id) cannot be tapped by saved gain or routing while protected")
            suite.expect(mixer.applyingCurrentVolumes(to: [app])[0].volume == 1,
                         "\(id) publishes unity while preserving the saved boost")

            mixer.setCallAppVolumeControl(true, for: app)
            suite.expect(!mixer.apps[0].isBypassed && mixer.apps[0].volume == 1.2
                         && mixer.apps[0].selectedOutputDeviceUID == "airpods"
                         && mixer.appNeedsEngine(mixer.apps[0]) && mixer.rowMayBeTapped(mixer.apps[0]),
                         "\(id) opt-in restores the saved level and output")
            let allowed = mixer.savedCallAppVolumeEnabled()
            suite.expect(allowed.contains(id.lowercased())
                         && !MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: id, name: "Call",
                                                                   allowCallAppVolume: allowed.contains(id.lowercased())),
                         "\(id) explicit opt-in survives a new discovery pass")

            let staleRead = mixer.refresh.begin()!
            let staleBuild = mixer.builds.begin(id)!
            let unrelatedBuild = mixer.builds.begin("com.spotify.client")!
            mixer.setCallAppVolumeControl(false, for: mixer.apps[0])
            let protected = mixer.apps[0]
            suite.expect(protected.isBypassed && protected.volume == 1
                         && protected.selectedOutputDeviceUID == nil && protected.effectiveOutputDeviceUID == nil
                         && protected.universalOutputRouteUID == nil && !protected.outputDeviceUnavailable,
                         "\(id) protection clears all live gain and route requests")
            suite.expect(mixer.applied.last == protected && !mixer.appNeedsEngine(protected)
                         && !mixer.rowMayBeTapped(protected),
                         "\(id) protection immediately asks routing to release the tap")
            suite.expect(!mixer.refresh.finish(staleRead) && !mixer.builds.isCurrent(id, token: staleBuild)
                         && mixer.builds.isCurrent("com.spotify.client", token: unrelatedBuild),
                         "\(id) rejects late reads and builds without cancelling another app's build")
            suite.expect(mixer.volumes[id] == 1.2 && mixer.savedRoutes[id] == "airpods"
                         && !mixer.savedCallAppVolumeEnabled().contains(id.lowercased()),
                         "\(id) protection preserves settings and removes the opt-in")

            mixer.setCallAppVolumeControl(true, for: protected)
            let replacement = mixer.builds.begin(id)
            mixer.builds.finish(id, token: staleBuild)
            suite.expect(mixer.apps[0].volume == 1.2 && mixer.apps[0].selectedOutputDeviceUID == "airpods"
                         && replacement.map { mixer.builds.isCurrent(id, token: $0) } == true,
                         "\(id) can resume after protection without an old build cancelling its replacement")
        }

        for id in ["com.hnc.Discord", "com.microsoft.teams2"] {
            for bypassed in [false, true] {
                for (firstSupports, secondSupports) in [(true, true), (true, false), (false, true)] {
                    let mixer = Mixer()
                    var first = row(id, persistenceID: id, bypassed: bypassed)
                    var second = row(id, objects: [101], persistenceID: id, bypassed: bypassed)
                    first.supportsVolumeOverride = firstSupports
                    second.supportsVolumeOverride = secondSupports
                    mixer.apps = Mixer.coalescingAppsWithDuplicateIDs([first, second])
                    suite.expect(mixer.apps.count == 1 && mixer.apps[0].supportsVolumeOverride,
                                 "\(id) keeps its volume control option after combining owner processes")
                    mixer.setCallAppVolumeControl(bypassed, for: mixer.apps[0])
                    suite.expect(mixer.apps[0].isBypassed != bypassed
                                 && mixer.applied.last == mixer.apps[0],
                                 "\(id) can change call protection after combining rows, bypassed: \(bypassed)")
                }
            }
        }

        let mixer = Mixer()
        let zoom = row("us.zoom.xos", persistenceID: "us.zoom.xos", bypassed: true)
        mixer.apps = [zoom]
        mixer.setCallAppVolumeControl(true, for: zoom)
        suite.expect(mixer.apps == [zoom] && mixer.applied.isEmpty,
                     "the override cannot enable taps for apps with a permanent bypass")
        Preferences.standard.arrays = [:]
    }

    static func driverUpdates(_ suite: TestSuite) {
        UpdateHAL.installedComponentBuild = 4; UpdateHAL.requiredComponentBuild = 5; UpdateHAL.ready = false
        UpdateBundle.available = true; UpdateLauncher.shared.succeeds = true
        UpdateLauncher.shared.opened = []; UpdateAlert.shown = []; UpdateMixer.shared.syncs = 0
        Preferences.standard.set(true, forKey: DefaultsKey.mixerSoftwareVolumeEnabled)
        let cancelled = UpdateHost()
        cancelled.offerComponentUpdateIfNeeded(enabled: true, needsUpdate: true)
        suite.expect(UpdateAlert.shown.count == 1 && cancelled.updateAlert != nil,
                     "an already-enabled fallback offers the required bundled driver update")
        cancelled.updateAlert?.dismiss(with: .alertSecondButtonReturn)
        cancelled.offerComponentUpdateIfNeeded(enabled: true, needsUpdate: true)
        suite.expect(UpdateAlert.shown.count == 1 && UpdateLauncher.shared.opened.isEmpty
                     && Preferences.standard.bool(forKey: DefaultsKey.mixerSoftwareVolumeEnabled),
                     "declining an update neither launches Installer nor repeats the offer on refresh")
        let stale = UpdateHost()
        stale.offerComponentUpdateIfNeeded(enabled: true, needsUpdate: true)
        UpdateHAL.installedComponentBuild = 6; UpdateHAL.ready = true
        stale.updateAlert?.dismiss(with: .alertFirstButtonReturn)
        suite.expect(UpdateLauncher.shared.opened.isEmpty,
                     "accepting a stale alert rechecks the installed version and never launches a downgrade")
        UpdateHAL.installedComponentBuild = 4; UpdateHAL.ready = false
        let disabled = UpdateHost()
        disabled.offerComponentUpdateIfNeeded(enabled: true, needsUpdate: true)
        disabled.acceptsOutputSelections = false
        Preferences.standard.set(false, forKey: DefaultsKey.mixerSoftwareVolumeEnabled)
        disabled.updateAlert?.dismiss(with: .alertFirstButtonReturn)
        suite.expect(UpdateLauncher.shared.opened.isEmpty && !Preferences.standard.bool(forKey: DefaultsKey.mixerSoftwareVolumeEnabled),
                     "an old automatic alert cannot re-enable fallback after the user turned it off")
        let installing = UpdateHost()
        installing.installForFallback()
        suite.expect(UpdateLauncher.shared.opened == [URL(fileURLWithPath: "/bundled/VorssaintAudio.pkg")]
                     && installing.installerOpened && Preferences.standard.bool(forKey: DefaultsKey.mixerSoftwareVolumeEnabled),
                     "confirmed installation opens only the bundled package and exposes the pending desired setting")
        Preferences.standard.set(false, forKey: DefaultsKey.mixerSoftwareVolumeEnabled)
        UpdateBundle.available = false
        let missing = UpdateHost()
        missing.installForFallback()
        suite.expect(!missing.installerOpened && !Preferences.standard.bool(forKey: DefaultsKey.mixerSoftwareVolumeEnabled)
                     && missing.error != nil,
                     "a missing installer reports failure without enabling fallback")
        UpdateBundle.available = true; UpdateHAL.requiredComponentBuild = 4; UpdateHAL.installedComponentBuild = 4
        Preferences.standard.values = [:]
    }

    private static func rememberedControl(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.remembered-mixer-volume"
        let defaults = Foundation.UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        VolumeDefaults.current = defaults
        defer {
            defaults.removePersistentDomain(forName: domain)
            VolumeDefaults.current = nil
        }
        let app = row("controlled", persistenceID: "com.example.Controlled")
        let writer = VolumeHost()
        writer.persistVolume(0.5, for: app)
        writer.persistVolume(1, for: app)
        suite.expect(writer.savedVolumes()[app.persistenceID!] == 1,
                     "reset to100 retains the explicit control choice in real preferences")
        // A different defaults object and a fresh routing host represent a
        // relaunch: no engine/editing/session state is carried across.
        VolumeDefaults.current = Foundation.UserDefaults(suiteName: domain)!
        let relaunched = Mixer()
        relaunched.volumes = VolumeHost().savedVolumes()
        suite.expect(relaunched.appNeedsEngine(app) && relaunched.rowMayBeTapped(app)
                     && relaunched.engines.isEmpty && relaunched.volumeEdits.isEmpty,
                     "a relaunch prepares previously controlled playing unity before its first slider change")
        let paused = row("controlled", persistenceID: app.persistenceID, playing: false)
        suite.expect(!relaunched.appNeedsEngine(paused) && relaunched.volumes[app.persistenceID!] == 1,
                     "stopped unity IO releases its engine without forgetting control history")
        suite.expect(relaunched.appNeedsEngine(app),
                     "resuming a remembered unity app prepares control again")
        let untouched = row("untouched", persistenceID: "com.example.Untouched")
        suite.expect(!relaunched.appNeedsEngine(untouched) && !relaunched.rowMayBeTapped(untouched),
                     "remembered apps never opt untouched playing apps into capture")
        let bypassed = row("controlled", persistenceID: app.persistenceID, bypassed: true)
        suite.expect(!relaunched.appNeedsEngine(bypassed) && !relaunched.rowMayBeTapped(bypassed),
                     "call bypass remains authoritative over remembered unity control")
        let noObjects = row("controlled", objects: [], persistenceID: app.persistenceID)
        suite.expect(!relaunched.appNeedsEngine(noObjects),
                     "remembered control waits for an actual audio connection")
        let anonymous = row("process:889", persistenceID: nil)
        let before = writer.savedVolumes()
        writer.persistVolume(0.5, for: anonymous)
        writer.persistVolume(1, for: anonymous)
        suite.expect(writer.sessionVolumes[anonymous.id] == 1 && writer.savedVolumes() == before,
                     "anonymous unity control stays in its session and never invents a persistent identity")
        relaunched.sessionVolumes = writer.sessionVolumes
        suite.expect(relaunched.appNeedsEngine(anonymous) && relaunched.rowMayBeTapped(anonymous),
                     "anonymous control prepares unity within this session")
        let fresh = Mixer()
        fresh.volumes = writer.savedVolumes()
        suite.expect(!fresh.appNeedsEngine(anonymous) && !fresh.rowMayBeTapped(anonymous),
                     "anonymous process control is not restored for a reused PID on another launch")
        defaults.set(["invalid": Double.nan, "legacy": 0.4], forKey: DefaultsKey.appVolumes)
        suite.expect(writer.savedVolumes() == ["legacy": 0.4],
                     "old volume adjustments remain valid and invalid entries never become control history")
    }

    private static func routeOnlyUnityCleanup(_ suite: TestSuite) {
        let mixer = Mixer()
        mixer.currentOutputDeviceUID = "airpods"
        let app = row("route-only", persistenceID: "com.example.RouteOnly")
        mixer.apps = [app]
        mixer.setOutputDeviceUID("airpods", for: app)
        mixer.engines[app.id] = true
        suite.expect(mixer.appNeedsEngine(mixer.apps[0]) && mixer.volumes.isEmpty,
                     "an explicit same-device route requires processing without inventing a saved volume")
        mixer.setOutputDeviceUID(nil, for: mixer.apps[0])
        let cleared = mixer.apps[0]
        suite.expect(cleared.selectedOutputDeviceUID == nil && cleared.effectiveOutputDeviceUID == "airpods"
                     && mixer.savedRoutes.isEmpty && !mixer.rowMayBeTapped(cleared),
                     "System Default clears route-only control while keeping the same physical destination")
        suite.expect(!mixer.appNeedsEngine(cleared),
                     "clearing a same-device route releases an unsaved unity engine even while playing")
        var universal = cleared
        universal.universalOutputRouteUID = "airpods"
        suite.expect(mixer.appNeedsEngine(universal), "a remaining universal route still requires its unity engine")
        universal.universalOutputRouteUID = nil
        suite.expect(!mixer.appNeedsEngine(universal),
                     "clearing the last universal route also releases unsaved unity processing")
        mixer.volumes[app.persistenceID!] = 1
        suite.expect(mixer.appNeedsEngine(cleared) && mixer.rowMayBeTapped(cleared),
                     "removing a route preserves separately remembered volume control at unity")
    }

    static func run(_ suite: TestSuite) {
        rememberedControl(suite)
        driverUpdates(suite)
        routeOnlyUnityCleanup(suite)
        let editingMixer = Mixer()
        let editingApp = row("editing")
        editingMixer.apps = [editingApp]
        editingMixer.engines[editingApp.id] = true
        editingMixer.volumes[editingApp.persistenceID!] = 1
        editingMixer.volumeEditingChanged(true, for: editingApp)
        suite.expect(editingMixer.appNeedsEngine(editingApp) && editingMixer.applied.isEmpty,
                     "beginning a drag keeps the existing unity engine without starting a new route")
        editingMixer.volumeEditingChanged(false, for: editingApp)
        suite.expect(editingMixer.appNeedsEngine(editingApp) && editingMixer.volumeEdits.isEmpty && editingMixer.applied.count == 1,
                     "ending or cancelling at unity retains the running tap while playback continues")
        editingMixer.volumeEditingChanged(false, for: editingApp)
        suite.expect(editingMixer.applied.count == 1, "duplicate cancellation is inert")
        suite.expect(editingMixer.appNeedsEngine(editingApp),
                     "reset to unity during playback keeps the running tap ready for the next adjustment")
        let pausedEditingApp = row("editing", playing: false)
        suite.expect(!editingMixer.appNeedsEngine(pausedEditingApp),
                     "a unity tap can be released after output playback stops")
        editingMixer.engines.removeAll()
        editingMixer.volumes.removeAll()
        suite.expect(!editingMixer.appNeedsEngine(editingApp),
                     "playing at untouched unity never creates a tap")
        editingMixer.engines[editingApp.id] = true
        editingMixer.volumeEditingChanged(true, for: editingApp)
        editingMixer.apps = []
        editingMixer.volumeEditingChanged(false, for: editingApp)
        suite.expect(editingMixer.volumeEdits.isEmpty && editingMixer.applied.count == 1,
                     "disappearing rows clear editing without recreating an audio route")

        Preferences.standard.values = [:]
        Preferences.standard.arrays = [:]
        callAudioCompatibility(suite)
        Mixer.deviceLists = [100: [10], 200: [20]]
        Mixer.reads = []; Mixer.writes = []; Mixer.writeStatus = noErr
        let wine = row()
        let native = row("com.example.Player", objects: [200], persistenceID: "com.example.Player")
        func snapshot(_ apps: [MixerApp] = [wine, native], requested: String? = "airpods",
                      current: String? = "airpods", devices: Set<AudioObjectID> = [20],
                      previous: [String: [AudioObjectID]] = [:]) -> [MixerApp] {
            Mixer.applyingUniversalOutputRoute(to: apps, requestedUID: requested, defaultUID: current,
                                              defaultDevices: devices, previouslyRoutedObjects: previous)
        }

        suite.expect(snapshot(requested: nil).allSatisfy { $0.universalOutputRouteUID == nil }
                     && Mixer.reads.isEmpty,
                     "listing apps alone never reads their outputs or forces their routes")
        let mixer = Mixer()
        mixer.apps = [wine, native]
        mixer.savedRoutes = ["Wine Game": "speakers"]
        mixer.sessionRoutes = ["process:88": "speakers"]
        mixer.volumes = ["Wine Game": 0.7]
        let generation = mixer.refresh.begin()!
        let token = mixer.builds.begin(wine.id)!
        suite.expect(mixer.setDefaultOutputDeviceUID("airpods"), "the universal output change succeeds")
        suite.expect(mixer.universalOutputDeviceUID == nil && Preferences.standard.values.isEmpty
                     && mixer.savedRoutes.isEmpty && mixer.sessionRoutes.isEmpty
                     && mixer.volumes == ["Wine Game": 0.7],
                     "a successful universal choice clears both route stores and preserves gains, changing only the default")
        suite.expect(mixer.currentOutputDeviceUID == "airpods" && mixer.apps == [wine, native]
                     && mixer.applied.isEmpty && mixer.refreshCount == 1,
                     "existing routes stay live until a fresh HAL snapshot can replace them")
        suite.expect(!mixer.refresh.finish(generation) && !mixer.builds.isCurrent(wine.id, token: token),
                     "a universal change rejects old snapshots and builds")
        suite.expect(Mixer.writes.count == 1 && Mixer.writes[0].0 == 20
                     && Mixer.writes[0].1 == kAudioHardwarePropertyDefaultOutputDevice,
                     "universal selection writes only the requested default output")

        SelectionHAL.current = VirtualOutputSupport.deviceUID
        let queued = SelectionSession()
        let acceptedNative = queued.selectOutput("nativeA")
        queued.queue.pending.removeFirst()()
        suite.expect(acceptedNative && queued.selectOutput("fixed"),
                     "rapid native/fixed choices are both accepted")
        suite.expect(queued.requestedOutputUID == "fixed", "latest accepted output remains the logical cycling target")
        SelectionQueues.main.flush()
        suite.expect(queued.requestedOutputUID == "fixed", "completion of an older selection cannot clear the newer pending choice")
        queued.queue.flush(); SelectionQueues.main.flush()
        suite.expect(queued.requestedOutputUID == nil, "completed latest selection clears its pending logical target")
        suite.expect(SelectionHAL.current == VirtualOutputSupport.deviceUID && queued.bridge?.physicalUID == "fixed",
                     "queued fixed selection reacquires a bridge after an earlier native choice released it")
        SelectionHAL.current = VirtualOutputSupport.deviceUID
        let queuedNative = SelectionSession()
        _ = queuedNative.selectOutput("nativeA"); _ = queuedNative.selectOutput("nativeB")
        queuedNative.queue.flush(); SelectionQueues.main.flush()
        suite.expect(SelectionHAL.current == "nativeB", "successive queued native choices select the final actual hardware output")

        SelectionHAL.current = VirtualOutputSupport.deviceUID
        SelectionHAL.nativeSelections = []
        let coalesced = SelectionSession()
        _ = coalesced.selectOutput("nativeA"); _ = coalesced.selectOutput("nativeB"); _ = coalesced.selectOutput("fixed")
        coalesced.queue.flush(); SelectionQueues.main.flush()
        suite.expect(SelectionHAL.nativeSelections.isEmpty && SelectionHAL.current == VirtualOutputSupport.deviceUID,
                     "superseded queued output choices do not reconfigure hardware or interrupt audio")

        SelectionHAL.current = VirtualOutputSupport.deviceUID
        SelectionHAL.nativeSelections = []
        let stoppedSelection = SelectionSession()
        stoppedSelection.installerOpened = true
        let stoppingAlert = UpdateAlert(NSAlert(), completion: { _ in })
        stoppedSelection.updateAlert = stoppingAlert
        _ = stoppedSelection.selectOutput("nativeA")
        stoppedSelection.stop(); SelectionQueues.main.flush()
        suite.expect(stoppedSelection.requestedOutputUID == nil && SelectionHAL.nativeSelections.isEmpty
                     && !stoppedSelection.selectOutput("nativeB"),
                     "stopping cancels queued selections and cannot recreate a disabled bridge")
        suite.expect(!stoppedSelection.installerOpened && stoppedSelection.updateAlert == nil && stoppingAlert.completion == nil,
                     "stopping also cancels outstanding driver-update UI and pending install state")

        SelectionHAL.current = "nativeA"; SelectionHAL.systemCurrent = "alerts"
        let coldNative = SelectionSession()
        coldNative.isActive = false; coldNative.virtual = nil; coldNative.bridge = nil
        suite.expect(coldNative.selectOutput("nativeB"), "enabled fallback serializes native selections even before a bridge is active")
        coldNative.queue.flush(); SelectionQueues.main.flush()
        suite.expect(SelectionHAL.current == "nativeB" && SelectionHAL.systemCurrent == "alerts",
                     "a native-only selection leaves an independently chosen alert output unchanged")
        SelectionHAL.current = "nativeA"; SelectionHAL.systemCurrent = "alerts"
        let coldFixed = SelectionSession()
        coldFixed.isActive = false; coldFixed.virtual = nil; coldFixed.bridge = nil
        suite.expect(coldFixed.selectOutput("fixed"), "fixed output is prepared before switching the default from native playback")
        coldFixed.queue.flush(); SelectionQueues.main.flush()
        suite.expect(coldFixed.bridge?.physicalUID == "fixed" && coldFixed.previousSystemOutput == "alerts",
                     "starting fallback from native output preserves the previous alert destination for restoration")

        SelectionHAL.current = VirtualOutputSupport.deviceUID
        let queuedForeign = SelectionSession()
        _ = queuedForeign.selectOutput("nativeA"); _ = queuedForeign.selectOutput("externalVirtual")
        queuedForeign.queue.flush(); SelectionQueues.main.flush()
        suite.expect(SelectionHAL.current == "externalVirtual" && queuedForeign.bridge == nil,
                     "an external output chosen after a queued physical choice remains the final native output")

        VirtualOutputService.shared.physicalOutputUID = "speakers"
        VirtualOutputService.shared.requestedOutputUID = nil
        Mixer.shared.outputDevices = [Device(uid: "speakers", canBeDefaultOutput: true, audioObjectID: 10), Device(uid: "airpods", canBeDefaultOutput: true, audioObjectID: 20), Device(uid: VirtualOutputSupport.deviceUID, canBeDefaultOutput: true, audioObjectID: 99)]
        Mixer.shared.currentOutputDeviceUID = VirtualOutputSupport.deviceUID
        Mixer.shared.prioritySelections = []
        let priorityHost = PriorityHost()
        priorityHost.outputPriorityUIDs = [VirtualOutputSupport.deviceUID, "airpods", "speakers"]
        priorityHost.enforceOutputPriority()
        suite.expect(Mixer.shared.prioritySelections == ["airpods"], "automatic output priority also excludes the implementation driver")
        Mixer.shared.prioritySelections = []
        priorityHost.outputPriorityUIDs = ["speakers", "airpods"]
        priorityHost.enforceOutputPriority()
        suite.expect(Mixer.shared.prioritySelections.isEmpty, "priority compares the physical fallback target rather than repeatedly choosing its virtual wrapper")
        VirtualOutputService.shared.physicalOutputUID = nil

        let softwareUID = VirtualOutputSupport.deviceUID
        Preferences.standard.arrays[DefaultsKey.soundOutputSwitcherDeviceUIDs] = [softwareUID, VirtualOutputSupport.legacyDeviceUID, VirtualOutputSupport.loopbackUID, "airpods"]
        suite.expect(Switcher().selectedDeviceUIDs() == ["airpods"],
                     "saved implementation devices never become output-switcher targets")
        Preferences.standard.values[DefaultsKey.softwareVolumePhysicalOutputUID] = "speakers"
        let selection = Switcher()
        selection.migrateSoftwareOutputSelection()
        suite.expect(Preferences.standard.arrays[DefaultsKey.soundOutputSwitcherDeviceUIDs] == ["speakers", "airpods"],
                     "stored current/legacy driver choices migrate once to the physical speaker without duplicates")
        selection.setSelectedDeviceUIDs(["airpods", softwareUID, VirtualOutputSupport.loopbackUID])
        suite.expect(selection.selectedDeviceUIDs() == ["airpods"], "new saved choices cannot reintroduce an internal device")
        Preferences.standard.arrays = [:]
        Preferences.standard.values = [:]
        let fallbackCycle = Mixer()
        fallbackCycle.outputDevices.append(Device(uid: softwareUID, canBeDefaultOutput: true, audioObjectID: 99))
        fallbackCycle.currentOutputDeviceUID = softwareUID
        VirtualOutputService.shared.isActive = true
        VirtualOutputService.shared.physicalOutputUID = "speakers"
        VirtualOutputService.shared.selectedUIDs = []
        suite.expect(fallbackCycle.switchToNextSoundOutput(in: ["speakers", "airpods", softwareUID])
                     && VirtualOutputService.shared.selectedUIDs == ["airpods"],
                     "shortcut advances from the actual speaker behind the software output and skips the driver")
        suite.expect(fallbackCycle.switchToNextSoundOutput(in: ["speakers", "airpods", softwareUID])
                     && VirtualOutputService.shared.selectedUIDs.suffix(2) == ["airpods", "speakers"],
                     "rapid shortcut presses advance from the accepted target before HAL refresh")
        suite.expect(!fallbackCycle.switchToNextSoundOutput(in: [softwareUID, VirtualOutputSupport.legacyDeviceUID]),
                     "implementation-only saved selection is not a playable cycle")
        VirtualOutputService.shared.isActive = false
        VirtualOutputService.shared.physicalOutputUID = nil
        VirtualOutputService.shared.requestedOutputUID = nil
        VirtualOutputService.shared.selectedUIDs = []

        let nativeMixer = Mixer()
        VirtualOutputService.shared.isActive = true
        let oldWrites = Mixer.writes.count
        suite.expect(nativeMixer.setDefaultOutputDeviceUID("airpods")
                     && VirtualOutputService.shared.selectedUIDs.last == "airpods"
                     && Mixer.writes.count == oldWrites,
                     "native fallback switches the bridge target without replacing the virtual default behind its owner")
        suite.expect(nativeMixer.currentOutputDeviceUID == "airpods", "accepted bridge switch publishes the logical choice for rapid shortcuts")
        nativeMixer.outputDevices.append(Device(uid: "externalVirtual", canBeDefaultOutput: true, audioObjectID: 30))
        VirtualOutputService.shared.rejectedUIDs = ["externalVirtual"]
        suite.expect(nativeMixer.setDefaultOutputDeviceUID("externalVirtual") && Mixer.writes.last?.0 == 30,
                     "an external virtual device still uses native selection when it is not a physical bridge target")
        VirtualOutputService.shared.rejectedUIDs = []
        VirtualOutputService.shared.isActive = false
        VirtualOutputService.shared.requestedOutputUID = nil
        VirtualOutputService.shared.selectedUIDs = []

        mixer.volumes = [:]
        mixer.currentOutputDeviceUID = "airpods"
        mixer.apps = snapshot()
        suite.expect(mixer.apps[0].universalOutputRouteUID == "airpods"
                     && mixer.apps[1].universalOutputRouteUID == nil,
                     "only the process still using the speakers needs a universal tap")
        suite.expect(Mixer.reads.allSatisfy {
            $0.1 == kAudioProcessPropertyDevices && $0.2 == kAudioObjectPropertyScopeOutput
        }, "the route check reads actual process outputs, not input devices")
        suite.expect(mixer.appNeedsEngine(mixer.apps[0]) && mixer.rowMayBeTapped(mixer.apps[0])
                     && !mixer.appNeedsEngine(mixer.apps[1]) && !mixer.rowMayBeTapped(mixer.apps[1]),
                     "both engine gates enforce the requested output at 100 percent and leave a following app untouched")
        mixer.currentOutputDeviceUID = "speakers"
        suite.expect(mixer.appNeedsEngine(mixer.apps[0]) && mixer.rowMayBeTapped(mixer.apps[0]),
                     "publishing the next output choice does not drop the existing route before the HAL refresh")
        mixer.currentOutputDeviceUID = "airpods"
        for gain in [0.99, 1.0, 1.01] {
            var app = mixer.apps[0]
            app.volume = gain
            suite.expect(mixer.appNeedsEngine(app) && mixer.rowMayBeTapped(app),
                         "returning a routed game to \(gain * 100) percent preserves its output")
        }

        Mixer.deviceLists[100] = []
        let previous = [wine.id: wine.audioObjects]
        let silent = snapshot([wine], previous: previous)[0]
        suite.expect(silent.universalOutputRouteUID == "airpods",
                     "silence or an unreadable process device list does not discard an established route")
        suite.expect(snapshot([wine])[0].universalOutputRouteUID == nil,
                     "an empty device list alone never starts a tap")
        suite.expect(snapshot([row(objects: [101])], previous: previous)[0].universalOutputRouteUID == nil,
                     "new audio objects do not inherit a stale routing observation")
        suite.expect(snapshot([row(objects: [])], previous: previous)[0].universalOutputRouteUID == nil,
                     "an app with no audio objects cannot acquire a route")
        Mixer.deviceLists[100] = [20]
        suite.expect(snapshot([silent], previous: previous)[0].universalOutputRouteUID == nil,
                     "a process that really moves to the requested device returns to passthrough")
        suite.expect(snapshot([wine], devices: [20, 21])[0].universalOutputRouteUID == nil,
                     "an app using one physical member of the default aggregate already follows that output")
        Mixer.deviceLists[100] = [10, 20]
        suite.expect(snapshot([wine])[0].universalOutputRouteUID == "airpods",
                     "playing on the requested device as well as the speakers still requires rerouting")
        suite.expect(snapshot([silent], devices: [], previous: previous)[0].universalOutputRouteUID == nil,
                     "a missing default device cannot retain a forced route")
        Mixer.reads = []
        suite.expect(snapshot([silent], current: "speakers", previous: previous)[0].universalOutputRouteUID == nil
                     && Mixer.reads.isEmpty,
                     "a later hardware or priority change does not route apps to the old universal choice")
        suite.expect(snapshot([row(bypassed: true), row(selectedUID: "airpods")])
                        .allSatisfy { $0.universalOutputRouteUID == nil } && Mixer.reads.isEmpty,
                     "bypassed apps and later per-app choices are excluded from universal routing")

        Mixer.deviceLists = [:]
        let grouped = Mixer.coalescingAppsWithDuplicateIDs([wine, row(objects: [101])])
        suite.expect(grouped.count == 1 && grouped[0].audioObjects == [100, 101]
                     && snapshot(grouped, previous: [wine.id: [100, 101]])[0].universalOutputRouteUID == "airpods",
                     "a silent app with several owner processes keeps one route for all of its audio objects")
        let bypassed = Mixer.coalescingAppsWithDuplicateIDs([row(bypassed: true), row(objects: [101])])
        suite.expect(bypassed[0].isBypassed && snapshot(bypassed)[0].universalOutputRouteUID == nil,
                     "combining rows cannot remove an app's tap bypass")

        mixer.volumes = [:]
        mixer.apps = [wine]
        mixer.setOutputDeviceUID("airpods", for: wine)
        suite.expect(mixer.savedRoutes == ["Wine Game": "airpods"]
                     && mixer.apps[0].selectedOutputDeviceUID == "airpods"
                     && mixer.apps[0].effectiveOutputDeviceUID == "airpods"
                     && mixer.applied.last?.selectedOutputDeviceUID == "airpods",
                     "a named bare process applies its route by persistence identity, not its PID row key")
        suite.expect(mixer.appNeedsEngine(mixer.apps[0]) && mixer.rowMayBeTapped(mixer.apps[0]),
                     "an explicit AirPods choice is enforced at 100 percent even while AirPods are the default")
        mixer.setOutputDeviceUID(nil, for: mixer.apps[0])
        suite.expect(mixer.savedRoutes.isEmpty && mixer.apps[0].selectedOutputDeviceUID == nil,
                     "clearing a named process's explicit route removes the stored choice immediately")
        let unnamed = row("process:88", persistenceID: nil)
        mixer.apps = [unnamed]
        mixer.setOutputDeviceUID("airpods", for: unnamed)
        suite.expect(mixer.sessionRoutes[unnamed.id] == "airpods"
                     && mixer.apps[0].selectedOutputDeviceUID == "airpods",
                     "a process without a persistent identity still applies its session-only route")

        mixer.savedRoutes = ["Wine Game": "airpods"]
        Mixer.writeStatus = -1
        suite.expect(!mixer.setDefaultOutputDeviceUID("speakers")
                     && mixer.savedRoutes == ["Wine Game": "airpods"]
                     && mixer.sessionRoutes[unnamed.id] == "airpods",
                     "a failed universal switch preserves all earlier routing choices")
        let writes = Mixer.writes.count
        suite.expect(!mixer.setDefaultOutputDeviceUID("missing") && Mixer.writes.count == writes,
                     "an unavailable output cannot begin a universal switch")

        Mixer.writeStatus = noErr
        let rapid = Mixer()
        suite.expect(rapid.switchToNextSoundOutput(in: ["speakers", "airpods"])
                     && rapid.switchToNextSoundOutput(in: ["speakers", "airpods"])
                     && rapid.currentOutputDeviceUID == "speakers"
                     && Mixer.writes.suffix(2).map(\.0) == [20, 10],
                     "successive shortcut presses cycle from the chosen output without waiting for a HAL refresh")

        suite.expect(Mixer.runningAddress(kAudioProcessPropertyDevices).mScope == kAudioObjectPropertyScopeOutput
                     && Mixer.runningAddress(kAudioProcessPropertyIsRunningOutput).mScope == kAudioObjectPropertyScopeGlobal,
                     "process routing changes use the output-scoped listener while running state keeps its global scope")

        // A refresh pass reads the HAL for a while after it captured the saved
        // volumes. Publishing must resolve them again, so a slider or MIDI write
        // made in between is never reverted by the pass (measured: 0.835 requested,
        // 0.614 written during the pass, 0.835 published).
        let publishing = Mixer()
        var chrome = row("com.google.Chrome", persistenceID: "com.google.Chrome")
        chrome.volume = 0.835
        var unkeyed = row("process:88", persistenceID: nil)
        unkeyed.volume = 0.9
        let zoom = row("us.zoom.xos", persistenceID: "us.zoom.xos", bypassed: true)
        publishing.volumes = ["com.google.Chrome": 0.835, "us.zoom.xos": 0.5]
        publishing.sessionVolumes = ["process:88": 0.9]
        let read = [chrome, unkeyed, zoom]
        suite.expect(publishing.applyingCurrentVolumes(to: read) == read,
                     "publishing unchanged volumes keeps every row as read, a bypassed one at unity")

        publishing.volumes["com.google.Chrome"] = 0.614
        publishing.sessionVolumes["process:88"] = 0.4
        var written = read
        written[0].volume = 0.614
        written[1].volume = 0.4
        suite.expect(publishing.applyingCurrentVolumes(to: read) == written,
                     "a volume written while the pass read the HAL replaces the one captured at request time, and nothing else changes")

        publishing.volumes.removeValue(forKey: "com.google.Chrome")
        suite.expect(publishing.applyingCurrentVolumes(to: read)[0].volume == 1,
                     "a volume returned to 100 percent while the pass read publishes as unity, not the old gain")
    }
}
