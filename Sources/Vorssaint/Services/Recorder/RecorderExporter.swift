// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Writes the finished file: reads the master, applies the edit and encodes.
///
/// Deliberately AVAssetReader into AVAssetWriter rather than an export
/// session: it is the only route that gives real control over the encoder
/// settings and the output size, and it keeps peak memory flat, because the
/// pixel buffer pool recycles instead of growing with the length of the clip.
final class RecorderExporter {

    final class ShareArtifact {
        let fileURL: URL

        fileprivate init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func discard() {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    enum Output {
        case video
        case gif
    }

    enum Failure: Error, Equatable {
        case noVideo
        case readFailed
        case writeFailed
        case tooLongForGIF
        case tooLargeForSharing
        case invalidShareArtifact
        case cancelled
    }

    /// Flipped from the main thread and read from the writer queues, so a
    /// cancel lands within a frame instead of at the end of the file.
    private let cancelled = Cancellation()

    func cancel() {
        cancelled.cancel()
    }

    // MARK: - Entry

    func export(take: RecorderTakeStore.Take,
                document: RecorderEditDocument,
                output: Output,
                to destination: URL,
                progress: @escaping (Double) -> Void) async -> Failure? {
        let asset = AVURLAsset(url: take.videoURL)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let durationTime = try? await asset.load(.duration)
        else { return .noVideo }

        let duration = CMTimeGetSeconds(durationTime)
        let trim = document.trim(duration: duration)
        guard trim.duration > 0 else { return .noVideo }
        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let sourceSize = RecorderSupport.videoGeometry(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform).size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return .noVideo }
        let frameRate = Int(((try? await videoTrack.load(.nominalFrameRate)) ?? 60).rounded())

        try? FileManager.default.removeItem(at: destination)

        switch output {
        case .video:
            return await exportVideo(asset: asset,
                                     videoTrack: videoTrack,
                                     pointerURL: take.pointerURL,
                                     document: document,
                                     trim: trim,
                                     sourceSize: sourceSize,
                                     frameRate: RecorderSupport.sanitizedFrameRate(frameRate),
                                     to: destination,
                                     progress: progress)
        case .gif:
            return await exportGIF(asset: asset,
                                   videoTrack: videoTrack,
                                   pointerURL: take.pointerURL,
                                   document: document,
                                   sourceSize: sourceSize,
                                   to: destination,
                                   progress: progress)
        }
    }

    /// Produces the only artifact the sharing service accepts. There is no
    /// file picker or generic URL entry point: this file can only come from a
    /// take owned by the recorder and the current edit document.
    func exportForSharing(take: RecorderTakeStore.Take,
                          document: RecorderEditDocument,
                          progress: @escaping (Double) -> Void) async
        -> (artifact: ShareArtifact?, failure: Failure?) {
        guard RecorderTakeStore.shared.owns(take) else {
            return (nil, .invalidShareArtifact)
        }
        let asset = AVURLAsset(url: take.videoURL)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let durationTime = try? await asset.load(.duration)
        else { return (nil, .noVideo) }

        let duration = CMTimeGetSeconds(durationTime)
        let trim = document.trim(duration: duration)
        guard trim.duration > 0 else { return (nil, .noVideo) }
        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let sourceSize = RecorderSupport.videoGeometry(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform).size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return (nil, .noVideo)
        }
        let frameRate = RecorderSupport.sanitizedFrameRate(
            Int(((try? await videoTrack.load(.nominalFrameRate)) ?? 60).rounded()))
        guard let directory = Self.shareDirectory() else { return (nil, .writeFailed) }
        let destination = directory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("mp4")

