// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreMedia
import Foundation

/// Encodes a video to a chosen file size.
///
/// The resolution mode drives `avconvert`, which only takes presets and so can
/// never aim at a number of megabytes. Reading into a writer can: the bitrate
/// is an explicit setting there, and a bitrate held for a known duration is a
/// file size. Rate control still lands near the budget rather than on it, so a
/// pass that overshoots hands the next one a smaller scale.
enum MediaVideoTargetEncoder {
    struct Source {
        let asset: AVAsset
        let videoTrack: AVAssetTrack
        let audioTracks: [AVAssetTrack]
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let frameRate: Double
    }

    enum EncodeError: Error {
        case unsupported
        case targetTooSmall
        case cancelled
        case failed(String)
    }

    static let maximumPasses = 3

    /// Returns the size of the file it wrote, always at or under `targetBytes`.
    static func encode(source: Source,
                       trim: MediaTrimRange,
                       targetBytes: Int64,
                       destination: URL,
                       isCancelled: () -> Bool,
                       progress: (Double) -> Void) throws -> Int64 {
        var scale = 1.0
        for pass in 0..<maximumPasses {
            guard let plan = MediaSupport.videoSizePlan(targetBytes: targetBytes,
                                                        duration: trim.duration,
                                                        sourceSize: source.naturalSize,
                                                        frameRate: source.frameRate,
                                                        hasAudio: !source.audioTracks.isEmpty,
                                                        scale: scale)
            else { throw EncodeError.targetTooSmall }

            try runPass(source: source,
                        trim: trim,
                        plan: plan,
                        destination: destination,
                        isCancelled: isCancelled,
                        progress: progress)

            let bytes = fileSize(destination)
            if bytes <= targetBytes { return bytes }
            guard pass + 1 < maximumPasses,
                  let next = MediaSupport.targetRetryScale(current: scale,
                                                           actualBytes: bytes,
                                                           targetBytes: targetBytes)
            else { break }
            scale = next
        }
        try? FileManager.default.removeItem(at: destination)
        throw EncodeError.targetTooSmall
    }

    private static func runPass(source: Source,
                                trim: MediaTrimRange,
                                plan: MediaVideoSizePlan,
                                destination: URL,
                                isCancelled: () -> Bool,
                                progress: (Double) -> Void) throws {
        try? FileManager.default.removeItem(at: destination)
        guard let reader = try? AVAssetReader(asset: source.asset),
              let writer = try? AVAssetWriter(outputURL: destination, fileType: .mp4)
        else { throw EncodeError.unsupported }

        let start = CMTime(seconds: trim.start, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: start,
                                       duration: CMTime(seconds: trim.duration, preferredTimescale: 600))
        // A file that exists to be uploaded is read from the front.
        writer.shouldOptimizeForNetworkUse = true

        let videoOutput = AVAssetReaderTrackOutput(track: source.videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw EncodeError.unsupported }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        if !source.audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: source.audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let settings = videoSettings(plan: plan, frameRate: source.frameRate)
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw EncodeError.unsupported
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = false
        // The frames are encoded at their natural orientation and the rotation
        // travels as metadata, so a portrait source stays portrait.
        videoInput.transform = source.preferredTransform
        guard writer.canAdd(videoInput) else { throw EncodeError.unsupported }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: plan.audioBitRate,
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading(), writer.startWriting() else {
            throw EncodeError.failed(writer.error?.localizedDescription ?? "Encoder unavailable.")
        }
        writer.startSession(atSourceTime: start)

        let expectedFrames = max(1, Int((trim.duration * max(1, source.frameRate)).rounded()))
        var appendedFrames = 0
        var pendingVideo = videoOutput.copyNextSampleBuffer()
        var pendingAudio = audioOutput?.copyNextSampleBuffer()

        // Both tracks are drained by whichever holds the earlier sample, so the
        // writer receives them interleaved the way it would from a live source.
        // It answers by holding one input back while it waits on the other,
        // which is why a pass never waits on the input it would have preferred:
        // it hands the sample to whichever input can take one.
        while pendingVideo != nil || pendingAudio != nil {
            if isCancelled() {
                reader.cancelReading()
                writer.cancelWriting()
                throw EncodeError.cancelled
            }
            let videoTime = pendingVideo.map { CMSampleBufferGetPresentationTimeStamp($0) }
            let audioTime = pendingAudio.map { CMSampleBufferGetPresentationTimeStamp($0) }
            let prefersVideo: Bool
            switch (videoTime, audioTime) {
            case let (video?, audio?): prefersVideo = video <= audio
            case (_?, nil): prefersVideo = true
            default: prefersVideo = false
            }
            let takesVideo = pendingVideo != nil && videoInput.isReadyForMoreMediaData
            let takesAudio = pendingAudio != nil && audioInput?.isReadyForMoreMediaData == true

            if takesVideo, prefersVideo || !takesAudio, let buffer = pendingVideo {
                guard videoInput.append(buffer) else { throw writeFailure(writer) }
                appendedFrames += 1
                progress(min(0.99, Double(appendedFrames) / Double(expectedFrames)))
                pendingVideo = videoOutput.copyNextSampleBuffer()
            } else if takesAudio, let input = audioInput, let buffer = pendingAudio {
                guard input.append(buffer) else { throw writeFailure(writer) }
                pendingAudio = audioOutput?.copyNextSampleBuffer()
            } else if pendingAudio != nil, audioInput == nil {
                // The audio track was read but the writer refused an input for
                // it, so the samples are dropped instead of piling up.
                pendingAudio = nil
            } else {
                guard writer.status == .writing else { throw writeFailure(writer) }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        guard reader.status != .failed else {
            writer.cancelWriting()
            throw EncodeError.failed(reader.error?.localizedDescription ?? "Video could not be read.")
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if isCancelled() {
                writer.cancelWriting()
                throw EncodeError.cancelled
            }
        }
        guard writer.status == .completed else { throw writeFailure(writer) }
    }

    private static func writeFailure(_ writer: AVAssetWriter) -> EncodeError {
        .failed(writer.error?.localizedDescription ?? "Video could not be encoded.")
    }

    private static func videoSettings(plan: MediaVideoSizePlan, frameRate: Double) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(plan.size.width),
            AVVideoHeightKey: Int(plan.size.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: plan.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: Int(MediaSupport.sanitizedFPS(frameRate,
                                                                                fallback: 30,
                                                                                maxFPS: 60)),
                AVVideoMaxKeyFrameIntervalDurationKey: 4,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
