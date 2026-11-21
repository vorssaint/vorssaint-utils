// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreGraphics
import CoreImage

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

        // The file is written beside the destination and only takes its place
        // once it is whole. Save as can be pointed at a recording that already
        // exists, and a cancel or a failure halfway through must leave that
        // recording where it is instead of taking it down with the attempt.
        let staged = RecorderSupport.stagingURL(for: destination)
        defer { try? FileManager.default.removeItem(at: staged) }
        let failure: Failure?
        switch output {
        case .video:
            failure = await exportVideo(asset: asset,
                                        videoTrack: videoTrack,
                                        pointerURL: take.pointerURL,
                                        document: document,
                                        trim: trim,
                                        sourceSize: sourceSize,
                                        frameRate: RecorderSupport.sanitizedFrameRate(frameRate),
                                        to: staged,
                                        progress: progress)
        case .gif:
            failure = await exportGIF(asset: asset,
                                      videoTrack: videoTrack,
                                      pointerURL: take.pointerURL,
                                      document: document,
                                      sourceSize: sourceSize,
                                      to: staged,
                                      progress: progress)
        }
        if let failure { return failure }
        // Finalizing the video or GIF can finish after a cancellation arrives.
        // The destination must still be kept until that last chance to cancel.
        guard !cancelled.isCancelled else { return .cancelled }
        guard RecorderSupport.commitExport(from: staged, to: destination) else {
            return .writeFailed
        }
        return nil
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
                                                           includesAudio: keepsAnyAudio,
                                                           playbackSpeed: document.exportTiming.speed),
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
        guard let composition = await RecorderComposer.videoComposition(
            track: timelineVideo,
            asset: timeline,
            duration: timelineDuration,
            frameRate: outputFrameRate,
            composer: composer,
            sourceSize: sourceSize,
            outputSize: outputSize,
            playbackSpeed: document.exportTiming.speed)
        else { return .readFailed }

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
            if document.exportTiming.speed != 1 {
                // Decode scaled audio edits at their new duration while
                // preserving speech pitch, rather than relabeling PCM times.
                output.audioTimePitchAlgorithm = .spectral
            }
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
                && RecorderWriter.hevcEncodes(width: Int(outputSize.width), height: Int(outputSize.height))
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
        let frameProgress = ProgressThrottle(progress)

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
                    frameProgress.report(min(0.9, Double(done) / Double(expectedFrames) * 0.9))
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

    /// Sample the edited timeline and encode it chunk by chunk into a
    /// disk-backed GIF. Decoded frames never exceed one chunk and the encoded
    /// file is not held in memory, however long the recording gets.
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
                                                           includesAudio: false,
                                                           playbackSpeed: document.exportTiming.speed),
              let timelineVideo = try? await result.asset.loadTracks(withMediaType: .video).first
        else { return .readFailed }
        let timeline = result.asset
        let outputDuration = CMTimeGetSeconds((try? await timeline.load(.duration)) ?? .zero)
        let frameCount = RecorderSupport.gifFrameCount(duration: outputDuration, fps: fps)
        guard frameCount > 0 else { return .noVideo }

        // Rendered through the same composer as the video, so a background and
        // a smoothed pointer are in it too, at the editor's GIF scale.
        let frameRate = Int(((try? await videoTrack.load(.nominalFrameRate)) ?? 60).rounded())
        let track = RecorderPointerTrack.decoded(try? Data(contentsOf: pointerURL))
        let plan = RecorderComposer.makePlan(document: document,
                                             track: track,
                                             sourceSize: sourceSize,
                                             frameRate: RecorderSupport.sanitizedFrameRate(frameRate),
                                             duration: duration,
                                             outputScale: CGFloat(document.outputScale(for: .gif)),
                                             outputFormat: .gif)
        let composer = plan.map { RecorderComposer(plan: $0) }
        // GIF dimensions are independent of the video bitrate and size preset.
        let canvas = composer?.canvasSize
            ?? RecorderSupport.gifOutputSize(source: RecorderSupport.evenSize(sourceSize),
                scalePercent: document.resolvedGIFScalePercent)

        let formats = (try? await videoTrack.load(.formatDescriptions)) ?? []
        let characteristics = try? await videoTrack.load(.mediaCharacteristics)
        let canReadDirectly = characteristics?.contains(.containsAlphaChannel) == false
            && Self.supportsFastGIF(formats)
        // Decode imports with special geometry or alpha at presentation size
        // before applying edits. A raw raster can be narrower than the plan,
        // and AV video composition flattens transparent input over black.
        // Pure resizing also stays after decoding so missing frames are reported.
        let renderAfterDecode = composer != nil && (plan?.isScaleOnly == true || !canReadDirectly)
        let renderContext = renderAfterDecode ? CIContext(options: [.cacheIntermediates: false]) : nil
        let generator = AVAssetImageGenerator(asset: timeline)
        defer { generator.cancelAllCGImageGeneration() }
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = composer == nil ? canvas : (renderAfterDecode ? sourceSize : .zero)
        if let composer, !renderAfterDecode {
            guard let composition = await RecorderComposer.videoComposition(
                track: timelineVideo,
                asset: timeline,
                duration: (try? await timeline.load(.duration)) ?? .zero,
                frameRate: RecorderSupport.sanitizedFrameRate(frameRate),
                composer: composer,
                sourceSize: sourceSize,
                outputSize: canvas,
                playbackSpeed: document.exportTiming.speed)
            else { return .readFailed }
            generator.videoComposition = composition
        }

        let frameProgress = ProgressThrottle(progress)
        let canUseFastEncoder = canvas.width * canvas.height >= 512 * 512 && canReadDirectly

        func write(useFastEncoder: Bool) async throws -> Failure? {
            if cancelled.isCancelled { return .cancelled }
            let workspace = try RecorderGIFWorkspace()
            defer { workspace.discard() }
            let writer = try RecorderGIFWriter(url: workspace.fileURL, fps: fps)
            if useFastEncoder, let fast = RecorderFastGIFWriter(writer: writer, size: canvas,
                    isCancelled: { [cancelled] in cancelled.isCancelled }) {
                try await writeFastGIFFrames(fast, timeline: timeline, track: timelineVideo,
                    composer: composer, canvas: canvas, timing: document.exportTiming,
                    fps: fps, frameCount: frameCount, progress: frameProgress)
            } else {
                // Use the generator as well as ImageIO on fallback. It applies
                // display geometry, preserves alpha and recovers individual
                // images after damaged stretches that stop a sequential reader.
                var previous: CGImage?
                var missing = 0
                for index in 0..<frameCount {
                    if cancelled.isCancelled { return .cancelled }
                    let seconds = Double(index) / Double(fps)
                    let time = CMTime(seconds: seconds, preferredTimescale: 600)
                    let decoded = try? await generator.image(at: time).image
                    if let frame = decoded ?? previous {
                        for outputIndex in (index - missing)...index {
                            if cancelled.isCancelled { return .cancelled }
                            if let renderContext, let composer {
                                let editTime = document.exportTiming.sourceTime(forOutputTime: Double(outputIndex) / Double(fps))
                                let rendered = composer.render(CIImage(cgImage: frame), at: editTime)
                                guard let picture = renderContext.createCGImage(rendered, from: CGRect(origin: .zero, size: canvas))
                                else { return .readFailed }
                                try writer.append(picture)
                            } else {
                                try writer.append(frame)
                            }
                        }
                        missing = 0
                        previous = frame
                    } else { missing += 1 }
                    frameProgress.report(min(0.99, Double(index + 1) / Double(frameCount)))
                }
                guard previous != nil else { return .readFailed }
                if cancelled.isCancelled { return .cancelled }
                try writer.finish()
            }
            if cancelled.isCancelled { return .cancelled }
            try FileManager.default.copyItem(at: workspace.fileURL, to: destination)
            return nil
        }

        do {
            do {
                if let failure = try await write(useFastEncoder: canUseFastEncoder) { return failure }
            } catch RecorderFastGIFWriter.Failure.unavailable {
                // The first attempt has released its workspace, decoder and
                // buffers. The same throttle ignores lower progress on retry.
                if let failure = try await write(useFastEncoder: false) { return failure }
            }
        } catch RecorderFastGIFWriter.Failure.cancelled {
            return .cancelled
        } catch {
            return .writeFailed
        }
        progress(1)
        return nil
    }

    private func writeFastGIFFrames(_ writer: RecorderFastGIFWriter, timeline: AVAsset, track: AVAssetTrack,
                                    composer: RecorderComposer?, canvas: CGSize, timing: RecorderExportTiming,
                                    fps: Int, frameCount: Int, progress: ProgressThrottle) async throws {
        guard let reader = try? AVAssetReader(asset: timeline),
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { throw RecorderFastGIFWriter.Failure.unavailable }
        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        frames.alwaysCopiesSampleData = false
        guard reader.canAdd(frames) else { throw RecorderFastGIFWriter.Failure.unavailable }
        reader.add(frames)
        guard reader.startReading() else { throw RecorderFastGIFWriter.Failure.unavailable }
        defer { reader.cancelReading() }

        let geometry = RecorderSupport.videoGeometry(naturalSize: naturalSize, preferredTransform: transform)
        // Track transforms use a top-left origin; Core Image uses bottom-left.
        let imageTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: naturalSize.height)
            .concatenating(geometry.transform)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: geometry.size.height))
        var currentSample: CMSampleBuffer?
        var nextSample = frames.copyNextSampleBuffer()
        for index in 0..<frameCount {
            let seconds = Double(index) / Double(fps)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            try autoreleasepool {
                if cancelled.isCancelled { throw RecorderFastGIFWriter.Failure.cancelled }
                while let sample = nextSample, CMSampleBufferGetPresentationTimeStamp(sample) <= time {
                    currentSample = sample
                    nextSample = frames.copyNextSampleBuffer()
                    if cancelled.isCancelled { throw RecorderFastGIFWriter.Failure.cancelled }
                }
                guard reader.status != .failed, let sample = currentSample,
                      CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(sample),
                                CMSampleBufferGetDuration(sample)) > time,
                      let pixel = CMSampleBufferGetImageBuffer(sample),
                      CGSize(width: CVPixelBufferGetWidth(pixel), height: CVPixelBufferGetHeight(pixel)) == naturalSize
                else { throw RecorderFastGIFWriter.Failure.unavailable }
                let source = CIImage(cvPixelBuffer: pixel).transformed(by: imageTransform)
                let rendered = composer?.render(source, at: timing.sourceTime(forOutputTime: seconds))
                    ?? source.transformed(by: CGAffineTransform(scaleX: canvas.width / geometry.size.width,
                                                               y: canvas.height / geometry.size.height))
                let sourceBytes = CVPixelBufferGetDataSize(pixel)
                guard sourceBytes > 0 else { throw RecorderFastGIFWriter.Failure.unavailable }
                try writer.append(rendered, sourceBytes: sourceBytes)
            }
            progress.report(min(0.99, Double(index + 1) / Double(frameCount)))
        }
        try writer.finish()
    }

    static func supportsFastGIF(_ formats: [CMFormatDescription]) -> Bool {
        !formats.isEmpty && formats.allSatisfy { format in
            let codec = CMFormatDescriptionGetMediaSubType(format)
            guard codec == kCMVideoCodecType_H264 || codec == kCMVideoCodecType_HEVC else { return false }
            let extensions = CMFormatDescriptionGetExtensions(format).map { $0 as NSDictionary } ?? [:]
            // HEVC with alpha also identifies itself as hvc1. NV12 drops the
            // alpha plane before any shader could inspect it.
            guard (extensions[kCMFormatDescriptionExtension_ContainsAlphaChannel] as? NSNumber)?.boolValue != true,
                  extensions[kCMFormatDescriptionExtension_AlphaChannelMode] == nil else { return false }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            let encoded = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            // The generator applies clean aperture and pixel aspect ratio.
            // A direct pixel buffer only has the encoded raster.
            guard CMVideoFormatDescriptionGetPresentationDimensions(format, usePixelAspectRatio: true,
                      useCleanAperture: false) == encoded,
                  CMVideoFormatDescriptionGetCleanAperture(format, originIsAtTopLeft: true)
                    == CGRect(origin: .zero, size: encoded) else { return false }
            let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String
            let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String
            // Unknown HEVC can be untagged HDR. Do not force it through 8-bit NV12.
            if transfer == nil && codec == kCMVideoCodecType_HEVC { return false }
            return (transfer == nil || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
                    || transfer == (kCMFormatDescriptionTransferFunction_sRGB as String))
                && (primaries == nil || primaries == (kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String))
        }
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

/// Passes progress on at most ten times a second, and only once it has
/// moved by half a percent. Frames are appended far faster than that, and
/// every report redraws the editor on the main thread (#3075).
private final class ProgressThrottle: @unchecked Sendable {
    private static let interval: TimeInterval = 0.1
    private static let step = 0.005
    private let lock = NSLock()
    private let forward: (Double) -> Void
    private var lastValue = 0.0
    private var lastTime = -TimeInterval.infinity

    init(_ forward: @escaping (Double) -> Void) {
        self.forward = forward
    }

    func report(_ value: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard value - lastValue >= Self.step, now - lastTime >= Self.interval else {
            lock.unlock()
            return
        }
        lastValue = value
        lastTime = now
        lock.unlock()
        forward(value)
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
