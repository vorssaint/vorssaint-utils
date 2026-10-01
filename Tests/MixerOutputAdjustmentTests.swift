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
        static var volume: Float32? = 0.2
        static var muted: Bool? = false
    }

    static func run(_ suite: TestSuite) {
        func make() -> Mixer {
            DispatchQueue.main = Queue()
            Hardware.device = 1
            Hardware.writes = []
            Hardware.succeeds = true
            Hardware.afterVolumeWrite = nil
            Hardware.volume = 0.2
            Hardware.muted = false
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

        func step(_ delta: Double) -> (Double) -> Double { { $0 + delta } }

        mixer = make()
        completions = []
        Hardware.volume = 0.02
        mixer.requestOutputStep(level: step(0.01)) { completions.append($0) }
        suite.expect(mixer.systemOutputVolume == 0.2 && Hardware.writes.isEmpty,
                     "a volume key waits for the output's own reading before stepping")
        mixer.requestOutputStep(level: step(0.01)) { completions.append($0) }
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [3, 4]
                     && completions == [true, true],
                     "keys step from the device's level, not a stale reading from before sleep")

        for directMute in [true, false] {
            mixer = make()
            completions = []
            Hardware.volume = 0.7
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
            if directMute {
                mixer.requestOutputAdjustment(muted: true) { completions.append($0) }
            } else {
                mixer.requestOutputAdjustment(volume: 0.35) { completions.append($0) }
            }
            finish(mixer)
            suite.expect(Hardware.writes.compactMap(\.volume) == (directMute ? [] : [Float(0.35)])
                         && mixer.systemOutputMuted == directMute
                         && completions == [true, true],
                         "a newer direct \(directMute ? "mute" : "level") supersedes a key awaiting its HAL read")
        }

        mixer = make()
        completions = []
        Hardware.volume = 0.7
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
        mixer.requestOutputAdjustment(volume: 0.35) { completions.append($0) }
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [35, 45]
                     && completions == [true, true, true],
                     "a key after a direct level change follows that level rather than the stale HAL read")

        for directMute in [true, false] {
            mixer = make()
            completions = []
            Hardware.volume = nil
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
            if directMute {
                mixer.requestOutputAdjustment(muted: true) { completions.append($0) }
            } else {
                mixer.requestOutputAdjustment(volume: 0.35) { completions.append($0) }
            }
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
            finish(mixer)
            suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() }
                            == (directMute ? [10] : [35, 45])
                         && mixer.systemOutputMuted == false
                         && completions == [true, true, true],
                         "a key after a direct \(directMute ? "mute" : "level") follows it when the superseded read fails")
        }

        mixer = make()
        completions = []
        Hardware.volume = 0.5
        mixer.requestOutputAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 10).rounded() } == [3, 4],
                     "a key during this app's own write continues from the level it requested")

        mixer = make()
        completions = []
        Hardware.volume = 0.4
        Hardware.muted = true
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(Hardware.writes.first?.volume.map { ($0 * 10).rounded() } == 1
                     && mixer.systemOutputMuted == false,
                     "a key on a muted output steps up from silence and unmutes")

        // A level of zero also throws the mute switch, as the system's own
        // keys and the Control Center slider do, because the bottom of the
        // range alone is not silence on every output.
        mixer = make()
        completions = []
        mixer.requestOutputAdjustment(volume: 0) { completions.append($0) }
        suite.expect(mixer.systemOutputVolume == 0 && mixer.systemOutputMuted == true,
                     "a level of zero publishes the output as muted before the driver confirms it")
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && completions == [true],
                     "a level of zero writes the level and then mutes the output, as the system's own keys do")

        mixer = make()
        completions = []
        Hardware.volume = 0.015625
        mixer.requestOutputStep(level: { NotchSupport.volumeLevel(current: $0, direction: -1, fine: true) }) {
            completions.append($0)
        }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && mixer.systemOutputMuted == true && completions == [true],
                     "a volume key stepping down to zero mutes the output and stays handled")
        Hardware.volume = 0
        Hardware.muted = true
        mixer.requestOutputStep(level: { NotchSupport.volumeLevel(current: $0, direction: 1, fine: false) }) {
            completions.append($0)
        }
        finish(mixer)
        suite.expect(Array(Hardware.writes.suffix(2)) == [.init(device: 1, volume: 0.0625, muted: nil),
                                                          .init(device: 1, volume: nil, muted: false)]
                     && mixer.systemOutputMuted == false && completions == [true, true],
                     "a volume key from muted zero unmutes and steps up to the first level")

        mixer = make()
        completions = []
        Hardware.volume = 0.03125
        mixer.requestOutputStep(level: { NotchSupport.volumeLevel(current: $0, direction: -1, fine: true) }) {
            completions.append($0)
        }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0.015625, muted: nil),
                                         .init(device: 1, volume: nil, muted: false)]
                     && mixer.systemOutputMuted == false && completions == [true],
                     "the finest key step above zero keeps the output audible")

        mixer = make()
        completions = []
        Hardware.volume = 0.0627
        mixer.requestOutputStep(level: { NotchSupport.volumeLevel(current: $0, direction: -1, fine: false) }) {
            completions.append($0)
        }
        finish(mixer)
        suite.expect(Hardware.writes.map(\.muted) == [nil, true]
                     && mixer.systemOutputMuted == true && completions == [true],
                     "a coarse key step from a reading a hair above one step lands on 0% and mutes")

        mixer = make()
        completions = []
        Hardware.muted = nil
        mixer.selectOutput(1, volume: 0.2, muted: nil)
        mixer.requestOutputAdjustment(volume: 0) { completions.append($0) }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil)]
                     && completions == [true] && mixer.systemOutputMuted == nil,
                     "an output without a mute switch takes the zero level alone and reports the request handled")

        mixer = make()
        completions = []
        mixer.requestOutputAdjustment(volume: 0.5) { completions.append($0) }
        mixer.requestOutputAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestOutputAdjustment(volume: 0) { completions.append($0) }
        suite.expect(mixer.systemOutputMuted == true, "a drag that ends at zero publishes the output as muted")
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0.5, muted: nil),
                                         .init(device: 1, volume: nil, muted: false),
                                         .init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && completions == [true, true, true],
                     "a drag that ends at zero mutes even when it coalesces with an audible level")

        mixer = make()
        completions = []
        mixer.requestOutputAdjustment(volume: 0.5) { completions.append($0) }
        mixer.requestOutputAdjustment(volume: 0) { completions.append($0) }
        mixer.requestOutputAdjustment(volume: 0.1) { completions.append($0) }
        suite.expect(mixer.systemOutputVolume == 0.1 && mixer.systemOutputMuted == false,
                     "a drag through zero and back up publishes the audible level unmuted")
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0.5, muted: nil),
                                         .init(device: 1, volume: nil, muted: false),
                                         .init(device: 1, volume: 0.1, muted: nil),
                                         .init(device: 1, volume: nil, muted: false)]
                     && completions == [true, true, true],
                     "a drag through zero and back up drains once, unmuted at the level it ends on")

        mixer = make()
        completions = []
        mixer.requestOutputAdjustment(volume: 0, muted: false) { completions.append($0) }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: false)]
                     && mixer.systemOutputMuted == false && completions == [true],
                     "an explicit mute request wins over the one a level of zero implies")

        // The menu bar panel's slider outside the island and the command
        // bar's volume write the level and the switch directly.
        mixer = make()
        suite.expect(mixer.setCurrentOutputVolume(0)
                     && Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                            .init(device: 1, volume: nil, muted: true)]
                     && mixer.systemOutputVolume == 0 && mixer.systemOutputMuted == true,
                     "the panel's slider at zero mutes the output and publishes it")
        Hardware.writes = []
        suite.expect(mixer.setCurrentOutputVolume(0.3)
                     && Hardware.writes == [.init(device: 1, volume: 0.3, muted: nil),
                                            .init(device: 1, volume: nil, muted: false)]
                     && mixer.systemOutputMuted == false,
                     "the panel's slider above zero unmutes the output")

        mixer = make()
        Hardware.muted = nil
        mixer.selectOutput(1, volume: 0.2, muted: nil)
        suite.expect(mixer.setCurrentOutputVolume(0)
                     && Hardware.writes == [.init(device: 1, volume: 0, muted: nil)]
                     && mixer.systemOutputMuted == nil,
                     "the panel's slider at zero invents no mute state for an output without a mute switch")

        mixer = make()
        suite.expect(mixer.setCurrentOutputVolume(0.004)
                     && Hardware.writes == [.init(device: 1, volume: 0.004, muted: nil),
                                            .init(device: 1, volume: nil, muted: true)]
                     && mixer.systemOutputMuted == true,
                     "the panel's slider at a level the labels show as 0% mutes the output")

        mixer = make()
        suite.expect(mixer.setCurrentOutputVolume(0.005)
                     && Hardware.writes == [.init(device: 1, volume: 0.005, muted: nil),
                                            .init(device: 1, volume: nil, muted: false)]
                     && mixer.systemOutputMuted == false,
                     "the panel's slider at the first level the labels show as 1% keeps the output audible")

        mixer = make()
        suite.expect(Mixer.setSystemOutputVolume(0)
                     && Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                            .init(device: 1, volume: nil, muted: true)],
                     "the command bar's volume 0 mutes the output")
        Hardware.writes = []
        suite.expect(Mixer.setSystemOutputVolume(0.25)
                     && Hardware.writes == [.init(device: 1, volume: 0.25, muted: nil),
                                            .init(device: 1, volume: nil, muted: false)],
                     "the command bar's volume above zero unmutes the output")
        Hardware.writes = []
        Hardware.succeeds = false
        suite.expect(!Mixer.setSystemOutputVolume(0)
                     && Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                            .init(device: 1, volume: nil, muted: true)],
                     "the command bar's volume 0 still mutes an output that refuses the level")
        Hardware.succeeds = true

        mixer = make()
        completions = []
        for _ in 0..<3 { mixer.requestOutputStep(level: step(0.1)) { completions.append($0) } }
        Hardware.device = 2
        finish(mixer)
        suite.expect(Hardware.writes.isEmpty && completions == [true, true, true] && mixer.listenerRefreshes == 1,
                     "keys piled up for an output that is no longer the default settle instead of replaying natively")

        mixer = make()
        completions = []
        for _ in 0..<3 { mixer.requestOutputStep(level: step(0.1)) { completions.append($0) } }
        Hardware.device = 2
        mixer.selectOutput(2, volume: 0.1, muted: false)
        finish(mixer)
        suite.expect(Hardware.writes.isEmpty && completions == [true, true, true],
                     "keys whose output was replaced during the read never step the output that took over")

        for oldReadFinished in [false, true] {
            mixer = make()
            completions = []
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
            if oldReadFinished { mixer.halQueue.runOne() }
            Hardware.device = 2
            Hardware.volume = 0.4
            mixer.selectOutput(2, volume: 0.4, muted: false)
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
            finish(mixer)
            suite.expect(Hardware.writes.compactMap { write in
                write.volume.map { (write.device, Int(($0 * 10).rounded())) }
            }.contains { $0 == (2, 5) } && completions == [true, true],
                         "a key on the new output survives an old read, including one awaiting its main callback")
        }

        mixer = make()
        completions = []
        Hardware.volume = nil
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(Hardware.writes.isEmpty && completions == [false],
                     "an output without software volume leaves the key to the system")

        mixer = make()
        completions = []
        for value in [Double.nan, .infinity, -.infinity] {
            mixer.requestOutputAdjustment(volume: value) { completions.append($0) }
        }
        suite.expect(completions == [false, false, false] && mixer.halQueue.jobs.isEmpty,
                     "nonfinite output requests never reach the driver")
    }
}
