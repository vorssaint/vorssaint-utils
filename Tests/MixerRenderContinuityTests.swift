// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Runs the production IO callback without touching an audio device. The tap
/// can supply fewer frames than the output clock consumes, or no buffer at all.
enum MixerRenderContinuityTests {
    final class FloatBox {
        var value: Float
        init(_ value: Float) { self.value = value }
    }

    final class Counter {
        var value = 0
        func increment() { value += 1 }
    }

    final class Configuration {
        var canRender = true
    }

    final class Renderer {
        let box = FloatBox(1)
        let compensation = FloatBox(1)
        let release = FloatBox(BoostLimiter.release(sampleRate: 48_000))
        let ramp = TapLevelRamp()
        let cycles = Counter()
        let configuration = Configuration()
        let tapChannels: Int
        let limiterBox: LimiterBox

        init(tapChannels: Int = 2, channelCapacity: Int? = nil) {
            self.tapChannels = tapChannels
            limiterBox = LimiterBox(channelCapacity: channelCapacity ?? tapChannels)
        }

        func render(_ source: [Float]?, frames: Int, layout: [UInt32],
                    microphone: [Float]? = nil) -> [Float] {
            let input = AudioBufferList.allocate(maximumBuffers: microphone == nil ? 1 : 2)
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: max(1, source?.count ?? 0))
            if let source { samples.update(from: source, count: source.count) }
            let microphoneSamples = microphone.map { values -> UnsafeMutablePointer<Float> in
                let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, values.count))
                pointer.update(from: values, count: values.count)
                return pointer
            }
            if let microphone {
                input[0] = AudioBuffer(mNumberChannels: UInt32(tapChannels),
                                       mDataByteSize: UInt32(microphone.count * MemoryLayout<Float>.size),
                                       mData: microphoneSamples.map { UnsafeMutableRawPointer($0) })
            }
            input[input.count - 1] = AudioBuffer(
                mNumberChannels: UInt32(tapChannels),
                mDataByteSize: UInt32((source?.count ?? 0) * MemoryLayout<Float>.size),
                mData: source == nil ? nil : samples)
            let output = AudioBufferList.allocate(maximumBuffers: layout.count)
            let storage = layout.map { channels -> UnsafeMutablePointer<Float> in
                let pointer = UnsafeMutablePointer<Float>.allocate(capacity: frames * Int(channels))
                pointer.initialize(repeating: -99, count: frames * Int(channels))
                return pointer
            }
            defer {
                storage.forEach { $0.deallocate() }
                samples.deallocate()
                microphoneSamples?.deallocate()
                free(input.unsafeMutablePointer)
                free(output.unsafeMutablePointer)
            }
            for index in layout.indices {
                output[index] = AudioBuffer(mNumberChannels: layout[index],
                                            mDataByteSize: UInt32(frames * Int(layout[index]) * MemoryLayout<Float>.size),
                                            mData: storage[index])
            }
            var now = AudioTimeStamp()
            process(now: &now, input: input.unsafePointer, output: output.unsafeMutablePointer)
            return (0..<frames).flatMap { frame in
                layout.indices.flatMap { index in
                    (0..<Int(layout[index])).map { storage[index][frame * Int(layout[index]) + $0] }
                }
            }
        }
    }

    static func run(_ suite: TestSuite) {
        for channels in [2, 8, 16, 32] {
            let frames = 768
            var source: [Float] = []
            source.reserveCapacity(frames * channels)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let amplitude: Float = 0.3 * Float(channel + 1) / Float(channels)
                    let frequency = Double(220 + channel * 11)
                    let angularFrequency = 2.0 * Double.pi * frequency
                    let phase = angularFrequency * Double(frame) / 48_000.0
                    source.append(amplitude * Float(sin(phase)))
                }
            }
            // The physical device records before the tap in the aggregate.
            // Give it the same shape so only its position distinguishes it.
            let microphone = Array(repeating: Float(0.75), count: frames * channels)
            for layout in [[UInt32(channels)], Array(repeating: UInt32(1), count: channels)] {
                for gain: Float in [0.9801, 1.5] {
                    let renderer = Renderer(tapChannels: channels)
                    renderer.box.value = gain
                    let rendered = renderer.render(source, frames: frames, layout: layout,
                                                   microphone: microphone)
                    let expected = Array(repeating: Float.zero, count: 256 * channels)
                        + source.prefix((frames - 256) * channels).map { $0 * gain }
                    let error = zip(rendered, expected).map { abs($0 - $1) }.max() ?? .infinity
                    suite.expect(rendered.count == expected.count && error < 0.00001,
                                 "a \(channels)-channel tap preserves every channel at gain \(gain), excluding the microphone (layout \(layout), maximum error \(error))")
                    suite.expect(renderer.cycles.value == 1,
                                 "a valid multichannel tap advances render progress")

                    // A changed format invalidates the engine while delayed
                    // samples still exist. None may escape under the new format.
                    renderer.configuration.canRender = false
                    let invalid = renderer.render(source, frames: frames, layout: layout,
                                                  microphone: microphone)
                    suite.expect(invalid == Array(repeating: Float.zero, count: frames * channels)
                                    && renderer.cycles.value == 1,
                                 "an invalidated \(channels)-channel format silences the output without draining the old lookahead or advancing progress")
                    renderer.configuration.canRender = true
                    let resumed = renderer.render(Array(repeating: 0.1, count: source.count),
                                                   frames: frames, layout: layout)
                    let resumedExpected = Array(repeating: Float.zero, count: 256 * channels)
                        + Array(repeating: Float(0.1) * gain, count: (frames - 256) * channels)
                    suite.expect(zip(resumed, resumedExpected).allSatisfy { abs($0 - $1) < 0.00001 },
                                 "resuming an unchanged format discards all samples queued before suspension")
                }
            }
        }

        let emptyTap = Renderer(tapChannels: 32)
        let missing = emptyTap.render(nil, frames: 512, layout: [32],
                                      microphone: Array(repeating: 0.75, count: 512 * 32))
        suite.expect(missing.allSatisfy { $0 == 0 } && emptyTap.cycles.value == 0,
                     "a wide tap with no data never selects the microphone before it")

        let unformatted = AudioBufferList.allocate(maximumBuffers: 1)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: 7, alignment: 1)
        raw.initializeMemory(as: UInt8.self, repeating: 0x7f, count: 7)
        unformatted[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 5, mData: raw)
        MixerRender.silence(unformatted)
        let bytes = Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: UInt8.self), count: 7))
        suite.expect(bytes == [0, 0, 0, 0, 0, 0x7f, 0x7f],
                     "suspension zeros every output byte without assuming Float32 or overrunning the buffer")
        raw.deallocate()
        free(unformatted.unsafeMutablePointer)

        // Each gap follows live audio, so the lookahead still owns samples
        // that must be emitted before the silence reaches the output.
        let blocks: [(input: Int?, output: Int)] = [
            (1_024, 1_024), (128, 512), (512, 512), (nil, 512),
            (512, 512), (0, 512), (512, 512), (1_024, 1_024),
        ]
        for layout: [UInt32] in [[2], [1, 1], [1]] {
            for amplitude: Float in [0.4, 1.2] {
                let renderer = Renderer()
                renderer.box.value = 1.5
                var timeline: [Float] = []
                var rendered: [Float] = []
                var offset = 0
                for block in blocks {
                    let source = block.input.map { count in
                        (0..<count).flatMap { frame -> [Float] in
                            let sample = amplitude * Float(sin(2 * Double.pi * 440 * Double(offset + frame) / 48_000))
                            return [sample, sample * 0.5]
                        }
                    }
                    timeline += source ?? []
                    timeline += Array(repeating: 0, count: (block.output - (block.input ?? 0)) * 2)
                    rendered += renderer.render(source, frames: block.output, layout: layout)
                    offset += block.output
                }
                let reference = Renderer()
                reference.box.value = renderer.box.value
                let expected = reference.render(timeline, frames: offset, layout: layout)
                let error = zip(rendered, expected).map { abs($0 - $1) }.max() ?? .infinity
                suite.expect(rendered.count == expected.count && error < 0.00001,
                             "short, missing and empty tap blocks preserve the output timeline (layout \(layout), amplitude \(amplitude), maximum error \(error))")
                suite.expect(renderer.cycles.value == 6,
                             "only callbacks with source frames advance the engine's progress")
                suite.expect(rendered.allSatisfy { $0.isFinite && abs($0) <= BoostLimiter.ceiling + 0.0001 },
                             "gaps and resumption keep amplified output inside the ceiling")
            }
        }

        let tail = Renderer()
        _ = tail.render(Array(repeating: 0.4, count: 512 * 2), frames: 512, layout: [2])
        let drained = tail.render(nil, frames: 512, layout: [2])
        suite.expect(drained == Array(repeating: 0.4, count: 256 * 2) + Array(repeating: 0, count: 256 * 2),
                     "a missing tap drains the valid lookahead tail before emitting silence")
        let resumed = tail.render(Array(repeating: 0.2, count: 512 * 2), frames: 512, layout: [2])
        suite.expect(resumed == Array(repeating: 0, count: 256 * 2) + Array(repeating: 0.2, count: 256 * 2),
                     "resuming after a gap never replays audio from before the gap")

        let limiter = Renderer.LimiterBox(channelCapacity: 2)
        let output = AudioBufferList.allocate(maximumBuffers: 2)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 65)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 65)
        left.initialize(repeating: 0.4, count: 65)
        right.initialize(repeating: 0.2, count: 65)
        defer {
            left.deallocate()
            right.deallocate()
            free(output.unsafeMutablePointer)
        }
        for index in 0..<2 {
            output[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        }
        limiter.process(output, release: BoostLimiter.release(sampleRate: 48_000))
        output[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 64 * 4, mData: left)
        output[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 32 * 4, mData: right)
        limiter.process(output, release: BoostLimiter.release(sampleRate: 48_000))
        suite.expect(Array(UnsafeBufferPointer(start: left, count: 65))
                        == Array(repeating: 0, count: 32) + Array(repeating: 0.4, count: 33)
                     && Array(UnsafeBufferPointer(start: right, count: 65))
                        == Array(repeating: 0, count: 32) + Array(repeating: 0.2, count: 33),
                     "inactive outputs leave the delay untouched and unequal buffers stop at their common writable bound")
    }
}
