// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// The real headphone disconnect lowering and its restore run against an
/// in-memory pair of outputs. No device volume or mute switch is touched.
enum MixerHeadphonesDisconnectContract {
    struct MixerOutputDevice {
        let uid: String
        let isHeadphones: Bool
        let audioObjectID: AudioObjectID
    }

    enum Mixer {
        typealias MixerOutputDevice = MixerHeadphonesDisconnectContract.MixerOutputDevice
        /// Volume per device; a device missing here cannot be lowered.
        static var volumes: [AudioObjectID: Float32] = [:]
        /// Mute per device; a device missing here has no mute switch.
        static var mutes: [AudioObjectID: Bool] = [:]
        static var muteSettable = true
        static var muteWrites: [Bool] = []

        static func outputVolume(for device: AudioObjectID) -> Float32? { volumes[device] }
        static func setOutputVolume(_ volume: Float32, for device: AudioObjectID) -> Bool {
            guard volumes[device] != nil else { return false }
            volumes[device] = volume
            return true
        }
        static func outputMuted(for device: AudioObjectID) -> Bool? { mutes[device] }
        @discardableResult
        static func setOutputMuted(_ muted: Bool, for device: AudioObjectID) -> Bool {
            guard mutes[device] != nil, muteSettable else { return false }
            muteWrites.append(muted)
            mutes[device] = muted
            return true
        }
    }

    static func run(_ suite: TestSuite) {
        let headphones = MixerOutputDevice(uid: "headphones", isHeadphones: true, audioObjectID: 1)
        let speakers = MixerOutputDevice(uid: "speakers", isHeadphones: false, audioObjectID: 2)
        func reset(speakerVolume: Float32 = 0.6, speakerMuted: Bool? = false) {
            Mixer.volumes = [1: 0.5, 2: speakerVolume]
            Mixer.mutes = [1: false]
            Mixer.mutes[2] = speakerMuted
            Mixer.muteSettable = true
            Mixer.muteWrites = []
        }
        func disconnect(percent: Int) -> Mixer.LoweredOutputState {
            Mixer.loweringOutputVolumeIfHeadphonesDisconnected(
                state: Mixer.LoweredOutputState(),
                previousDefaultUID: "headphones", previousOutputDevices: [headphones, speakers],
                nextDefaultUID: "speakers", nextOutputDevices: [speakers],
                lowerOnDisconnect: true, lowerToPercent: percent)
        }
        func reconnect(_ state: Mixer.LoweredOutputState) -> Mixer.LoweredOutputState {
            Mixer.loweringOutputVolumeIfHeadphonesDisconnected(
                state: state,
                previousDefaultUID: "speakers", previousOutputDevices: [speakers],
                nextDefaultUID: "headphones", nextOutputDevices: [headphones, speakers],
                lowerOnDisconnect: true, lowerToPercent: 0)
        }

        reset()
        var state = disconnect(percent: 0)
        suite.expect(Mixer.volumes[2] == 0 && Mixer.mutes[2] == true
                     && state.loweredOutput?.mutedByLowering == true,
                     "a headphone disconnect lowered to silence also mutes the speakers")
        state = reconnect(state)
        suite.expect(Mixer.volumes[2] == 0.6 && Mixer.mutes[2] == false && state.loweredOutput == nil,
                     "headphones coming back unmute the speakers the disconnect muted and restore their volume")

        reset()
        _ = disconnect(percent: 5)
        suite.expect(Mixer.mutes[2] == false && Mixer.muteWrites.isEmpty,
                     "a low but audible disconnect volume never touches the speakers' mute")

        reset(speakerMuted: true)
        state = disconnect(percent: 0)
        suite.expect(state.loweredOutput?.mutedByLowering == false && Mixer.muteWrites.isEmpty,
                     "speakers muted before the disconnect are not recorded as muted by it")
        state = reconnect(state)
        suite.expect(Mixer.mutes[2] == true && Mixer.muteWrites.isEmpty,
                     "speakers muted before the disconnect stay muted when the headphones come back")

        reset()
        state = disconnect(percent: 0)
        Mixer.mutes[2] = false
        Mixer.muteWrites = []
        state = reconnect(state)
        suite.expect(Mixer.muteWrites.isEmpty && Mixer.mutes[2] == false,
                     "a mute switched off after the disconnect is not written again when the headphones come back")

        reset()
        state = disconnect(percent: 0)
        Mixer.volumes[2] = 0.3
        Mixer.muteWrites = []
        state = reconnect(state)
        suite.expect(Mixer.volumes[2] == 0.3 && Mixer.mutes[2] == true
                     && Mixer.muteWrites.isEmpty && state.loweredOutput == nil,
                     "speakers changed after the disconnect keep their volume and their mute when the headphones come back")

        reset()
        Mixer.muteSettable = false
        state = disconnect(percent: 0)
        suite.expect(Mixer.volumes[2] == 0 && state.loweredOutput?.mutedByLowering == false,
                     "a mute switch that cannot be set is not recorded as muted by the disconnect")

        reset(speakerVolume: 0)
        state = disconnect(percent: 0)
        suite.expect(Mixer.mutes[2] == true && state.loweredOutput?.mutedByLowering == true,
                     "speakers already at zero are still remembered as muted by the disconnect")
        state = reconnect(state)
        suite.expect(Mixer.mutes[2] == false && state.loweredOutput == nil,
                     "speakers already at zero are unmuted again when the headphones come back")
    }
}
