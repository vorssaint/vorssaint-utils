// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

enum MixerRenderTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Mixer render (issue #397)

        // The tap always hands over two interleaved channels; the device on
        // the other side does not have to match. Pouring stereo into a
        // headset's single channel used to copy every sample straight across,
        // which plays the audio an octave low and half as long.

        /// Runs `render` over freshly allocated buffers and hands back what
        /// each output buffer received, plus the frame count it reported.
        var renderedFrames = 0
        func rendered(source: [Float], sourceChannels: UInt32,
                      outputs: [(channels: UInt32, frames: Int)],
                      gain: Float = 1) -> [[Float]] {
            let sourceStorage = UnsafeMutablePointer<Float>.allocate(capacity: max(source.count, 1))
            sourceStorage.update(from: source, count: source.count)
            var storages: [UnsafeMutablePointer<Float>] = []
            let list = AudioBufferList.allocate(maximumBuffers: max(outputs.count, 1))
            for (index, output) in outputs.enumerated() {
                let count = max(output.frames * Int(output.channels), 1)
                let storage = UnsafeMutablePointer<Float>.allocate(capacity: count)
                storage.update(repeating: -99, count: count)
                storages.append(storage)
                list[index] = AudioBuffer(
                    mNumberChannels: output.channels,
                    mDataByteSize: UInt32(output.frames * Int(output.channels) * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(storage))
            }
            let buffer = AudioBuffer(
                mNumberChannels: sourceChannels,
                mDataByteSize: UInt32(source.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(sourceStorage))
            renderedFrames = MixerRender.render(source: buffer, into: list, gain: gain)
            var results: [[Float]] = []
            for (index, output) in outputs.enumerated() {
                let count = output.frames * Int(output.channels)
                results.append(Array(UnsafeBufferPointer(start: storages[index], count: count)))
            }
            storages.forEach { $0.deallocate() }
            sourceStorage.deallocate()
            free(list.unsafeMutablePointer)
            return results
        }

        /// Positive-going zero crossings, the cheap way to hear speed change.
        func crossings(_ samples: [Float], channels: Int) -> Int {
            var count = 0
            var previous: Float = 0
            for frame in 0..<(samples.count / channels) {
                let value = samples[frame * channels]
                if previous <= 0, value > 0 { count += 1 }
                previous = value
            }
            return count
        }

        expect(MixerRender.frames(bytes: 4096, channels: 2) == 512,
               "a stereo buffer of 4096 bytes carries 512 frames")
        expect(MixerRender.frames(bytes: 2048, channels: 1) == 512,
               "a mono buffer of 2048 bytes carries the same 512 frames")
        expect(MixerRender.frames(bytes: 4096, channels: 0) == 0,
               "a buffer with no channels carries nothing")
        let missingOutputSource = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        missingOutputSource.initialize(repeating: 0.5, count: 2)
        let missingOutputList = AudioBufferList.allocate(maximumBuffers: 1)
        missingOutputList[0] = AudioBuffer(mNumberChannels: 2,
                                           mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                           mData: nil)
        let missingOutputFrames = MixerRender.render(
            source: AudioBuffer(mNumberChannels: 2,
                                mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                mData: missingOutputSource),
            into: missingOutputList,
            gain: 1)
        expect(missingOutputFrames == 0,
               "mixer progress advances only when a destination received audio")
        missingOutputSource.deallocate()
        free(missingOutputList.unsafeMutablePointer)

        let unmappedOutputSource = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        unmappedOutputSource.initialize(repeating: 0.5, count: 2)
        let unmappedOutputDestination = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        unmappedOutputDestination.initialize(to: -99)
        let unmappedOutputList = AudioBufferList.allocate(maximumBuffers: 2)
        unmappedOutputList[0] = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
            mData: nil)
        unmappedOutputList[1] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(MemoryLayout<Float>.size),
            mData: unmappedOutputDestination)
        let unmappedOutputFrames = MixerRender.render(
            source: AudioBuffer(mNumberChannels: 2,
                                mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                mData: unmappedOutputSource),
            into: unmappedOutputList,
            gain: 1)
        expect(unmappedOutputFrames == 0 && unmappedOutputDestination.pointee == 0,
               "a writable channel that can only receive silence does not advance mixer progress")
        unmappedOutputSource.deallocate()
        unmappedOutputDestination.deallocate()
        free(unmappedOutputList.unsafeMutablePointer)

        // MARK: Unwritten output frames (issue #326)

        // The output buffer arrives holding whatever CoreAudio last left in
        // that memory. A tap shorter than the buffer used to fill the front
        // and leave the rest, and a cycle that found no tap left the whole
        // buffer, so the device played back a fragment of older audio.
        let shortTap = rendered(source: [0.5, 0.5, 0.5, 0.5], sourceChannels: 2,
                                outputs: [(channels: 2, frames: 4)])[0]
        expect(renderedFrames == 2,
               "a tap shorter than the output writes only the frames it has")
        expect(shortTap == [0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0],
               "the frames the tap could not fill are silenced, not left as the device found them")
        let splitTail = rendered(source: [0.5, 0.5], sourceChannels: 2,
                                 outputs: [(channels: 1, frames: 3), (channels: 1, frames: 3)])
        expect(splitTail[0] == [0.5, 0, 0] && splitTail[1] == [0.5, 0, 0],
               "every buffer of a split output is silenced past the frames the tap filled")
        let staleOutput = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        staleOutput.update(repeating: -99, count: 4)
        let staleList = AudioBufferList.allocate(maximumBuffers: 1)
        staleList[0] = AudioBuffer(mNumberChannels: 2,
                                   mDataByteSize: 4 * UInt32(MemoryLayout<Float>.size),
                                   mData: staleOutput)
        MixerRender.silence(staleList)
        expect(Array(UnsafeBufferPointer(start: staleOutput, count: 4)) == [0, 0, 0, 0],
               "a cycle with no tap to read hands the device silence, not what it left behind")
        staleOutput.deallocate()
        free(staleList.unsafeMutablePointer)

        let toneFrames = 4800
        var toneStereo = [Float](repeating: 0, count: toneFrames * 2)
        for frame in 0..<toneFrames {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            toneStereo[frame * 2] = value
            toneStereo[frame * 2 + 1] = value
        }
        let toneCrossings = crossings(toneStereo, channels: 2)

        let toMono = rendered(source: toneStereo, sourceChannels: 2,
                              outputs: [(channels: 1, frames: toneFrames)])[0]
        expect(crossings(toMono, channels: 1) == toneCrossings,
               "a device with one channel plays the tapped audio at its own speed")
        var monoMatches = true
        for frame in 0..<toneFrames
        where abs(toMono[frame] - (toneStereo[frame * 2] + toneStereo[frame * 2 + 1]) / 2) > 0.0001 {
            monoMatches = false
            break
        }
        expect(monoMatches, "one channel gets both sides of the stereo, averaged")

        let quieterMono = rendered(source: toneStereo, sourceChannels: 2,
                                   outputs: [(channels: 1, frames: toneFrames)], gain: 0.4)[0]
        var quieterMatches = true
        for frame in 0..<toneFrames where abs(quieterMono[frame] - toMono[frame] * 0.4) > 0.0001 {
            quieterMatches = false
            break
        }
        expect(quieterMatches && quieterMono.map({ abs($0) }).max()! > 0.39,
               "the chosen volume still applies when the audio is folded to one channel")
        expect(renderedFrames == toneFrames,
               "the fold reports every frame it wrote, which is what bounds the limiter")

        let toStereo = rendered(source: toneStereo, sourceChannels: 2,
                                outputs: [(channels: 2, frames: toneFrames)], gain: 0.5)[0]
        var stereoMatches = true
        for index in 0..<(toneFrames * 2) where abs(toStereo[index] - toneStereo[index] * 0.5) > 0.0001 {
            stereoMatches = false
            break
        }
        expect(stereoMatches, "a stereo device still gets a plain scaled copy")

        let toSurround = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                  outputs: [(channels: 4, frames: 2)])[0]
        expect(toSurround == [1, 2, 0, 0, 3, 4, 0, 0],
               "a device with more channels than the tap fills the first pair and silences the rest")

        let split = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                             outputs: [(channels: 1, frames: 2), (channels: 1, frames: 2)])
        expect(split == [[1, 3], [2, 4]],
               "a device that keeps its channels in separate buffers gets one channel each")

        let quieterSplit = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                    outputs: [(channels: 1, frames: 2), (channels: 1, frames: 2)],
                                    gain: 0.5)
        expect(quieterSplit == [[0.5, 1.5], [1, 2]],
               "the chosen volume applies to every channel a spread-out device carries")

        let quieterSurround = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                       outputs: [(channels: 4, frames: 2)], gain: 0.5)[0]
        expect(quieterSurround == [0.5, 1, 0, 0, 1.5, 2, 0, 0],
               "the chosen volume applies when the tap is spread over more channels")

        let fromMono = rendered(source: [1, 2], sourceChannels: 1,
                                outputs: [(channels: 2, frames: 2)])[0]
        expect(fromMono == [1, 1, 2, 2],
               "a single-channel source is heard on both sides, not only the left")

        let shortOutput = rendered(source: [1, 2, 3, 4, 5, 6], sourceChannels: 2,
                                   outputs: [(channels: 2, frames: 2)])[0]
        expect(shortOutput == [1, 2, 3, 4] && renderedFrames == 2,
               "an output buffer smaller than the tap's is filled without running past its end")

        let tapOnly = AudioBufferList.allocate(maximumBuffers: 2)
        let deviceInput = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        let tapSamples = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        defer {
            deviceInput.deallocate()
            tapSamples.deallocate()
        }
        tapOnly[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 4,
                                 mData: UnsafeMutableRawPointer(deviceInput))
        tapOnly[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8,
                                 mData: UnsafeMutableRawPointer(tapSamples))
        expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 2) == 1,
               "on an output device that also records, the tap is not the first buffer")
        expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 1) == 0,
               "the tap is picked by the shape it announced, not by its position")
        expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 7) == nil,
               "with nothing matching the tap, the microphone is never played out of the speakers")
        tapOnly[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8, mData: nil)
        expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 2) == nil,
               "a buffer with no samples is never mistaken for the tap")
        free(tapOnly.unsafeMutablePointer)

        let lonely = AudioBufferList.allocate(maximumBuffers: 1)
        lonely[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8,
                                mData: UnsafeMutableRawPointer(tapSamples))
        expect(MixerRender.tapBufferIndex(in: lonely, tapChannels: 7) == 0,
               "an output device with nothing of its own leaves only the tap to render")
        free(lonely.unsafeMutablePointer)

        expect(MixerRender.sourceChannel(for: 0, sourceChannels: 2) == 0
            && MixerRender.sourceChannel(for: 1, sourceChannels: 2) == 1,
               "stereo feeds the first two channels in order")
        expect(MixerRender.sourceChannel(for: 2, sourceChannels: 2) == nil,
               "channels the tap cannot fill stay silent")
        expect(MixerRender.sourceChannel(for: 1, sourceChannels: 1) == 0,
               "a single channel is copied to the right as well as the left")
    }
}
