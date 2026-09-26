// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreImage
import Foundation
import ImageIO

enum RecorderExportRenderingTests {
    static func run(_ suite: TestSuite) {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await probe(suite)
            } catch {
                suite.expect(false, "export fixture failed \(error)")
            }
            done.signal()
        }
        suite.expect(done.wait(timeout: .now() + 90) == .success,
                     "export regression finishes within its deadline")
    }

    private enum FixtureFailure: Error { case writeFailed }

    private static func probe(_ suite: TestSuite) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-export-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let take = RecorderTakeStore.Take(id: UUID(), folder: folder)
        let writer = try AVAssetWriter(outputURL: take.videoURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 128,
        ])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 128,
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<120 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var maybe: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &maybe)
            let pixel = maybe!
            CVPixelBufferLockBaseAddress(pixel, [])
            let ptr = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixel)
            for y in 0..<128 { for x in 0..<128 {
                let value: UInt8 = ((x / 4 + y / 4) % 2 == 0) ? 0 : 255
                let offset = y * stride + x * 4
                ptr[offset] = value; ptr[offset+1] = value; ptr[offset+2] = value; ptr[offset+3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adapter.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 60))
            else { throw FixtureFailure.writeFailed }
        }
        input.markAsFinished()
        await writer.finishWriting()
        suite.expect(writer.status == .completed, "the synthetic 60 fps master is written")
        try await audioAndGIF(suite, take: take)
        // The last case ends protection in the removed interval. The frame
        // held immediately before the splice must retain the pre-cut blur.
        let cases: [(cuts: Bool, blurStart: Double, blurEnd: Double, protectedTime: Double, clearTime: Double)] = [
            (false, 0.2, 0.999, 0.99899, 1.2),
            (true, 0.2, 0.999, 0.69899, 0.9),
            (true, 0, 0.499, 0.19999, 0.3),
        ]
        for scenario in cases {
            let hasCuts = scenario.cuts
            var doc = RecorderEditDocument()
            doc.backdrop = ""
            doc.showsPointer = false
            doc.zoomEnabled = false
            doc.quality = RecorderSupport.Quality.high.rawValue
            doc.blurs = [RecorderBlurRegion(start: scenario.blurStart, end: scenario.blurEnd,
                                             rect: CGRect(x: 0, y: 0, width: 1, height: 1))]
            if hasCuts {
                doc.trimStart = 0.05
                doc.cuts = [.init(start: 0.25, end: 0.5)]
            }
            for speed in [0.25, 0.5, 1.0, 1.37, 4.0] {
                doc.exportSpeed = speed
                let output = folder.appendingPathComponent("export-\(hasCuts)-\(scenario.blurEnd)-\(speed).mp4")
                let failure = await RecorderExporter().export(take: take, document: doc,
                    output: .video, to: output, progress: { _ in })
                suite.expect(failure == nil, "production export succeeds at \(speed)x with cuts \(hasCuts)")
                guard failure == nil else { continue }
                let asset = AVURLAsset(url: output)
                let duration = try await asset.load(.duration).seconds
                suite.expectClose(duration, doc.exportDuration(duration: 2),
                                  "retimed export duration", tol: 1.0 / 60 + 0.001)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                // The final output frame inside the blur must remain obscured,
                // even when it holds the preceding source frame. Later content
                // must still be visible; extending the blur forever cannot pass.
                for (editedTime, protected) in [(scenario.protectedTime, true), (scenario.clearTime, false)] {
                    let time = floor(editedTime / speed * 60) / 60
                    let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60000))
                    let contrast = contrast(of: frame.image)
                    suite.expect(protected ? contrast < 40 : contrast > 100,
                        "privacy coverage \(protected) at \(speed)x with cuts \(hasCuts), contrast \(contrast)")
                }
            }
        }
    }

    private static func audioAndGIF(_ suite: TestSuite, take: RecorderTakeStore.Take) async throws {
        let folder = take.folder.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audioTake = RecorderTakeStore.Take(id: UUID(), folder: folder)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: take.videoURL)
        let video = try await videoAsset.loadTracks(withMediaType: .video)[0]
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)), of: video, at: .zero)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        for (source, frequency, offset) in [(RecorderAudioSource.system, 440.0, 0.0), (.microphone, 880.0, 0.3)] {
            let url = folder.appendingPathComponent("\(source.rawValue).wav")
            let count = AVAudioFrameCount((2 - offset) * 48_000)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            buffer.frameLength = count
            for index in 0..<Int(count) {
                let time = Double(index) / 48_000 + offset
                let silent = source == .microphone && time >= 0.7 && time < 1.0
                buffer.floatChannelData![0][index] = silent ? 0 : Float(0.4 * sin(2 * .pi * frequency * time))
            }
            do {
                let file = try AVAudioFile(forWriting: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false,
                ])
                try file.write(from: buffer)
            }
            let asset = AVURLAsset(url: url)
            let track = try await asset.loadTracks(withMediaType: .audio)[0]
            let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try target.insertTimeRange(CMTimeRange(start: .zero, duration: try await asset.load(.duration)),
                                       of: track, at: CMTime(seconds: offset, preferredTimescale: 600))
        }
        let mux = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        mux.outputURL = audioTake.videoURL
        mux.outputFileType = .mov
        await mux.export()
        suite.expect(mux.status == .completed, "two-track fixture retains delayed microphone and its silent gap")
        guard mux.status == .completed else { return }
        for speed in [0.25, 0.5, 1.0, 1.37, 4.0] {
            var doc = RecorderEditDocument(exportSpeed: speed, keepsSystemAudio: false, microphoneGain: 0.5)
            doc.showsPointer = false
            doc.zoomEnabled = false
            doc.trimStart = 0.05
            doc.cuts = [.init(start: 0.2, end: 0.25)]
            let output = folder.appendingPathComponent("audio-\(speed).mp4")
            let failure = await RecorderExporter().export(take: audioTake, document: doc, output: .video, to: output, progress: { _ in })
            suite.expect(failure == nil, "audio export succeeds at \(speed)x")
            guard failure == nil else { continue }
            let samples = try await readAudio(output)
            func window(_ start: Double, _ end: Double) -> [Float] {
                // This fixture removes 50 ms at the start and another 50 ms
                // before the microphone begins at source time 300 ms.
                let editedStart = start - (start < 0.2 ? 0.05 : 0.1)
                let editedEnd = end - (end < 0.2 ? 0.05 : 0.1)
                let lower = min(samples.count, Int(editedStart / speed * 48_000))
                let upper = min(samples.count, Int(editedEnd / speed * 48_000))
                return Array(samples[lower..<upper])
            }
            func rms(_ samples: [Float]) -> Double {
                sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(max(1, samples.count)))
            }
            suite.expect(rms(window(0.08, 0.18)) < 0.01, "muted system audio and microphone offset survive retiming")
            suite.expect(rms(window(0.8, 0.9)) < 0.01, "microphone silence stays aligned at \(speed)x")
            let tone = window(0.42, 0.58)
            let amplitude = rms(tone)
            suite.expect(amplitude > 0.09 && amplitude < 0.18, "microphone half-gain is retained at \(speed)x")
            let crossings = zip(tone, tone.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
            let pitch = Double(crossings) * 48_000 / Double(max(1, tone.count))
            suite.expectClose(pitch, 880, "speech pitch is preserved at \(speed)x", tol: 70)
        }
        let gifURL = folder.appendingPathComponent("speed.gif")
        let gifFailure = await RecorderExporter().export(take: take,
            document: RecorderEditDocument(exportSpeed: 2), output: .gif, to: gifURL, progress: { _ in })
        suite.expect(gifFailure == nil, "GIF uses the retimed composition")
        if let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) {
            suite.expect(CGImageSourceGetCount(source) == 12, "two source seconds at 2x produce twelve GIF frames")
        } else { suite.expect(false, "exported GIF decodes") }
        let destination = folder.appendingPathComponent("preserved.mp4")
        let original = Data("previous export".utf8)
        try original.write(to: destination)
        let cancelled = RecorderExporter()
        cancelled.cancel()
        let failure = await cancelled.export(take: take, document: RecorderEditDocument(exportSpeed: 0.5),
                                             output: .video, to: destination, progress: { _ in })
        suite.expect(failure == .cancelled && (try? Data(contentsOf: destination)) == original,
                     "cancelled retimed export preserves the existing destination")
    }

    private static func readAudio(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .audio)[0]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        reader.startReading()
        var result: [Float] = []
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var floats = [Float](repeating: 0, count: count)
            _ = floats.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
            }
            result.append(contentsOf: floats)
        }
        return result
    }

    private static func contrast(of image: CGImage) -> Double {
        let context = CIContext()
        var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
        context.render(CIImage(cgImage: image), toBitmap: &bytes, rowBytes: 128 * 4,
                       bounds: CGRect(x: 0, y: 0, width: 128, height: 128),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let samples = (32..<96).flatMap { y in
            (32..<96).map { x in Double(bytes[(y * 128 + x) * 4]) }
        }
        let mean = samples.reduce(0, +) / Double(samples.count)
        return sqrt(samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count))
    }
}
