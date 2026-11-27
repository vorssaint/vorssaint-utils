// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MonitorVolumeKeySettingsTests {
    static func run(_ suite: TestSuite) {
        typealias Keys = NotchVolumeRoutingTests
        typealias Hardware = MixerOutputAdjustmentContract.Hardware
        typealias Write = DisplaySpeakerVolumeTests.Write
        let volume = BrightnessSupport.audioVolumeCode
        let mute = BrightnessSupport.audioMuteCode
        let limits = MonitorVolumeKeySettings(stepPercent: 10, minimumPercent: 20, maximumPercent: 70)

        var tap = Keys.Service()
        func connect(raw: UInt16, maximum: UInt16 = 100, muted: Bool? = false, unmutedReads: UInt16 = 2,
                     chip: UInt32 = BrightnessSupport.chipAddress, registryEntryID: UInt64? = 1,
                     settings: MonitorVolumeKeySettings = .init(stepPercent: 1, maximumPercent: 5)) -> DisplaySpeakerVolumeTests.Service {
            Hardware.reset()
            Keys.DispatchQueue.main = MixerOutputAdjustmentContract.Queue()
            Keys.AppVolumeMixer.shared = MixerOutputAdjustmentContract.Mixer()
            Keys.UserDefaults.precise = false
            Keys.NotchService.shared.shownLevels = []
            tap = Keys.Service()
            let service = DisplaySpeakerVolumeTests.connect(Keys.AppVolumeMixer.shared, raw: raw, maximum: maximum,
                muted: muted, unmutedReads: unmutedReads, chip: chip, registryEntryID: registryEntryID)
            service.monitorVolumeKeySettings = settings
            return service
        }

        // Route both halves of a physical press through the production handler. The
        // mixer, queue and DDC readback run against the existing in-memory display.
        @discardableResult
        func press(_ key: PreciseVolumeMediaKey, flags: CGEventFlags = []) -> Bool {
            let code = Int(key.rawValue) << 16
            let down = tap.routeMonitorVolume(.init(data1: code | 0x0a00), flags: flags)
            let up = tap.routeMonitorVolume(.init(data1: code | 0x0b00), flags: flags)
            return down && up
        }

        var service = connect(raw: 2)
        suite.expect(press(.volumeDown), "one-percent mode claims the plain volume-down key")
        service.finish()
        suite.expect(service.writes == [Write(volume, 1)] && Keys.NotchService.shared.shownLevels == [0.01],
                     "a quiet monitor goes from two to one percent with confirmed feedback")
        service = connect(raw: 0)
        press(.volumeDown)
        service.finish()
        suite.expect(service.writes == [Write(mute, 1)], "down at zero can still silence native speakers")

        service = connect(raw: 2)
        service.maximum = 0
        press(.volumeDown)
        service.finish()
        suite.expect(service.writes.isEmpty && Keys.NotchService.shared.shownLevels.isEmpty,
                     "a missing range after discovery cannot seed the first key or announce a write")

        service = connect(raw: 2)
        press(.volumeUp)
        press(.volumeUp)
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 3), Write(volume, 4), Write(mute, 1)]
                     && service.nativeMuted == true && Hardware.writes.isEmpty,
                     "queued one-percent presses finish before a later mute and never reach CoreAudio")

        service = connect(raw: 2, settings: limits)
        press(.volumeDown)
        service.finish()
        suite.expect(service.writes.isEmpty && service.raw == 2, "down below the floor cannot turn the volume up")
        press(.volumeUp, flags: [.maskAlternate, .maskShift])
        service.finish()
        suite.expect(service.writes == [Write(volume, 3)], "a fine raise below the floor still moves just one percent")
        service = connect(raw: 40, settings: limits)
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 50)], "a plain key uses the configured ten-percent grid")
        service = connect(raw: 40, settings: limits)
        Keys.AppFeature.mixerAvailable = false
        Keys.UserDefaults.precise = true
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 50)],
                     "a disabled mixer's saved fine-step preference cannot override the monitor's key step")
        Keys.AppFeature.mixerAvailable = true
        service = connect(raw: 29, settings: .init(stepPercent: 2))
        press(.volumeDown)
        service.finish()
        suite.expect(service.writes == [Write(volume, 28)], "an exact half-step on the monitor rejoins the nearest grid point")

        service = connect(raw: 1, maximum: 3, settings: limits)
        press(.volumeUp, flags: [.maskAlternate, .maskShift])
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 2)], "a coarse monitor moves one unit but cannot round past its ceiling")
        service = connect(raw: 1, maximum: 3, settings: .init(stepPercent: 1, minimumPercent: 34, maximumPercent: 60))
        press(.volumeUp)
        press(.volumeDown)
        service.finish()
        suite.expect(service.writes.isEmpty, "keys leave an unrepresentable range alone")

        service = connect(raw: 4)
        press(.volumeUp)
        service.monitorVolumeKeySettings = .init(stepPercent: 1, minimumPercent: 0, maximumPercent: 3)
        service.finish()
        suite.expect(service.writes.isEmpty, "the ceiling in effect at write time also protects an already queued key")
        Keys.AppVolumeMixer.shared.requestOutputAdjustment(volume: 0.8)
        service.finish()
        suite.expect(service.raw == 80, "the explicit monitor slider still reaches its full range")
        service = connect(raw: 4)
        service.onSend = { [weak service] in
            service?.monitorVolumeKeySettings = .init(stepPercent: 1, maximumPercent: 3)
        }
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes.isEmpty && Keys.NotchService.shared.shownLevels.isEmpty,
                     "a ceiling lowered after the DDC read also cancels the paced write")

        for (initial, target): (UInt16, UInt16) in [(40, 5), (0, 1)] {
            service = connect(raw: initial, muted: true)
            press(.mute)
            service.finish()
            suite.expect(service.writes == [Write(volume, target), Write(mute, 2)] && service.nativeMuted == false,
                         "a capped unmute confirms a positive level even when the original level was zero")
        }
        service = connect(raw: 0, maximum: 10, muted: true)
        press(.mute)
        service.finish()
        suite.expect(service.writes.isEmpty && service.nativeMuted == true,
                     "a ceiling below one hardware unit leaves native mute engaged")
        service = connect(raw: 0, muted: true, settings: .init())
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(mute, 2)] && service.nativeMuted == false && service.raw == 0,
                     "without a ceiling the mute key can release native mute independently of a zero level")
        service = connect(raw: 40, muted: true)
        service.ignoreVolume = true
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 5)] && service.nativeMuted == true
                     && Keys.NotchService.shared.shownLevels.isEmpty,
                     "an ignored level write cannot release mute at the old loud level")
        for restored: UInt16 in [0, 40] {
            service = connect(raw: 40, muted: true)
            service.volumeOnUnmute = restored
            press(.mute)
            service.finish()
            suite.expect(service.writes == [Write(volume, 5), Write(mute, 2), Write(mute, 1)]
                         && service.nativeMuted == true && Keys.NotchService.shared.shownLevels.isEmpty,
                         "firmware that restores a loud or default level cannot confirm capped unmute")
        }
        for restored: UInt16 in [5, 80] {
            service = connect(raw: 40, muted: true)
            service.volumeOnUnmute = restored
            var readAfterUnmute = false
            service.afterUnmute = { [weak service] in
                service?.wantsMonitorVolumeKeys = false
                service?.onRead = { code in
                    if code == volume { readAfterUnmute = true }
                }
            }
            press(.mute)
            service.finish()
            let tooLoud = restored > 5
            let expected = [Write(volume, 5), Write(mute, 2)] + (tooLoud ? [Write(mute, 1)] : [])
            suite.expect(readAfterUnmute && service.raw == restored && service.nativeMuted == tooLoud
                         && service.writes == expected && Keys.NotchService.shared.shownLevels.isEmpty,
                         "disabling keys just after unmute checks the restored \(restored)% and silences only an unsafe level")
        }
        service = connect(raw: 40, muted: true)
        service.afterUnmute = { [weak service] in service?.actualDevice = 32 }
        press(.mute)
        service.finish()
        suite.expect(service.raw == 5 && service.nativeMuted == false && service.writes == [Write(volume, 5), Write(mute, 2)]
                     && Keys.NotchService.shared.shownLevels.isEmpty,
                     "a quiet unmute cannot announce success after the output changes ahead of its listener")

        service = connect(raw: 40, muted: true)
        service.afterSend = { [weak service] in service?.wantsMonitorVolumeKeys = false }
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 5)] && service.nativeMuted == true,
                     "disabling keys after the capped level write still cancels the pending unmute")

        for nativeMute in [true, false] {
            for hasRegistryID in [false, true] {
                let id: UInt64? = hasRegistryID ? 1 : nil
                service = nativeMute ? connect(raw: 40, muted: true, registryEntryID: id)
                                     : connect(raw: 0, unmutedReads: 0, registryEntryID: id)
                if hasRegistryID {
                    service.afterSend = { [weak service] in service?.connectedSpeakerEndpointID = 2 }
                }
                service.nativeMuted = true
                service.volumeOnUnmute = 80
                let claimed = press(nativeMute ? .mute : .volumeUp)
                service.finish()
                let expectedWrites = hasRegistryID ? [Write(volume, nativeMute ? 5 : 1)] : []
                suite.expect(claimed == (hasRegistryID || !nativeMute) && service.writes == expectedWrites && service.nativeMuted == true
                             && (!hasRegistryID || service.connectedSpeakerEndpointID == 2)
                             && Keys.NotchService.shared.shownLevels.isEmpty,
                             "a missing or vanished registry endpoint prevents unmute (native: \(nativeMute), registered: \(hasRegistryID))")
            }
        }
        service = connect(raw: 1, registryEntryID: nil)
        let claimedMissingMute = press(.mute)
        press(.volumeDown)
        var acceptedMute: Bool?
        Keys.AppVolumeMixer.shared.requestOutputAdjustment(muted: true) { acceptedMute = $0 }
        service.finish()
        suite.expect(!claimedMissingMute && acceptedMute == false && service.writes.isEmpty && service.nativeMuted == false
                     && service.displays.first?.audio?.muted == false && !Keys.AppVolumeMixer.shared.canToggleOutputMute,
                     "a monitor without a verifiable endpoint offers no mute and cannot be silenced by a key or mixer")
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 2)] && Keys.AppVolumeMixer.shared.systemOutputMuted == false
                     && !Keys.AppVolumeMixer.shared.canToggleOutputMute,
                     "changing an audible level preserves the reported mute and disabled control")

        for latches in [false, true] {
            service = connect(raw: 10, muted: latches ? false : nil, unmutedReads: 0, registryEntryID: nil)
            guard let target = service.displays.first?.audio?.target else {
                suite.expect(false, "a monitor without an endpoint ID keeps its panel volume slider")
                continue
            }
            var accepted: Bool?
            service.requestSpeakers(.set(volume: 0, muted: nil), target: target) { accepted = $0 }
            service.finish()
            suite.expect(accepted == true && service.writes == [Write(volume, latches ? 1 : 0)],
                         "the panel keeps the lowest reversible volume when zero would require a separate unmute")
        }

        service = connect(raw: 2)
        service.onSend = { [weak service] in service?.connectedSpeakerEndpointID = 2 }
        press(.mute)
        service.finish()
        suite.expect(service.writes.isEmpty && service.nativeMuted == false,
                     "losing the endpoint while a claimed mute waits for DDC prevents the mute write")

        for nativeMute in [true, false] {
            let target: UInt16 = nativeMute ? 5 : 1
            let restorations: [(UInt16, Bool)] = [(target, false), (80, false), (80, true)]
            for (restored, ignoresMute) in restorations {
                service = nativeMute ? connect(raw: 40, muted: true) : connect(raw: 0, unmutedReads: 0)
                service.volumeOnUnmute = restored
                service.ignoreMute = ignoresMute
                var checkedVolume = false
                service.afterUnmute = { [weak service] in
                    guard let service else { return }
                    service.wantsMonitorVolume = false
                    service.syncWithPreferences()
                    service.onRead = { code in
                        if code == volume { checkedVolume = true }
                    }
                }
                press(nativeMute ? .mute : .volumeUp)
                service.finish()
                var expected = [Write(volume, target), Write(mute, 2)]
                if restored > target { expected.append(Write(mute, 1)) }
                if ignoresMute { expected.append(Write(volume, target)) }
                suite.expect(checkedVolume && service.writes == expected && service.writtenIDs.allSatisfy { $0 == 7 }
                             && service.nativeMuted == (restored > target && !ignoresMute)
                             && service.raw == (ignoresMute ? target : restored)
                             && service.audioRoutes.isEmpty && service.displays.first?.audio == nil
                             && Keys.AppVolumeMixer.shared.monitorOutput == nil
                             && Hardware.writes.isEmpty && Keys.NotchService.shared.shownLevels.isEmpty,
                             "disabled speaker controls finish the accepted unmute at \(restored)% (native: \(nativeMute), ignores mute: \(ignoresMute))")
            }
        }

        let disconnects: [(String, (DisplaySpeakerVolumeTests.Service) -> Void)] = [
            ("sleep", { $0.displayIsAsleep = true }),
            ("replacement display", { $0.displayFingerprint = "replacement" }),
            ("replacement DDC endpoint on the same port", { $0.connectedSpeakerEndpointID = 2 }),
            ("explicit stop", { $0.stop() }),
        ]
        for (reason, disconnect) in disconnects {
            service = connect(raw: 40, muted: true)
            service.volumeOnUnmute = 80
            var readsAfterLoss = 0
            service.afterUnmute = { [weak service] in
                guard let service else { return }
                service.wantsMonitorVolume = false
                service.syncWithPreferences()
                disconnect(service)
                service.onRead = { _ in readsAfterLoss += 1 }
            }
            press(.mute)
            service.finish()
            suite.expect(readsAfterLoss == 0 && service.writes == [Write(volume, 5), Write(mute, 2)]
                         && Keys.NotchService.shared.shownLevels.isEmpty,
                         "after speaker controls are disabled, \(reason) prevents further DDC reads and writes")
        }

        service = connect(raw: 40, muted: true)
        service.volumeOnUnmute = 80
        var readsDuringRecovery: [UInt8] = []
        var revokedDuringLookup = false
        service.afterUnmute = { [weak service] in
            guard let service else { return }
            service.wantsMonitorVolume = false
            service.syncWithPreferences()
            service.onRead = { [weak service] code in
                readsDuringRecovery.append(code)
                service?.onEndpointLookup = { [weak service] in
                    guard let service else { return }
                    service.onEndpointLookup = nil
                    service.stateLock.withLock { service.invalidateSpeakerRoutes() }
                    revokedDuringLookup = true
                }
            }
        }
        press(.mute)
        service.finish()
        suite.expect(revokedDuringLookup && readsDuringRecovery == [volume]
                     && service.writes == [Write(volume, 5), Write(mute, 2)] && Keys.NotchService.shared.shownLevels.isEmpty,
                     "a physical disconnect during the next registry lookup cancels the remaining recovery reads and writes")

        for nativeMute in [true, false] {
            service = nativeMute ? connect(raw: 40, muted: true) : connect(raw: 0, unmutedReads: 0)
            service.volumeOnUnmute = 80
            service.rejectMute = true
            service.afterUnmute = { [weak service] in
                guard let service else { return }
                service.brightnessControlsEnabled = false
                service.syncWithPreferences()
            }
            press(nativeMute ? .mute : .volumeUp)
            service.finish()
            let target: UInt16 = nativeMute ? 5 : 1
            suite.expect(!service.running && service.audioRoutes.isEmpty && service.raw == target
                         && service.writes == [Write(volume, target), Write(mute, 2), Write(mute, 1), Write(volume, target)]
                         && service.writtenIDs == [7, 7, 7, 7] && Keys.NotchService.shared.shownLevels.isEmpty,
                         "disabled controls finish the rejected re-mute at the last verified positive level (native: \(nativeMute))")
        }

        service = connect(raw: 40, muted: true)
        service.afterUnmute = { [weak service] in
            service?.monitorVolumeKeySettings = .init(stepPercent: 1, maximumPercent: 3)
        }
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 5), Write(mute, 2), Write(mute, 1)] && service.nativeMuted == true
                     && Keys.NotchService.shared.shownLevels.isEmpty,
                     "lowering the ceiling to three percent just after unmute silences a monitor still at five")

        for maximum: UInt16 in [20, 100] {
            service = connect(raw: maximum, maximum: maximum, muted: true)
            service.volumeOnUnmute = maximum
            service.rejectMute = true
            service.afterUnmute = { [weak service] in
                service?.monitorVolumeKeySettings = .init(maximumPercent: 3)
            }
            press(.mute)
            service.finish()
            let writes = [Write(volume, maximum / 20), Write(mute, 2), Write(mute, 1)]
            suite.expect(service.writes == writes + (maximum == 100 ? [Write(volume, 3)] : [])
                         && service.raw == (maximum == 100 ? 3 : maximum) && Keys.NotchService.shared.shownLevels.isEmpty,
                         "the latest ceiling bounds the recovery level and a ceiling below one unit prevents the write")
        }
        for (maximum, ignoresWrite): (UInt16, Bool) in [(100, false), (100, true), (20, false)] {
            let restored = min(80, maximum)
            service = connect(raw: min(40, maximum), maximum: maximum, muted: true)
            service.volumeOnUnmute = restored
            service.rejectMute = true
            var readbacks: [UInt16] = []
            service.onRead = { [weak service] code in
                guard let service, code == volume else { return }
                if service.writes.count == 4 { readbacks.append(service.raw) }
                if service.writes.last == Write(mute, 1) {
                    service.onSend = { [weak service] in
                        service?.monitorVolumeKeySettings = .init(maximumPercent: 3)
                        service?.ignoreVolume = ignoresWrite
                    }
                }
            }
            press(.mute)
            service.finish()
            let recovery = maximum == 100 ? [Write(volume, 3)] : []
            let finalLevel: UInt16 = maximum == 100 && !ignoresWrite ? 3 : restored
            suite.expect(service.monitorVolumeKeySettings.maximumPercent == 3 && service.raw == finalLevel
                         && service.writes == [Write(volume, maximum / 20), Write(mute, 2), Write(mute, 1)] + recovery
                         && service.singleAttemptWrites == recovery && readbacks == (recovery.isEmpty ? [] : [finalLevel])
                         && Keys.NotchService.shared.shownLevels.isEmpty,
                         "a ceiling lowered during recovery pacing sets a representable live level once and reads it back")
        }

        for chip in [BrightnessSupport.chipAddress, BrightnessSupport.hdmiConverterChipAddress] {
            service = connect(raw: 0, unmutedReads: 0, chip: chip)
            service.volumeOnUnmute = 80
            press(.volumeUp)
            service.finish()
            suite.expect(service.nativeMuted == true && Keys.NotchService.shared.shownLevels.isEmpty
                         && service.writes == [Write(volume, 1), Write(mute, 2), Write(mute, 1)]
                         && service.chips.allSatisfy { $0 == chip },
                         "a nonstandard unmute that restores a loud volume is silenced on the original DDC route")
        }
        let converter = BrightnessSupport.hdmiConverterChipAddress
        for nativeMute in [true, false] {
            service = nativeMute ? connect(raw: 40, muted: true, chip: converter)
                                 : connect(raw: 0, unmutedReads: 0, chip: converter)
            service.audioRoutes[8] = .init(path: "port-b", fingerprint: service.displayFingerprint,
                                           service: NSObject(), registryEntryID: 2, chipAddress: BrightnessSupport.chipAddress,
                                           hasNativeMute: true, unmutesLeavingZero: false)
            let otherTarget = BrightnessSupport.SpeakerTarget(displayID: 8, path: "port-b")
            service.displays.append(.init(id: 8, name: "Monitor B", audio: .init(target: otherTarget, volume: 0.5, muted: false, canToggleMute: true)))
            service.volumeOnUnmute = 80
            service.ignoreMute = true
            var checkedMute = false
            var checkedLevel = false
            service.onRead = { [weak service] code in
                if code == mute, service?.writes.last == Write(mute, 1) { checkedMute = true }
                if code == volume, service?.writes.count == 4 { checkedLevel = true }
            }
            service.afterUnmute = { [weak service] in
                guard let service else { return }
                service.actualDevice = 32
                service.selectedAudioOutput = (32, "Monitor B", "monitor-b")
                service.audioOutputGeneration += 1
                Keys.AppVolumeMixer.shared.monitorOutput = service.monitorSpeakerOutput()
            }
            press(nativeMute ? .mute : .volumeUp)
            service.finish()
            let target: UInt16 = nativeMute ? 5 : 1
            let expected = [Write(volume, target), Write(mute, 2), Write(mute, 1), Write(volume, target)]
            suite.expect(checkedMute && checkedLevel && service.nativeMuted == false && service.raw == target && service.writes == expected
                         && service.writtenIDs == [7, 7, 7, 7] && service.chips.allSatisfy { $0 == converter }
                         && Keys.AppVolumeMixer.shared.monitorOutput?.target.displayID == 8
                         && Keys.AppVolumeMixer.shared.systemOutputVolume == 0.5
                         && Hardware.writes.isEmpty && Keys.NotchService.shared.shownLevels.isEmpty,
                         "after switching outputs only the original monitor receives and verifies the recovery level (native: \(nativeMute))")
        }

        service = connect(raw: 40, muted: true)
        service.volumeOnUnmute = 80
        service.afterUnmute = { [weak service] in
            service?.onSend = { [weak service] in service?.displayFingerprint = "replacement" }
        }
        press(.mute)
        service.finish()
        suite.expect(service.displayFingerprint == "replacement" && service.writes == [Write(volume, 5), Write(mute, 2)]
                     && Keys.NotchService.shared.shownLevels.isEmpty,
                     "a monitor that replaces the original during re-mute pacing never receives its safety write")

        for (reason, disconnect) in disconnects {
            service = connect(raw: 40, muted: true)
            service.volumeOnUnmute = 80
            service.ignoreMute = true
            var interrupted = false
            service.onRead = { [weak service] code in
                guard let service, code == mute, service.writes.last == Write(mute, 1) else { return }
                service.onSend = { [weak service] in
                    guard let service else { return }
                    disconnect(service)
                    interrupted = true
                }
            }
            press(.mute)
            service.finish()
            suite.expect(interrupted && service.writes == [Write(volume, 5), Write(mute, 2), Write(mute, 1)]
                         && Keys.NotchService.shared.shownLevels.isEmpty,
                         "\(reason) during recovery pacing cancels the fallback volume write")
        }

        service = connect(raw: 40, muted: true)
        service.volumeOnUnmute = 80
        var readsAfterReplacement = 0
        service.afterUnmute = { [weak service] in
            guard let service, let old = service.audioRoutes[7] else { return }
            service.audioRoutes[7] = .init(path: old.path, fingerprint: old.fingerprint, service: old.service,
                                           registryEntryID: 2, chipAddress: old.chipAddress,
                                           hasNativeMute: true, unmutesLeavingZero: false)
            service.onRead = { _ in readsAfterReplacement += 1 }
        }
        press(.mute)
        service.finish()
        suite.expect(readsAfterReplacement == 0 && service.writes == [Write(volume, 5), Write(mute, 2)]
                     && Keys.NotchService.shared.shownLevels.isEmpty,
                     "even a reused service handle cannot transfer verification or re-mute to a new registry entry")

        service = connect(raw: 40, muted: nil, settings: .init(stepPercent: 1, minimumPercent: 3, maximumPercent: 5))
        let claimedMute = press(.mute)
        service.finish()
        suite.expect(!claimedMute && service.writes.isEmpty && Keys.NotchService.shared.shownLevels.isEmpty,
                     "the mute key passes through without feedback when only volume is supported")

        let defaults = MonitorVolumeKeySettings(stepPercent: .nan, minimumPercent: -1, maximumPercent: 0)
        suite.expect(defaults.stepPercent == 6.25 && defaults.minimumPercent == 0 && defaults.maximumPercent == 100,
                     "invalid or missing preferences use the standard grid and full range")
        let domain = "vorss.tests.monitor-volume-keys.\(UUID().uuidString)"
        if let preferences = UserDefaults(suiteName: domain) {
            defer { preferences.removePersistentDomain(forName: domain) }
            preferences.set(10.0, forKey: DefaultsKey.ddcVolumeStep)
            preferences.set(20, forKey: DefaultsKey.ddcVolumeMinimum)
            preferences.set(70, forKey: DefaultsKey.ddcVolumeMaximum)
            suite.expect(MonitorVolumeKeySettings(in: preferences) == limits,
                         "the keys read the step and limits stored by the settings controls")
        } else {
            suite.expect(false, "the isolated monitor volume preference suite opens")
        }
        for key in [DefaultsKey.ddcVolumeStep, DefaultsKey.ddcVolumeMinimum, DefaultsKey.ddcVolumeMaximum] {
            suite.expect(SettingsBackupSupport.exportKeys().contains(key), "monitor key setting travels in backup: \(key)")
        }
    }
}
