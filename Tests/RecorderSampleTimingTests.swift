// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

enum RecorderSampleTimingTests {
    static func run(expect: (Bool, String) -> Void) {
        for rate: CMTimeScale in [44_100, 48_000] {
            for count in [1, 480, 1024] {
                let original = audio(count: count, rate: rate, time: CMTime(value: 100, timescale: 1))
                let target = CMTime(value: 3, timescale: 2)
                guard let system = RecorderSampleTiming.retimed(original, to: target),
                      let converted = RecorderSampleTiming.retimed(original, to: CMTime(value: 200, timescale: 1)),
                      let microphone = RecorderSampleTiming.retimed(converted, to: target) else {
                    expect(false, "audio retiming succeeds")
                    continue
                }
                for shifted in [system, microphone] {
                    expect(CMSampleBufferGetDuration(shifted) == CMSampleBufferGetDuration(original),
                           "retiming preserves \(count) audio sample durations at \(rate) Hz")
                    var last = CMSampleTimingInfo()
                    expect(CMSampleBufferGetSampleTimingInfo(shifted, at: count - 1, timingInfoOut: &last) == noErr
                        && last.presentationTimeStamp == target + CMTime(value: Int64(count - 1), timescale: rate),
                           "the last audio sample stays on its original cadence after either capture path")
                    expect(CMSampleBufferGetDataBuffer(shifted) === CMSampleBufferGetDataBuffer(original),
                           "retiming shares the captured audio data")
                }
                expect(CMSampleBufferGetPresentationTimeStamp(original) == CMTime(value: 100, timescale: 1),
                       "retiming leaves the captured buffer unchanged")
            }
        }

        var entries = [
            CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                               presentationTimeStamp: CMTime(value: 10, timescale: 1),
                               decodeTimeStamp: CMTime(value: 9, timescale: 1)),
            CMSampleTimingInfo(duration: .invalid,
                               presentationTimeStamp: CMTime(value: 21, timescale: 2),
                               decodeTimeStamp: .invalid),
        ]
        var sample: CMSampleBuffer?
        precondition(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: nil, sampleCount: 2, sampleTimingEntryCount: entries.count,
            sampleTimingArray: &entries, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sample) == noErr)
        if let shifted = RecorderSampleTiming.retimed(sample!, to: .zero) {
            for index in entries.indices {
                var actual = CMSampleTimingInfo()
                let status = CMSampleBufferGetSampleTimingInfo(shifted, at: index, timingInfoOut: &actual)
                expect(status == noErr && actual.duration == entries[index].duration,
                       "retiming preserves each timing entry, including an unknown video duration")
                expect(actual.presentationTimeStamp == entries[index].presentationTimeStamp - CMTime(value: 10, timescale: 1),
                       "retiming preserves relative presentation timestamps")
                expect(entries[index].decodeTimeStamp.isValid
                    ? actual.decodeTimeStamp == CMTime(value: -1, timescale: 1)
                    : !actual.decodeTimeStamp.isValid,
                       "retiming shifts valid decode timestamps and preserves invalid ones")
            }
        } else {
            expect(false, "buffers with multiple timing entries can be retimed")
        }
        expect(RecorderSampleTiming.retimed(sample!, to: .invalid) == nil,
               "an invalid destination timestamp is rejected")

        let clock = offsetClock()
        let microphone = audio(count: 480, time: CMTime(value: 500, timescale: 1))
        if let converted = RecorderSampleTiming.converted(microphone, from: clock, to: CMClockGetHostTimeClock()) {
            expect(CMSampleBufferGetPresentationTimeStamp(converted) == CMTime(value: 100, timescale: 1)
                && CMSampleBufferGetDuration(converted) == CMTime(value: 1, timescale: 100),
                   "clock conversion changes the epoch without stretching audio samples")
        } else {
            expect(false, "audio converts between clocks with different epochs")
        }
    }

    static func offsetClock() -> CMTimebase {
        var clock: CMTimebase?
        precondition(CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(), timebaseOut: &clock) == noErr)
        precondition(CMTimebaseSetRateAndAnchorTime(clock!, rate: 1,
            anchorTime: CMTime(value: 500, timescale: 1),
            immediateSourceTime: CMTime(value: 100, timescale: 1)) == noErr)
        return clock!
    }

    static func audio(count: Int, rate: CMTimeScale = 48_000, time: CMTime) -> CMSampleBuffer {
        var format = AudioStreamBasicDescription(mSampleRate: Double(rate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var description: CMAudioFormatDescription?
        precondition(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &description) == noErr)
        var block: CMBlockBuffer?
        precondition(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
            memoryBlock: nil, blockLength: count * 4, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: count * 4, flags: 0,
            blockBufferOut: &block) == noErr)
        precondition(CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0,
            dataLength: count * 4) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: rate),
                                       presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var size = 4
        var buffer: CMSampleBuffer?
        precondition(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: description, sampleCount: count, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &buffer) == noErr)
        return buffer!
    }
}
