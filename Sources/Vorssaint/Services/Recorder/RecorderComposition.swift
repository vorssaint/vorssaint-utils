// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

/// Turns the stretches of a recording that survive the trim and the cuts into
/// one continuous asset.
///
/// Both the editor preview and the export read from this, which is what makes
/// the preview honest: a piece cut out of the middle is genuinely absent while
/// scrubbing, not hidden by a player that skips over it.
enum RecorderComposition {

    static func build(from asset: AVAsset,
                      ranges: [ClosedRange<Double>],
                      includesAudio: Bool) async -> AVMutableComposition? {
        guard !ranges.isEmpty else { return nil }
        let composition = AVMutableComposition()
        guard let sourceVideo = try? await asset.loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        let sourceAudio = includesAudio
            ? (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            : []
        var audio: [AVMutableCompositionTrack] = []
        for _ in sourceAudio {
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            audio.append(track)
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
                for (index, track) in audio.enumerated() where index < sourceAudio.count {
                    try track.insertTimeRange(window, of: sourceAudio[index], at: cursor)
                }
            } catch {
                // A range the source cannot serve is skipped rather than
                // failing the whole export; the rest of the recording is still
                // worth having.
                continue
            }
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor.seconds > 0 else { return nil }
        return composition
    }
}
