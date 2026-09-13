// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

enum RecorderWriterTests {
    static func run(expect: @escaping (Bool, String) -> Void) {
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await check(expect: expect)
                try await check(expect: expect, delayedVideo: true)
                try await check(expect: expect, delayedVideo: true, capturesAudio: false)
            }
            catch { expect(false, "recorder writer fixture failed: \(error)") }
            finished.signal()
        }
        finished.wait()
    }

    private static func check(expect: (Bool, String) -> Void,
                              delayedVideo: Bool = false, capturesAudio: Bool = true) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-sync-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let pause = RecorderPauseClock()
        let origin = CMTime(value: 100, timescale: 1)
        let microphoneClock = RecorderSampleTimingTests.offsetClock()
        let writer = RecorderWriter(url: url, pixelSize: CGSize(width: 64, height: 64), frameRate: 30,
            capturesSystemAudio: capturesAudio, capturesMicrophone: capturesAudio, pauseClock: pause)!
        precondition(writer.start())
        writer.beginSession(at: origin)

        // The microphone callback arrives first but its capture starts later.
        // Video and system audio must retain their earlier timestamps.
        writer.append(RecorderSampleTimingTests.audio(count: 480, time: origin + time(0.1)), kind: .microphone)
        for index in 0..<100 {
            if index == 50 {
                pause.pause(at: 100.5)
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
            }
            writer.append(audio, kind: .systemAudio)
            if index > 10 {
                // Exercise the additional clock-conversion pass the microphone uses.
                let microphone = RecorderSampleTiming.retimed(audio, to: source + time(400))!
                let converted = RecorderSampleTiming.converted(microphone,
                    from: microphoneClock, to: CMClockGetHostTimeClock())!
                writer.append(converted, kind: .microphone)
            }
            // Real-time writer inputs apply backpressure; give the encoders time.
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let finished = await writer.finish(at: origin + time(1.5))
        expect(finished, "the raw multitrack MOV finishes")
        expect(writer.videoFrameCount == 3, "all three captured video frames are retained")
        guard finished else { return }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        expect(tracks.count == (capturesAudio ? 3 : 1), "the raw MOV contains exactly the enabled tracks")
        for track in tracks {
            let type = track.mediaType
            let range = try await track.load(.timeRange)
            expect(abs(range.end.seconds - 1) < 0.05, "\(type.rawValue) ends on the shared timeline after the pause")
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
        }
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48_000)
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
