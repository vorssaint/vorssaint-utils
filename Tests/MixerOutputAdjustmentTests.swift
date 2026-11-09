// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Actual mixer methods run against controlled queues and an in-memory audio
/// device. Scheduling, HAL conversion and transport are simulated; production
/// planning and confirmation methods run unchanged. No real output device,
/// volume, mute state or event tap is touched.
enum MixerOutputAdjustmentContract {
    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func asyncAfter(deadline: DispatchTime, execute work: @escaping () -> Void) { jobs.append(work) }
        func runOne() { precondition(!jobs.isEmpty); jobs.removeFirst()() }
    }
    enum DispatchQueue { static var main = Queue() }
    struct ProcessInfo {
        static let processInfo = ProcessInfo()
        var systemUptime: TimeInterval { Hardware.uptime }
    }
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
        /// The level a volume write lands on. Nil accepts the requested level.
        static var accepts: ((Float32) -> Float32)?
        /// A simulated HAL conversion, independent of whether writes are applied.
        /// Nil means identity; a closure may return nil for unavailable conversion.
        static var quantizes: ((Float32) -> Float32?)?
        static var supportsScalarConversion = true
        static var requiresQuantizedKeys = false
        static var scalarWrites = 0
        static var queries: [Float32] = []
        static var uptime: TimeInterval = 0
        static var volumeReads = 0
        static var muteReads = 0
        static var readVolume: (() -> Float32?)?
        static var readMute: (() -> Bool?)?

        static func reset() {
            device = 1
            writes = []
            succeeds = true
            afterVolumeWrite = nil
            volume = 0.2
            muted = false
            accepts = nil
            quantizes = nil
            supportsScalarConversion = true
            requiresQuantizedKeys = false
            scalarWrites = 0
            queries = []
            uptime = 0
            volumeReads = 0
            muteReads = 0
            readVolume = nil
            readMute = nil
        }
    }

    struct Panel {
        let inNotch: Bool
        let mixer: Mixer
    }
    final class NotchService {
        enum Module { case volume }
        static let shared = NotchService()
        var ownVolumeAdjustments = 0
        func noteOwnLevelAdjustment(_ module: Module) { ownVolumeAdjustments += 1 }
    }

    static func run(_ suite: TestSuite) {
        func make() -> Mixer {
            DispatchQueue.main = Queue()
            Hardware.reset()
            NotchService.shared.ownVolumeAdjustments = 0
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
        Hardware.volume = 0.02
        var zeroResult: Bool?
        mixer.requestOutputStep(level: { $0 - 0.1 }) { zeroResult = $0.handled }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && mixer.systemOutputVolume == 0 && mixer.systemOutputMuted == true && zeroResult == true,
                     "a volume key that reaches or crosses zero mutes the output")
        Hardware.volume = 0
        Hardware.muted = true
        Hardware.writes = []
        mixer.requestOutputStep(level: { $0 + 0.1 })
        finish(mixer)
        suite.expect(Hardware.writes.last?.muted == false
                     && abs((mixer.systemOutputVolume ?? -1) - 0.1) < 0.0001 && mixer.systemOutputMuted == false,
                     "the next positive volume key unmutes an output muted at zero")

        mixer = make()
        Hardware.muted = nil
        mixer.selectOutput(1, volume: 0.2, muted: nil)
        mixer.requestOutputAdjustment(volume: 0)
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil)],
                     "zero volume on an output without mute writes only the volume")

        mixer = make()
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
        mixer.requestOutputStep(level: step(0.01)) { completions.append($0.handled) }
        suite.expect(mixer.systemOutputVolume == 0.2 && Hardware.writes.isEmpty,
                     "a volume key waits for the output's own reading before stepping")
        mixer.requestOutputStep(level: step(0.01)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [3, 4]
                     && completions == [true, true],
                     "keys step from the device's level, not a stale reading from before sleep")

        for directMute in [true, false] {
            mixer = make()
            completions = []
            Hardware.volume = 0.7
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
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
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
        mixer.requestOutputAdjustment(volume: 0.35) { completions.append($0) }
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [35, 45]
                     && completions == [true, true, true],
                     "a key after a direct level change follows that level rather than the stale HAL read")

        for directMute in [true, false] {
            mixer = make()
            completions = []
            Hardware.volume = nil
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
            if directMute {
                mixer.requestOutputAdjustment(muted: true) { completions.append($0) }
            } else {
                mixer.requestOutputAdjustment(volume: 0.35) { completions.append($0) }
            }
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
            finish(mixer)
            suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() }
                            == (directMute ? [] : [35, 45])
                         && mixer.systemOutputMuted == directMute
                         && completions == (directMute ? [true, true, false] : [true, true, true]),
                         "after a direct \(directMute ? "mute" : "level"), a key uses a fresh reading or falls back when volume is unavailable")
        }

        mixer = make()
        completions = []
        Hardware.volume = 0.5
        mixer.requestOutputAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 10).rounded() } == [3, 4],
                     "a key during this app's own write continues from the level it requested")

        mixer = make()
        completions = []
        Hardware.volume = 0.4
        Hardware.muted = true
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(Hardware.writes.first?.volume.map { ($0 * 10).rounded() } == 1
                     && mixer.systemOutputMuted == false,
                     "a key on a muted output steps up from silence and unmutes")

        // An output that takes only a few levels, like USB speakers that step
        // in 3 dB: a write lands on the nearest one, so a key's step can come
        // back to the level it started from.
        let coarseLevels: [Float32] = [0, 0.05, 0.12, 0.2, 0.3, 0.45, 0.65, 1]
        func coarse(_ value: Float32) -> Float32 {
            coarseLevels.min { abs($0 - value) < abs($1 - value) }!
        }
        func press(_ mixer: Mixer, _ delta: Double, times: Int) -> [Float32?] {
            (0..<times).map { _ in
                mixer.requestOutputStep(level: step(delta))
                finish(mixer)
                return Hardware.volume
            }
        }

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 0.3
        suite.expect(press(mixer, 1.0 / 16, times: 4) == [0.45, 0.65, 1, 1],
                     "every volume-up press advances a coarse output until full volume")

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 1
        suite.expect(press(mixer, -1.0 / 16, times: 3) == [0.65, 0.45, 0.3],
                     "every volume-down press advances a coarse output, including the first press at full volume")

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 0.3
        _ = press(mixer, 1.0 / 16, times: 1)
        Hardware.volume = 0.05
        Hardware.writes = []
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 10000).rounded() } == [1200],
                     "a key steps from a level the output moved to on its own, not from a step it rounded back")

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 0.3
        _ = press(mixer, 1.0 / 16, times: 1)
        mixer.requestOutputAdjustment(volume: 0.3)
        finish(mixer)
        Hardware.writes = []
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 10000).rounded() } == [4500],
                     "a direct level change starts the next key from that level")

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 0.3
        _ = press(mixer, 1.0 / 16, times: 1)
        mixer.readSnapshot(volume: 0.3, muted: false)
        suite.expect(press(mixer, 1.0 / 16, times: 1) == [0.65],
                     "a stale snapshot cannot undo the accepted level the next key reads from the device")

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 0.3
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(press(mixer, -1.0 / 16, times: 1) == [0.3],
                     "reversing direction returns to the previous hardware level in one press")

        mixer = make()
        Hardware.accepts = { $0 }
        Hardware.volume = 0.5
        _ = press(mixer, 1.0 / 16, times: 1)
        mixer.readSnapshot(volume: 0.5625, muted: false)
        Hardware.volume = 0.5
        Hardware.writes = []
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(Hardware.writes.compactMap(\.volume) == [0.5625],
                     "a step the output took carries nothing over after another control returns it to where the key started")

        mixer = make()
        Hardware.accepts = { $0 }
        Hardware.volume = 0.5
        _ = press(mixer, 1.0 / 16, times: 1)
        mixer.requestOutputAdjustment(volume: 0.5)
        finish(mixer)
        Hardware.writes = []
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(Hardware.writes.compactMap(\.volume) == [0.5625],
                     "a level set from the menu bar before the step's own reading starts the next key from that level")

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 0.3
        Hardware.succeeds = false
        _ = press(mixer, 1.0 / 16, times: 1)
        Hardware.succeeds = true
        Hardware.writes = []
        var nextAfterRefusal: Mixer.OutputKeyResult?
        mixer.requestOutputStep(level: step(1.0 / 16)) { nextAfterRefusal = $0 }
        finish(mixer)
        suite.expect(nextAfterRefusal == .fallback && Hardware.writes.isEmpty,
                     "a refused write keeps later keys native even when the driver recovers")

        for delta in [1.0 / 16, 1.0 / 64, -1.0 / 16, -1.0 / 64] {
            for initial in coarseLevels {
                mixer = make()
                Hardware.accepts = coarse
                Hardware.requiresQuantizedKeys = true
                Hardware.quantizes = { coarse($0) }
                Hardware.volume = initial
                var accepted: Mixer.OutputKeyResult?
                mixer.requestOutputStep(level: step(delta)) { accepted = $0 }
                finish(mixer)
                let actual = Double(Hardware.volume!)
                let atLimit = delta > 0 ? initial == 1 : initial == 0
                suite.expect(accepted == .applied && (atLimit || (actual - Double(initial)) * delta > 0),
                             "one \(delta) key moves the hardware from \(initial), unless already at its endpoint")
                suite.expectClose(mixer.systemOutputVolume ?? -1, actual,
                                  "feedback shows the accepted hardware level")
                suite.expect(Hardware.writes.compactMap(\.volume).count <= 1 && Hardware.queries.count <= 11
                             && Hardware.scalarWrites == Hardware.writes.compactMap(\.volume).count,
                             "a coarse or fine key plans with bounded conversions and writes volume at most once")
            }
        }

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 0.3
        var burstLevels: [Double] = []
        for _ in 0..<3 {
            mixer.requestOutputStep(level: step(1.0 / 16)) { applied in
                suite.expect(applied == .applied, "each key in a burst completes successfully")
                burstLevels.append(mixer.systemOutputVolume ?? -1)
            }
        }
        finish(mixer)
        suite.expect(burstLevels.map { ($0 * 100).rounded() } == [45, 65, 100],
                     "queued keys each advance from the hardware level accepted by the previous key")

        mixer = make()
        Hardware.accepts = { _ in 0.3 }
        Hardware.volume = 0.3
        var ignored: Mixer.OutputKeyResult?
        mixer.requestOutputStep(level: step(1.0 / 64)) { ignored = $0 }
        finish(mixer)
        suite.expect(ignored == .unconfirmed && Hardware.writes.compactMap(\.volume).count == 1
                     && !Hardware.writes.contains { $0.muted != nil },
                     "an ignored successful write is not retried, unmuted or replayed natively")

        mixer = make()
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        Hardware.volume = 0.3
        Hardware.afterVolumeWrite = {
            Hardware.device = 2
            mixer.selectOutput(2, volume: 0.2, muted: false)
        }
        mixer.requestOutputStep(level: step(1.0 / 64))
        finish(mixer)
        suite.expect(Hardware.writes.count == 1 && Hardware.writes[0].device == 1,
                     "switching output during a rounded write stops further attempts and skips stale mute")

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
            completions.append($0.handled)
        }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && mixer.systemOutputMuted == true && completions == [true],
                     "a volume key stepping down to zero mutes the output and stays handled")
        Hardware.volume = 0
        Hardware.muted = true
        mixer.requestOutputStep(level: { NotchSupport.volumeLevel(current: $0, direction: 1, fine: false) }) {
            completions.append($0.handled)
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
            completions.append($0.handled)
        }
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0.015625, muted: nil)]
                     && mixer.systemOutputMuted == false && completions == [true],
                     "the finest key step above zero keeps the output audible")

        mixer = make()
        completions = []
        Hardware.volume = 0.0627
        mixer.requestOutputStep(level: { NotchSupport.volumeLevel(current: $0, direction: -1, fine: false) }) {
            completions.append($0.handled)
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

        // Direct slider requests use the serialized queue; the command bar
        // keeps its standalone synchronous volume API.
        mixer = make()
        mixer.requestOutputAdjustment(volume: 0)
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                            .init(device: 1, volume: nil, muted: true)]
                     && mixer.systemOutputVolume == 0 && mixer.systemOutputMuted == true,
                     "the panel's slider at zero mutes the output and publishes it")
        Hardware.writes = []
        mixer.requestOutputAdjustment(volume: 0.3)
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0.3, muted: nil),
                                            .init(device: 1, volume: nil, muted: false)]
                     && mixer.systemOutputMuted == false,
                     "the panel's slider above zero unmutes the output")

        mixer = make()
        Hardware.muted = nil
        mixer.selectOutput(1, volume: 0.2, muted: nil)
        mixer.requestOutputAdjustment(volume: 0)
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0, muted: nil)]
                     && mixer.systemOutputMuted == nil,
                     "the panel's slider at zero invents no mute state for an output without a mute switch")

        mixer = make()
        mixer.requestOutputAdjustment(volume: 0.004)
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0.004, muted: nil),
                                            .init(device: 1, volume: nil, muted: true)]
                     && mixer.systemOutputMuted == true,
                     "the panel's slider at a level the labels show as 0% mutes the output")

        mixer = make()
        mixer.requestOutputAdjustment(volume: 0.005)
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: 0.005, muted: nil),
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
        for _ in 0..<3 { mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) } }
        Hardware.device = 2
        finish(mixer)
        suite.expect(Hardware.writes.isEmpty && completions == [true, true, true] && mixer.listenerRefreshes == 1,
                     "keys piled up for an output that is no longer the default settle instead of replaying natively")

        mixer = make()
        completions = []
        for _ in 0..<3 { mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) } }
        Hardware.device = 2
        mixer.selectOutput(2, volume: 0.1, muted: false)
        finish(mixer)
        suite.expect(Hardware.writes.isEmpty && completions == [true, true, true],
                     "keys whose output was replaced during the read never step the output that took over")

        for oldReadFinished in [false, true] {
            mixer = make()
            completions = []
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
            if oldReadFinished { mixer.halQueue.runOne() }
            Hardware.device = 2
            Hardware.volume = 0.4
            mixer.selectOutput(2, volume: 0.4, muted: false)
            mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
            finish(mixer)
            suite.expect(Hardware.writes.compactMap { write in
                write.volume.map { (write.device, Int(($0 * 10).rounded())) }
            }.contains { $0 == (2, 5) } && completions == [true, true],
                         "a key on the new output survives an old read, including one awaiting its main callback")
        }

        mixer = make()
        completions = []
        Hardware.volume = nil
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(Hardware.writes.isEmpty && completions == [false],
                     "an output without software volume leaves the key to the system")

        mixer = make()
        completions = []
        Hardware.muted = true
        mixer.requestOutputMuteToggle { completions.append($0.handled) }
        suite.expect(mixer.systemOutputMuted == false && Hardware.writes.isEmpty,
                     "the mute key waits for the output's own reading before toggling")
        finish(mixer)
        suite.expect(Hardware.writes == [.init(device: 1, volume: nil, muted: false)] && completions == [true],
                     "the mute key toggles the device's state, not a stale reading from before sleep")

        mixer = make()
        completions = []
        mixer.requestOutputMuteToggle { completions.append($0.handled) }
        mixer.requestOutputMuteToggle { completions.append($0.handled) }
        finish(mixer)
        suite.expect(mixer.systemOutputMuted == false && completions == [true, true],
                     "two quick mute presses cancel out instead of both reading the same state")

        mixer = make()
        completions = []
        Hardware.muted = true
        Hardware.volume = 0.02
        mixer.requestOutputMuteToggle { completions.append($0.handled) }
        mixer.requestOutputStep(level: step(0.01)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(Hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [3]
                     && mixer.systemOutputMuted == false && completions == [true, true],
                     "a volume key right after an unmuting press steps from the level the same read fetched")

        mixer = make()
        completions = []
        Hardware.volume = nil
        mixer.requestOutputMuteToggle { completions.append($0.handled) }
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(completions.count == 2 && completions.filter { $0 }.count == 1 && mixer.systemOutputMuted == true,
                     "an output with mute but no software volume still toggles mute and leaves volume to the system")

        mixer = make()
        var replacedOutputKeys: [Mixer.OutputKeyResult] = []
        mixer.requestOutputMuteToggle { replacedOutputKeys.append($0) }
        mixer.requestOutputStep(level: step(0.1)) { replacedOutputKeys.append($0) }
        Hardware.device = 2
        finish(mixer)
        suite.expect(Hardware.writes.isEmpty && replacedOutputKeys == [.superseded, .superseded]
                     && mixer.listenerRefreshes == 1,
                     "mute and volume for a replaced output are consumed without native replay onto its replacement")

        mixer = make()
        completions = []
        mixer.requestOutputMuteToggle { completions.append($0.handled) }
        mixer.halQueue.runOne()
        Hardware.device = 2
        Hardware.volume = 0.4
        Hardware.muted = true
        mixer.selectOutput(2, volume: 0.4, muted: true)
        mixer.requestOutputMuteToggle { completions.append($0.handled) }
        mixer.requestOutputStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(Hardware.writes.contains { $0.device == 2 && $0.muted == false }
                     && Hardware.writes.contains { $0.device == 2 && $0.volume == 0.5 }
                     && completions == [true, true, true],
                     "an old mute read cannot swallow the new output's mute and volume keys")

        // Conversion describes the driver's levels; it is deliberately separate
        // from write acceptance so an ignored write cannot confirm itself.
        mixer = make()
        Hardware.volume = 0.3
        Hardware.muted = true
        Hardware.accepts = coarse
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { coarse($0) }
        var keyResult: Mixer.OutputKeyResult?
        mixer.requestOutputStep(level: step(1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && Hardware.volume == 0.05 && Hardware.muted == false,
                     "one fine key from muted nonzero volume reaches the first audible coarse level")
        suite.expect(Hardware.writes.compactMap(\.volume) == [0.05] && Hardware.scalarWrites == 1
                     && Hardware.writes.last?.muted == false,
                     "coarse unmute plans its level before the only volume write")

        mixer = make()
        Hardware.volume = 0.3
        Hardware.muted = true
        keyResult = nil
        mixer.requestOutputStep(level: step(-1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && Hardware.volume == 0.3 && Hardware.muted == true
                     && Hardware.writes.isEmpty,
                     "volume down while muted preserves the stored level without another write")

        mixer = make()
        Hardware.volume = 0.05
        let floorLevels: [Float32] = [0.05, 0.12, 0.3, 1]
        let floor: (Float32) -> Float32 = { value in
            floorLevels.min { abs($0 - value) < abs($1 - value) }!
        }
        Hardware.accepts = floor
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { floor($0) }
        keyResult = nil
        mixer.requestOutputStep(level: step(-1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && Hardware.volume == 0.05 && Hardware.muted == true
                     && !Hardware.writes.contains { $0.muted == false },
                     "reaching the bottom mutes even when the driver's minimum scalar is positive")

        mixer = make()
        Hardware.volume = 0.9
        Hardware.muted = true
        Hardware.accepts = { _ in 0.9 }
        keyResult = nil
        mixer.requestOutputStep(level: step(1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .unconfirmed && Hardware.muted == true
                     && Hardware.writes.compactMap(\.volume).count == 1
                     && !Hardware.writes.contains { $0.muted != nil },
                     "an ignored fine key never unmutes at the old high stored volume")
        suite.expectClose(mixer.systemOutputVolume ?? -1, 0.9,
                          "an unconfirmed key leaves no optimistic target in the published volume")

        for missingControl in [true, false] {
            mixer = make()
            Hardware.requiresQuantizedKeys = true
            Hardware.supportsScalarConversion = !missingControl
            if !missingControl { Hardware.quantizes = { _ in nil } }
            keyResult = nil
            mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
            finish(mixer)
            suite.expect(keyResult == .fallback && Hardware.writes.isEmpty,
                         "missing scalar control or conversion returns the key before writing")
        }

        mixer = make()
        Hardware.supportsScalarConversion = false
        Hardware.quantizes = { _ in nil }
        keyResult = nil
        mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && Hardware.queries.isEmpty && Hardware.scalarWrites == 0
                     && Hardware.writes.compactMap(\.volume).count == 1,
                     "ordinary outputs keep native virtual-volume control without a USB conversion")

        for delta in [1.0 / 16, -1.0 / 16] {
            mixer = make()
            Hardware.accepts = { ($0 * 100).rounded() / 100 }
            keyResult = nil
            mixer.requestOutputStep(level: step(delta)) { keyResult = $0 }
            finish(mixer)
            suite.expect(keyResult == .applied && Hardware.scalarWrites == 0
                         && Hardware.writes.compactMap(\.volume).count == 1 && Hardware.queries.isEmpty,
                         "ordinary outputs confirm a rounded readback without USB conversion or another write")
            suite.expectClose(mixer.systemOutputVolume ?? -1, delta > 0 ? 0.26 : 0.14,
                              "ordinary output feedback publishes the accepted rounded level")
        }

        mixer = make()
        Hardware.volume = 0.5
        Hardware.muted = true
        Hardware.accepts = { ($0 * 100).rounded() / 100 }
        keyResult = nil
        mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && Hardware.volume == 0.06 && Hardware.muted == false
                     && Hardware.writes.compactMap(\.volume) == [0.0625],
                     "an ordinary output may unmute after confirming a nearby rounded low level")
        suite.expectClose(mixer.systemOutputVolume ?? -1, 0.06,
                          "rounded unmute feedback uses the hardware level")

        mixer = make()
        Hardware.requiresQuantizedKeys = true
        keyResult = nil
        mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .fallback && Hardware.writes.isEmpty,
                     "a continuous USB conversion is not treated as evidence of hardware quantization")

        for replacement in [AudioObjectID(1), AudioObjectID(2)] {
            mixer = make()
            Hardware.requiresQuantizedKeys = true
            var keyResults: [Mixer.OutputKeyResult] = []
            mixer.requestOutputStep(level: step(1.0 / 16)) { keyResults.append($0) }
            mixer.requestOutputMuteToggle { keyResults.append($0) }
            finish(mixer)
            suite.expect(keyResults == [.fallback, .fallback] && Hardware.writes.isEmpty,
                         "mute follows a continuous USB volume key into native handling instead of overtaking it")

            Hardware.device = replacement
            Hardware.volume = 0.4
            Hardware.requiresQuantizedKeys = false
            mixer.selectOutput(replacement, volume: 0.4, muted: false)
            keyResults = []
            mixer.requestOutputStep(level: step(0.1)) { keyResults.append($0) }
            mixer.requestOutputMuteToggle { keyResults.append($0) }
            finish(mixer)
            suite.expect(keyResults == [.applied, .applied] && Hardware.volume == 0.5
                         && Hardware.muted == true && Hardware.writes.allSatisfy { $0.device == replacement },
                         "a new output lifetime clears native-only key handling, including a reused device ID")
        }

        mixer = make()
        Hardware.succeeds = false
        var keysAfterWriteFailure: [Mixer.OutputKeyResult] = []
        mixer.requestOutputStep(level: step(0.1)) {
            keysAfterWriteFailure.append($0)
            Hardware.succeeds = true
        }
        mixer.requestOutputMuteToggle { keysAfterWriteFailure.append($0) }
        finish(mixer)
        suite.expect(keysAfterWriteFailure == [.fallback, .fallback]
                     && Hardware.writes.count == 1 && Hardware.writes[0].volume != nil
                     && Hardware.writes[0].muted == nil && Hardware.muted == false,
                     "mute stays native after a failed volume write even when the driver recovers before the next key")

        mixer = make()
        var validAfterInvalid: [Mixer.OutputKeyResult] = []
        mixer.requestOutputStep(level: { _ in .nan }) { validAfterInvalid.append($0) }
        mixer.requestOutputStep(level: step(0.1)) { validAfterInvalid.append($0) }
        finish(mixer)
        suite.expect(validAfterInvalid == [.fallback, .applied]
                     && Hardware.writes.compactMap(\.volume).count == 1,
                     "an invalid key target does not strand the next valid key in the queue")
        suite.expectClose(mixer.systemOutputVolume ?? -1, 0.3,
                          "the valid key after an invalid target still publishes its accepted level")

        for invalid in [Float32.nan, .infinity, -0.1, 1.1] {
            mixer = make()
            Hardware.requiresQuantizedKeys = true
            Hardware.quantizes = { _ in invalid }
            keyResult = nil
            mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
            finish(mixer)
            suite.expect(keyResult == .fallback && Hardware.writes.isEmpty,
                         "an invalid converted scalar never reaches the output")
        }

        mixer = make()
        Hardware.volume = 0.3
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { $0 <= 0.4 ? 0.3 : 0.2 }
        keyResult = nil
        mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .fallback && Hardware.writes.isEmpty && Hardware.queries.count <= 11,
                     "a conversion that reverses direction cannot authorize a volume write")

        mixer = make()
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = {
            if abs($0 - 0.2) < 0.002 { return 0.2 }
            if abs($0 - 0.3) < 0.0001 { return 0.4 }
            return 0.3
        }
        keyResult = nil
        mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .fallback && Hardware.writes.isEmpty,
                     "a conversion that cannot represent its own predicted level is rejected")

        mixer = make()
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { value in Hardware.uptime += 0.06; return value }
        keyResult = nil
        mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .fallback && Hardware.queries.count == 1 && Hardware.writes.isEmpty,
                     "a conversion that exhausts the time budget starts no further query or write")

        mixer = make()
        var missingReads = 0
        Hardware.afterVolumeWrite = {
            Hardware.readVolume = { missingReads += 1; return nil }
        }
        keyResult = nil
        mixer.requestOutputStep(level: step(0.1)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .unconfirmed && missingReads > 0 && missingReads <= 4
                     && Hardware.writes.compactMap(\.volume).count == 1
                     && !Hardware.writes.contains { $0.muted != nil },
                     "missing readback uses bounded reads without another write, mute or native fallback")
        suite.expectClose(mixer.systemOutputVolume ?? -1, 0.2,
                          "missing readback does not publish the requested key target")

        mixer = make()
        Hardware.afterVolumeWrite = { Hardware.readVolume = { 0.2 } }
        var keysAfterTimeout: [Mixer.OutputKeyResult] = []
        mixer.requestOutputStep(level: step(0.1)) {
            keysAfterTimeout.append($0)
            Hardware.readVolume = nil
        }
        mixer.requestOutputStep(level: step(0.1)) { keysAfterTimeout.append($0) }
        mixer.requestOutputMuteToggle { keysAfterTimeout.append($0) }
        finish(mixer)
        suite.expect(keysAfterTimeout == [.unconfirmed, .fallback, .fallback]
                     && Hardware.writes.count == 1 && Hardware.writes[0].volume != nil
                     && Hardware.writes[0].muted == nil,
                     "an accepted write that times out is not replayed and later volume and mute keys stay native")

        mixer = make()
        var delayedReads = 0
        Hardware.afterVolumeWrite = {
            Hardware.readVolume = {
                delayedReads += 1
                return delayedReads < 3 ? 0.2 : Hardware.volume
            }
        }
        keyResult = nil
        mixer.requestOutputStep(level: step(0.1)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && delayedReads == 3
                     && Hardware.writes.compactMap(\.volume).count == 1,
                     "delayed volume confirmation rechecks the original write instead of advancing it")
        suite.expectClose(mixer.systemOutputVolume ?? -1, 0.3,
                          "a delayed key publishes only the level confirmed by the driver")

        mixer = make()
        var delayedMuteReads = 0
        Hardware.readMute = {
            guard Hardware.writes.contains(where: { $0.muted != nil }) else { return Hardware.muted }
            delayedMuteReads += 1
            return delayedMuteReads < 3 ? false : Hardware.muted
        }
        keyResult = nil
        mixer.requestOutputMuteToggle { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && delayedMuteReads == 3
                     && Hardware.writes == [.init(device: 1, volume: nil, muted: true)]
                     && mixer.systemOutputMuted == true,
                     "a delayed mute confirmation never repeats the toggle")

        mixer = make()
        Hardware.afterVolumeWrite = { Hardware.device = 2 }
        keyResult = nil
        mixer.requestOutputStep(level: step(1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .superseded && Hardware.writes.count == 1
                     && Hardware.writes[0].device == 1 && mixer.listenerRefreshes > 0,
                     "a default change before listener delivery consumes the old key without stale mute or fallback")

        mixer = make()
        keyResult = nil
        mixer.requestOutputStep(level: step(0.1)) { keyResult = $0 }
        mixer.halQueue.runOne()
        DispatchQueue.main.runOne()
        Hardware.device = 2
        finish(mixer)
        suite.expect(keyResult == .superseded && Hardware.writes.isEmpty,
                     "a default change between the fresh read and write never adjusts the replacement")

        mixer = make()
        var sliderReadbacks = 0
        Hardware.afterVolumeWrite = {
            Hardware.readVolume = {
                sliderReadbacks += 1
                return sliderReadbacks < 3 ? 0.2 : Hardware.volume
            }
        }
        keyResult = nil
        mixer.requestOutputAdjustment(volume: 0.8)
        mixer.requestOutputStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied
                     && Hardware.writes.compactMap(\.volume).map { ($0 * 10000).rounded() } == [8000, 8625],
                     "a key behind an asynchronous slider waits for its accepted level instead of stepping the old reading")
        suite.expectClose(mixer.systemOutputVolume ?? -1, 0.8625,
                          "feedback follows the slider's confirmed level plus the queued key")

        mixer = make()
        Hardware.accepts = { _ in 0.2 }
        var keysBehindUnconfirmedSlider: [Mixer.OutputKeyResult] = []
        var keysAtSliderCompletion: [Mixer.OutputKeyResult] = []
        mixer.requestOutputAdjustment(volume: 0.8) { _ in
            keysAtSliderCompletion = keysBehindUnconfirmedSlider
            mixer.requestOutputStep(level: step(1.0 / 16)) { keysBehindUnconfirmedSlider.append($0) }
        }
        mixer.requestOutputStep(level: step(1.0 / 16)) { keysBehindUnconfirmedSlider.append($0) }
        mixer.requestOutputMuteToggle { keysBehindUnconfirmedSlider.append($0) }
        finish(mixer)
        suite.expect(keysBehindUnconfirmedSlider == [.unconfirmed, .unconfirmed, .fallback]
                     && keysAtSliderCompletion == [.unconfirmed, .unconfirmed]
                     && Hardware.writes.compactMap(\.volume) == [0.8],
                     "a slider timeout consumes old keys before its callback, whose new key goes native without replaying the old ones")
        let writesAtSliderTimeout = Hardware.writes
        mixer.requestOutputStep(level: step(1.0 / 16)) { keysBehindUnconfirmedSlider.append($0) }
        mixer.requestOutputMuteToggle { keysBehindUnconfirmedSlider.append($0) }
        finish(mixer)
        suite.expect(keysBehindUnconfirmedSlider == [.unconfirmed, .unconfirmed, .fallback, .fallback, .fallback]
                     && Hardware.writes == writesAtSliderTimeout,
                     "new volume and mute presses after a slider timeout use native handling without more HAL writes")
        Hardware.volume = 0.45
        Hardware.accepts = nil
        mixer.requestOutputStep(level: step(1.0 / 16)) { keysBehindUnconfirmedSlider.append($0) }
        finish(mixer)
        suite.expect(keysBehindUnconfirmedSlider == [.unconfirmed, .unconfirmed, .fallback, .fallback, .fallback, .fallback]
                     && Hardware.writes == writesAtSliderTimeout && Hardware.volume == 0.45,
                     "an external volume change needs no stale slider acknowledgement before a new native key")

        for inNotch in [false, true] {
            mixer = make()
            let panel = Panel(inNotch: inNotch, mixer: mixer)
            keyResult = nil
            mixer.requestOutputStep(level: step(0.1)) { keyResult = $0 }
            panel.setSystemOutputVolume(0.7)
            suite.expect(mixer.systemOutputVolume == 0.7 && Hardware.writes.isEmpty,
                         "the real panel slider publishes immediately while its write waits on the queue")
            finish(mixer)
            suite.expect(keyResult == .superseded
                         && Hardware.writes.compactMap(\.volume) == [0.7]
                         && NotchService.shared.ownVolumeAdjustments == (inNotch ? 1 : 0),
                         "the real \(inNotch ? "notch" : "menu bar") panel slider supersedes an older key")
            suite.expectClose(mixer.systemOutputVolume ?? -1, 0.7,
                              "the real panel slider keeps its final value after the old key settles")
        }

        mixer = make()
        var directResult: Bool?
        var publishedWhenSuperseded: Double?
        Hardware.afterVolumeWrite = {
            mixer.requestOutputAdjustment(volume: 0.7) { directResult = $0 }
        }
        keyResult = nil
        mixer.requestOutputStep(level: step(0.1)) {
            keyResult = $0
            publishedWhenSuperseded = mixer.systemOutputVolume
        }
        finish(mixer)
        suite.expect(keyResult == .superseded && directResult == true
                     && Hardware.writes.compactMap(\.volume).map { ($0 * 10).rounded() } == [3, 7],
                     "a newer direct slider supersedes key confirmation and retains its own write")
        suite.expectClose(publishedWhenSuperseded ?? -1, 0.7,
                          "the old key callback cannot overwrite a newer optimistic slider level")
        suite.expectClose(mixer.systemOutputVolume ?? -1, 0.7,
                          "the direct slider remains published after the old key completes")

        mixer = make()
        var replacedBurst: [Mixer.OutputKeyResult] = []
        Hardware.afterVolumeWrite = { Hardware.device = 2 }
        for _ in 0..<3 {
            mixer.requestOutputStep(level: step(1.0 / 16)) { replacedBurst.append($0) }
        }
        finish(mixer)
        suite.expect(replacedBurst == [.superseded, .superseded, .superseded]
                     && Hardware.writes.compactMap(\.volume).count == 1,
                     "a default change before its listener settles the old burst without replay or stranded keys")
        Hardware.device = 1
        var afterReturn: Mixer.OutputKeyResult?
        mixer.requestOutputStep(level: step(1.0 / 16)) { afterReturn = $0 }
        finish(mixer)
        suite.expect(afterReturn == .applied,
                     "returning to the same default before resubscription does not keep an old burst stuck")

        mixer = make()
        completions = []
        for value in [Double.nan, .infinity, -.infinity] {
            mixer.requestOutputAdjustment(volume: value) { completions.append($0) }
        }
        suite.expect(completions == [false, false, false] && mixer.halQueue.jobs.isEmpty,
                     "nonfinite output requests never reach the driver")
    }
}
