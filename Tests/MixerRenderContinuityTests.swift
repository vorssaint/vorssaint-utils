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

    final class Renderer {
        let box = FloatBox(1)
        let compensation = FloatBox(1)
        let release = FloatBox(BoostLimiter.release(sampleRate: 48_000))
        let ramp = TapLevelRamp()
        let cycles = Counter()
        let tapChannels = 2
        let limiterBox = LimiterBox(channelCapacity: 2)

        func render(_ source: [Float]?, frames: Int, layout: [UInt32]) -> [Float] {
            let input = AudioBufferList.allocate(maximumBuffers: 1)
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: max(1, source?.count ?? 0))
            if let source { samples.update(from: source, count: source.count) }
            input[0] = AudioBuffer(mNumberChannels: 2,
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
