// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

enum RecorderWriterTests {
    static func run(_ suite: TestSuite) {
        checkClock(suite)
        checkAudioNormalization(suite)
        checkPreparation(suite)
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await check(suite)
                try await check(suite, delayedVideo: true)
                try await check(suite, delayedVideo: true, capturesAudio: false)
                try await check(suite, changingMicrophone: true)
                try await check(suite, delayedVideo: true, changingMicrophone: true)
                try await check(suite, changingMicrophone: true, microphoneChannels: 4)
                try await check(suite, changingMicrophone: true, microphoneChannels: 1,
                                microphoneFormat: .pcmFormatInt16)
                try await check(suite, changingMicrophone: true, microphoneChannels: 1,
                                microphoneFormat: .pcmFormatInt16, malformedMicrophone: true)
                try await check(suite, changingSystemAudio: true)
            }
            catch { suite.expect(false, "recorder writer fixture failed: \(error)") }
            finished.signal()
        }
        suite.expect(finished.wait(timeout: .now() + 90) == .success,
                     "recorder writer scenarios finish within their bounded fixture deadline")
    }

    private static func checkAudioNormalization(_ suite: TestSuite) {
        var converter: AVAudioConverter?
        let levels: [Int16] = [-24_576, -8_192, 0, 8_192, 24_576]
        for rate: CMTimeScale in [44_100, 48_000] {
            for count in [3, 512] {
                let source = RecorderSampleTimingTests.audio(count: count, rate: rate, time: time(100))
                let values = (0..<(count * 2)).map { levels[$0 % levels.count] }
                precondition(CMBlockBufferReplaceDataBytes(with: values, blockBuffer: CMSampleBufferGetDataBuffer(source)!,
                    offsetIntoDestination: 0, dataLength: values.count * 2) == noErr)
                for channels: AVAudioChannelCount in [1, 2, 4] {
                    for format: AVAudioCommonFormat in [.pcmFormatInt16, .pcmFormatFloat32] {
                        for interleaved in [false, true] {
                            let sample = audioSample(source, interleaved: interleaved, channels: channels, format: format)
                            guard let normalized = RecorderWriter.interleavedAudioSample(sample, converter: &converter) else {
                                suite.expect(false, "valid mono, stereo and multichannel PCM can be normalized")
                                continue
                            }
                            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
                                CMSampleBufferGetFormatDescription(normalized)!)!.pointee
                            let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
                                && asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
                                && asbd.mBitsPerChannel == 32 && asbd.mBytesPerFrame == channels * 4
                            suite.expect(isFloat, "both integer and float PCM reach the encoder as interleaved Float32")
                            suite.expect(asbd.mSampleRate == Double(rate) && asbd.mChannelsPerFrame == channels
                                && CMSampleBufferGetNumSamples(normalized) == count
                                && CMSampleBufferGetDuration(normalized) == CMSampleBufferGetDuration(sample)
                                && CMSampleBufferGetPresentationTimeStamp(normalized) == CMSampleBufferGetPresentationTimeStamp(sample),
                                "normalization preserves channels, sample rate, frame count and timing")
                            guard isFloat else { continue }
                            var decoded = [Float](repeating: 0, count: count * Int(channels))
                            let status = CMBlockBufferCopyDataBytes(CMSampleBufferGetDataBuffer(normalized)!, atOffset: 0,
                                dataLength: decoded.count * 4, destination: &decoded)
                            suite.expect(status == noErr && decoded.enumerated().allSatisfy { index, value in
                                let frame = index / Int(channels), channel = index % Int(channels)
                                return abs(value - Float(values[frame * 2 + channel % 2]) / 32_768) < 0.00001
                            }, "normalization preserves signed sample amplitudes and channel order without noise")
                        }
                    }
                }
            }
        }
        for length in [512, 2_048] {
            suite.expect(RecorderWriter.interleavedAudioSample(malformedAudio(byteCount: length), converter: &converter) == nil,
                "Int16 mono buffers with fewer or more bytes than their 512 declared frames are rejected")
        }
    }

    /// Reproduce the issue's 512 Int16 mono frames carrying 2,048 bytes,
    /// plus a truncated packet. Core Media accepts both inconsistent buffers.
    private static func malformedAudio(byteCount: Int) -> CMSampleBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: true)!
        var block: CMBlockBuffer?
        precondition(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
            memoryBlock: nil, blockLength: byteCount, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: 0,
            blockBufferOut: &block) == noErr)
        precondition(CMBlockBufferFillDataBytes(with: 0x30, blockBuffer: block!, offsetIntoDestination: 0,
            dataLength: byteCount) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: time(100), decodeTimeStamp: .invalid)
        var size = 2
        var sample: CMSampleBuffer?
        precondition(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: format.formatDescription, sampleCount: 512, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample) == noErr)
        return sample!
    }

    private static func checkPreparation(_ suite: TestSuite) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-prepare-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        var returned = false
        var completed = false
        RecorderWriter.prepare(url: url, pixelSize: CGSize(width: 64, height: 64), frameRate: 30,
                               capturesSystemAudio: false, capturesMicrophone: false,
                               pauseClock: RecorderPauseClock()) { writer in
            suite.expect(returned && Thread.isMainThread && writer != nil,
                         "writer preparation returns asynchronously to the main thread with a usable encoder")
            writer?.cancel()
            completed = true
        }
        returned = true
        let deadline = Date(timeIntervalSinceNow: 30)
        while !completed, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        suite.expect(completed, "writer preparation finishes within its fixture deadline")
    }

    private static func checkClock(_ suite: TestSuite) {
        let clock = RecorderPauseClock()
        suite.expect(clock.eventTime(100) == nil && clock.sampleTime(start: 100, duration: 0.01) == nil
            && clock.elapsed(at: 100) == 0 && !clock.pause(at: 100),
               "a session that has not begun admits no capture events or pauses")
        suite.expect(!clock.begin(at: .nan) && !clock.begin(at: .infinity) && clock.begin(at: 100),
               "the shared origin requires a finite timestamp")
        suite.expect(!clock.begin(at: 100.3) && abs(clock.elapsed(at: 100.3) - 0.3) < 0.0001,
               "starting a later source cannot reset the recording origin or elapsed display")
        suite.expect(clock.eventTime(99.9) == nil && clock.sampleTime(start: 99.9, duration: 0.01) == nil,
               "events and samples preceding the recording are rejected")
        suite.expect(clock.pause(at: 110) && clock.elapsed(at: 115) == 10 && clock.eventTime(115) == nil,
               "pausing freezes the shared elapsed display and discards events")
        suite.expect(clock.resume(at: 120) && clock.sampleTime(start: 121, duration: 0.01) == 11
            && clock.eventTime(121) == 11 && clock.elapsed(at: 121) == 11,
               "samples, events and elapsed display remove the same pause")
    }

    private static func check(_ suite: TestSuite,
                              delayedVideo: Bool = false, capturesAudio: Bool = true,
                              changingMicrophone: Bool = false,
                              microphoneChannels: AVAudioChannelCount = 2,
                              microphoneFormat: AVAudioCommonFormat = .pcmFormatFloat32,
                              malformedMicrophone: Bool = false,
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
        if malformedMicrophone {
            suite.expect(writer.append(malformedAudio(byteCount: 2_048), kind: .microphone) == .dropped,
                         "inconsistent microphone PCM is dropped before it can corrupt the AAC track")
        }
        var pointer = RecorderPointerTrack()
        var typing = RecorderTypingTrack()

        // The microphone callback arrives first but its capture starts later.
        // Video and system audio must retain their earlier timestamps.
        let firstAudio = RecorderSampleTimingTests.audio(count: 480, time: origin + time(0.1))
        let firstMicrophone = changingMicrophone
            ? audioSample(firstAudio, interleaved: false, channels: microphoneChannels, format: microphoneFormat)
            : firstAudio
        try await feed(firstMicrophone, kind: .microphone, to: writer, required: capturesAudio)
        for index in 0..<100 {
            if index == 50 {
                pause.pause(at: 100.5)
                suite.expect(pause.eventTime(100.75) == nil && pause.elapsed(at: 100.75) == 0.5,
                       "events during a pause do not reach either metadata track")
                pause.resume(at: 101)
            }
            let source = origin + time(Double(index) / 100 + (index >= 50 ? 0.5 : 0))
            if [delayedVideo ? 20 : 0, 40, 80].contains(index) {
                try await feed(video(at: source), kind: .video, to: writer)
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
            try await feed(systemAudio, kind: .systemAudio, to: writer, required: capturesAudio)
            if index > 10 {
                let captured = changingMicrophone
                    ? audioSample(audio, interleaved: index >= 50, channels: microphoneChannels, format: microphoneFormat)
                    : audio
                // Exercise the additional clock-conversion pass the microphone uses.
                let microphone = RecorderSampleTiming.retimed(captured, to: source + time(400))!
                let converted = RecorderSampleTiming.converted(microphone,
                    from: microphoneClock, to: CMClockGetHostTimeClock())!
                try await feed(converted, kind: .microphone, to: writer, required: capturesAudio)
            }
        }
        let finished = await writer.finish(at: origin + time(1.5))
        suite.expect(finished, changingMicrophone || changingSystemAudio
            ? "the multitrack MOV survives an audio buffer-layout change across a pause"
            : "the raw multitrack MOV finishes")
        suite.expect(writer.videoFrameCount == 3, "all three captured video frames are retained")
        guard finished else { return }
        // Use the same stored formats read by the editor, including their
        // timestamp precision, alongside the MOV's decoded timestamps below.
        let savedPointer = RecorderPointerTrack.decoded(pointer.encoded())
        let savedTyping = RecorderTypingTrack.decoded(typing.encoded())
        let eventTimes = savedPointer.samples.map(\.time) + savedPointer.clicks.map(\.time) + savedTyping.times
        suite.expect(eventTimes.count == 6, "both metadata tracks retain markers before and after pause/resume")
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        suite.expect(tracks.count == (capturesAudio ? 3 : 1), "the raw MOV contains exactly the enabled tracks")
        for track in tracks {
            let type = track.mediaType
            let range = try await track.load(.timeRange)
            suite.expect(abs(range.end.seconds - 1) < 0.05, "\(type.rawValue) ends on the shared timeline after the pause")
            suite.expect(abs(range.end.seconds - pause.elapsed(at: 101.5)) < 0.05,
                   "the elapsed display ends with every recorded track")
            if type == .video {
                let segments = try await track.load(.segments)
                suite.expect(!segments.contains { $0.isEmpty && $0.timeMapping.target.start.seconds < 0.001 },
                       "video has no empty opening edit when the first capture is delayed")
                suite.expect(abs(range.start.seconds) < 0.001, "video begins at the explicit recording origin")
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
                suite.expect(timestamps.first.map { abs($0) < 0.001 } ?? false,
                       "the first decoded image starts at zero, including delayed capture with sound off")
                suite.expect(reader.status == .completed, "the saved video decodes fully")
                suite.expect([0.4, 0.8].allSatisfy { expected in timestamps.contains { abs($0 - expected) < 0.001 } },
                       "the raw MOV preserves video marker timestamps across pause/resume")
                suite.expect(eventTimes.allSatisfy { event in timestamps.contains { abs($0 - event) < 0.001 } },
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
            var quietPeak: Float = 0
            while let sample = output.copyNextSampleBuffer() {
                let block = CMSampleBufferGetDataBuffer(sample)!
                let frames = CMSampleBufferGetNumSamples(sample)
                var values = [Float](repeating: 0, count: frames * 2)
                precondition(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: values.count * 4,
                    destination: &values) == noErr)
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                for frame in 0..<frames {
                    let position = start + Double(frame) / 48_000
                    if (0.15..<0.35).contains(position) || (0.55..<0.75).contains(position) {
                        quietPeak = max(quietPeak, abs(values[frame * 2]), abs(values[frame * 2 + 1]))
                    }
                }
                for frame in 0..<frames where abs(values[frame * 2]) > 0.1 {
                    let marker = start + Double(frame) / 48_000
                    if markers.last.map({ marker - $0 > 0.1 }) ?? true { markers.append(marker) }
                }
            }
            suite.expect(reader.status == .completed, "the saved audio decodes fully")
            suite.expect(quietPeak < 0.001, "silent sections remain quiet after AAC encoding and decoding")
            suite.expect(markers.count == 2 && abs(markers[0] - 0.4) < 0.025 && abs(markers[1] - 0.8) < 0.025,
                   "audio markers align with video before and after the pause")
            suite.expect(eventTimes.allSatisfy { event in markers.contains { abs($0 - event) < 0.025 } },
                   "stored pointer, click and typing markers align with decoded audio")
        }
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48_000)
    }

    private static func feed(_ sample: CMSampleBuffer,
                             kind: RecorderCaptureEngine.Kind,
                             to writer: RecorderWriter,
                             required: Bool = true) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var attempts = 0
        while attempts < 2_000 && ProcessInfo.processInfo.systemUptime < deadline {
            switch writer.append(sample, kind: kind) {
            case .appended:
                return
            case .dropped:
                if required { throw FixtureError.dropped(kind) }
                return
            case .notReady:
                attempts += 1
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        throw FixtureError.timedOut(kind)
    }

    private enum FixtureError: Error, CustomStringConvertible {
        case dropped(RecorderCaptureEngine.Kind)
        case timedOut(RecorderCaptureEngine.Kind)

        var description: String {
            switch self {
            case .dropped(let kind): "writer dropped required \(kind) fixture sample"
            case .timedOut(let kind): "writer stayed backpressured for required \(kind) fixture sample"
            }
        }
    }

    /// Emulate a device switching between planar and interleaved PCM. The
    /// production writer must keep both representations in the same movie.
    private static func audioSample(_ sample: CMSampleBuffer,
                                    interleaved: Bool,
                                    channels: AVAudioChannelCount,
                                    format: AVAudioCommonFormat = .pcmFormatFloat32) -> CMSampleBuffer {
        let count = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        var source = [Int16](repeating: 0, count: Int(count) * 2)
        precondition(CMBlockBufferCopyDataBytes(CMSampleBufferGetDataBuffer(sample)!, atOffset: 0,
            dataLength: source.count * 2, destination: &source) == noErr)
        let rate = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sample)!)!.pointee.mSampleRate
        let deviceFormat = AVAudioFormat(commonFormat: format, sampleRate: rate,
            interleaved: interleaved, channelLayout: AVAudioChannelLayout(
                layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)!)
        let device = AVAudioPCMBuffer(pcmFormat: deviceFormat, frameCapacity: count)!
        device.frameLength = count
        for frame in 0..<Int(count) {
            for channel in 0..<Int(channels) {
                let buffer = interleaved ? 0 : channel
                let index = interleaved ? frame * Int(channels) + channel : frame
                let value = source[frame * 2 + channel % 2]
                if format == .pcmFormatInt16 {
                    device.int16ChannelData![buffer][index] = value
                } else {
                    device.floatChannelData![buffer][index] = Float(value) / 32_768
                }
            }
        }
        // A multichannel device need not provide speaker labels.
        var description: CMAudioFormatDescription?
        precondition(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
            asbd: deviceFormat.streamDescription, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)),
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
