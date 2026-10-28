// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Pure rules behind a monitor's own speaker volume: the DDC replies, the
/// volume and mute key parsing and routing, and the remembered-path cache.
enum DisplaySpeakerVolumeTests {
    static func run(_ suite: TestSuite) {
        suite.expect(BrightnessSupport.audioReply(current: 50, maximum: 100) == 0.5
                     && BrightnessSupport.audioReply(current: 100, maximum: 100) == 1,
                     "a volume reply is read against its own maximum")
        suite.expect(BrightnessSupport.audioReply(current: 5, maximum: 0) == nil,
                     "a volume reply without a maximum is never trusted")

        suite.expect(BrightnessSupport.muteReply(current: 1, maximum: 2) == true
                     && BrightnessSupport.muteReply(current: 2, maximum: 2) == false,
                     "only the two MCCS mute values read as muted or unmuted")
        suite.expect(BrightnessSupport.muteReply(current: 0, maximum: 2) == nil
                     && BrightnessSupport.muteReply(current: 3, maximum: 100) == nil
                     && BrightnessSupport.muteReply(current: 1, maximum: 1) == nil,
                     "any other mute value is not a mute control")
        suite.expect(BrightnessSupport.muteDeviceValue(true) == BrightnessSupport.audioMutedValue
                     && BrightnessSupport.muteDeviceValue(false) == BrightnessSupport.audioUnmutedValue,
                     "mute writes use the MCCS values")

        suite.expect(BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeHDMI)
                     && BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeDisplayPort)
                     && !BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeBuiltIn)
                     && !BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeBluetooth),
                     "only HDMI and DisplayPort outputs can belong to a monitor")
        suite.expect(BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeHDMI, outputHasSettableVolume: false)
                     && !BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeHDMI, outputHasSettableVolume: true)
                     && !BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeBuiltIn, outputHasSettableVolume: false),
                     "keys reach a monitor only when its output cannot take macOS volume")
        typealias Mute = BrightnessSupport
        suite.expect(Mute.monitorMuteChange(from: 0.0625, muted: false, to: 0, raises: false) == true
                     && Mute.monitorMuteChange(from: 0, muted: true, to: 0, raises: false) == nil,
                     "reaching zero mutes a monitor once, as macOS does for its own outputs")
        suite.expect(Mute.monitorMuteChange(from: 0, muted: false, to: 0.0625, raises: true) == false,
                     "leaving zero unmutes even when the last reading said unmuted, for monitors that mute themselves")
        suite.expect(Mute.monitorMuteChange(from: 0.4, muted: true, to: 0.5, raises: true) == false
                     && Mute.monitorMuteChange(from: 0.4, muted: true, to: 0.3, raises: false) == nil
                     && Mute.monitorMuteChange(from: 0.4, muted: false, to: 0.5, raises: true) == nil,
                     "a raise lifts a chosen mute, a lower leaves it, and an audible step writes no mute")
        suite.expect(Mute.monitorMuteChange(from: 0.0625, muted: nil, to: 0, raises: false) == nil
                     && Mute.monitorMuteChange(from: 0, muted: nil, to: 0.0625, raises: true) == nil,
                     "a monitor without an MCCS mute control never gets a mute write")
        suite.expect(Mute.unmutesAfterLevel(muted: false, volume: 0.01)
                     && !Mute.unmutesAfterLevel(muted: true, volume: 0)
                     && !Mute.unmutesAfterLevel(muted: false, volume: nil)
                     && !Mute.unmutesAfterLevel(muted: false, volume: 0)
                     && !Mute.unmutesAfterLevel(muted: nil, volume: 0.5),
                     "an unmute that leaves zero follows the level write, since monitors refuse it at zero")

        let monitors: [(id: UInt32, name: String)] = [(2, "LG HDR 4K"), (3, "DELL U2720Q")]
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "DELL U2720Q",
                        candidates: monitors, connectedDisplayCount: 2) == 3
                     && BrightnessSupport.displayForAudioOutput(deviceName: "dell u2720q",
                        candidates: monitors, connectedDisplayCount: 2) == 3,
                     "the sound device is matched to its display by name, ignoring case")
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "LG HDR 4K Audio",
                        candidates: monitors, connectedDisplayCount: 2) == 2,
                     "a device name that extends the display name still matches it")
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "MacBook Pro Speakers",
                        candidates: monitors, connectedDisplayCount: 2) == nil
                     && BrightnessSupport.displayForAudioOutput(deviceName: "",
                        candidates: monitors, connectedDisplayCount: 2) == nil,
                     "sound from another device or with no name never routes keys to a display")
        let lone: [(id: UInt32, name: String)] = [(7, "Studio Display")]
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "Built-in Output",
                        candidates: lone, connectedDisplayCount: 1) == 7
                     && BrightnessSupport.displayForAudioOutput(deviceName: "Built-in Output",
                        candidates: lone, connectedDisplayCount: 2) == nil,
                     "a lone candidate answers only while it is the only connected display")

        func keyData(_ code: Int, state: Int, repeatBit: Int = 0) -> Int {
            (code << 16) | (state << 8) | repeatBit
        }
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(0, state: 10))
                        == BrightnessSupport.VolumeKeyEvent(action: .step(direction: 1),
                                                            isKeyDown: true, isRepeat: false),
                     "the volume-up key press parses as one step up")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(1, state: 11))
                        == BrightnessSupport.VolumeKeyEvent(action: .step(direction: -1),
                                                            isKeyDown: false, isRepeat: false),
                     "the volume-down key release parses as one step down")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(7, state: 10))
                        == BrightnessSupport.VolumeKeyEvent(action: .toggleMute,
                                                            isKeyDown: true, isRepeat: false),
                     "the mute key press parses as a mute toggle")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8,
                        data1: keyData(0, state: 10, repeatBit: 1))?.isRepeat == true,
                     "a held volume key is marked as a repeat")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(2, state: 10)) == nil
                     && BrightnessSupport.volumeKeyEvent(subtype: 7, data1: keyData(0, state: 10)) == nil
                     && BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(0, state: 7)) == nil,
                     "brightness keys, other subtypes and other states are never volume keys")

        suite.expect(BrightnessSupport.volumeKeyDelta(direction: 1, fine: false) == 1.0 / 16.0
                     && BrightnessSupport.volumeKeyDelta(direction: -1, fine: true) == -1.0 / 100.0,
                     "a plain key moves a sixteenth and Option+Shift a percent, in the key's direction")
        suite.expect(BrightnessSupport.volumeKeyFineness(option: true, shift: true,
                        commandOrControl: false) == true
                     && BrightnessSupport.volumeKeyFineness(option: false, shift: false,
                        commandOrControl: false) == false
                     && BrightnessSupport.volumeKeyFineness(option: true, shift: false,
                        commandOrControl: false) == nil
                     && BrightnessSupport.volumeKeyFineness(option: true, shift: true,
                        commandOrControl: true) == nil,
                     "Option+Shift is the fine step, Option alone and Command or Control stay with macOS")
        suite.expect(BrightnessSupport.steppedLevel(0.95, delta: 0.1) == 1
                     && BrightnessSupport.steppedLevel(0.05, delta: -0.1) == 0
                     && BrightnessSupport.steppedLevel(0.5, delta: 0.25) == 0.75,
                     "a volume step stays between silent and full")

        suite.expect(BrightnessSupport.updatedRememberedPaths(["a", "b"], path: "c",
                        remembered: true, limit: 2) == ["b", "c"]
                     && BrightnessSupport.updatedRememberedPaths(["a", "b"], path: "a",
                        remembered: false) == ["b"],
                     "a silent-speaker path is remembered newest and forgotten when it changes")
        suite.expect(!BrightnessSupport.shouldProbe(pathKey: "a", rememberedPaths: ["a"])
                     && BrightnessSupport.shouldProbe(pathKey: "b", rememberedPaths: ["a"])
                     && BrightnessSupport.shouldProbe(pathKey: nil, rememberedPaths: ["a"]),
                     "a remembered silent path is not probed again, and an unknown path always is")
        suite.expect(BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: true, recheckedPaths: [])
                     && !BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: true, recheckedPaths: ["a"])
                     && !BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: [])
                     && BrightnessSupport.shouldProbeLuminance(pathKey: "b", writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: [])
                     && BrightnessSupport.shouldProbeLuminance(pathKey: nil, writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: []),
                     "a remembered write-only path is read again once while speakers are wanted, then trusted")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: true, repliedThisSession: true) == 2
                     && BrightnessSupport.ddcRetryDelay(attempt: 2, probesAudio: true, repliedThisSession: true) == 5
                     && BrightnessSupport.ddcRetryDelay(attempt: 3, probesAudio: true, repliedThisSession: true) == 15,
                     "a monitor that answered before is read again after about 2, 5 and 15 seconds")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 4, probesAudio: true, repliedThisSession: true) == nil,
                     "the write-only answer stands once the third retry fails")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: false, repliedThisSession: true) == nil
                     && BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: true, repliedThisSession: false) == nil,
                     "a failed read is retried only while speakers are wanted and the monitor answered this session")
        suite.expect(BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 100, lastRescan: nil)
                     && !BrightnessSupport.rescansForVolumeKey(hasTarget: true, displayOwnsOutput: true,
                        now: 100, lastRescan: nil)
                     && !BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: false,
                        now: 100, lastRescan: nil),
                     "an unclaimed volume key rescans only while a monitor output has no target")
        suite.expect(!BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 109, lastRescan: 100)
                     && BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 110, lastRescan: 100),
                     "volume keys rescan at most once every 10 seconds")
        suite.expect(BrightnessSupport.needsAudioScan(wanted: true, scanned: false, queued: nil)
                     && !BrightnessSupport.needsAudioScan(wanted: true, scanned: false, queued: true)
                     && !BrightnessSupport.needsAudioScan(wanted: true, scanned: true, queued: nil)
                     && BrightnessSupport.needsAudioScan(wanted: false, scanned: true, queued: true)
                     && !BrightnessSupport.needsAudioScan(wanted: false, scanned: true, queued: false),
                     "a speaker scan is forced once per setting change, not again while one is queued")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.displayVolumeEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.displayVolumeKeysEnabled] as? Bool == false,
                     "speaker volume and its volume keys are off until enabled")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeEnabled)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeKeysEnabled),
                     "the speaker volume switches travel in a settings backup")
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.displayAudioSilentPaths)
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayAudioSilentPaths),
                     "a monitor's silent-speaker memory stays on this Mac")
    }
}
