// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The production confirmation waits for the hardware when a switch lands late.
enum OutputDeviceConfirmationTests {
    struct MixerOutputDevice: Equatable {
        let uid: String
    }
    enum OutputDeviceFeedback {
        static var shown: [(uid: String, sound: Bool)] = []
        static func show(device: MixerOutputDevice, playConfirmationSound: Bool) {
            shown.append((device.uid, playConfirmationSound))
        }
    }
    static func run(expect: (Bool, String) -> Void) {
        let headphones = MixerOutputDevice(uid: "headphones")
        let speakers = MixerOutputDevice(uid: "speakers")

        OutputDeviceFeedback.shown = []
        let mixer = Mixer()
        mixer.confirmOutputSwitch(to: headphones, playConfirmationSound: true, defaultUID: "headphones", now: 10)
        expect(OutputDeviceFeedback.shown.map(\.uid) == ["headphones"] && OutputDeviceFeedback.shown.first?.sound == true
               && mixer.pendingOutputConfirmation == nil,
               "a switch the hardware already applied confirms at once")

        OutputDeviceFeedback.shown = []
        mixer.confirmOutputSwitch(to: speakers, playConfirmationSound: true, defaultUID: "headphones", now: 10)
        expect(OutputDeviceFeedback.shown.isEmpty && mixer.pendingOutputConfirmation?.device == speakers,
               "a switch the hardware has not applied yet waits instead of confirming")
        mixer.confirmPendingOutputSwitch(defaultUID: "headphones", now: 10.2)
        expect(OutputDeviceFeedback.shown.isEmpty && mixer.pendingOutputConfirmation != nil,
               "a refresh that still reports the previous output keeps waiting")
        mixer.confirmPendingOutputSwitch(defaultUID: "speakers", now: 10.5)
        expect(OutputDeviceFeedback.shown.map(\.uid) == ["speakers"] && OutputDeviceFeedback.shown.first?.sound == true
               && mixer.pendingOutputConfirmation == nil,
               "the refresh that reports the new default confirms the delayed switch with its sound")
        mixer.confirmPendingOutputSwitch(defaultUID: "speakers", now: 10.6)
        expect(OutputDeviceFeedback.shown.count == 1, "a delayed switch confirms only once")

        OutputDeviceFeedback.shown = []
        mixer.confirmOutputSwitch(to: headphones, playConfirmationSound: false, defaultUID: "speakers", now: 20)
        mixer.confirmPendingOutputSwitch(defaultUID: "headphones", now: 20 + Mixer.outputConfirmationWindow + 0.1)
        expect(OutputDeviceFeedback.shown.isEmpty && mixer.pendingOutputConfirmation == nil,
               "a switch that lands after the window confirms nothing and stops waiting")

        mixer.confirmOutputSwitch(to: headphones, playConfirmationSound: false, defaultUID: "speakers", now: 30)
        mixer.confirmOutputSwitch(to: speakers, playConfirmationSound: false, defaultUID: "speakers", now: 30.1)
        mixer.confirmPendingOutputSwitch(defaultUID: "headphones", now: 30.2)
        expect(OutputDeviceFeedback.shown.map(\.uid) == ["speakers"],
               "a newer switch replaces the one still waiting")
    }
}
