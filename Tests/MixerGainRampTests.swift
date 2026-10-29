// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// A volume change used to reach the audio as one constant gain per block, so
/// every slider or fader event stepped the waveform at a block edge and a drag
/// sounded like a zipper. These checks drive `MixerRender` the way an engine's
/// IO proc does, block after block through one `AppliedGain`, and read what
/// lands in the output buffers.
enum MixerGainRampContract {
    static func run(_ suite: TestSuite) {
        slidesFromTheLastGain(suite)
        steadyGainIsUntouched(suite)
        bothSidesStayEqual(suite)
        slidesToAndFromSilence(suite)
        slidesAroundBlocksThatWroteLittle(suite)
        spoilsOnlyItsOwnBlock(suite)
    }

    // MARK: Checks

    /// A constant source makes the output the gain itself, so the slide can
    /// be read sample by sample. The block after a slide is read on its own
    /// run, from 0.9801 to 1: that step is not a power of two, so vDSP ends
    /// the ramp a hair away from 1, and only a state that kept the gain it
    /// was given, not that end, lets the next block take the constant path.
    private static func slidesFromTheLastGain(_ suite: TestSuite) {
        let source = [Float](repeating: 1, count: 3 * 512 * 2)
        let gains: [Float] = [1, 0.5, 0.5]
        let landing: [Float] = [0.9801, 1, 1]
        let steady = [Float](repeating: 1, count: 512)
        let share: Double = 0.5 / 512
        let slack: Double = 1 + 1e-3
        let stepBound: Double = share * slack
        let shapes: [(name: String, outputs: [UInt32])] = [("stereo", [2]), ("mono", [1]), ("split", [1, 1])]
        for shape in shapes {
            let slid = leftChannel(source, outputs: shape.outputs, gains: gains, sliding: true)
            let stepped = leftChannel(source, outputs: shape.outputs, gains: gains, sliding: false)
            let landed = leftChannel(source, outputs: shape.outputs, gains: landing, sliding: true)
            let startsFromLast: Bool = slid[512] == 1
            let stepsOneAtATime: Bool = maxStep(slid) <= stepBound
            let goesOneWay: Bool = neverRises(slid)
            let afterSlide: Bool = Array(landed[1024..<1536]) == steady
            let jumpsWhole: Bool = maxStep(stepped) >= 0.5
            suite.expect(startsFromLast,
                         "\(shape.name): a changed gain starts from the gain the last block ended on")
            suite.expect(stepsOneAtATime,
                         "\(shape.name): a changed gain slides one sample step at a time")
            suite.expect(goesOneWay, "\(shape.name): the slide keeps going one way")
            suite.expect(afterSlide,
                         "\(shape.name): the block after a slide holds the new gain from its first sample")
            suite.expect(jumpsWhole,
                         "\(shape.name): a gain stepped once per block jumps by the whole change")
        }
    }

    /// An engine that never changes its gain, and the first block of one that
    /// has just started, play the samples the constant path always played.
    private static func steadyGainIsUntouched(_ suite: TestSuite) {
        let source = wave(frames: 3 * 512, channels: 2, hertz: 440, amplitude: 0.5)
        let shapes: [(name: String, outputs: [UInt32])] = [("stereo", [2]), ("mono", [1]), ("split", [1, 1])]
        for shape in shapes {
            let firstSliding = blocks(source, sourceChannels: 2, blockFrames: 512, outputs: shape.outputs,
                                      gains: [0.7], sliding: true)
            let firstStepped = blocks(source, sourceChannels: 2, blockFrames: 512, outputs: shape.outputs,
                                      gains: [0.7], sliding: false)
            let steadySliding = blocks(source, sourceChannels: 2, blockFrames: 512, outputs: shape.outputs,
                                       gains: [0.5, 0.5, 0.5], sliding: true)
            let steadyStepped = blocks(source, sourceChannels: 2, blockFrames: 512, outputs: shape.outputs,
                                       gains: [0.5, 0.5, 0.5], sliding: false)
            let firstSame: Bool = firstSliding == firstStepped
            let steadySame: Bool = steadySliding == steadyStepped
            suite.expect(firstSame, "\(shape.name): a new engine's first block plays its gain as it is")
            suite.expect(steadySame, "\(shape.name): a steady gain plays the samples it played before")
        }
    }

