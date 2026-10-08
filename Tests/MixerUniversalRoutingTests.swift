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
        func string(forKey key: String) -> String? { values[key] }
        func set(_ value: String?, forKey key: String) { values[key] = value }
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
    }

    static func row(_ id: String = "process:77", objects: [AudioObjectID] = [100],
                    persistenceID: String? = "Wine Game", selectedUID: String? = nil,
                    bypassed: Bool = false) -> MixerApp {
        MixerApp(id: id, persistenceID: persistenceID, ownerPid: 77, name: "Game",
                 audioObjects: objects, isPlaying: true, isBypassed: bypassed,
                 selectedOutputDeviceUID: selectedUID, effectiveOutputDeviceUID: "airpods",
                 outputDeviceUnavailable: false, volume: 1)
    }

    static func run(_ suite: TestSuite) {
        Preferences.standard.values = [:]
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
        suite.expect(mixer.universalOutputDeviceUID == "airpods"
                     && mixer.savedRoutes.isEmpty && mixer.sessionRoutes.isEmpty
                     && mixer.volumes == ["Wine Game": 0.7],
                     "a successful universal choice clears both route stores, preserves gains and records routing intent")
        suite.expect(Mixer().universalOutputDeviceUID == "airpods",
                     "relaunching the mixer retains the user's universal output request")
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
                     && mixer.universalOutputDeviceUID == "airpods"
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
    }
}
