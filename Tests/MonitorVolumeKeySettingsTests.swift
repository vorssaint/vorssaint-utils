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
                     chip: UInt32 = BrightnessSupport.chipAddress,
                     settings: MonitorVolumeKeySettings = .init(stepPercent: 1, maximumPercent: 5)) -> DisplaySpeakerVolumeTests.Service {
            Hardware.reset()
            Keys.DispatchQueue.main = MixerOutputAdjustmentContract.Queue()
            Keys.AppVolumeMixer.shared = MixerOutputAdjustmentContract.Mixer()
            Keys.UserDefaults.precise = false
            Keys.NotchService.shared.shownLevels = []
            tap = Keys.Service()
            let service = DisplaySpeakerVolumeTests.connect(Keys.AppVolumeMixer.shared,
                                                            raw: raw, maximum: maximum, muted: muted, unmutedReads: unmutedReads, chip: chip)
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
        service = connect(raw: 40, muted: nil, settings: .init(stepPercent: 1, minimumPercent: 3, maximumPercent: 5))
        press(.mute)
        service.finish()
        press(.mute)
        service.finish()
        suite.expect(service.writes == [Write(volume, 0), Write(volume, 5)],
                     "volume-only mute can silence below the floor and restores at most the ceiling")

        // Speed. A monitor answers over a slow bus, so a key that first reads the
        // level, writes and then reads it back made every press wait for three
        // transactions. A level this app confirmed moments ago is stepped from
        // directly: one write, with a single read once the keys go quiet.
        let tenths = MonitorVolumeKeySettings(stepPercent: 10)
        var reads = 0
        func countReads(_ service: DisplaySpeakerVolumeTests.Service) { service.onRead = { reads += 1 } }
        func runQueues(_ service: DisplaySpeakerVolumeTests.Service, until done: () -> Bool) {
            while !done(), !service.workQueue.jobs.isEmpty || !Keys.DispatchQueue.main.jobs.isEmpty {
                if !service.workQueue.jobs.isEmpty { service.workQueue.runOne() }
                if !Keys.DispatchQueue.main.jobs.isEmpty { Keys.DispatchQueue.main.runOne() }
            }
        }
        func shown() -> [Double] { Keys.NotchService.shared.shownLevels }

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        reads = 0
        countReads(service)
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        suite.expect(service.writes == [Write(volume, 50), Write(volume, 60)] && reads == 0 && shown() == [0.5, 0.6],
                     "a key right after a confirmed one writes the next level and shows it without reading first")
        suite.expect(service.displays[0].audio?.volume == 0.6 && service.displays[0].audio?.muted == false,
                     "the level a direct step wrote is published as audible")
        service.finish()
        suite.expect(reads == 2 && service.writes.count == 2 && service.displays[0].audio?.volume == 0.6,
                     "once the keys go quiet the monitor is read once, level and mute, and nothing is written")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        service.ignoreVolume = true
        press(.volumeUp)
        service.finish()
        suite.expect(shown() == [0.5, 0.6] && service.raw == 50 && service.displays[0].audio?.volume == 0.5,
                     "a level the monitor did not take is corrected by the read that follows")

        service = connect(raw: 40, muted: nil, settings: tenths)
        press(.volumeUp)
        service.finish()
        reads = 0
        countReads(service)
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        suite.expect(service.writes == [Write(volume, 50), Write(volume, 60)] && reads == 0
                     && service.displays[0].audio?.muted == false,
                     "a monitor with volume control only is stepped directly too")

        // A monitor behind the Mac's HDMI converter answers on another chip, and
        // a monitor still owed an unmute must have it sent: neither is a reason
        // to skip the speed-up, but both must survive it.
        service = connect(raw: 40, chip: 0x4A, settings: tenths)
        press(.volumeUp)
        service.finish()
        service.chips = []
        reads = 0
        countReads(service)
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        suite.expect(service.writes == [Write(volume, 50), Write(volume, 60)] && reads == 0
                     && service.chips == [0x4A],
                     "a direct step is sent to the chip the monitor's route was found on")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        service.pendingSpeakerUnmutes["port-a"] = service.audioLifetime
        reads = 0
        countReads(service)
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        suite.expect(reads > 0 && service.writes.first == Write(volume, 50),
                     "a monitor still owed an unmute is read and decided in full, not stepped blind")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        service.rejectVolume = true
        press(.volumeUp)
        service.finish()
        suite.expect(service.speakerBeliefs.isEmpty && shown() == [0.5],
                     "a write the monitor refused leaves no level to step from")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        // The monitor was reconnected and changed meanwhile: the new connection
        // publishes its own reading and nothing seen on the old one applies.
        service.audioLifetime &+= 1
        service.raw = 20
        if let audio = service.displays[0].audio {
            var target = audio.target
            target.connectionGeneration = service.audioLifetime
            service.displays[0].audio = .init(target: target, volume: 0.2, muted: false)
        }
        reads = 0
        countReads(service)
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 50), Write(volume, 30)] && reads > 0,
                     "a level seen on another connection of the monitor is not stepped from")

        service = connect(raw: 20, settings: .init(stepPercent: 10, minimumPercent: 0))
        press(.volumeDown)
        service.finish()
        service.rejectVolume = true
        press(.volumeDown)
        service.finish()
        suite.expect(service.speakerBeliefs.isEmpty,
                     "a change decided from a fresh reading that fails leaves no level to step from")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        service.raw = 20
        Hardware.uptime = 4
        reads = 0
        countReads(service)
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 50), Write(volume, 30)] && reads > 0,
                     "a level confirmed more than three seconds ago is not stepped from")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        service.onSend = { [weak service] in
            service?.monitorVolumeKeySettings = .init(stepPercent: 10, maximumPercent: 50)
        }
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 50)] && shown() == [0.5],
                     "a ceiling lowered while a direct step waits for the bus cancels it too")

        service = connect(raw: 20, settings: .init(stepPercent: 10, minimumPercent: 0))
        press(.volumeDown)
        service.finish()
        reads = 0
        countReads(service)
        press(.volumeDown)
        service.finish()
        suite.expect(reads > 0 && service.raw == 0 && service.nativeMuted == true,
                     "reaching zero is decided from a fresh reading and still mutes the monitor")

        service = connect(raw: 40, settings: tenths)
        press(.mute)
        service.finish()
        reads = 0
        countReads(service)
        press(.volumeUp)
        service.finish()
        suite.expect(reads > 0 && service.nativeMuted == false,
                     "a key after a mute reads the monitor before it lifts the mute")

        service = connect(raw: 40, muted: nil, settings: tenths)
        press(.mute)
        service.finish()
        reads = 0
        countReads(service)
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 0), Write(volume, 10)] && reads > 0,
                     "a key at a silenced volume-only monitor is decided from a fresh reading")

        service = connect(raw: 40, settings: .init(stepPercent: 10, maximumPercent: 50))
        press(.volumeUp)
        service.finish()
        reads = 0
        countReads(service)
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 50)] && reads > 0,
                     "a key at the ceiling leaves the monitor alone after asking it")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        reads = 0
        countReads(service)
        press(.mute)
        service.finish()
        suite.expect(reads > 0 && service.nativeMuted == true,
                     "a mute after a key is decided from a fresh reading")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        reads = 0
        countReads(service)
        Keys.AppVolumeMixer.shared.requestOutputAdjustment(volume: 0.8)
        runQueues(service, until: { service.writes.count == 2 })
        suite.expect(service.writes == [Write(volume, 50), Write(volume, 80)] && reads == 0,
                     "the monitor slider also writes straight after a confirmed level")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        reads = 0
        countReads(service)
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        press(.volumeUp)
        // The read that follows a quiet moment would fall due after this press.
        let due = Keys.DispatchQueue.main.jobs.removeFirst()
        Keys.DispatchQueue.main.jobs.append(due)
        service.finish()
        suite.expect(service.writes == [Write(volume, 50), Write(volume, 60), Write(volume, 70)] && reads == 2
                     && service.displays[0].audio?.volume == 0.7,
                     "a key that lands before the quiet-time read takes its place, so one read follows the last key")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        reads = 0
        countReads(service)
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        press(.volumeUp)
        service.finish()
        suite.expect(service.writes == [Write(volume, 50), Write(volume, 60), Write(volume, 70)]
                     && service.raw == 70 && service.displays[0].audio?.volume == 0.7,
                     "a key that lands while the quiet-time read is running is applied after it")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        Hardware.uptime = 2
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        Hardware.uptime = 4
        reads = 0
        countReads(service)
        press(.volumeUp)
        // The read that follows a quiet moment falls due after this press.
        let early = Keys.DispatchQueue.main.jobs.removeFirst()
        Keys.DispatchQueue.main.jobs.append(early)
        runQueues(service, until: { shown().count == 3 })
        suite.expect(service.writes.count == 3 && reads > 0,
                     "steps written without a reading stop being trusted three seconds after the last real one")
        service.finish()

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        service.displays[0].isActive = false
        reads = 0
        countReads(service)
        service.finish()
        suite.expect(reads == 0 && service.writes.count == 2,
                     "a monitor that went away is not read once the keys go quiet")

        service = connect(raw: 40, settings: tenths)
        press(.volumeUp)
        service.finish()
        press(.volumeUp)
        runQueues(service, until: { shown().count == 2 })
        let late = Keys.DispatchQueue.main.jobs.removeFirst()
        press(.volumeUp)
        service.finish()
        reads = 0
        countReads(service)
        late()
        service.finish()
        suite.expect(reads == 0 && service.writes.count == 3,
                     "a quiet-time read that falls due after a newer key finished does nothing")

        // The rule behind it, without the queue: which changes may start from a
        // level that was not just read.
        typealias Level = BrightnessSupport.SpeakerLevel
        typealias Change = BrightnessSupport.SpeakerChange
        func belief(raw: UInt16 = 40, maximum: UInt16 = 100, muted: Bool? = false, generation: UInt64 = 1,
                    readAt: TimeInterval = 10, predicted: Bool = false) -> BrightnessSupport.SpeakerBelief {
            BrightnessSupport.SpeakerBelief(level: Level(raw: raw, maximum: maximum), muted: muted,
                                            generation: generation, readAt: readAt, predicted: predicted)
        }
        func known(_ change: Change, _ belief: BrightnessSupport.SpeakerBelief?, generation: UInt64 = 1,
                   now: TimeInterval = 11, settings: MonitorVolumeKeySettings = tenths) -> Level? {
            BrightnessSupport.knownLevelTarget(for: change, belief: belief, generation: generation,
                                               now: now, keySettings: settings)
        }
        let raise = Change.step(levels: [{ $0 + 0.1 }], raises: true)
        let lower = Change.step(levels: [{ $0 - 0.1 }], raises: false)
        suite.expect(known(raise, belief()) == Level(raw: 50, maximum: 100)
                     && known(lower, belief()) == Level(raw: 30, maximum: 100),
                     "a fresh reading is stepped from without asking the monitor")
        suite.expect(known(raise, belief(predicted: true)) == Level(raw: 50, maximum: 100),
                     "a level this app wrote and has not read back yet can be stepped from")
        suite.expect(known(raise, belief(readAt: 10), now: 13) != nil && known(raise, belief(readAt: 10), now: 13.01) == nil
                     && known(raise, belief(readAt: 10), now: 9) == nil,
                     "a reading is trusted for three seconds, never longer and never from the future")
        suite.expect(known(raise, belief(generation: 1), generation: 2) == nil && known(raise, nil) == nil,
                     "a reading from another connection, or none at all, is not a level to step from")
        suite.expect(known(raise, belief(muted: true)) == nil && known(raise, belief(muted: nil)) == nil
                     && known(raise, belief(raw: 0)) == nil,
                     "a muted, undecided or silent monitor is read before any change")
        suite.expect(known(lower, belief(raw: 10)) == nil && known(lower, belief(raw: 5)) == nil,
                     "a step that reaches zero is decided from a fresh reading")
        suite.expect(known(raise, belief(raw: 50), settings: .init(stepPercent: 10, maximumPercent: 50)) == nil
                     && known(lower, belief(raw: 20), settings: .init(stepPercent: 10, minimumPercent: 20)) == nil,
                     "a step that changes nothing at a limit is left to a fresh reading")
        suite.expect(known(.step(levels: [{ _ in .nan }], raises: true), belief()) == nil
                     && known(.step(levels: [{ _ in .infinity }], raises: true), belief()) == nil,
                     "a step that is not a number never reaches the monitor")
        suite.expect(known(.toggleMute, belief()) == nil && known(.verification, belief()) == nil,
                     "a mute toggle and the quiet-time read always talk to the monitor first")
        suite.expect(known(.set(volume: 0.8, muted: nil), belief()) == Level(raw: 80, maximum: 100)
                     && known(.set(volume: 0.8, muted: nil), belief(maximum: 40)) == Level(raw: 32, maximum: 40),
                     "an absolute level is scaled to the monitor's own range")
        suite.expect(known(.set(volume: 0, muted: nil), belief()) == nil
                     && known(.set(volume: 0.4, muted: nil), belief()) == nil
                     && known(.set(volume: .nan, muted: nil), belief()) == nil
                     && known(.set(volume: 0.5, muted: false), belief()) == nil
                     && known(.set(volume: nil, muted: nil), belief()) == nil,
                     "silence, no change, a mute request or a bad number are left to a fresh reading")
        do {
            var restore: Level?
            var needsUnmute = false
            var wrote = false
            let quiet = BrightnessSupport.applySpeakerChange(
                .verification, hasNativeMute: true, unmutesLeavingZero: false,
                keySettings: MonitorVolumeKeySettings(minimumPercent: 0),
                restore: &restore, needsUnmute: &needsUnmute,
                read: { $0 == volume ? (0, 100) : (2, 2) }, write: { _, _ in wrote = true; return true })
            suite.expect(!wrote && quiet?.level == Level(raw: 0, maximum: 100) && quiet?.muted == false,
                         "the quiet-time read only reports, even for a monitor sitting at zero unmuted")
        }

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