    /// A centred sound stays centred while its gain slides: the two sides of
    /// a left-equals-right tone start from the same gain and move together,
    /// whatever shape the device asks for.
    private static func bothSidesStayEqual(_ suite: TestSuite) {
        let tone = wave(frames: 3 * 512, channels: 2, hertz: 440, amplitude: 0.5)
        let shapes: [(name: String, outputs: [UInt32])] = [("stereo", [2]), ("split", [1, 1]), ("surround", [4])]
        let gains: [Float] = [1, 0.9801, 0.5]
        for shape in shapes {
            let buffers = blocks(tone, sourceChannels: 2, blockFrames: 512,
                                 outputs: shape.outputs, gains: gains, sliding: true)
            var width = 0
            for count in shape.outputs { width += Int(count) }
            let left = channel(buffers, outputs: shape.outputs, index: 0)
            let right = channel(buffers, outputs: shape.outputs, index: 1)
            var restSilent = true
            if width > 2 {
                for index in 2..<width {
                    let rest = channel(buffers, outputs: shape.outputs, index: index)
                    restSilent = restSilent && rest.allSatisfy { $0 == 0 }
                }
            }
            let playing: Bool = left.contains { $0 != 0 }
            let bothSidesEqual: Bool = playing && left == right && restSilent
            suite.expect(bothSidesEqual, "\(shape.name): both sides of a sliding gain stay equal")
        }
    }

    /// Silence is a gain like any other: going to it fades over the block and
    /// coming from it fades in.
    private static func slidesToAndFromSilence(_ suite: TestSuite) {
        let source = [Float](repeating: 1, count: 3 * 512 * 2)
        let down = leftChannel(source, outputs: [2], gains: [1, 0, 0], sliding: true)
        let downStepped = leftChannel(source, outputs: [2], gains: [1, 0, 0], sliding: false)
        let up = leftChannel(source, outputs: [2], gains: [0, 1, 1], sliding: true)
        let upStepped = leftChannel(source, outputs: [2], gains: [0, 1, 1], sliding: false)
        let lastDown: Float = 1.0 / 512
        let lastUp: Float = 511.0 / 512
        let fadesOut: Bool = down[512] == 1 && down[1023] == lastDown
        let silentAfter: Bool = Array(down[1024..<1536]) == Array(downStepped[1024..<1536])
        let fadesIn: Bool = up[512] == 0 && up[1023] == lastUp
        let playsAfter: Bool = Array(up[1024..<1536]) == Array(upStepped[1024..<1536])
        suite.expect(fadesOut, "a slide to silence fades over one block")
        suite.expect(silentAfter, "after a slide to silence the next block is silent")
        suite.expect(fadesIn, "a slide from silence fades in over one block")
        suite.expect(playsAfter, "after a slide from silence the next block plays its gain")
    }

