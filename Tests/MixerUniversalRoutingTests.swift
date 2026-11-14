// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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

    final class Preferences {
        static let standard = Preferences()
        var values: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var arrays: [String: [String]] {
            get { lists }
            set { lists = newValue }
        }
        func string(forKey key: String) -> String? { values[key] }
        func set(_ value: String?, forKey key: String) { values[key] = value }
        func array(forKey key: String) -> [Any]? { lists[key] }
        func stringArray(forKey key: String) -> [String]? { lists[key] }
        func set(_ value: [String], forKey key: String) { lists[key] = value }
        func removeObject(forKey key: String) { values[key] = nil; lists[key] = nil }
    }

    final class Mixer {
        typealias MixerApp = MixerUniversalRoutingContract.MixerApp
        typealias L10n = MixerUniversalRoutingContract.L10n
        typealias AirPlayRouteManager = AirPlay
        typealias UserDefaults = Preferences
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
        var savedRoutes: [String: String] = [:]
        var volumes: [String: Double] = [:]
        var sessionRoutes: [String: String] = [:]
        var sessionVolumes: [String: Double] = [:]
        var sessionMutes: Set<String> = []
        var volumeWrites: [Double] = []
        var reconciled = 0
        var tappedWhenRouted: [Bool] = []
        var refresh = MixerRefreshCoordinator()
        var builds = MixerEngineBuilds()
        var engineRecovery = MixerEngineRecovery()
        var refreshCount = 0
        var applied: [MixerApp] = []
        func refreshApps() { refreshCount += 1 }
        func savedOutputDeviceUIDs() -> [String: String] { savedRoutes }
        func savedVolumes() -> [String: Double] { volumes }
        func persistVolume(_ volume: Double, for app: MixerApp) {
            volumeWrites.append(volume)
            if let key = app.persistenceID { volumes[key] = volume } else { sessionVolumes[app.id] = volume }
        }
        func reconcileEngines(with apps: [MixerApp]) { reconciled += 1 }
        func persistOutputDeviceUIDs(_ routes: [String: String]) { savedRoutes = routes }
        func persistOutputDeviceUID(_ uid: String?, for app: MixerApp) {
            if let key = app.persistenceID { savedRoutes[key] = uid }
            else { sessionRoutes[app.id] = uid }
        }
        func applyRouting(for app: MixerApp) {
            applied.append(app)
            tappedWhenRouted.append(rowMayBeTapped(app))
        }
        func chooseAirPlaySpeaker(for app: MixerApp) {}
        func clearPermissionIfNoActiveAdjustments() {}
    }

    static func row(_ id: String = "process:77", objects: [AudioObjectID] = [100],
                    persistenceID: String? = "Wine Game", selectedUID: String? = nil,
                    bypassed: Bool = false, muted: Bool = false) -> MixerApp {
        MixerApp(id: id, persistenceID: persistenceID, ownerPid: 77, name: "Game",
                 audioObjects: objects, isPlaying: true, isBypassed: bypassed,
                 selectedOutputDeviceUID: selectedUID, effectiveOutputDeviceUID: "airpods",
                 outputDeviceUnavailable: false, volume: 1, isMuted: muted)
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

    static func run(_ suite: TestSuite) {
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

        // The same goes for a mute: one written while the pass read the HAL is not
        // reverted, a mute still saved stays, and a bypassed row is never muted,
        // whatever is saved under its key.
        publishing.volumes["com.google.Chrome"] = 0.835
        publishing.sessionVolumes["process:88"] = 0.9
        Preferences.standard.lists = [:]
        publishing.sessionMutes = ["process:88"]
        var steady = read
        steady[0].isMuted = true
        steady[1].isMuted = true
        publishing.persistMute(true, for: chrome)
        suite.expect(publishing.applyingCurrentVolumes(to: steady) == steady,
                     "publishing a mute that is still saved keeps the row muted, a bypassed one never")
        suite.expect(publishing.applyingCurrentVolumes(to: read) == steady,
                     "a mute written while the pass read the HAL replaces the state captured at request time")
        publishing.persistMute(true, for: zoom)
        suite.expect(publishing.applyingCurrentVolumes(to: read) == steady,
                     "a bypassed row stays unmuted whatever is saved under its key")
        publishing.persistMute(false, for: zoom)
        publishing.persistMute(false, for: chrome)
        publishing.sessionMutes = []
        suite.expect(publishing.applyingCurrentVolumes(to: steady) == read,
                     "an unmute written while the pass read the HAL is not reverted either")
        Preferences.standard.lists = [:]

        muteCases(suite)
    }

    /// The mute is a flag of its own: the real `toggleMute`, `setVolume`,
    /// `storedMute`, `savedMutes` and `persistMute` bodies against fake preferences.
    static func muteCases(_ suite: TestSuite) {
        // Every mixer shares the one fake preferences object, so each case starts it empty.
        func fresh() -> Mixer {
            Preferences.standard.lists = [:]
            return Mixer()
        }
        let player = row("com.example.Player", objects: [200], persistenceID: "com.example.Player")

        let muting = fresh()
        muting.apps = [player]
        muting.toggleMute(player)
        suite.expect(muting.apps[0].isMuted && muting.apps[0].volume == 1
                     && muting.volumeWrites.isEmpty && muting.savedMutes() == ["com.example.Player"],
                     "muting keeps the app's level and saves the mute under its persistence id")
        suite.expect(muting.tappedWhenRouted == [true] && muting.applied.last?.isMuted == true
                     && muting.appNeedsEngine(muting.apps[0]) && muting.reconciled == 1,
                     "a muted app at 100% with no route is routed into a tap, with its mute already saved")
        muting.toggleMute(muting.apps[0])
        suite.expect(!muting.apps[0].isMuted && muting.savedMutes().isEmpty && muting.tappedWhenRouted == [true, false]
                     && !muting.appNeedsEngine(muting.apps[0]) && !muting.rowMayBeTapped(muting.apps[0]),
                     "unmuting an app at 100% with no route hands it back to untouched output")

        let stale = fresh()
        stale.apps = [player]
        stale.toggleMute(player)   // muted from the other view
        stale.toggleMute(player)   // a click on the copy drawn before that
        suite.expect(!stale.apps[0].isMuted && stale.savedMutes().isEmpty && stale.tappedWhenRouted == [true, false],
                     "a click on a copy drawn before the row changed toggles the live row, not the copy")

        let quit = fresh()
        quit.toggleMute(player)
        suite.expect(quit.savedMutes() == ["com.example.Player"] && quit.applied.last?.isMuted == true && quit.apps.isEmpty,
                     "muting an app that just left the list saves the mute for its next launch")

        let recovering = fresh()
        recovering.apps = [player]
        let configuration = MixerEngineRecovery.Configuration(objects: player.audioObjects,
                                                              outputDeviceUID: "airpods")
        _ = recovering.engineRecovery.recordFailure(player.id, configuration: configuration)
        _ = recovering.engineRecovery.recordFailure(player.id, configuration: configuration)
        let gaveUp = !recovering.engineRecovery.allowsBuild(player.id, configuration: configuration)
        recovering.toggleMute(player)
        suite.expect(gaveUp && recovering.engineRecovery.allowsBuild(player.id, configuration: configuration),
                     "muting gives an app whose tap was given up another build, so a red speaker never plays")

        let unnamed = row("process:91", objects: [300], persistenceID: nil)
        let session = fresh()
        session.apps = [unnamed]
        session.toggleMute(unnamed)
        suite.expect(session.apps[0].isMuted && session.rowMayBeTapped(session.apps[0])
                     && Mixer.storedMute(for: unnamed.identity, saved: [], session: session.sessionMutes)
                     && !Mixer.storedMute(for: MixerRowIdentity(rowID: "process:92", persistenceID: nil),
                                          saved: [], session: session.sessionMutes)
                     && !Mixer.storedMute(for: MixerRowIdentity(rowID: "process:91", persistenceID: "Other Game"),
                                          saved: [], session: session.sessionMutes)
                     && Mixer.storedMute(for: MixerRowIdentity(rowID: "process:93", persistenceID: "Other Game"),
                                         saved: ["Other Game"], session: []),
                     "a process without a persistent identity stays muted through the next refresh, by row and only for this session")
        suite.expect(session.savedMutes().isEmpty && Preferences.standard.lists.isEmpty,
                     "a session mute is never written down")
        session.toggleMute(session.apps[0])
        suite.expect(!session.apps[0].isMuted && session.sessionMutes.isEmpty
                     && !Mixer.storedMute(for: unnamed.identity, saved: [], session: session.sessionMutes),
                     "unmuting a process without a persistent identity ends its session mute")

        let storage = fresh()
        // Eight ids: a Set's order changes with every process, and a few unsorted ones would pass by chance.
        let ids = ["com.example.h", "com.example.c", "com.example.f", "com.example.a",
                   "com.example.g", "com.example.b", "com.example.e", "com.example.d"]
        for id in ids { storage.persistMute(true, for: row("process:" + id, persistenceID: id)) }
        suite.expect(Preferences.standard.lists[DefaultsKey.appMutes] == ids.sorted(),
                     "the saved mutes are a sorted list of persistence ids")
        storage.persistMute(false, for: row("process:" + ids[0], persistenceID: ids[0]))
        suite.expect(storage.savedMutes() == Set(ids.dropFirst()),
                     "unmuting one app leaves the other saved mutes alone")
        for id in ids { storage.persistMute(false, for: row("process:" + id, persistenceID: id)) }
        suite.expect(Preferences.standard.lists[DefaultsKey.appMutes] == nil && storage.savedMutes().isEmpty,
                     "the saved list goes away when no app is muted")

        let level = fresh()
        level.apps = [player]
        level.setVolume(0, for: player)
        suite.expect(level.apps[0].volume == 0 && !level.apps[0].isMuted && level.savedMutes().isEmpty,
                     "turning an app down to 0% silences it without muting it")
        level.toggleMute(level.apps[0])
        suite.expect(level.apps[0].isMuted && level.apps[0].volume == 0 && level.volumeWrites == [0],
                     "a click on the speaker of an app at 0% mutes it and leaves the level at 0%")
        level.setVolume(0.5, for: level.apps[0])
        suite.expect(level.apps[0].isMuted && level.apps[0].volume == 0.5 && level.savedMutes() == ["com.example.Player"]
                     && level.effectiveVolume(of: level.apps[0]) == 0,
                     "moving a muted app's level keeps it muted")

        var loud = row("com.example.Loud", objects: [400], persistenceID: "com.example.Loud")
        loud.volume = 1.5
        let boost = fresh()
        boost.apps = [loud]
        boost.toggleMute(loud)
        let silenced = boost.effectiveVolume(of: boost.apps[0]) == 0
        boost.toggleMute(boost.apps[0])
        suite.expect(silenced && boost.apps[0].volume == 1.5 && boost.effectiveVolume(of: boost.apps[0]) == 1.5
                     && boost.volumeWrites.isEmpty,
                     "a boosted app goes fully silent when muted and comes back boosted, never through 100%")

        let zoom = row("us.zoom.xos", objects: [500], persistenceID: "us.zoom.xos", bypassed: true)
        let conference = fresh()
        conference.apps = [zoom]
        conference.toggleMute(zoom)
        suite.expect(!conference.apps[0].isMuted && conference.savedMutes().isEmpty && conference.applied.isEmpty,
                     "muting an app that manages its own audio does nothing")
        let merged = Mixer.coalescingAppsWithDuplicateIDs([row(muted: true), row(objects: [101])])
        let mergedBypass = Mixer.coalescingAppsWithDuplicateIDs([row(objects: [101], muted: true), row(bypassed: true)])
        suite.expect(merged[0].isMuted && mergedBypass[0].isBypassed && !mergedBypass[0].isMuted,
                     "combining rows keeps a mute, but never on an app that manages its own audio")
    }
}
