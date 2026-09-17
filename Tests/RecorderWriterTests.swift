// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

enum RecorderWriterTests {
    static func run(expect: @escaping (Bool, String) -> Void) {
        checkClock(expect: expect)
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await check(expect: expect)
                try await check(expect: expect, delayedVideo: true)
                try await check(expect: expect, delayedVideo: true, capturesAudio: false)
                try await check(expect: expect, changingMicrophone: true)
                try await check(expect: expect, delayedVideo: true, changingMicrophone: true)
                try await check(expect: expect, changingMicrophone: true, microphoneChannels: 4)
                try await check(expect: expect, changingSystemAudio: true)
            }
            catch { expect(false, "recorder writer fixture failed: \(error)") }
            finished.signal()
        }
        finished.wait()
    }

    private static func checkClock(expect: (Bool, String) -> Void) {
        let clock = RecorderPauseClock()
        expect(clock.eventTime(100) == nil && clock.sampleTime(start: 100, duration: 0.01) == nil
            && clock.elapsed(at: 100) == 0 && !clock.pause(at: 100),
               "a session that has not begun admits no capture events or pauses")
        expect(!clock.begin(at: .nan) && !clock.begin(at: .infinity) && clock.begin(at: 100),
               "the shared origin requires a finite timestamp")
        expect(!clock.begin(at: 100.3) && abs(clock.elapsed(at: 100.3) - 0.3) < 0.0001,
               "starting a later source cannot reset the recording origin or elapsed display")
        expect(clock.eventTime(99.9) == nil && clock.sampleTime(start: 99.9, duration: 0.01) == nil,
               "events and samples preceding the recording are rejected")
        expect(clock.pause(at: 110) && clock.elapsed(at: 115) == 10 && clock.eventTime(115) == nil,
               "pausing freezes the shared elapsed display and discards events")
        expect(clock.resume(at: 120) && clock.sampleTime(start: 121, duration: 0.01) == 11
            && clock.eventTime(121) == 11 && clock.elapsed(at: 121) == 11,
               "samples, events and elapsed display remove the same pause")
    }

    private static func check(expect: (Bool, String) -> Void,
                              delayedVideo: Bool = false, capturesAudio: Bool = true,
                              changingMicrophone: Bool = false,
                              microphoneChannels: AVAudioChannelCount = 2,
                              changingSystemAudio: Bool = false) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-sync-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let pause = RecorderPauseClock()
        let origin = CMTime(value: 100, timescale: 1)
        let microphoneClock = RecorderSampleTimingTests.offsetClock()
        let writer = RecorderWriter(url: url, pixelSize: CGSize(width: 64, height: 64), frameRate: 30,
            capturesSystemAudio: capturesAudio, capturesMicrophone: capturesAudio, pauseClock: pause)!
        precondition(writer.start())
        writer.beginSession(at: origin)
        var pointer = RecorderPointerTrack()
        var typing = RecorderTypingTrack()

        // The microphone callback arrives first but its capture starts later.
        // Video and system audio must retain their earlier timestamps.
        let firstAudio = RecorderSampleTimingTests.audio(count: 480, time: origin + time(0.1))
        let firstMicrophone = changingMicrophone
            ? audioSample(firstAudio, interleaved: false, channels: microphoneChannels)
            : firstAudio
        writer.append(firstMicrophone, kind: .microphone)
        for index in 0..<100 {
            if index == 50 {
                pause.pause(at: 100.5)
                expect(pause.eventTime(100.75) == nil && pause.elapsed(at: 100.75) == 0.5,
                       "events during a pause do not reach either metadata track")
                pause.resume(at: 101)
            }
            let source = origin + time(Double(index) / 100 + (index >= 50 ? 0.5 : 0))
            if [delayedVideo ? 20 : 0, 40, 80].contains(index) {
                writer.append(video(at: source), kind: .video)
            }
            let audio = RecorderSampleTimingTests.audio(count: 480, time: source)
            if index == 40 || index == 80 {
                let block = CMSampleBufferGetDataBuffer(audio)!
                precondition(CMBlockBufferFillDataBytes(with: 0x30, blockBuffer: block,
                    offsetIntoDestination: 0, dataLength: 480 * 4) == noErr)
                // The event sources first contribute after video startup. Their
                // later start must not shift these markers ahead of the pixels.
                if let eventTime = pause.eventTime(source.seconds) {
                    pointer.samples.append(.init(time: eventTime, point: CGPoint(x: 0.5, y: 0.5)))
                    pointer.clicks.append(.init(time: eventTime, isDown: true))
                    typing.times.append(eventTime)
                }
            }
            let systemAudio = changingSystemAudio
                ? audioSample(audio, interleaved: index < 50, channels: 2)
                : audio
            writer.append(systemAudio, kind: .systemAudio)
            if index > 10 {
                let captured = changingMicrophone
                    ? audioSample(audio, interleaved: index >= 50, channels: microphoneChannels)
                    : audio
                // Exercise the additional clock-conversion pass the microphone uses.
                let microphone = RecorderSampleTiming.retimed(captured, to: source + time(400))!
                let converted = RecorderSampleTiming.converted(microphone,
                    from: microphoneClock, to: CMClockGetHostTimeClock())!
                writer.append(converted, kind: .microphone)
            }
            // Real-time writer inputs apply backpressure; give the encoders time.
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let finished = await writer.finish(at: origin + time(1.5))
        expect(finished, changingMicrophone || changingSystemAudio
            ? "the multitrack MOV survives an audio buffer-layout change across a pause"
            : "the raw multitrack MOV finishes")
        expect(writer.videoFrameCount == 3, "all three captured video frames are retained")
        guard finished else { return }
        // Use the same stored formats read by the editor, including their
        // timestamp precision, alongside the MOV's decoded timestamps below.
        let savedPointer = RecorderPointerTrack.decoded(pointer.encoded())
        let savedTyping = RecorderTypingTrack.decoded(typing.encoded())
        let eventTimes = savedPointer.samples.map(\.time) + savedPointer.clicks.map(\.time) + savedTyping.times
        expect(eventTimes.count == 6, "both metadata tracks retain markers before and after pause/resume")
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        expect(tracks.count == (capturesAudio ? 3 : 1), "the raw MOV contains exactly the enabled tracks")
        for track in tracks {
            let type = track.mediaType
            let range = try await track.load(.timeRange)
            expect(abs(range.end.seconds - 1) < 0.05, "\(type.rawValue) ends on the shared timeline after the pause")
            expect(abs(range.end.seconds - pause.elapsed(at: 101.5)) < 0.05,
                   "the elapsed display ends with every recorded track")
            if type == .video {
                let segments = try await track.load(.segments)
                expect(!segments.contains { $0.isEmpty && $0.timeMapping.target.start.seconds < 0.001 },
                       "video has no empty opening edit when the first capture is delayed")
                expect(abs(range.start.seconds) < 0.001, "video begins at the explicit recording origin")
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                ])
                reader.add(output)
                precondition(reader.startReading())
                var timestamps: [Double] = []
                while let sample = output.copyNextSampleBuffer() {
                    timestamps.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                }
                expect(timestamps.first.map { abs($0) < 0.001 } ?? false,
                       "the first decoded image starts at zero, including delayed capture with sound off")
                expect(reader.status == .completed, "the saved video decodes fully")
                expect([0.4, 0.8].allSatisfy { expected in timestamps.contains { abs($0 - expected) < 0.001 } },
                       "the raw MOV preserves video marker timestamps across pause/resume")
                expect(eventTimes.allSatisfy { event in timestamps.contains { abs($0 - event) < 0.001 } },
                       "stored pointer, click and typing markers align with decoded video after delayed startup and pauses")
                continue
            }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            ])
            reader.add(output)
            precondition(reader.startReading())
            var markers: [Double] = []
            while let sample = output.copyNextSampleBuffer() {
                let block = CMSampleBufferGetDataBuffer(sample)!
                let frames = CMSampleBufferGetNumSamples(sample)
                var values = [Float](repeating: 0, count: frames * 2)
                precondition(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: values.count * 4,
                    destination: &values) == noErr)
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                for frame in 0..<frames where abs(values[frame * 2]) > 0.1 {
                    let marker = start + Double(frame) / 48_000
                    if markers.last.map({ marker - $0 > 0.1 }) ?? true { markers.append(marker) }
                }
            }
            expect(reader.status == .completed, "the saved audio decodes fully")
            expect(markers.count == 2 && abs(markers[0] - 0.4) < 0.025 && abs(markers[1] - 0.8) < 0.025,
                   "audio markers align with video before and after the pause")
            expect(eventTimes.allSatisfy { event in markers.contains { abs($0 - event) < 0.025 } },
                   "stored pointer, click and typing markers align with decoded audio")
        }
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48_000)
    }

    /// Emulate a device switching between planar and interleaved PCM. The
    /// production writer must keep both representations in the same movie.
    private static func audioSample(_ sample: CMSampleBuffer,
                                    interleaved: Bool,
                                    channels: AVAudioChannelCount) -> CMSampleBuffer {
        let count = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        var source = [Int16](repeating: 0, count: Int(count) * 2)
        precondition(CMBlockBufferCopyDataBytes(CMSampleBufferGetDataBuffer(sample)!, atOffset: 0,
            dataLength: source.count * 2, destination: &source) == noErr)
        let deviceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
            interleaved: interleaved, channelLayout: AVAudioChannelLayout(
                layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)!)
        let device = AVAudioPCMBuffer(pcmFormat: deviceFormat, frameCapacity: count)!
        device.frameLength = count
        for frame in 0..<Int(count) {
            for channel in 0..<Int(channels) {
                let buffer = interleaved ? 0 : channel
                let index = interleaved ? frame * Int(channels) + channel : frame
                device.floatChannelData![buffer][index] = Float(source[frame * 2 + channel % 2]) / 32_768
            }
        }
        // A multichannel device need not provide speaker labels.
        var description: CMAudioFormatDescription?
        precondition(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
            asbd: deviceFormat.streamDescription, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample), decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        precondition(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
            sampleCount: Int(device.frameLength), sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result) == noErr)
        precondition(CMSampleBufferSetDataBufferFromAudioBufferList(result!,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, bufferList: device.audioBufferList) == noErr)
        precondition(CMSampleBufferSetDataReady(result!) == noErr)
        return result!
    }

    private static func video(at time: CMTime) -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
            nil, &pixels) == kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(pixels!, [])
        memset(CVPixelBufferGetBaseAddress(pixels!), 0, CVPixelBufferGetDataSize(pixels!))
        CVPixelBufferUnlockBaseAddress(pixels!, [])
        var format: CMVideoFormatDescription?
        precondition(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixels!, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        precondition(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels!,
            formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return sample!
    }
}