    /// The slide follows what was actually written: a block that wrote
    /// nothing moves nothing, and an output shorter than the source slides
    /// over the frames it has.
    private static func slidesAroundBlocksThatWroteLittle(_ suite: TestSuite) {
        let source = [Float](repeating: 1, count: 3 * 512 * 2)

        let applied = MixerRender.AppliedGain()
        let head = Array(source[0..<1024])
        _ = renderBlock(source: head, sourceChannels: 2, outputs: [2], outputFrames: 512,
                        gain: 1, applied: applied)
        let skipped = renderBlock(source: head, sourceChannels: 2, outputs: [2], outputFrames: 512,
                                  gain: 0.5, applied: applied, writable: false)
        let third = renderBlock(source: head, sourceChannels: 2, outputs: [2], outputFrames: 512,
                                gain: 0.5, applied: applied)
        let thirdLeft = channel(third.buffers, outputs: [2], index: 0)
        let wroteNothing: Bool = skipped.written == 0
        let resumed: Bool = wroteNothing && thirdLeft[0] == 1
        suite.expect(resumed, "a block that wrote nothing leaves the slide where it was")

        let shortApplied = MixerRender.AppliedGain()
        var shortBlocks: [(buffers: [[Float]], written: Int)] = []
        for gain: Float in [1, 0.5, 0.5] {
            shortBlocks.append(renderBlock(source: head, sourceChannels: 2, outputs: [2], outputFrames: 256,
                                           gain: gain, applied: shortApplied))
        }
        let secondLeft = channel(shortBlocks[1].buffers, outputs: [2], index: 0)
        let thirdShort = channel(shortBlocks[2].buffers, outputs: [2], index: 0)
        let wroteAll: Bool = shortBlocks[1].written == 256
        let reachesEnd: Bool = secondLeft[255] == 0.501953125
        let landsNext: Bool = thirdShort[0] == 0.5
        let shortOK: Bool = wroteAll && reachesEnd && landsNext
        suite.expect(shortOK, "a slide over a short output reaches the new gain on the next block")
    }

    /// A gain that is not a number plays as it always did, and the engine
    /// forgets it: the block before and the block after are untouched.
    private static func spoilsOnlyItsOwnBlock(_ suite: TestSuite) {
        let nanOK = spoilsOnlyItself(gain: Float.nan)
        suite.expect(nanOK, "a gain that is not a number spoils only its own block")
    }

    // MARK: Measures

    private static func spoilsOnlyItself(gain bad: Float) -> Bool {
        let source = [Float](repeating: 1, count: 3 * 512 * 2)
        let gains: [Float] = [1, bad, 0.5]
        let slid = blocks(source, sourceChannels: 2, blockFrames: 512, outputs: [2],
                          gains: gains, sliding: true)[0]
        let stepped = blocks(source, sourceChannels: 2, blockFrames: 512, outputs: [2],
                             gains: gains, sliding: false)[0]
        let width = 512 * 2
        let firstSame: Bool = Array(slid[0..<width]) == Array(stepped[0..<width])
        let lastBlock: Range<Int> = (2 * width)..<(3 * width)
        let lastSame: Bool = Array(slid[lastBlock]) == Array(stepped[lastBlock])
        let lastFinite: Bool = slid[lastBlock].allSatisfy { $0.isFinite }
        return firstSame && lastSame && lastFinite
    }

    /// The biggest jump between neighbouring samples.
    private static func maxStep(_ samples: [Float]) -> Double {
        var worst: Double = 0
        for index in 1..<samples.count {
            let jump: Double = abs(Double(samples[index]) - Double(samples[index - 1]))
            worst = max(worst, jump)
        }
        return worst
    }

    private static func neverRises(_ samples: [Float]) -> Bool {
        for index in 1..<samples.count where samples[index] > samples[index - 1] { return false }
        return true
    }

    /// An interleaved wave, the same on every channel.
    private static func wave(frames: Int, channels: Int, hertz: Double, amplitude: Double) -> [Float] {
        let twoPi: Double = 2.0 * Double.pi
        let perFrame: Double = twoPi * hertz / 48000.0
        var samples: [Float] = []
        samples.reserveCapacity(frames * channels)
        for frame in 0..<frames {
            let angle: Double = perFrame * Double(frame)
            let sample = Float(amplitude * sin(angle))
            for _ in 0..<channels { samples.append(sample) }
        }
        return samples
    }

    /// The first output channel of a run of blocks.
    private static func leftChannel(_ source: [Float], outputs: [UInt32], gains: [Float],
                                    sliding: Bool) -> [Float] {
        let buffers = blocks(source, sourceChannels: 2, blockFrames: 512, outputs: outputs,
                             gains: gains, sliding: sliding)
        return channel(buffers, outputs: outputs, index: 0)
    }

