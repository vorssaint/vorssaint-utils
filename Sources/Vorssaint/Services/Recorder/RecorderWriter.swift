// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreMedia

/// Writes the master file a recording produces: the pixels exactly as they
/// were on screen, plus one track per sound source. Nothing is composited
/// here and nothing is paced here, so a screen that sits still costs almost
/// nothing and every decision about how the recording finally looks stays
/// open until the editor makes it.
///
/// Everything except `start()` and `finish()` runs on the session's serial
/// writer queue. `finish()` is only called once every source has been stopped
/// and awaited, so no buffer can still be in flight.
final class RecorderWriter {

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private let pauseClock: RecorderPauseClock

    /// Everything is re-timed against the first sample that arrives, so the
    /// file starts at zero instead of at the machine's uptime.
    private var origin: CMTime?
    private var lastVideoSample: CMSampleBuffer?
    private var lastVideoTime: CMTime = .zero
    private var started = false
    private var failed = false

    /// Frames actually written, so a recording that produced nothing can be
    /// reported as a failure instead of leaving an unplayable file behind.
    private(set) var videoFrameCount = 0

    var url: URL { writer.outputURL }

    init?(url: URL,
          pixelSize: CGSize,
          frameRate: Int,
          capturesSystemAudio: Bool,
          capturesMicrophone: Bool,
          pauseClock: RecorderPauseClock) {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        // A recording that outlives a crash is worth the few extra bytes a
        // fragmented file costs.
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        let settings = Self.videoSettings(width: width,
                                          height: height,
                                          frameRate: frameRate,
                                          codec: .hevc)
        let resolved = writer.canApply(outputSettings: settings, forMediaType: .video)
            ? settings
            : Self.videoSettings(width: width,
                                 height: height,
                                 frameRate: frameRate,
                                 codec: .h264)
        guard writer.canApply(outputSettings: resolved, forMediaType: .video) else { return nil }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: resolved)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)

        var systemAudioInput: AVAssetWriterInput?
        if capturesSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio,
                                           outputSettings: Self.audioSettings)
            input.expectsMediaDataInRealTime = true
            input.metadata = RecorderAudioSource.system.trackMetadata
            if writer.canAdd(input) {
                writer.add(input)
                systemAudioInput = input
            }
        }

        var microphoneInput: AVAssetWriterInput?
        if capturesMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio,
                                           outputSettings: Self.audioSettings)
            input.expectsMediaDataInRealTime = true
            input.metadata = RecorderAudioSource.microphone.trackMetadata
            if writer.canAdd(input) {
                writer.add(input)
                microphoneInput = input
            }
        }

        self.writer = writer
        self.videoInput = videoInput
        self.systemAudioInput = systemAudioInput
        self.microphoneInput = microphoneInput
        self.pauseClock = pauseClock
    }

    // MARK: - Settings

    private static func videoSettings(width: Int,
                                      height: Int,
                                      frameRate: Int,
                                      codec: AVVideoCodecType) -> [String: Any] {
        let bitRate = RecorderSupport.averageBitRate(width: width,
                                                     height: height,
                                                     fps: frameRate,
                                                     quality: RecorderSupport.takeQuality)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalDurationKey: RecorderSupport.takeQuality.keyframeSeconds,
            // No reordering: screen content gains little from it and the
            // editor scrubs a file without B-frames far more smoothly.
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
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
    }

    private static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 160_000,
    ]

    // MARK: - Writing

    func start() -> Bool {
        guard writer.startWriting() else { return false }
        return true
    }

    func append(_ sampleBuffer: CMSampleBuffer, kind: RecorderCaptureEngine.Kind) {
        guard !failed else { return }
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentation.isValid else { return }

        if origin == nil {
            // The session opens on the first sample of any source, so the two
            // tracks share one zero and stay aligned without a second clock.
            origin = presentation
            writer.startSession(atSourceTime: .zero)
            started = true
        }
        guard let origin, started else { return }
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let seconds = duration.isValid && !duration.isIndefinite ? max(0, duration.seconds) : 0
        guard let mapped = pauseClock.sampleTime(start: presentation.seconds,
                                                 duration: seconds,
                                                 since: origin.seconds) else { return }
        let shifted = CMTime(seconds: mapped, preferredTimescale: 600_000_000)

        switch kind {
        case .video:
            guard videoInput.isReadyForMoreMediaData,
                  let retimed = Self.retimed(sampleBuffer, to: shifted)
            else { return }
            if videoInput.append(retimed) {
                videoFrameCount += 1
                lastVideoSample = sampleBuffer
                lastVideoTime = shifted
            } else {
                failed = true
            }
        case .systemAudio:
            guard let systemAudioInput, systemAudioInput.isReadyForMoreMediaData,
                  let retimed = Self.retimed(sampleBuffer, to: shifted)
            else { return }
            if !systemAudioInput.append(retimed) {
                failed = true
            }
        case .microphone:
            guard let microphoneInput, microphoneInput.isReadyForMoreMediaData,
                  let retimed = Self.retimed(sampleBuffer, to: shifted)
            else { return }
            if !microphoneInput.append(retimed) {
                failed = true
            }
        }
    }

    /// Closes the file. The last frame is written once more at the moment the
    /// person pressed stop, otherwise a recording that ended on a still screen
    /// would be as short as its last change instead of as long as it felt.
    func finish(at wallClockEnd: CMTime) async -> Bool {
        guard started, !failed, videoFrameCount > 0 else {
            writer.cancelWriting()
            return false
        }
        if let origin, let lastVideoSample {
            let end = CMTime(
                seconds: pauseClock.elapsed(since: origin.seconds, at: wallClockEnd.seconds),
                preferredTimescale: 600_000_000)
            if end > lastVideoTime, videoInput.isReadyForMoreMediaData,
               let tail = Self.retimed(lastVideoSample, to: end) {
                videoInput.append(tail)
            }
        }
        lastVideoSample = nil
        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }

    func cancel() {
        lastVideoSample = nil
        guard writer.status == .writing else { return }
        writer.cancelWriting()
    }

    /// A copy of the buffer carrying a new presentation time. The pixels are
    /// shared, not duplicated.
    private static func retimed(_ sampleBuffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy)
        return status == noErr ? copy : nil
    }
}
