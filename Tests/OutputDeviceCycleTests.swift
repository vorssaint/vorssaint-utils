// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The production cycle action reads hardware independently of the UI snapshot.
enum OutputDeviceCycleTests {
    struct Device {
        let uid: String
        var canBeDefaultOutput = true
    }
    class State {
        static var hardwareUID: String? = "speakers"
        var currentOutputDeviceUID: String? = "speakers"
        var outputDevices = [Device(uid: "speakers"), Device(uid: "stream-mic"), Device(uid: "stream-speakers")]
        var requests: [String] = []
        var soundRequests: [Bool] = []
        static func defaultOutputDeviceUID() -> String? { hardwareUID }
        func setUniversalOutputDeviceUID(_ uid: String, playConfirmationSound: Bool = false) -> Bool {
            soundRequests.append(playConfirmationSound)
            requests.append(uid)
            Self.hardwareUID = uid
            // A queued UI snapshot can still describe the previous output.
            return true
        }
    }
    static func run(expect: (Bool, String) -> Void) {
        let mixer = Mixer()
        let selected = mixer.outputDevices.map(\.uid)
        State.hardwareUID = "speakers"
        for _ in 0..<6 { _ = mixer.switchToNextSoundOutput(in: selected) }
        expect(mixer.requests == ["stream-mic", "stream-speakers", "speakers",
                                  "stream-mic", "stream-speakers", "speakers"],
               "successive output shortcuts follow hardware even when the UI snapshot lags")
        expect(mixer.soundRequests.allSatisfy { $0 }, "shortcut cycling requests optional confirmation sound")
        State.hardwareUID = "stream-speakers"
        _ = mixer.switchToNextSoundOutput(in: selected)
        expect(mixer.requests.last == "speakers", "an external output change immediately advances from the actual device")
        State.hardwareUID = nil
        let count = mixer.requests.count
        expect(!mixer.switchToNextSoundOutput(in: selected) && mixer.requests.count == count,
               "a failed hardware read does not guess a cycle position from stale UI state")
    }
}
