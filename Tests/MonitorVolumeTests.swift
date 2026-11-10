// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MonitorVolumeTests {
    static func run(_ suite: TestSuite) {
        typealias Fixture = DisplaySpeakerVolumeTests
        let service = Fixture.Service()
        Fixture.Service.shared = service
        let domain = "com.vorssaint.tests.write-only-speakers.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        service.speakerPreferences = MonitorVolumeSupport.Preferences(defaults: defaults)
        let endpoint = NSObject()
        let path = "fixture-display|port-a"
        let panel = BrightnessSupport.SpeakerTarget(displayID: 7, path: path)
        let code = BrightnessSupport.audioVolumeCode

        func rescan() {
            let found = service.probeAudio(for: 7, service: endpoint, path: path)
            service.audioRoutes[7] = nil
            if let found, found.state != nil {
                service.audioRoutes[7] = Fixture.AudioRoute(path: path, fingerprint: "fixture-identity",
                    service: endpoint, hasNativeMute: found.hasNativeMute, writeOnly: found.setup.writeOnly)
            }
            service.displays = [Fixture.BrightnessDisplay(id: 7, name: "Monitor A",
                                                          audio: found?.state, speakerSetup: found?.setup)]
        }

        var unsupported: [UInt8] = [0x6E, 0x88, 0x02, 0x01, code, 0, 0, 100, 0, 5]
        unsupported.append(unsupported.reduce(0x50, ^))
        service.volumeResponse = Fixture.DDCProbe.reading(unsupported, code: code)
        rescan()
        suite.expect(service.displays[0].speakerSetup == nil && service.monitorSpeakerOutput() == nil,
                     "a valid unsupported reply cannot offer manual or automatic control")

        service.volumeResponse = .writeOnly
        rescan()
        suite.expect(service.displays[0].speakerSetup?.enabled == false && service.monitorSpeakerOutput() == nil,
                     "an unanswered monitor offers setup without publishing an invented volume")
        service.setSpeakerEnabled(true, reference: nil, for: panel)
        service.setSpeakerEnabled(true, reference: 101, for: panel)
        service.setSpeakerEnabled(true, reference: 70, for: .init(displayID: 7, path: "other-port"))
        suite.expect(service.workQueue.jobs.isEmpty, "invalid baselines and stale setup rows schedule nothing")
        service.setSpeakerEnabled(true, reference: 1, for: panel)
        service.finish()
        rescan()
        guard let output = service.monitorSpeakerOutput() else {
            suite.expect(false, "an explicit reference enables the selected monitor")
            return
        }
        suite.expect(output.volume == 0.01 && output.muted == nil && service.writes.isEmpty,
                     "enabling a write-only monitor at 1% neither changes its volume nor guesses mute")

        let fineStep = BrightnessSupport.SpeakerChange.step(levels: [{ $0 + 0.01 }], raises: true)
        var completed: Bool?
        service.requestSpeakers(fineStep, target: output.target, requiresKeys: true) { completed = $0 }
        suite.expect(completed == nil && service.displays[0].audio?.volume == 0.01,
                     "a queued key does not update the remembered volume")
        service.finish()
        suite.expect(completed == true && service.writes == [Fixture.Write(code, 2)]
                     && service.monitorSpeakerOutput()?.volume == 0.02 && service.displays[0].speakerSetup?.reference == 2,
                     "the real speaker request writes 2% and remembers it only after the transport accepts it")

        service.rejectVolume = true
        service.requestSpeakers(fineStep, target: output.target) { completed = $0 }
        service.finish()
        rescan()
        suite.expect(completed == false && service.monitorSpeakerOutput()?.volume == 0.02,
                     "a refused write keeps the last accepted volume across rescan")
        service.rejectVolume = false
        service.writes = []
        service.requestSpeakers(.toggleMute, target: output.target) { completed = $0 }
        service.finish()
        rescan()
        suite.expect(completed == false && service.writes.isEmpty && service.monitorSpeakerOutput()?.muted == nil,
                     "a write-only display never guesses a mute command")
        service.requestSpeakers(.set(volume: 0, muted: nil), target: output.target)
        service.finish()
        suite.expect(service.writes == [Fixture.Write(code, 1)] && service.monitorSpeakerOutput()?.volume == 0.01,
                     "an absolute request at the lower bound cannot send the MCCS default-level value")
        service.writes = []
        service.requestSpeakers(fineStep, target: output.target)
        service.actualDevice = 75
        service.finish()
        suite.expect(service.writes.isEmpty, "switching outputs while a write-only step waits prevents the DDC write")
        service.actualDevice = 31
        rescan()
        service.requestSpeakers(fineStep, target: output.target)
        service.audioLifetime &+= 1
        service.finish()
        rescan()
        suite.expect(service.writes.isEmpty && service.monitorSpeakerOutput()?.volume == 0.01,
                     "an old request never follows a reused display number after reconnect")
        guard let reconnected = service.monitorSpeakerOutput(), let row = service.displays[0].speakerSetup else {
            suite.expect(false, "the identified path still offers its last accepted reference")
            return
        }
        service.requestSpeakers(fineStep, target: reconnected.target)
        service.setSpeakerEnabled(false, reference: nil, for: row.target)
        service.finish()
        rescan()
        suite.expect(service.writes.isEmpty && service.monitorSpeakerOutput() == nil,
                     "disabling the monitor revokes a pending step")
        service.volumeResponse = .replied(current: 50, maximum: 100)
        rescan()
        suite.expect(service.displays[0].speakerSetup?.enabled == false && service.monitorSpeakerOutput() == nil,
                     "a successful read does not re-enable an explicitly disabled monitor")
        service.setSpeakerEnabled(true, reference: nil, for: row.target)
        service.finish()
        rescan()
        suite.expect(service.monitorSpeakerOutput()?.volume == 0.5 && service.writes.isEmpty,
                     "a re-enabled readable monitor displays its reported volume")

        let saved = service.speakerPreferences.value(for: path, persistent: true)
        suite.expect(saved?.raw == 50 && service.speakerPreferences.value(for: "port-b", persistent: true) == nil
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.displaySpeakerPreferences),
                     "a newer reported level updates the reference on this physical path only")
        let serialless = MonitorVolumeSupport.connection(path: path, displaySerial: 0, serviceSerial: 0, entryID: 1)
        let replaced = MonitorVolumeSupport.connection(path: path, displaySerial: 0, serviceSerial: 0, entryID: 2)
        let serialA = MonitorVolumeSupport.connection(path: path, displaySerial: 0, serviceSerial: 123, entryID: 1)
        let serialB = MonitorVolumeSupport.connection(path: path, displaySerial: 0, serviceSerial: 456, entryID: 1)
        suite.expect(serialless?.persistent == false && serialless?.path != replaced?.path
                     && serialA?.persistent == true && serialA?.path != serialB?.path
                     && MonitorVolumeSupport.connection(path: path, displaySerial: 123, serviceSerial: 456, entryID: 1) == nil,
                     "conflicting serials refuse the route and anonymous monitors cannot inherit a saved percentage")
        service.speakerPreferences.save(.init(enabled: true, raw: 3), for: "anonymous", persistent: false)
        let reopened = MonitorVolumeSupport.Preferences(defaults: defaults)
        suite.expect(reopened.value(for: "anonymous", persistent: false) == nil
                     && reopened.value(for: path, persistent: true)?.raw == 50,
                     "a new session restores only the identified monitor")
        service.volumeResponse = .replied(current: 80, maximum: 255)
        rescan()
        service.volumeResponse = .writeOnly
        rescan()
        suite.expect(service.monitorSpeakerOutput()?.volume == 80.0 / 255,
                     "a previously reported raw value and range survive when only writes work again")
        service.writes = []
        service.requestSpeakers(fineStep, target: reconnected.target)
        service.finish()
        suite.expect(service.writes == [Fixture.Write(code, 83)] && service.monitorSpeakerOutput()?.volume == 83.0 / 255,
                     "a one-percent key uses the monitor's own 255-step range behind the dock")
    }
}
