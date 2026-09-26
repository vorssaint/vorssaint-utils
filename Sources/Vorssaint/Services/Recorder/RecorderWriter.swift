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

    enum AppendOutcome {
        case appended
        case notReady
        case dropped
    }

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private let pauseClock: RecorderPauseClock
    private var systemAudioConverter: AVAudioConverter?
    private var microphoneConverter: AVAudioConverter?

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

    func beginSession(at time: CMTime) {
        guard !started, time.isNumeric, pauseClock.begin(at: time.seconds) else { return }
        writer.startSession(atSourceTime: .zero)
        started = true
    }

    @discardableResult
    func append(_ sampleBuffer: CMSampleBuffer,
                kind: RecorderCaptureEngine.Kind) -> AppendOutcome {
        guard !failed else { return .dropped }
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentation.isValid else { return .dropped }

        guard started else { return .dropped }
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let seconds = duration.isValid && !duration.isIndefinite ? max(0, duration.seconds) : 0
        guard let mapped = pauseClock.sampleTime(start: presentation.seconds,
                                                 duration: seconds) else { return .dropped }
        let shifted = CMTime(seconds: mapped, preferredTimescale: 600_000_000)

        switch kind {
        case .video:
            // Hold the first captured image over startup latency. Keep the
            // shared origin and every later timestamp so audio stays aligned.
            let videoTime: CMTime = videoFrameCount == 0 ? .zero : shifted
            guard videoInput.isReadyForMoreMediaData else { return .notReady }
            guard let retimed = RecorderSampleTiming.retimed(sampleBuffer, to: videoTime)
            else { return .dropped }
            if videoInput.append(retimed) {
                videoFrameCount += 1
                lastVideoSample = sampleBuffer
                lastVideoTime = videoTime
                return .appended
            } else {
                failed = true
                return .dropped
            }
        case .systemAudio:
            guard let systemAudioInput else { return .dropped }
            guard systemAudioInput.isReadyForMoreMediaData else { return .notReady }
            guard
                  let interleaved = Self.interleavedAudioSample(sampleBuffer, converter: &systemAudioConverter),
                  let retimed = RecorderSampleTiming.retimed(interleaved, to: shifted)
            else { return .dropped }
            guard systemAudioInput.append(retimed) else {
                failed = true
                return .dropped
            }
            return .appended
        case .microphone:
            guard let microphoneInput else { return .dropped }
            guard microphoneInput.isReadyForMoreMediaData else { return .notReady }
            guard
                  let interleaved = Self.interleavedAudioSample(sampleBuffer, converter: &microphoneConverter),
                  let retimed = RecorderSampleTiming.retimed(interleaved, to: shifted)
            else { return .dropped }
            guard microphoneInput.append(retimed) else {
                failed = true
                return .dropped
            }
            return .appended
        }
    }

    /// The encoder cannot switch between one PCM buffer and a buffer per
    /// channel mid-recording. Interleave captured audio without resampling
    /// or remixing it, keeping the device's timing and channel layout intact.
    private static func interleavedAudioSample(_ sample: CMSampleBuffer,
                                               converter: inout AVAudioConverter?) -> CMSampleBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0,
              asbd.mChannelsPerFrame > 1 else { return sample }
        // Some devices omit speaker labels for their discrete input channels.
        // AVAudioFormat requires a layout above stereo; preserve their order.
        let sourceLayout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: nil)
            .map { AVAudioChannelLayout(layout: $0) }
            ?? AVAudioChannelLayout(layoutTag: asbd.mChannelsPerFrame == 2
                ? kAudioChannelLayoutTag_Stereo
                : kAudioChannelLayoutTag_DiscreteInOrder | asbd.mChannelsPerFrame)
        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd, channelLayout: sourceLayout)
        else { return nil }
        if converter?.inputFormat != sourceFormat {
            let (bytesPerFrame, frameOverflow) = asbd.mBytesPerFrame.multipliedReportingOverflow(by: asbd.mChannelsPerFrame)
            let (bytesPerPacket, packetOverflow) = asbd.mBytesPerPacket.multipliedReportingOverflow(by: asbd.mChannelsPerFrame)
            guard !frameOverflow, !packetOverflow else { return nil }
            asbd.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved
            asbd.mBytesPerFrame = bytesPerFrame
            asbd.mBytesPerPacket = bytesPerPacket
            guard let outputFormat = AVAudioFormat(streamDescription: &asbd, channelLayout: sourceFormat.channelLayout)
            else { return nil }
            converter = AVAudioConverter(from: sourceFormat, to: outputFormat)
        }
        let sampleCount = CMSampleBufferGetNumSamples(sample)
        guard let converter,
              let count = AVAudioFrameCount(exactly: sampleCount), count > 0,
              let frameCount = Int32(exactly: sampleCount),
              let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: count),
              let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: count)
        else { return nil }
        input.frameLength = count
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: frameCount,
            into: input.mutableAudioBufferList) == noErr else { return nil }
        do { try converter.convert(to: output, from: input) }
        catch { return nil }
        guard output.frameLength == count else { return nil }

        var timingCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0,
            arrayToFill: nil, entriesNeededOut: &timingCount) == noErr, timingCount > 0 else { return nil }
        var timing = Array(repeating: CMSampleTimingInfo(), count: timingCount)
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timingCount,
            arrayToFill: &timing, entriesNeededOut: nil) == noErr else { return nil }
        var result: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: output.format.formatDescription,
            sampleCount: Int(output.frameLength), sampleTimingEntryCount: timingCount, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result) == noErr,
            let result,
            CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: output.audioBufferList) == noErr,
            CMSampleBufferSetDataReady(result) == noErr else { return nil }
        return result
    }

    /// Closes the file. The last frame is written once more at the moment the
    /// person pressed stop, otherwise a recording that ended on a still screen
    /// would be as short as its last change instead of as long as it felt.
    func finish(at wallClockEnd: CMTime) async -> Bool {
        guard started, !failed, videoFrameCount > 0 else {
            writer.cancelWriting()
            return false
        }
        if let lastVideoSample {
            let end = CMTime(
                seconds: pauseClock.elapsed(at: wallClockEnd.seconds),
                preferredTimescale: 600_000_000)
            if end > lastVideoTime, videoInput.isReadyForMoreMediaData,
               let tail = RecorderSampleTiming.retimed(lastVideoSample, to: end) {
                videoInput.append(tail)
            }
            writer.endSession(atSourceTime: end)
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
}
