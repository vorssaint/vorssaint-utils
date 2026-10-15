// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
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
        suite.expect(done.wait(timeout: .now() + 300) == .success,
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
        let gifFolder = folder.appendingPathComponent("gif-phase-source")
        try FileManager.default.createDirectory(at: gifFolder, withIntermediateDirectories: true)
        let gifTake = RecorderTakeStore.Take(id: UUID(), folder: gifFolder)
        try await writePhaseVideo(to: gifTake.videoURL)
        let gifURL = folder.appendingPathComponent("speed.gif")
        let gifDocument = RecorderEditDocument(trimStart: 0.5, trimEnd: 1.5, exportSpeed: 2)
        let gifFailure = await RecorderExporter().export(take: gifTake,
            document: gifDocument, output: .gif, to: gifURL, progress: { _ in })
        suite.expect(gifFailure == nil, "GIF uses the current trim and retimed composition")
        if let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) {
            suite.expect(CGImageSourceGetCount(source) == 6,
                         "one trimmed source second at 2x produces six GIF frames")
            let colours = (0..<CGImageSourceGetCount(source)).compactMap {
                CGImageSourceCreateImageAtIndex(source, $0, nil).map(meanRGB)
            }
            suite.expect(colours.count == 6,
                         "every encoded animation frame decodes")
            suite.expect(colours.first.map { $0.green > $0.red * 2 && $0.green > $0.blue * 2 }
                    == true,
                         "the current trim begins in the green source phase")
            suite.expect(colours.last.map { $0.blue > $0.red * 2 && $0.blue > $0.green * 2 }
                    == true,
                         "the current trim ends in the blue source phase")
            suite.expect(colours.allSatisfy {
                ($0.green > $0.red * 2 && $0.green > $0.blue * 2)
                    || ($0.blue > $0.red * 2 && $0.blue > $0.green * 2)
            }, "trimmed GIF excludes the red opening and white closing phases")
        } else { suite.expect(false, "exported GIF decodes") }
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        suite.expect(RecorderGIFClipboard.publish(fileURL: gifURL, to: pasteboard),
                     "the production GIF publishes to a private pasteboard")
        let nativeGIFType = NSPasteboard.PasteboardType("com.compuserve.gif")
        suite.expect(RecorderGIFClipboard.pasteboardType == nativeGIFType,
                     "the clipboard helper declares the native GIF pasteboard type")
        if let copied = pasteboard.data(forType: nativeGIFType),
           let source = CGImageSourceCreateWithData(copied as CFData, nil) {
            suite.expect(copied == (try? Data(contentsOf: gifURL)),
                         "copy publishes the encoded GIF bytes rather than a flattened image")
            suite.expect(CGImageSourceGetCount(source) == 6,
                         "the copied GIF keeps every animation frame")
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
            let gif = properties?[kCGImagePropertyGIFDictionary] as? NSDictionary
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber
            // GIF stores delays in centiseconds, so ImageIO quantizes 1/12 s
            // to 8 cs while retaining the exporter-selected cadence.
            suite.expectClose(delay?.doubleValue ?? -1, 0.08,
                              "the copied GIF keeps its animation timing", tol: 0.0001)
        } else {
            suite.expect(false, "copied GIF data decodes from its native pasteboard type")
        }
        let longFolder = folder.appendingPathComponent("long-gif-source")
        try FileManager.default.createDirectory(at: longFolder, withIntermediateDirectories: true)
        let longTake = RecorderTakeStore.Take(id: UUID(), folder: longFolder)
        try await writePhaseVideo(to: longTake.videoURL, seconds: 30)
        let longURL = folder.appendingPathComponent("thirty-seconds.gif")
        var longDocument = RecorderEditDocument(gifFrameRate: 15)
        longDocument.backdrop = ""
        longDocument.showsPointer = false
        longDocument.zoomEnabled = false
        let scratchBefore = Set((try? FileManager.default.contentsOfDirectory(
            atPath: RecorderGIFWorkspace.root.path)) ?? [])
        let longFailure = await RecorderExporter().export(take: longTake, document: longDocument,
            output: .gif, to: longURL, progress: { _ in })
        suite.expect(longFailure == nil, "30-second GIF at 15 fps exports beyond the old 20-second cap")
        if let source = CGImageSourceCreateWithURL(longURL as CFURL, nil) {
            suite.expect(CGImageSourceGetCount(source) == 450,
                         "long production GIF retains all 450 frames")
            var duration = 0.0
            for index in 0..<CGImageSourceGetCount(source) {
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?
                let gif = properties?[kCGImagePropertyGIFDictionary] as? NSDictionary
                duration += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? 0
            }
            suite.expectClose(duration, 30, "long production GIF keeps its playback duration", tol: 0.005)
            let first = CGImageSourceCreateImageAtIndex(source, 0, nil).map(meanRGB)
            let last = CGImageSourceCreateImageAtIndex(source, 449, nil).map(meanRGB)
            suite.expect(first.map { $0.red > $0.green * 2 && $0.red > $0.blue * 2 } == true
                    && last.map { $0.red > 100 && $0.green > 100 && $0.blue > 100 } == true,
                         "long GIF includes its opening and closing source phases")
        } else { suite.expect(false, "long production GIF decodes") }
        suite.expect(RecorderGIFClipboard.publish(fileURL: longURL, to: pasteboard),
                     "long GIF copies through the production clipboard helper")
        if let copied = pasteboard.data(forType: nativeGIFType),
           let source = CGImageSourceCreateWithData(copied as CFData, nil) {
            suite.expect(CGImageSourceGetCount(source) == 450,
                         "clipboard retains all frames of the long GIF")
        } else { suite.expect(false, "long copied GIF decodes") }
        try await stillClipStaysCompact(suite, folder: folder)
        let scratchAfter = Set((try? FileManager.default.contentsOfDirectory(
            atPath: RecorderGIFWorkspace.root.path)) ?? [])
        suite.expect(scratchAfter.subtracting(scratchBefore).isEmpty,
                     "completed GIF export leaves no scratch workspace")
        let invalidURL = folder.appendingPathComponent("not-a-gif.gif")
        try Data("not a gif".utf8).write(to: invalidURL)
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        suite.expect(!RecorderGIFClipboard.publish(fileURL: invalidURL, to: pasteboard)
                && pasteboard.string(forType: .string) == "keep me",
                     "invalid GIF preparation leaves the existing clipboard untouched")
        if let artifactPath = ProcessInfo.processInfo.environment["VORSSAINT_RECORDER_FIXTURE_DIR"] {
            let artifactDirectory = URL(fileURLWithPath: artifactPath, isDirectory: true)
            try FileManager.default.createDirectory(at: artifactDirectory,
                                                    withIntermediateDirectories: true)
            let sourceCopy = artifactDirectory.appendingPathComponent("source-two-seconds.mov")
            let gifCopy = artifactDirectory.appendingPathComponent("trimmed-half-second.gif")
            try? FileManager.default.removeItem(at: sourceCopy)
            try? FileManager.default.removeItem(at: gifCopy)
            try FileManager.default.copyItem(at: gifTake.videoURL, to: sourceCopy)
            try FileManager.default.copyItem(at: gifURL, to: gifCopy)
            let longCopy = artifactDirectory.appendingPathComponent("thirty-seconds.gif")
            try? FileManager.default.removeItem(at: longCopy)
            try FileManager.default.copyItem(at: longURL, to: longCopy)
        }
        // Esc while the GIF is still taking frames: the saved GIF stays and
        // nothing hidden is left beside it.
        let cancelFolder = folder.appendingPathComponent("cancelled-gif")
        try FileManager.default.createDirectory(at: cancelFolder, withIntermediateDirectories: true)
        let savedGIF = cancelFolder.appendingPathComponent("saved.gif")
        let previousGIF = Data("previous gif".utf8)
        try previousGIF.write(to: savedGIF)
        let gifExporter = RecorderExporter()
        let gifCancel = await gifExporter.export(take: take, document: RecorderEditDocument(),
                                                 output: .gif, to: savedGIF,
                                                 progress: { _ in gifExporter.cancel() })
        suite.expect(gifCancel == .cancelled && (try? Data(contentsOf: savedGIF)) == previousGIF,
                     "cancelled GIF export preserves the existing destination")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: cancelFolder.path)) ?? []
        suite.expect(leftovers == ["saved.gif"],
                     "cancelled GIF export leaves nothing beside the destination \(leftovers)")
        let scratchCancelled = Set((try? FileManager.default.contentsOfDirectory(
            atPath: RecorderGIFWorkspace.root.path)) ?? [])
        suite.expect(scratchCancelled.subtracting(scratchBefore).isEmpty,
                     "cancelled GIF export removes its scratch workspace")
        let missingFolder = folder.appendingPathComponent("missing-destination", isDirectory: true)
        let failedGIF = await RecorderExporter().export(take: gifTake, document: gifDocument,
            output: .gif, to: missingFolder.appendingPathComponent("failed.gif"), progress: { _ in })
        suite.expect(failedGIF == .writeFailed && !FileManager.default.fileExists(atPath: missingFolder.path),
                     "failed GIF publication reports the error without creating a destination folder")
        let scratchFailed = Set((try? FileManager.default.contentsOfDirectory(
            atPath: RecorderGIFWorkspace.root.path)) ?? [])
        suite.expect(scratchFailed.subtracting(scratchBefore).isEmpty,
                     "failed GIF export removes its completed scratch file")
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

    /// A still gradient with a small moving square, saved through the
    /// production exporter and compared with the same decoded frames through
    /// one multi-image ImageIO destination, the encoder used before chunking.
    private static func stillClipStaysCompact(_ suite: TestSuite, folder: URL) async throws {
        let stillFolder = folder.appendingPathComponent("still-gif-source")
        try FileManager.default.createDirectory(at: stillFolder, withIntermediateDirectories: true)
        let take = RecorderTakeStore.Take(id: UUID(), folder: stillFolder)
        try await writePhaseVideo(to: take.videoURL, movingSquare: true)
        var document = RecorderEditDocument()
        document.backdrop = ""
        document.showsPointer = false
        document.zoomEnabled = false
        let url = folder.appendingPathComponent("still.gif")
        let failure = await RecorderExporter().export(take: take, document: document, output: .gif,
                                                      to: url, progress: { _ in })
        guard failure == nil, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let size = (try? Data(contentsOf: url))?.count else {
            suite.expect(false, "still production GIF exports")
            return
        }
        let count = CGImageSourceGetCount(source)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: take.videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 128, height: 128)
        let reference = NSMutableData()
        guard count > 1, let sink = CGImageDestinationCreateWithData(
            reference as CFMutableData, "com.compuserve.gif" as CFString, count, nil) else {
            suite.expect(false, "still production GIF has frames to compare")
            return
        }
        for index in 0..<count {
            let time = CMTime(seconds: Double(index) / Double(document.resolvedGIFFrameRate),
                              preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(sink, frame, nil)
        }
        guard CGImageDestinationFinalize(sink) else {
            suite.expect(false, "still reference GIF encodes")
            return
        }
        // Both runs are ImageIO's multi-image encoder on the same frames, so
        // they should match to a few header bytes; 25% absorbs decoding
        // differences between the edit timeline and the plain asset. Encoding
        // each frame alone measured 2.8x on the trimmed fixture.
        suite.expect(size <= reference.length * 5 / 4,
                     "a mostly still GIF stays as compact as the single encoder (\(size) vs \(reference.length))")
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
            (32..<96).map { x in
                let offset = (y * 128 + x) * 4
                return Double(bytes[offset])
            }
        }
        let mean = samples.reduce(0, +) / Double(samples.count)
        return sqrt(samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count))
    }

    private static func writePhaseVideo(to url: URL, seconds: Int = 2,
                                        movingSquare: Bool = false) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
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
        for frame in 0..<(seconds * 60) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var maybe: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &maybe)
            guard let pixel = maybe else { throw FixtureFailure.writeFailed }
            CVPixelBufferLockBaseAddress(pixel, [])
            let pointer = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixel)
            for y in 0..<128 { for x in 0..<128 {
                let value: UInt8 = ((x / 4 + y / 4) % 2 == 0) ? 0 : 255
                let offset = y * stride + x * 4
                if movingSquare {
                    // A still gradient; a white square moves one point per frame.
                    let inSquare = (frame..<(frame + 12)).contains(x) && (40..<52).contains(y)
                    pointer[offset] = inSquare ? 255 : UInt8(x * 2)
                    pointer[offset + 1] = inSquare ? 255 : UInt8(y * 2)
                    pointer[offset + 2] = inSquare ? 255 : 64
                    pointer[offset + 3] = 255
                    continue
                }
                switch frame / (seconds * 15) {
                case 0: pointer[offset] = 0; pointer[offset + 1] = 0; pointer[offset + 2] = value
                case 1: pointer[offset] = 0; pointer[offset + 1] = value; pointer[offset + 2] = 0
                case 2: pointer[offset] = value; pointer[offset + 1] = 0; pointer[offset + 2] = 0
                default:
                    pointer[offset] = value; pointer[offset + 1] = value; pointer[offset + 2] = value
                }
                pointer[offset + 3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adapter.append(pixel,
                                 withPresentationTime: CMTime(value: Int64(frame), timescale: 60))
            else { throw FixtureFailure.writeFailed }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw FixtureFailure.writeFailed }
    }

    private static func meanRGB(of image: CGImage) -> (red: Double, green: Double, blue: Double) {
        let context = CIContext()
        var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
        context.render(CIImage(cgImage: image), toBitmap: &bytes, rowBytes: 128 * 4,
                       bounds: CGRect(x: 0, y: 0, width: 128, height: 128),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            red += Double(bytes[offset])
            green += Double(bytes[offset + 1])
            blue += Double(bytes[offset + 2])
        }
        let count = Double(128 * 128)
        return (red / count, green / count, blue / count)
    }
}
