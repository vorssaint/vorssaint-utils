// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AVFoundation
import Foundation

struct AudioEngine: ConversionEngine {
    static let nativeTargets: Set<FileFormat> = [.m4a, .wav, .aiff]

    func supports(from: FileFormat, to: FileFormat) -> Bool {
        from.category == .audio && to.category == .audio
    }

    func convert(_ request: ConversionRequest) async throws {
        if Self.nativeTargets.contains(request.target), !(request.options.audioBitrate != nil && FFmpeg.isAvailable),
           await MediaInfo.isNativelyReadable(request.source) {
            do {
                let asset = AVURLAsset(url: request.source)
                if request.target == .m4a {
                    try await AVExporter.export(asset: asset, to: request.destination, format: .m4a, preset: AVAssetExportPresetAppleM4A, progress: request.progress)
                } else {
                    try await AVExporter.exportAudioPCM(asset: asset, to: request.destination, format: request.target, progress: request.progress)
                }
                return
            } catch {
                try Task.checkCancellation()
                guard FFmpeg.isAvailable else { throw error }
            }
        }
        try await Self.ffmpegConvert(source: request.source, destination: request.destination, target: request.target, bitrate: request.options.audioBitrate, progress: request.progress)
    }

    static func codecArguments(for target: FileFormat, bitrate: Int? = nil) -> [String] {
        switch target {
        case .mp3: return ["-c:a", "libmp3lame", "-b:a", "\(bitrate ?? 192_000)"]
        case .m4a: return ["-c:a", "aac", "-b:a", "\(bitrate ?? 192_000)", "-movflags", "+faststart"]
        case .wav: return ["-c:a", "pcm_s16le"]
        case .aiff: return ["-c:a", "pcm_s16be"]
        case .flac: return ["-c:a", "flac"]
        case .ogg: return ["-c:a", "libvorbis", "-q:a", "5"]
        case .opus: return ["-c:a", "libopus", "-b:a", "\(bitrate ?? 128_000)"]
        case .wma: return ["-c:a", "wmav2", "-b:a", "\(bitrate ?? 192_000)"]
        default: return []
        }
    }

    static func resolvedCodecArguments(for target: FileFormat, bitrate: Int? = nil) async -> [String] {
        if target == .ogg {
            let encoders = await FFmpeg.availableEncoders()
            if !encoders.contains("libvorbis"), encoders.contains("libopus") {
                return ["-c:a", "libopus", "-b:a", "\(bitrate ?? 128_000)"]
            }
        }
        return codecArguments(for: target, bitrate: bitrate)
    }

    static func containerArguments(for target: FileFormat) -> [String] {
        switch target {
        case .m4a: return ["-f", "ipod"]
        case .ogg: return ["-f", "ogg"]
        case .opus: return ["-f", "opus"]
        case .wma: return ["-f", "asf"]
        case .aiff: return ["-f", "aiff"]
        case .wav: return ["-f", "wav"]
        case .mp3: return ["-f", "mp3"]
        case .flac: return ["-f", "flac"]
        default: return []
        }
    }

    static func ffmpegConvert(source: URL, destination: URL, target: FileFormat, extraFilters: [String] = [], bitrate: Int? = nil, progress: @escaping (Double) -> Void) async throws {
        let duration = await FFmpeg.probeDuration(source)
        var args = ["-i", source.path, "-vn", "-map_metadata", "0"]
        if !extraFilters.isEmpty { args += ["-af", extraFilters.joined(separator: ",")] }
        args += await resolvedCodecArguments(for: target, bitrate: bitrate)
        args += containerArguments(for: target)
        args.append(destination.path)
        try await FFmpeg.run(args, purpose: "Converting to \(target.displayName)", duration: duration, progress: progress)
    }
}