    /// One channel of the concatenated output buffers, counted across buffers
    /// in the order the device lists them.
    private static func channel(_ buffers: [[Float]], outputs: [UInt32], index: Int) -> [Float] {
        var first = 0
        for (position, count) in outputs.enumerated() {
            let width = Int(count)
            if index < first + width {
                let samples = buffers[position]
                var picked: [Float] = []
                picked.reserveCapacity(samples.count / width)
                var cursor = index - first
                while cursor < samples.count {
                    picked.append(samples[cursor])
                    cursor += width
                }
                return picked
            }
            first += width
        }
        return []
    }

    /// Renders `gains.count` blocks one after the other. Block `b` reads the
    /// source frames `[b * blockFrames, (b + 1) * blockFrames)`. With
    /// `sliding` the blocks share one `AppliedGain`, as one engine's blocks
    /// do; without it each block is the constant-gain render of before.
    /// Answers the blocks of each output buffer, joined.
    private static func blocks(_ source: [Float], sourceChannels: UInt32, blockFrames: Int,
                               outputs: [UInt32], gains: [Float], sliding: Bool) -> [[Float]] {
        let applied = MixerRender.AppliedGain()
        let perBlock = blockFrames * Int(sourceChannels)
        var joined: [[Float]] = outputs.map { _ in [] }
        for (block, gain) in gains.enumerated() {
            let lower = block * perBlock
            let rendered = renderBlock(source: Array(source[lower..<(lower + perBlock)]),
                                       sourceChannels: sourceChannels, outputs: outputs,
                                       outputFrames: blockFrames, gain: gain,
                                       applied: sliding ? applied : nil)
            for index in outputs.indices { joined[index].append(contentsOf: rendered.buffers[index]) }
        }
        return joined
    }

    /// Runs one render over freshly allocated buffers filled with a marker
    /// value, and answers what each output buffer received and how many
    /// frames the render says it wrote. `writable: false` hands over buffers
    /// with no memory behind them.
    private static func renderBlock(source: [Float], sourceChannels: UInt32, outputs: [UInt32],
                                    outputFrames: Int, gain: Float, applied: MixerRender.AppliedGain?,
                                    writable: Bool = true) -> (buffers: [[Float]], written: Int) {
        let sourceStorage = UnsafeMutablePointer<Float>.allocate(capacity: max(source.count, 1))
        sourceStorage.update(from: source, count: source.count)
        var storages: [UnsafeMutablePointer<Float>] = []
        let list = AudioBufferList.allocate(maximumBuffers: max(outputs.count, 1))
        for (index, channels) in outputs.enumerated() {
            let samples = outputFrames * Int(channels)
            let storage = UnsafeMutablePointer<Float>.allocate(capacity: max(samples, 1))
            storage.update(repeating: -99, count: max(samples, 1))
            storages.append(storage)
            list[index] = AudioBuffer(
                mNumberChannels: channels,
                mDataByteSize: UInt32(samples * MemoryLayout<Float>.size),
                mData: writable ? UnsafeMutableRawPointer(storage) : nil)
        }
        let buffer = AudioBuffer(
            mNumberChannels: sourceChannels,
            mDataByteSize: UInt32(source.count * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(sourceStorage))
        let written: Int
        if let applied {
            written = MixerRender.render(source: buffer, into: list, gain: gain, rampingFrom: applied)
        } else {
            written = MixerRender.render(source: buffer, into: list, gain: gain)
        }
        var results: [[Float]] = []
        for (index, channels) in outputs.enumerated() {
            let samples = outputFrames * Int(channels)
            results.append(Array(UnsafeBufferPointer(start: storages[index], count: samples)))
        }
        storages.forEach { $0.deallocate() }
        sourceStorage.deallocate()
        free(list.unsafeMutablePointer)
        return (results, written)
    }
}
