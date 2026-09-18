// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Actual mixer methods run against controlled queues and an in-memory audio
/// device. No output device, volume, mute state or event tap is touched.
enum MixerOutputAdjustmentContract {
    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func runOne() { precondition(!jobs.isEmpty); jobs.removeFirst()() }
    }
    enum DispatchQueue { static var main = Queue() }
    enum Hardware {
        struct Write: Equatable {
            let device: AudioObjectID
            let volume: Float?
            let muted: Bool?
        }
        static var device: AudioObjectID = 1
        static var writes: [Write] = []
        static var succeeds = true
        static var afterVolumeWrite: (() -> Void)?
    }

    static func run(_ suite: TestSuite) {
        func make() -> Mixer {
            DispatchQueue.main = Queue()
            Hardware.device = 1
            Hardware.writes = []
            Hardware.succeeds = true
            Hardware.afterVolumeWrite = nil
            let mixer = Mixer()
            mixer.selectOutput(1, volume: 0.2, muted: false)
            return mixer
        }
        func finish(_ mixer: Mixer) {
            while !mixer.halQueue.jobs.isEmpty || !DispatchQueue.main.jobs.isEmpty {
                if !mixer.halQueue.jobs.isEmpty { mixer.halQueue.runOne() }
                if !DispatchQueue.main.jobs.isEmpty { DispatchQueue.main.runOne() }
            }
        }

        var mixer = make()
        var completions: [Bool] = []
        mixer.requestOutputAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestOutputAdjustment(volume: 0.5) { completions.append($0) }
        mixer.requestOutputAdjustment(volume: 0.8) { completions.append($0) }
        mixer.readSnapshot(volume: 0.2, muted: true)
        suite.expect(mixer.systemOutputVolume == 0.8 && mixer.systemOutputMuted == false,
                     "an old volume read does not overwrite the newest pending adjustment")
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume) == [Float(0.3), Float(0.8)]
                     && completions == [true, true, true],
                     "one current write and the newest queued level apply once each")

        mixer = make()
        completions = []
        mixer.requestOutputAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestOutputAdjustment(volume: 0.6) { completions.append($0) }
        Hardware.device = 2
        mixer.selectOutput(2, volume: 0.1, muted: true)
        suite.expect(mixer.systemOutputVolume == 0.1 && mixer.systemOutputMuted == true,
                     "the new output publishes its own volume while an old write is pending")
        mixer.requestOutputAdjustment(volume: 0.8) { completions.append($0) }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 2, volume: 0.8, muted: nil),
                                         .init(device: 2, volume: nil, muted: false)],
                     "a new-output adjustment survives completion of the previous output's write")
        suite.expect(completions.count == 3 && completions.allSatisfy { $0 },
                     "discarded old keys settle without replaying onto the new output")

        mixer = make()
        mixer.requestOutputAdjustment(volume: 0.9)
        mixer.selectOutput(nil, volume: nil, muted: nil)
        mixer.selectOutput(1, volume: 0.15, muted: false)
        mixer.requestOutputAdjustment(volume: 0.25)
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume) == [Float(0.25)],
                     "reusing a device ID after stop cannot revive a previous lifetime's volume")

        mixer = make()
        var failed: Bool?
        Hardware.succeeds = false
        mixer.requestOutputAdjustment(volume: 0.4) { failed = $0 }
        finish(mixer)
        suite.expect(failed == false, "a current-output write failure remains available for native key fallback")
        suite.expect(mixer.controlRefreshes == [1], "a failed current write requests the actual output state")

        mixer = make()
        var settled: [Bool] = []
        mixer.requestOutputAdjustment(volume: 0.4) { settled.append($0) }
        Hardware.afterVolumeWrite = {
            Hardware.device = 2
            mixer.selectOutput(2, volume: 0.1, muted: true)
            mixer.requestOutputAdjustment(muted: false) { settled.append($0) }
        }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0.4, muted: nil),
                                         .init(device: 2, volume: nil, muted: false)],
                     "a switch during a driver write preserves the new mute request and skips stale unmute")
        suite.expect(settled == [true, true], "both in-progress and new-output requests settle once")

        mixer = make()
        completions = []
        for value in [Double.nan, .infinity, -.infinity] {
            mixer.requestOutputAdjustment(volume: value) { completions.append($0) }
        }
        suite.expect(completions == [false, false, false] && mixer.halQueue.jobs.isEmpty,
                     "nonfinite output requests never reach the driver")
    }
}
