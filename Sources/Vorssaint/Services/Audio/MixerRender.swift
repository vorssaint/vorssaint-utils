// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import CoreAudio

/// Puts a tapped app's audio onto whatever shape the output device asks for.
///
/// The tap always hands over the same thing: two interleaved channels. The
/// device on the other side does not have to match. A headset in a call
/// carries one channel, an audio interface can carry eight, and a device that
/// also records puts its own microphone in front of the tap in the same list
/// of buffers. Copying samples straight across without reading those shapes
/// plays the wrong thing at the wrong speed (issue #397): stereo poured into
/// one channel comes out an octave low and half as long, which is why a call
/// turned slow and unintelligible the moment the mixer touched it.
///
/// Everything here runs on the realtime audio thread: no allocation, no
/// locks, one pass over the samples.
enum MixerRender {
    /// How many frames a buffer holds.
    static func frames(bytes: UInt32, channels: UInt32) -> Int {
        guard channels > 0 else { return 0 }
        return Int(bytes) / (MemoryLayout<Float>.size * Int(channels))
    }

    /// Which input buffer carries the tap.
    ///
    /// An aggregate presents what its sub-device records first and the tap
    /// after it, so on an output device that also has a microphone the tap is
    /// not buffer zero: rendering that one plays the microphone's silence and
    /// the app goes quiet. The tap is the last buffer with the shape the tap
    /// announced.
    ///
    /// With nothing matching that shape, the tap can still be claimed when the
    /// device brings no input of its own: a single buffer has nowhere else to
    /// come from. Guessing among several would mean playing the device's own
    /// microphone out of its speakers, so the app stays silent instead.
    static func tapBufferIndex(in buffers: UnsafeMutableAudioBufferListPointer,
                               tapChannels: Int) -> Int? {
        var lone: Int?
        for index in stride(from: buffers.count - 1, through: 0, by: -1)
        where buffers[index].mData != nil && buffers[index].mNumberChannels > 0 {
            if Int(buffers[index].mNumberChannels) == tapChannels { return index }
            if buffers.count == 1 { lone = index }
        }
        return lone
    }

    /// Which source channel feeds one output channel, or nil when the device
    /// has more channels than the tap can fill and the rest must stay silent.
    static func sourceChannel(for outputChannel: Int, sourceChannels: Int) -> Int? {
        if outputChannel < sourceChannels { return outputChannel }
        // A single-channel source belongs in both front channels, not just
        // the left one.
        if sourceChannels == 1, outputChannel == 1 { return 0 }
        return nil
    }

    /// Silences every output frame from `frame` on.
    ///
    /// The output buffer is handed over dirty: it holds whatever CoreAudio
    /// last put in that memory. Frames the tap cannot fill — the tail of a
    /// buffer longer than the tap's, or the whole buffer on a cycle with no
    /// tap to read — used to be left as they were found and played back as a
    /// fragment of older audio (issue #326). Silence is the right content for
    /// a frame with no samples behind it.
    static func silence(_ output: UnsafeMutableAudioBufferListPointer, from frame: Int = 0) {
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0,
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let unwritten = frames(bytes: buffer.mDataByteSize,
                                   channels: buffer.mNumberChannels) - frame
            guard unwritten > 0 else { continue }
            vDSP_vclr(destination + frame * channels, 1, vDSP_Length(unwritten * channels))
        }
    }

    /// Renders one interleaved source buffer onto the output, scaled by
    /// `gain`, and answers how many frames it wrote. Whatever it does not
    /// write it silences, so the caller never has to think about the tail.
    @discardableResult
    static func render(source: AudioBuffer,
                       into output: UnsafeMutableAudioBufferListPointer,
                       gain: Float) -> Int {
        var written = 0
        defer { silence(output, from: written) }
        let sourceChannels = Int(source.mNumberChannels)
        guard sourceChannels > 0,
              let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return 0 }

        var frames = self.frames(bytes: source.mDataByteSize, channels: source.mNumberChannels)
        var outputChannels = 0
        var hasWritableOutput = false
        for buffer in output where buffer.mNumberChannels > 0 {
            outputChannels += Int(buffer.mNumberChannels)
            guard buffer.mData != nil else { continue }
            hasWritableOutput = true
            frames = min(frames, self.frames(bytes: buffer.mDataByteSize,
                                             channels: buffer.mNumberChannels))
        }
        guard frames > 0, outputChannels > 0, hasWritableOutput else { return 0 }
        var gain = gain

        // The usual shape: one interleaved buffer wanting exactly what the
        // tap produced. One pass, nothing to map.
        if output.count == 1, Int(output[0].mNumberChannels) == sourceChannels,
           let destination = output[0].mData?.assumingMemoryBound(to: Float.self) {
            vDSP_vsmul(samples, 1, &gain, destination, 1, vDSP_Length(frames * sourceChannels))
            written = frames
            return written
        }

        // One channel to play with: fold the source into it instead of
        // handing over every other sample.
        if outputChannels == 1, sourceChannels > 1 {
            guard let buffer = output.first(where: { $0.mNumberChannels == 1 && $0.mData != nil }),
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            var scale = gain / Float(sourceChannels)
            vDSP_vsmul(samples, vDSP_Stride(sourceChannels), &scale,
                       destination, 1, vDSP_Length(frames))
            for channel in 1..<sourceChannels {
                vDSP_vsma(samples + channel, vDSP_Stride(sourceChannels), &scale,
                          destination, 1, destination, 1, vDSP_Length(frames))
            }
            written = frames
            return written
        }

        var firstOutputChannel = 0
        var didWriteSourceChannel = false
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstOutputChannel += channels }
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0..<channels {
                guard let sourceChannel = sourceChannel(for: firstOutputChannel + channel,
                                                        sourceChannels: sourceChannels) else {
                    vDSP_vclr(destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
                    continue
                }
                didWriteSourceChannel = true
                vDSP_vsmul(samples + sourceChannel, vDSP_Stride(sourceChannels), &gain,
                           destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
            }
        }
        written = didWriteSourceChannel ? frames : 0
        return written
    }
}
