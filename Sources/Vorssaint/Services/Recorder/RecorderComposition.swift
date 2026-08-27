// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

/// The two sound sources a take can carry. Their stable identifiers live in
/// track metadata so new recordings never depend on track order.
enum RecorderAudioSource: String, CaseIterable, Hashable {
    case system
    case microphone

    private var contentIdentifier: String {
        "com.vorssaint.recorder.audio." + rawValue
    }

    var trackMetadata: [AVMetadataItem] {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataContentIdentifier
        item.value = contentIdentifier as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return [item]
    }

    static func tracks(in asset: AVAsset) async -> [RecorderAudioSource: AVAssetTrack] {
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        var result: [RecorderAudioSource: AVAssetTrack] = [:]
        var unmatched: [AVAssetTrack] = []

        for track in tracks {
            let metadata = (try? await track.load(.metadata)) ?? []
            var source: RecorderAudioSource?
            for item in metadata where item.identifier == .quickTimeMetadataContentIdentifier {
                guard let value = try? await item.load(.stringValue) else { continue }
                source = allCases.first { $0.contentIdentifier == value }
                if source != nil { break }
            }
            if let source, result[source] == nil {
                result[source] = track
            } else {
                unmatched.append(track)
            }
        }

        // Takes from before track metadata existed carried only system sound.
        // The fallback also keeps hand-authored files usable in the editor.
        for source in allCases where result[source] == nil {
            guard !unmatched.isEmpty else { break }
            result[source] = unmatched.removeFirst()
        }
        return result
    }
}

/// Turns the stretches of a recording that survive the trim and the cuts into
/// one continuous asset.
///
/// Both the editor preview and the export read from this, which is what makes
/// the preview honest: a piece cut out of the middle is genuinely absent while
/// scrubbing, not hidden by a player that skips over it.
enum RecorderComposition {

    struct Result {
        let asset: AVMutableComposition
        let audioTrackIDs: [RecorderAudioSource: CMPersistentTrackID]
        let duration: CMTime
    }

    static func audioMix(trackIDs: [RecorderAudioSource: CMPersistentTrackID],
                         document: RecorderEditDocument) -> AVAudioMix? {
        guard !trackIDs.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = RecorderAudioSource.allCases.compactMap { source in
            guard let trackID = trackIDs[source] else { return nil }
            let parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = trackID
            let kept: Bool
            let gain: Double
            switch source {
            case .system:
                kept = document.keepsSystemAudio
                gain = document.systemAudioGain
            case .microphone:
                kept = document.keepsMicrophone
                gain = document.microphoneGain
            }
            parameters.setVolume(kept ? Float(RecorderSupport.sanitizedAudioGain(gain)) : 0,
                                 at: .zero)
            return parameters
        }
        return mix
    }

    static func build(from asset: AVAsset,
                      ranges: [ClosedRange<Double>],
                      includesAudio: Bool) async -> Result? {
        guard !ranges.isEmpty else { return nil }
        let composition = AVMutableComposition()
        guard let sourceVideo = try? await asset.loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        video.preferredTransform = (try? await sourceVideo.load(.preferredTransform)) ?? .identity

        let sourceAudio = includesAudio ? await RecorderAudioSource.tracks(in: asset) : [:]
        var audio: [(source: RecorderAudioSource, from: AVAssetTrack,
                     sourceRange: CMTimeRange, to: AVMutableCompositionTrack)] = []
        for source in RecorderAudioSource.allCases {
            guard let from = sourceAudio[source] else { continue }
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let sourceRange = (try? await from.load(.timeRange)) ?? .invalid
            audio.append((source, from, sourceRange, track))
        }

        var cursor = CMTime.zero
        for range in ranges {
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
            let duration = CMTime(seconds: range.upperBound - range.lowerBound,
                                  preferredTimescale: 600)
            guard duration.seconds > 0 else { continue }
            let window = CMTimeRange(start: start, duration: duration)
            do {
                try video.insertTimeRange(window, of: sourceVideo, at: cursor)
            } catch {
                // A range the source cannot serve is skipped rather than
                // failing the whole export; the rest of the recording is still
                // worth having.
                continue
            }
            for pair in audio {
                let overlap = CMTimeRangeGetIntersection(window,
                                                         otherRange: pair.sourceRange)
                guard overlap.isValid, !overlap.isEmpty else { continue }
                let offset = CMTimeSubtract(overlap.start, window.start)
                try? pair.to.insertTimeRange(overlap,
                                             of: pair.from,
                                             at: CMTimeAdd(cursor, offset))
            }
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor.seconds > 0 else { return nil }
        return Result(asset: composition,
                      audioTrackIDs: Dictionary(uniqueKeysWithValues: audio.map {
                          ($0.source, $0.to.trackID)
                      }),
                      duration: cursor)
    }
}

/// A small, fixed summary of an audio track for the editor timeline. Reading
/// happens once off the main thread and keeps no decoded audio afterwards.
enum RecorderAudioWaveform {
    static func load(asset: AVAsset,
                     track: AVAssetTrack,
                     duration: Double,
                     count: Int) -> [Float] {
        guard duration > 0, count > 0,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        var peaks = Array(repeating: Float.zero, count: count)
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return []
            }
            guard let block = CMSampleBufferGetDataBuffer(sample),
                  let format = CMSampleBufferGetFormatDescription(sample),
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)
            else { continue }
            var lengthAtOffset = 0
            var totalLength = 0
            var bytes: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block,
                                              atOffset: 0,
                                              lengthAtOffsetOut: &lengthAtOffset,
                                              totalLengthOut: &totalLength,
                                              dataPointerOut: &bytes) == kCMBlockBufferNoErr,
                  let bytes else { continue }
            let channels = max(1, Int(description.pointee.mChannelsPerFrame))
            let frames = min(CMSampleBufferGetNumSamples(sample), totalLength / (4 * channels))
            let sampleRate = max(1, description.pointee.mSampleRate)
            let start = max(0, CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            bytes.withMemoryRebound(to: Float.self, capacity: frames * channels) { values in
                for frame in 0..<frames {
                    let time = start + Double(frame) / sampleRate
                    let index = min(count - 1, max(0, Int(time / duration * Double(count))))
                    var peak = peaks[index]
                    for channel in 0..<channels {
                        peak = max(peak, abs(values[frame * channels + channel]))
                    }
                    peaks[index] = min(1, peak)
                }
            }
        }
        return peaks
    }
}
