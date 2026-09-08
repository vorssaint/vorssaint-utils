// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

enum BoostLimiterTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Boost limiter (issue #326)

        // A boost above 100% used to clamp overshooting samples, flattening
        // every peak into crackle. The limiter must cap peaks without touching
        // audio that already fits, and its gain must ride across buffers.

        func sine(amplitude: Float, frames: Int, channels: Int = 1) -> [Float] {
            var samples = [Float](repeating: 0, count: frames * channels)
            for frame in 0..<frames {
                let value = amplitude * Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
                for channel in 0..<channels { samples[frame * channels + channel] = value }
            }
            return samples
        }
        func limited(_ samples: [Float], channels: Int = 1,
                     release: Float = BoostLimiter.release(sampleRate: 48000),
                     with limiter: inout BoostLimiter) -> [Float] {
            var output = samples
            output.withUnsafeMutableBufferPointer { buffer in
                limiter.process(buffer.baseAddress!,
                                frames: samples.count / channels,
                                channels: channels,
                                release: release)
            }
            return output
        }

        var quietLimiter = BoostLimiter()
        let quiet = sine(amplitude: 0.6, frames: 4800)
        expect(limited(quiet, with: &quietLimiter) == quiet,
               "audio inside the ceiling passes through bit-identical")

        var loudLimiter = BoostLimiter()
        let loud = limited(sine(amplitude: 1.5, frames: 9600), with: &loudLimiter)
        expect(loud.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "boosted peaks never leave the ceiling")
        let steady = loud.dropFirst(4800)
        let pinned = steady.filter { abs($0) >= BoostLimiter.ceiling - 0.001 }.count
        expect(pinned < steady.count / 5,
               "the limiter rides the level instead of flattening the wave into clipping")

        var recoveryLimiter = BoostLimiter()
        _ = limited(sine(amplitude: 1.5, frames: 4800), with: &recoveryLimiter)
        let afterLoud = limited(sine(amplitude: 0.5, frames: 48000), with: &recoveryLimiter)
        expect(afterLoud.prefix(480).max()! < 0.45,
               "right after a loud stretch the gain is still turned down")
        expect(afterLoud.suffix(4800).max()! > 0.499,
               "the gain recovers to unity once the audio gets quiet")

        var wholeLimiter = BoostLimiter()
        var chunkedLimiter = BoostLimiter()
        let long = sine(amplitude: 1.5, frames: 2048)
        let whole = limited(long, with: &wholeLimiter)
        let chunked = limited(Array(long[0..<1024]), with: &chunkedLimiter)
            + limited(Array(long[1024...]), with: &chunkedLimiter)
        expect(whole == chunked,
               "splitting the stream into buffers does not change the result")

        var stereoLimiter = BoostLimiter()
        var stereo = [Float](repeating: 0, count: 9600 * 2)
        for frame in 0..<9600 {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            stereo[frame * 2] = 1.5 * value
            stereo[frame * 2 + 1] = 0.75 * value
        }
        let linked = limited(stereo, channels: 2, with: &stereoLimiter)
        var stereoLinked = true
        for frame in 0..<9600 where abs(linked[frame * 2 + 1] - linked[frame * 2] / 2) > 0.0001 {
            stereoLinked = false
            break
        }
        expect(stereoLinked,
               "both channels of a frame share one gain so the stereo image stays put")

        var lookaheadInput = sine(amplitude: 1.5, frames: 9600)
        let lookahead = BoostLookaheadLimiter(channels: 1)
        _ = lookaheadInput.withUnsafeMutableBufferPointer { buffer in
            lookahead.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                              release: BoostLimiter.release(sampleRate: 48000))
        }
        let delayedSine = Array(repeating: Float(0), count: BoostLookaheadLimiter.lookaheadFrames)
            + Array(sine(amplitude: BoostLimiter.ceiling,
                         frames: 9600 - BoostLookaheadLimiter.lookaheadFrames))
        expect(lookaheadInput.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "lookahead keeps every boosted sample inside the output range")
        expect(zip(lookaheadInput.dropFirst(960), delayedSine.dropFirst(960)).allSatisfy {
            abs($0 - $1) < 0.0001
        }, "lookahead preserves a steady loud waveform instead of reshaping its peaks")

        var quietLookahead = sine(amplitude: 0.6, frames: 2048)
        let quietLookaheadSource = quietLookahead
        let quietLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        _ = quietLookahead.withUnsafeMutableBufferPointer { buffer in
            quietLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                          release: BoostLimiter.release(sampleRate: 48000))
        }
        expect(Array(quietLookahead.prefix(BoostLookaheadLimiter.lookaheadFrames))
                == Array(repeating: 0, count: BoostLookaheadLimiter.lookaheadFrames)
            && Array(quietLookahead.dropFirst(BoostLookaheadLimiter.lookaheadFrames))
                == Array(quietLookaheadSource.dropLast(BoostLookaheadLimiter.lookaheadFrames)),
               "quiet routed audio stays bit-identical after the fixed lookahead delay")

        let lookaheadSource = sine(amplitude: 1.5, frames: 4096)
        var wholeLookahead = lookaheadSource
        let wholeLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        _ = wholeLookahead.withUnsafeMutableBufferPointer { buffer in
            wholeLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                          release: BoostLimiter.release(sampleRate: 48000))
        }
        let chunkedLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        var chunkedLookahead = [Float]()
        for sourceChunk in [Array(lookaheadSource[0..<511]),
                            Array(lookaheadSource[511..<1537]),
                            Array(lookaheadSource[1537...])] {
            var chunk = sourceChunk
            _ = chunk.withUnsafeMutableBufferPointer { buffer in
                chunkedLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count,
                                                channels: 1,
                                                release: BoostLimiter.release(sampleRate: 48000))
            }
            chunkedLookahead += chunk
        }
        expect(wholeLookahead == chunkedLookahead,
               "lookahead produces the same signal across realtime buffer boundaries")

        var impulseTrain = [Float](repeating: 0.2, count: 4096)
        for frame in stride(from: 256, to: impulseTrain.count, by: 173) {
            impulseTrain[frame] = frame.isMultiple(of: 2) ? 2 : -2
        }
        let impulseLimiter = BoostLookaheadLimiter(channels: 1)
        _ = impulseTrain.withUnsafeMutableBufferPointer { buffer in
            impulseLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                   release: BoostLimiter.release(sampleRate: 48000))
        }
        expect(impulseTrain.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "overlapping future peaks are attenuated before they reach the output")

        var lookaheadStereo = [Float](repeating: 0, count: 4096 * 2)
        for frame in 0..<4096 {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            lookaheadStereo[frame * 2] = 1.5 * value
            lookaheadStereo[frame * 2 + 1] = 0.75 * value
        }
        let stereoLookaheadLimiter = BoostLookaheadLimiter(channels: 2)
        _ = lookaheadStereo.withUnsafeMutableBufferPointer { buffer in
            stereoLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count / 2,
                                           channels: 2,
                                           release: BoostLimiter.release(sampleRate: 48000))
        }
        expect((BoostLookaheadLimiter.lookaheadFrames..<4096).allSatisfy { frame in
            abs(lookaheadStereo[frame * 2 + 1] - lookaheadStereo[frame * 2] / 2) < 0.0001
        }, "lookahead applies one gain to every channel in a frame")

        func planarLookahead(_ sources: [[Float]], capacity: Int)
            -> (handled: Bool, output: [[Float]]) {
            let frames = sources.map(\.count).min() ?? 0
            let pointers = sources.map { source -> UnsafeMutablePointer<Float> in
                let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, source.count))
                pointer.update(from: source, count: source.count)
                return pointer
            }
            let list = AudioBufferList.allocate(maximumBuffers: max(1, sources.count))
            for index in sources.indices {
                list[index] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                    mData: pointers[index])
            }
            let limiter = BoostLookaheadBufferListLimiter(channelCapacity: capacity)
            let handled = limiter.process(list, frames: frames,
                                          release: BoostLimiter.release(sampleRate: 48_000))
            let output = pointers.map { Array(UnsafeBufferPointer(start: $0, count: frames)) }
            pointers.forEach { $0.deallocate() }
            free(list.unsafeMutablePointer)
            return (handled, output)
        }
        let planarFrames = 1_024
        let planarWave = (0..<planarFrames).map {
            Float(sin(2 * Double.pi * 440 * Double($0) / 48_000))
        }
        let planarStereo = planarLookahead(
            [planarWave.map { $0 * 1.5 }, planarWave.map { $0 * 0.5 }], capacity: 2)
        expect(planarStereo.handled
                && (BoostLookaheadLimiter.lookaheadFrames..<planarFrames).allSatisfy { frame in
                    abs(planarStereo.output[1][frame] - planarStereo.output[0][frame] / 3) < 0.0001
                },
               "non-interleaved stereo buffers share one lookahead gain")
        let ninePlanar = planarLookahead(
            (1...9).map { channel in
                Array(repeating: Float(channel) / 20, count: 512)
            }, capacity: 9)
        let thirtyThreePlanar = planarLookahead(
            (1...33).map { _ in Array(repeating: Float(0.2), count: 300) }, capacity: 33)
        expect(ninePlanar.handled && thirtyThreePlanar.handled
                && ninePlanar.output.allSatisfy {
                    Array($0.prefix(BoostLookaheadLimiter.lookaheadFrames))
                        == Array(repeating: 0, count: BoostLookaheadLimiter.lookaheadFrames)
                },
               "lookahead keeps one latency across nine buffers and 33 channels")

        var changedChannels = [Float](repeating: 0.4, count: 16)
        let adaptableLimiter = BoostLookaheadLimiter(channels: 2)
        let changedChannelsWereHandled = changedChannels.withUnsafeMutableBufferPointer { buffer in
            adaptableLimiter.process(
                buffer.baseAddress!, frames: 8, channels: 2,
                release: BoostLimiter.release(sampleRate: 48000))
        }
        expect(changedChannelsWereHandled,
               "a stream shape change reuses the preallocated lookahead storage")

        var tooManyChannels = [Float](repeating: 1.2, count: 24)
        let overflowWasHandled = tooManyChannels.withUnsafeMutableBufferPointer { buffer in
            BoostLookaheadLimiter(channels: 2).process(
                buffer.baseAddress!, frames: 8, channels: 3,
                release: BoostLimiter.release(sampleRate: 48000))
        }
        expect(!overflowWasHandled && tooManyChannels.allSatisfy { $0 == 1.2 },
               "a stream larger than the preallocated capacity falls through safely")

        var fallbackLimiter = BoostLimiter()
        let fallbackLimited = limited(sine(amplitude: 1.5, frames: 480),
                                      release: BoostLimiter.release(sampleRate: 0),
                                      with: &fallbackLimiter)
        expect(fallbackLimited.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "an unreadable sample rate still limits at the common device rate")

        // A headset that takes the microphone for a call changes the rate the
        // device runs at while the audio path stays up. The recovery has to
        // stay the same length of time, not the same number of samples.

        /// How many seconds the gain takes to come back after a loud stretch.
        func recoverySeconds(rate: Double, release: Float) -> Double {
            var limiter = BoostLimiter()
            let step = max(Int(rate / 1000), 1)
            func tone(_ amplitude: Float, seconds: Double) -> [Float] {
                let frames = Int(rate * seconds)
                var samples = [Float](repeating: 0, count: frames)
                for frame in 0..<frames {
                    samples[frame] = amplitude * Float(sin(2 * Double.pi * 440 * Double(frame) / rate))
                }
                return samples
            }
            _ = limited(tone(1.5, seconds: 0.1), release: release, with: &limiter)
            let quiet = limited(tone(0.5, seconds: 1.0), release: release, with: &limiter)
            let peaks = stride(from: 0, to: quiet.count, by: step).map { start in
                quiet[start..<min(start + step, quiet.count)].map { abs($0) }.max() ?? 0
            }
            guard let recovered = peaks.firstIndex(where: { $0 > 0.499 }) else { return .infinity }
            return Double(recovered) / 1000
        }

        let releaseAt48k = BoostLimiter.release(sampleRate: 48000)
        let releaseAt16k = BoostLimiter.release(sampleRate: 16000)
        expect(releaseAt16k < releaseAt48k,
               "a slower rate keeps less of the previous level in each sample")

        let recoveryAt48k = recoverySeconds(rate: 48000, release: releaseAt48k)
        let recoveryAt16k = recoverySeconds(rate: 16000, release: releaseAt16k)
        expect(abs(recoveryAt16k - recoveryAt48k) < 0.02,
               "the gain takes the same time to come back whatever rate the device runs at")

        // The defect this replaced: the figure was worked out once when the
        // engine was built, so a device that changed rate afterwards recovered
        // at the wrong speed for as long as it kept playing.
        let staleRecovery = recoverySeconds(rate: 16000, release: releaseAt48k)
        expect(staleRecovery > recoveryAt16k * 2,
               "keeping the old rate's figure after a change drags the recovery out")
    }
}