        var bitRateScale = 1.0
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: destination)
            let failure = await exportVideo(asset: asset,
                                            videoTrack: videoTrack,
                                            pointerURL: take.pointerURL,
                                            document: document,
                                            trim: trim,
                                            sourceSize: sourceSize,
                                            frameRate: frameRate,
                                            sharingBitRateScale: bitRateScale,
                                            to: destination,
                                            progress: progress)
            if let failure {
                try? FileManager.default.removeItem(at: destination)
                return (nil, failure)
            }
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if bytes <= RecordingSharingSupport.maximumUploadBytes {
                guard await Self.isValidShareArtifact(destination, in: directory) else {
                    try? FileManager.default.removeItem(at: destination)
                    return (nil, .invalidShareArtifact)
                }
                progress(1)
                return (ShareArtifact(fileURL: destination), nil)
            }
            guard let retry = RecordingSharingSupport.retryScale(current: bitRateScale,
                                                                  actualBytes: bytes) else {
                break
            }
            bitRateScale = retry
        }
        try? FileManager.default.removeItem(at: destination)
        return (nil, .tooLargeForSharing)
    }

    // MARK: - Video

    private func exportVideo(asset: AVURLAsset,
                             videoTrack: AVAssetTrack,
                             pointerURL: URL,
                             document: RecorderEditDocument,
                             trim: RecorderSupport.Trim,
                             sourceSize: CGSize,
                             frameRate: Int,
                             sharingBitRateScale: Double? = nil,
                             to destination: URL,
                             progress: @escaping (Double) -> Void) async -> Failure? {
        let duration = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
        let track = RecorderPointerTrack.decoded(try? Data(contentsOf: pointerURL))
        // The trim and the cuts become one continuous asset first, so the
        // reader never has to know that a piece was taken out of the middle.
        let ranges = document.keptRanges(duration: duration)
        let keepsAnyAudio = document.keepsSystemAudio || document.keepsMicrophone
        guard let result = await RecorderComposition.build(from: asset,
                                                           ranges: ranges,
                                                           includesAudio: keepsAnyAudio),
              let timelineVideo = try? await result.asset.loadTracks(withMediaType: .video).first
        else { return .readFailed }
        let timeline = result.asset
        let timelineDuration = (try? await timeline.load(.duration)) ?? .zero
        let audioTracks = (try? await timeline.loadTracks(withMediaType: .audio)) ?? []

        let style = document.resolvedBackdrop
        let padding = style.kind == .none ? 0 : style.padding * 0.18
        let fullCanvas = RecorderSupport.canvasSize(source: sourceSize,
                                                    padding: padding,
                                                    aspect: document.resolvedAspect,
                                                    cropsToAspect: style.kind == .none)
        let regularSize = RecorderSupport.evenSize(CGSize(
            width: fullCanvas.width * document.resolvedQuality.outputScale,
            height: fullCanvas.height * document.resolvedQuality.outputScale))
        let sharingPlan = sharingBitRateScale.flatMap {
            RecordingSharingSupport.encodingPlan(
                duration: timelineDuration.seconds,
                baseSize: regularSize,
                sourceFrameRate: frameRate,
                hasAudio: keepsAnyAudio && !audioTracks.isEmpty,
                bitRateScale: $0)
        }
        if sharingBitRateScale != nil, sharingPlan == nil { return .tooLargeForSharing }
        let outputFrameRate = sharingPlan?.frameRate ?? frameRate
        let outputScale: CGFloat
        if let sharingPlan {
            outputScale = min(1, min(sharingPlan.size.width / max(1, fullCanvas.width),
                                     sharingPlan.size.height / max(1, fullCanvas.height)))
        } else {
            outputScale = document.resolvedQuality.outputScale
        }

        // The export preset is folded into the canvas the composer draws, so
        // the background is rendered at the size it ships at instead of being
        // resampled afterwards.
        let plan = RecorderComposer.makePlan(document: document,
                                             track: track,
                                             sourceSize: sourceSize,
                                             frameRate: outputFrameRate,
                                             duration: duration,
                                             outputScale: outputScale)
        let composer = plan.map { RecorderComposer(plan: $0) }
        let outputSize = composer?.canvasSize
            ?? sharingPlan?.size
            ?? RecorderSupport.outputSize(source: RecorderSupport.evenSize(sourceSize),
                                          quality: document.resolvedQuality)
        let composition = await RecorderComposer.videoComposition(
            track: timelineVideo,
            asset: timeline,
            duration: timelineDuration,
            frameRate: outputFrameRate,
            composer: composer,
            sourceSize: sourceSize,
            outputSize: outputSize)

        guard let reader = try? AVAssetReader(asset: timeline),
              let writer = try? AVAssetWriter(outputURL: destination, fileType: .mp4)
        else { return .readFailed }
        writer.shouldOptimizeForNetworkUse = sharingPlan != nil

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [timelineVideo],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { return .readFailed }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        if keepsAnyAudio, !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsNonInterleaved: false,
                    AVLinearPCMIsBigEndianKey: false,
                ])
            output.audioMix = RecorderComposition.audioMix(trackIDs: result.audioTrackIDs,
                                                           document: document)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let resolved: [String: Any]
        if let sharingPlan {
            resolved = Self.sharingVideoSettings(size: outputSize,
                                                 frameRate: outputFrameRate,
                                                 bitRate: sharingPlan.videoBitRate)
        } else {
            let preferred = Self.videoSettings(size: outputSize,
                                               frameRate: outputFrameRate,
                                               quality: document.resolvedQuality,
                                               codec: .hevc)
            resolved = writer.canApply(outputSettings: preferred, forMediaType: .video)
                ? preferred
                : Self.videoSettings(size: outputSize,
                                     frameRate: outputFrameRate,
                                     quality: document.resolvedQuality,
                                     codec: .h264)
        }
        guard writer.canApply(outputSettings: resolved, forMediaType: .video) else {
            return .writeFailed
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: resolved)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { return .writeFailed }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: sharingPlan?.audioBitRate ?? 160_000,
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading(), writer.startWriting() else { return .writeFailed }
        writer.startSession(atSourceTime: .zero)

        let expectedFrames = max(1, Int((timelineDuration.seconds
            * Double(outputFrameRate)).rounded()))
        let counter = FrameCounter()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [cancelled] in
                await Self.pump(input: videoInput,
                                label: "recorder.export.video",
                                cancelled: cancelled) {
                    videoOutput.copyNextSampleBuffer()
                } onAppended: {
                    let done = counter.increment()
                    // Weighted so the bar never parks at almost-done while the
                    // sound is still being written. It reaches one when the
                    // file is closed, and not before.
                    progress(min(0.9, Double(done) / Double(expectedFrames) * 0.9))
                }
            }
            if let audioInput, let audioOutput {
                group.addTask { [cancelled] in
                    await Self.pump(input: audioInput,
                                    label: "recorder.export.audio",
                                    cancelled: cancelled) {
                        audioOutput.copyNextSampleBuffer()
                    } onAppended: {}
                }
            }
        }

        if cancelled.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            return .cancelled
        }
        let readerStatus = reader.status
        guard readerStatus == .completed else {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            return readerStatus == .failed ? .readFailed : .writeFailed
        }
        progress(0.95)
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            return .writeFailed
        }
        progress(1)
        return nil
    }

    /// One input drained on its own queue, the way AVFoundation asks: append
    /// while it says it is ready, return when it is not, and let it call back.
    private static func pump(input: AVAssetWriterInput,
                             label: String,
                             cancelled: Cancellation,
                             next: @escaping () -> CMSampleBuffer?,
                             onAppended: @escaping () -> Void) async {
        let queue = DispatchQueue(label: "com.vorssaint." + label, qos: .userInitiated)
        await withCheckedContinuation { continuation in
            let finished = OnceFlag()
            // AVFoundation invokes this callback only on the serial queue above.
            nonisolated(unsafe) let serializedInput = input
            input.requestMediaDataWhenReady(on: queue) {
                while serializedInput.isReadyForMoreMediaData {
                    if cancelled.isCancelled {
                        if finished.set() {
                            serializedInput.markAsFinished()
                            continuation.resume()
                        }
                        return
                    }
                    guard let buffer = next() else {
                        if finished.set() {
                            serializedInput.markAsFinished()
                            continuation.resume()
                        }
                        return
                    }
                    if serializedInput.append(buffer) {
                        onAppended()
                    } else {
                        if finished.set() {
                            serializedInput.markAsFinished()
                            continuation.resume()
                        }
                        return
                    }
                }
            }
        }
    }

    private static func videoSettings(size: CGSize,
                                      frameRate: Int,
                                      quality: RecorderSupport.Quality,
                                      codec: AVVideoCodecType) -> [String: Any] {
        let width = Int(size.width)
        let height = Int(size.height)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: RecorderSupport.averageBitRate(width: width,
                                                                     height: height,
                                                                     fps: frameRate,
                                                                     quality: quality),
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalDurationKey: quality.keyframeSeconds,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    private static func sharingVideoSettings(size: CGSize,
                                             frameRate: Int,
                                             bitRate: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalDurationKey: 4,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
    }

    private static func shareDirectory() -> URL? {
        let manager = FileManager.default
        guard let cache = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = cache
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.vorssaint.utils",
                                    isDirectory: true)
            .appendingPathComponent("Temporary Recording Uploads", isDirectory: true)
        do {
            try manager.createDirectory(at: directory,
                                        withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700],
                                      ofItemAtPath: directory.path)
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            let files = try manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles])
            for file in files {
                let values = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if values?.isRegularFile == true,
                   (values?.contentModificationDate ?? .distantFuture) < cutoff {
                    try? manager.removeItem(at: file)
                }
            }
            return directory
        } catch {
            return nil
        }
    }

    private static func isValidShareArtifact(_ url: URL, in directory: URL) async -> Bool {
        guard url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL,
              let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let bytes = values.fileSize,
              bytes > 0,
              bytes <= RecordingSharingSupport.maximumUploadBytes
        else { return false }

        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks),
              tracks.allSatisfy({ $0.mediaType == .video || $0.mediaType == .audio })
        else { return false }
        let video = tracks.filter { $0.mediaType == .video }
        let audio = tracks.filter { $0.mediaType == .audio }
        guard video.count == 1, audio.count <= 1,
              let videoFormats = try? await video[0].load(.formatDescriptions),
              !videoFormats.isEmpty,
              videoFormats.allSatisfy({ CMFormatDescriptionGetMediaSubType($0)
                == kCMVideoCodecType_H264 })
        else { return false }
        if let audioTrack = audio.first {
            guard let audioFormats = try? await audioTrack.load(.formatDescriptions),
                  !audioFormats.isEmpty,
                  audioFormats.allSatisfy({ CMFormatDescriptionGetMediaSubType($0)
                    == kAudioFormatMPEG4AAC })
            else { return false }
        }
        return true
    }

    // MARK: - GIF

    /// A GIF is written by ImageIO, which holds every frame until the file is
    /// closed. The frame budget in RecorderSupport is what keeps that from
    /// becoming the memory of the whole machine, so it is enforced here before
    /// a single frame is decoded.
    private func exportGIF(asset: AVURLAsset,
                           videoTrack: AVAssetTrack,
                           pointerURL: URL,
                           document: RecorderEditDocument,
                           sourceSize: CGSize,
                           to destination: URL,
                           progress: @escaping (Double) -> Void) async -> Failure? {
        let fps = document.resolvedGIFFrameRate
        let duration = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
        // The GIF is the same finished video, sampled: the trim and the cuts
        // become one continuous asset first, exactly as the video export does,
        // so a piece taken out of the middle is genuinely absent here too and
        // the composer is asked for frames on the clock it draws in.
        let ranges = document.keptRanges(duration: duration)
        guard let result = await RecorderComposition.build(from: asset,
                                                           ranges: ranges,
                                                           includesAudio: false),
              let timelineVideo = try? await result.asset.loadTracks(withMediaType: .video).first
        else { return .readFailed }
        let timeline = result.asset
        let outputDuration = CMTimeGetSeconds((try? await timeline.load(.duration)) ?? .zero)
        guard RecorderSupport.gifFitsBudget(duration: outputDuration, fps: fps) else {
            return .tooLongForGIF
        }
        let frameCount = RecorderSupport.gifFrameCount(duration: outputDuration, fps: fps)
        guard frameCount > 0 else { return .noVideo }

        // Rendered through the same composer as the video, so a background and
        // a smoothed pointer are in it too.
        let frameRate = Int(((try? await videoTrack.load(.nominalFrameRate)) ?? 60).rounded())
        let track = RecorderPointerTrack.decoded(try? Data(contentsOf: pointerURL))
        let plan = RecorderComposer.makePlan(document: document,
                                             track: track,
                                             sourceSize: sourceSize,
                                             frameRate: RecorderSupport.sanitizedFrameRate(frameRate),
                                             duration: duration)
        let composer = plan.map { RecorderComposer(plan: $0) }
        let canvas = composer?.canvasSize ?? RecorderSupport.evenSize(sourceSize)
        let size = RecorderSupport.gifOutputSize(source: canvas, size: document.resolvedGIFSize)

        let generator = AVAssetImageGenerator(asset: timeline)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = size
        if let composer {
            generator.videoComposition = await RecorderComposer.videoComposition(
                track: timelineVideo,
                asset: timeline,
                duration: (try? await timeline.load(.duration)) ?? .zero,
                frameRate: RecorderSupport.sanitizedFrameRate(frameRate),
                composer: composer,
                sourceSize: sourceSize,
                outputSize: canvas)
        }

        guard let sink = CGImageDestinationCreateWithURL(destination as CFURL,
                                                         UTType.gif.identifier as CFString,
                                                         frameCount,
                                                         nil)
        else { return .writeFailed }
        CGImageDestinationSetProperties(sink, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        let delay = RecorderSupport.gifDelay(fps: fps)
        // Readers clamp anything under 100 ms unless the unclamped delay is
        // written as well, so both go in and a 12 fps GIF actually plays at
        // 12 fps instead of at 10.
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary

        for index in 0..<frameCount {
            if cancelled.isCancelled {
                try? FileManager.default.removeItem(at: destination)
                return .cancelled
            }
            let seconds = min(outputDuration, Double(index) / Double(fps))
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(sink, frame, frameProperties)
            progress(min(0.99, Double(index + 1) / Double(frameCount)))
        }

        guard CGImageDestinationFinalize(sink) else {
            try? FileManager.default.removeItem(at: destination)
            return .writeFailed
        }
        progress(1)
        return nil
    }
}

/// Small thread-safe helpers the export queues share.
private final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}

private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

/// Guards the single resume of a continuation: the ready callback can fire
/// again after the last buffer, and resuming twice is a crash.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func set() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}
