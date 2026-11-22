// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AVFoundation
import Foundation

enum AVExporter {
    static func fileType(for format: FileFormat) -> AVFileType? {
        switch format {
        case .mp4: return .mp4
        case .mov: return .mov
        case .m4a: return .m4a
        case .wav: return .wav
        case .aiff: return .aiff
        default: return nil
        }
    }

    static func export(
        asset: AVAsset,
        to destination: URL,
        format: FileFormat,
        preset: String = AVAssetExportPresetHighestQuality,
        timeRange: CMTimeRange? = nil,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        metadata: [AVMetadataItem]? = nil,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        guard let type = fileType(for: format) else { throw OpenTangerineError.unsupportedConversion(.mp4, format) }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw OpenTangerineError.encodeFailed("export session for \(format.displayName)")
        }
        session.outputURL = destination
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        if let timeRange { session.timeRange = timeRange }
        if let videoComposition { session.videoComposition = videoComposition }
        if let audioMix { session.audioMix = audioMix }
        if let metadata { session.metadata = metadata }
        try? FileManager.default.removeItem(at: destination)

        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                let value = Double(session.progress)
                await MainActor.run { progress?(value) }
            }
        }
        await withTaskCancellationHandler {
            await session.export()
        } onCancel: {
            session.cancelExport()
        }
        ticker.cancel()
        try Task.checkCancellation()
        switch session.status {
        case .completed:
            progress?(1)
        case .cancelled:
            throw OpenTangerineError.cancelled
        default:
            throw OpenTangerineError.encodeFailed(session.error?.localizedDescription ?? "export failed")
        }
    }

    static func exportAudioPCM(asset: AVAsset, to destination: URL, format: FileFormat, timeRange: CMTimeRange? = nil, audioMix: AVAudioMix? = nil, progress: ((Double) -> Void)? = nil) async throws {
        try await withPCMWriter(asset: asset, to: destination, format: format, timeRange: timeRange, audioMix: audioMix, progress: progress)
    }

    private static func withPCMWriter(asset: AVAsset, to destination: URL, format: FileFormat, timeRange: CMTimeRange?, audioMix: AVAudioMix?, progress: ((Double) -> Void)?) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw OpenTangerineError.invalidInput("No audio track found.") }
        let duration = try await asset.load(.duration)
        try? FileManager.default.removeItem(at: destination)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: format == .aiff,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = audioMix
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw OpenTangerineError.encodeFailed("Unsupported PCM audio reader format") }
        reader.add(output)
        if let timeRange { reader.timeRange = timeRange }

        let formatDescriptions = try await track.load(.formatDescriptions)
        var channels = 2
        var sampleRate = 44_100.0
        if let first = formatDescriptions.first, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(first) {
            channels = Int(asbd.pointee.mChannelsPerFrame)
            sampleRate = asbd.pointee.mSampleRate
        }
        let fileType: AVFileType = format == .aiff ? .aiff : .wav
        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: format == .aiff,
            AVLinearPCMIsNonInterleaved: false,
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw OpenTangerineError.encodeFailed("Unsupported PCM audio writer format") }
        writer.add(input)
        guard reader.startReading() else { throw OpenTangerineError.encodeFailed(reader.error?.localizedDescription ?? "reader") }
        guard writer.startWriting() else { throw OpenTangerineError.encodeFailed(writer.error?.localizedDescription ?? "writer") }
        let start = timeRange?.start ?? .zero
        writer.startSession(atSourceTime: start)
        let total = CMTimeGetSeconds(timeRange?.duration ?? duration)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "opentangerine.pcm.writer")
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let sample = output.copyNextSampleBuffer() {
                        guard input.append(sample) else {
                            reader.cancelReading()
                            input.markAsFinished()
                            let error = writer.error
                            writer.cancelWriting()
                            continuation.resume(throwing: OpenTangerineError.encodeFailed(error?.localizedDescription ?? "Could not write PCM audio sample"))
                            return
                        }
                        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) - CMTimeGetSeconds(start)
                        if total > 0 { let value = min(1, max(0, time / total)); DispatchQueue.main.async { progress?(value) } }
                    } else {
                        input.markAsFinished()
                        if reader.status == .failed {
                            writer.cancelWriting()
                            continuation.resume(throwing: OpenTangerineError.encodeFailed(reader.error?.localizedDescription ?? "reader"))
                        } else {
                            writer.finishWriting {
                                if writer.status == .completed {
                                    continuation.resume()
                                } else {
                                    continuation.resume(throwing: OpenTangerineError.encodeFailed(writer.error?.localizedDescription ?? "writer"))
                                }
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    static func timeRange(start: Double, end: Double) -> CMTimeRange {
        let s = CMTime(seconds: max(0, start), preferredTimescale: 600)
        let e = CMTime(seconds: max(start, end), preferredTimescale: 600)
        return CMTimeRange(start: s, end: e)
    }
}

