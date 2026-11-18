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
        func connect(raw: UInt16, maximum: UInt16 = 100, muted: Bool? = false,
                     settings: MonitorVolumeKeySettings = .init(stepPercent: 1, maximumPercent: 5)) -> DisplaySpeakerVolumeTests.Service {
            Hardware.reset()
            Keys.DispatchQueue.main = MixerOutputAdjustmentContract.Queue()
            Keys.AppVolumeMixer.shared = MixerOutputAdjustmentContract.Mixer()
            Keys.UserDefaults.precise = false
            Keys.NotchService.shared.shownLevels = []
            tap = Keys.Service()
            let service = DisplaySpeakerVolumeTests.connect(Keys.AppVolumeMixer.shared,
                                                            raw: raw, maximum: maximum, muted: muted)
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

        service = connect(raw: 40, muted: true)
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 5), Write(mute, 2)] && service.nativeMuted == false,
                     "native unmute confirms the new ceiling before releasing mute")
        service = connect(raw: 40, muted: true)
        service.ignoreVolume = true
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 5)] && service.nativeMuted == true
                     && Keys.NotchService.shared.shownLevels.isEmpty,
                     "an ignored level write cannot release mute at the old loud level")
        service = connect(raw: 40, muted: true)
        service.volumeOnUnmute = 40
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 5), Write(mute, 2), Write(mute, 1)]
                     && service.nativeMuted == true && Keys.NotchService.shared.shownLevels.isEmpty,
                     "a monitor that restores a loud level on native unmute is muted again after readback")
        service = connect(raw: 40, muted: nil, settings: .init(stepPercent: 1, minimumPercent: 3, maximumPercent: 5))
        press(.mute)
        service.finish()
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 0), Write(volume, 5)],
                     "volume-only mute can silence below the floor and restores at most the ceiling")

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
