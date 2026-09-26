// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The real shortcut switch runs against in-memory outputs. Nothing is routed.
enum SoundOutputSwitchContract {
    struct Device {
        let uid: String
        let canBeDefaultOutput: Bool
    }

    static func run(_ suite: TestSuite) {
        let mixer = Mixer()
        mixer.outputDevices = [Device(uid: "BuiltInSpeakerDevice", canBeDefaultOutput: true),
                               Device(uid: "ExternalDisplay", canBeDefaultOutput: true)]
        mixer.currentOutputDeviceUID = "BuiltInSpeakerDevice"
        suite.expect(mixer.switchToNextSoundOutput(in: ["BuiltInSpeakerDevice"]) && mixer.switchedTo.isEmpty,
                     "the only selected output already playing is not reported as a failed switch")
        suite.expect(!mixer.switchToNextSoundOutput(in: ["USBHeadphones"]) && mixer.switchedTo.isEmpty,
                     "a selection with no connected output still fails")
        suite.expect(mixer.switchToNextSoundOutput(in: ["BuiltInSpeakerDevice", "ExternalDisplay"])
                     && mixer.switchedTo == ["ExternalDisplay"],
                     "two selected outputs still switch to the next one")

        // The AirPlay entry is a per-app route: the mixer never marks it as a
        // possible system output, so the shortcut skips it like any output
        // that cannot be the default.
        let airPlayUID = AirPlayRouteManager.airPlaySentinelUID
        mixer.outputDevices = [Device(uid: "BuiltInSpeakerDevice", canBeDefaultOutput: true),
                               Device(uid: airPlayUID, canBeDefaultOutput: false),
                               Device(uid: "ExternalDisplay", canBeDefaultOutput: true)]
        mixer.currentOutputDeviceUID = "BuiltInSpeakerDevice"
        mixer.switchedTo = []
        suite.expect(mixer.switchToNextSoundOutput(in: ["BuiltInSpeakerDevice", airPlayUID, "ExternalDisplay"])
                     && mixer.switchedTo == ["ExternalDisplay"],
                     "the output shortcut skips the per-app AirPlay entry")
    }
}
